// Node hashes formed from JSON, for the raw requests of checks 38 and 39 of the production
// verification kit. No client node code is used: the kit forms the hashes from the data a raw `g`
// answered, so that it can offer the server more than one candidate and print which one matches.
//
// The simple hash is the JS SDK's `ChildrenNode.hash` and `LeafNode.hash` (`@firebase/database`,
// `dist/index.esm.js`), extended to a node with no children and a priority (the server keeps such
// a node when a write below it removes its last child). The compound hash (`ch` of a listen) is
// Android's `snapshot/CompoundHash.java`, as the client's `lib/src/core/snap/compound_hash.dart`
// ports it.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// The SHA-1 hash, base64, of [text] (`sha1` in `@firebase/database`).
String sha1Base64Of(String text) =>
    base64.encode(sha1.convert(utf8.encode(text)).bytes);

/// [value] as the 16 lower-case hex digits of its IEEE 754 double (`doubleToIEEE754String`).
String ieee754Hex(num value) {
  final ByteData bytes = ByteData(8)..setFloat64(0, value.toDouble());
  return <String>[
    for (int i = 0; i < 8; i++)
      bytes.getUint8(i).toRadixString(16).padLeft(2, '0'),
  ].join();
}

final RegExp _intKey = RegExp(r'^-?\d{1,10}$');

int? _intOf(String key) {
  if (!_intKey.hasMatch(key)) {
    return null;
  }
  final int value = int.parse(key);
  return value >= -2147483648 && value <= 2147483647 ? value : null;
}

/// The key order of the database: integer-like keys first, by value, then the others by UTF-16
/// code units.
int compareKeys(String a, String b) {
  if (a == b) {
    return 0;
  }
  final int? x = _intOf(a);
  final int? y = _intOf(b);
  if (x != null && y != null) {
    return x == y ? a.length - b.length : x.compareTo(y);
  }
  if (x != null || y != null) {
    return x != null ? -1 : 1;
  }
  return a.compareTo(b);
}

/// The priority order: no priority first, then numbers, then strings.
int _comparePriority(Object? a, Object? b) {
  int rank(Object? p) => p == null ? 0 : (p is num ? 1 : 2);
  final int byRank = rank(a).compareTo(rank(b));
  if (byRank != 0 || a == null) {
    return byRank;
  }
  return a is num
      ? a.compareTo(b! as num)
      : (a as String).compareTo(b! as String);
}

String _priorityText(Object priority) =>
    priority is num ? 'number:${ieee754Hex(priority)}' : 'string:$priority';

/// A node as the server holds it, parsed from the JSON of a raw answer: a leaf, or children (in
/// key order) with an optional priority. A node with no children and a priority is a node emptied
/// by a write below it that kept its priority.
class JsonNode {
  JsonNode._(this.leaf, this.children, this.priority);

  /// The node of [json] (export form: `.value` and `.priority` keys), or null for no data.
  static JsonNode? parse(Object? json) {
    if (json == null) {
      return null;
    }
    if (json is! Map<String, Object?>) {
      return JsonNode._(json, const <String, JsonNode>{}, null);
    }
    final Object? priority = json['.priority'];
    if (json.containsKey('.value')) {
      return JsonNode._(json['.value'], const <String, JsonNode>{}, priority);
    }
    final List<String> keys =
        json.keys.where((String k) => k != '.priority').toList()
          ..sort(compareKeys);
    final Map<String, JsonNode> children = <String, JsonNode>{
      for (final String k in keys)
        if (parse(json[k]) case final JsonNode child) k: child,
    };
    if (children.isEmpty && priority == null) {
      return null;
    }
    return JsonNode._(null, children, priority);
  }

  /// The value of a leaf; null for a node with children.
  final Object? leaf;

  /// The children in key order.
  final Map<String, JsonNode> children;

  /// The priority, a number or a string; null for none.
  final Object? priority;

  /// Whether this is a leaf.
  bool get isLeaf => leaf != null;

  /// Whether this node has no children but keeps a priority.
  bool get isEmptied => leaf == null && children.isEmpty;
}

/// [node] without the nodes that hold only a kept priority, at every depth: the data a client
/// sees that drops a priority when the last child goes. Null when nothing is left.
JsonNode? withoutKeptPriorities(JsonNode? node) {
  if (node == null || node.isLeaf) {
    return node;
  }
  final Map<String, JsonNode> children = <String, JsonNode>{
    for (final MapEntry<String, JsonNode> e in node.children.entries)
      if (withoutKeptPriorities(e.value) case final JsonNode child)
        e.key: child,
  };
  return children.isEmpty ? null : JsonNode._(null, children, node.priority);
}

/// The simple hash of [node] (the `h` of a listen or a transaction put): `''` for no data; a
/// kept priority counts as the JS SDK counts the priority of a node with children, and children
/// go in priority order (by priority, kept priority included, then by key).
String simpleHash(JsonNode? node) {
  if (node == null) {
    return '';
  }
  final StringBuffer text = StringBuffer();
  final Object? priority = node.priority;
  if (priority != null) {
    text.write('priority:${_priorityText(priority)}:');
  }
  if (node.isLeaf) {
    final Object value = node.leaf!;
    text.write(switch (value) {
      num() => 'number:${ieee754Hex(value)}',
      bool() => 'boolean:$value',
      _ => 'string:$value',
    });
    return sha1Base64Of(text.toString());
  }
  final List<MapEntry<String, JsonNode>> ordered =
      node.children.entries.toList()
        ..sort((MapEntry<String, JsonNode> a, MapEntry<String, JsonNode> b) {
          final int byPriority = _comparePriority(
            a.value.priority,
            b.value.priority,
          );
          return byPriority != 0 ? byPriority : compareKeys(a.key, b.key);
        });
  for (final MapEntry<String, JsonNode> e in ordered) {
    final String child = simpleHash(e.value);
    if (child.isNotEmpty) {
      text.write(':${e.key}:$child');
    }
  }
  final String all = text.toString();
  return all.isEmpty ? '' : sha1Base64Of(all);
}

/// How a compound hash treats a node that holds only a kept priority (Android never meets one:
/// its empty node has no priority).
enum KeptPriorityRange {
  /// Left out, with its key: what the client sends (its data has no such node).
  leftOut,

  /// Its key with the priority as a leaf child: `"b":(".priority":(number:...))`.
  priorityLeaf,

  /// Its key with nothing inside: `"b":()` (Android visits a priority only before a key that
  /// sorts after `.priority`, and such a node has no key).
  emptyParens,
}

/// The `ch` of a listen: the range ends (`posts`, paths below the listened node) and the hash of
/// each range (`hashes`, one more than the posts, the last `''`).
typedef CompoundHashJson = ({List<String> posts, List<String> hashes});

String _quoted(String text) =>
    '"${text.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

String _leafV2(Object value, Object? priority) {
  final String prefix = priority == null
      ? ''
      : 'priority:${_leafV2(priority, null)}:';
  return prefix +
      switch (value) {
        num() => 'number:${ieee754Hex(value)}',
        bool() => 'boolean:$value',
        _ => 'string:${_quoted('$value')}',
      };
}

int _leafSize(Object value, Object? priority) {
  final int size = switch (value) {
    num() => 8,
    bool() => 4,
    _ => 2 + '$value'.length,
  };
  return priority == null ? size : 24 + size + _leafSize(priority, null);
}

/// The client's size estimate of [node] as JSON (`estimateSerializedNodeSize`).
int estimateSize(JsonNode node) {
  if (node.isLeaf) {
    return _leafSize(node.leaf!, node.priority);
  }
  int sum = 1;
  for (final MapEntry<String, JsonNode> e in node.children.entries) {
    sum += e.key.length + 4 + estimateSize(e.value);
  }
  final Object? priority = node.priority;
  return priority == null ? sum : sum + 12 + _leafSize(priority, null);
}

/// The compound hash of [node] with [mode] for nodes that hold only a kept priority. With
/// [KeptPriorityRange.leftOut] those nodes are removed first, as the client's data has none.
CompoundHashJson compoundHash(JsonNode? node, KeptPriorityRange mode) {
  final JsonNode? data = mode == KeptPriorityRange.leftOut
      ? withoutKeptPriorities(node)
      : node;
  if (data == null) {
    return (posts: const <String>[], hashes: const <String>['']);
  }
  final _Ranges ranges = _Ranges(
    math.max(512, math.sqrt(estimateSize(data) * 100).floor()),
  );
  _visit(data, ranges, mode);
  ranges.finish();
  return (posts: ranges.posts, hashes: ranges.hashes);
}

void _visit(JsonNode node, _Ranges ranges, KeptPriorityRange mode) {
  if (node.isLeaf) {
    ranges.leaf(_leafV2(node.leaf!, node.priority));
    return;
  }
  final Object? priority = node.priority;
  bool priorityDone = priority == null;
  void visitPriority() {
    priorityDone = true;
    ranges
      ..start('.priority')
      ..leaf(_leafV2(priority!, null))
      ..end();
  }

  for (final MapEntry<String, JsonNode> e in node.children.entries) {
    if (!priorityDone && compareKeys(e.key, '.priority') > 0) {
      visitPriority();
    }
    ranges.start(e.key);
    _visit(e.value, ranges, mode);
    ranges.end();
  }
  if (!priorityDone &&
      node.isEmptied &&
      mode == KeptPriorityRange.priorityLeaf) {
    visitPriority();
  }
}

/// Android's `CompoundHashBuilder` with its default split strategy: a range ends after a leaf
/// when its text is longer than [threshold], except at a priority.
class _Ranges {
  _Ranges(this.threshold);

  final int threshold;
  StringBuffer? _range;
  final List<String> _stack = <String>[];
  int _depth = 0;
  int _lastLeafDepth = -1;
  bool _needsComma = true;
  final List<String> posts = <String>[];
  final List<String> hashes = <String>[];

  void _ensureRange() {
    if (_range == null) {
      final StringBuffer range = StringBuffer('(');
      for (final String key in _stack.take(_depth)) {
        range.write('${_quoted(key)}:(');
      }
      _range = range;
      _needsComma = false;
    }
  }

  void leaf(String text) {
    _ensureRange();
    _lastLeafDepth = _depth;
    _range!.write(text);
    _needsComma = true;
    final bool atPriority = _depth > 0 && _stack[_depth - 1] == '.priority';
    if (_range!.length > threshold && !atPriority) {
      _endRange();
    }
  }

  void start(String key) {
    _ensureRange();
    if (_needsComma) {
      _range!.write(',');
    }
    _range!.write('${_quoted(key)}:(');
    if (_depth == _stack.length) {
      _stack.add(key);
    } else {
      _stack[_depth] = key;
    }
    _depth++;
    _needsComma = false;
  }

  void end() {
    _depth--;
    _range?.write(')');
    _needsComma = true;
  }

  void finish() {
    if (_range != null) {
      _endRange();
    }
    hashes.add('');
  }

  void _endRange() {
    final StringBuffer range = _range!;
    for (int i = 0; i < _depth; i++) {
      range.write(')');
    }
    range.write(')');
    hashes.add(sha1Base64Of(range.toString()));
    posts.add('/${_stack.take(_lastLeafDepth).join('/')}');
    _range = null;
  }
}
