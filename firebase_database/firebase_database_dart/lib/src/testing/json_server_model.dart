/// The data a Realtime Database server holds, as a plain JSON tree, with the server's rules for
/// writes and its hash. No upstream file. Used by [FakeServerActions] and the property test
/// (`test/core/sync_tree_property_test.dart`), so the two play the same server; it uses none of
/// the client's node code, so it can check that code.
///
/// The rules, measured on production (rtdb/from_boss/prodkit_production_run3_2026-11-25.txt
/// checks 27 and 38, prodkit_production_run4_check39_2026-11-25.txt check 39):
/// - a node whose last child is removed by a write below it keeps its priority, and a node that
///   then holds only such children stays too; a write at or above the node drops it;
/// - a priority written on a node that does not exist refuses the whole write
///   (`invalid_parameters: could not set priority on non-existent node`), except a null one in
///   an update, which is answered ok and changes nothing (production run 10 and the emulator,
///   2026-11-26, check 39 Q14), and a set of a null priority there, which is answered ok too
///   (production run 13, 2026-11-26, check 40); a set of a null priority that changes nothing,
///   on a missing node or on one without a priority, is pushed to no listener ([JsonServerModel.changesNothing];
///   production run 13: the emulator pushes a null at the `.priority` path, production nothing);
///   a node that keeps a priority, or holds only emptied children, takes one (check 38 (b),
///   check 39 Q2); the check is made on the data before the update, so an update that writes a
///   priority and creates its node in the same message is refused whole, in either key order
///   (production run 9 and the emulator, 2026-11-26, check 39 Q12; the object form
///   `{"x": {".priority": p, ...}}` is accepted);
/// - one update is applied in two passes, whatever its key order: every value entry first, at any
///   depth; then every priority entry, parents before children, each landing only on a node that
///   at that moment has a value or holds hidden state; a null priority removes a kept one, and an
///   emptied node left with nothing disappears (check 39 Q1, Q6, Q10, F1 to F9);
/// - the hash is the JS SDK's `ChildrenNode.hash` and `LeafNode.hash` over the node, kept
///   priorities included (check 38 (c), check 39 Q2);
/// - what the server sends of a node carries `{".priority": p}` for an emptied node (check 38 (a)).
///
/// Not measured, and kept as the client does: a value written below a leaf replaces the leaf with
/// children that keep the leaf's priority.
///
/// [FakeServerActions]: package:firebase_database_dart/src/testing/fake_server_actions.dart
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';

/// A node the server holds: a leaf (with [leaf] set) or children, either with a [priority].
final class JsonServerNode {
  /// A node with [leaf] (null for a node with children) and [priority] (null for none).
  JsonServerNode({this.leaf, this.priority});

  /// The node of export JSON [json] as the server sends or stores it (`.value`, `.priority`, a
  /// list read as a map of its indices); `{".priority": p}` is a node that keeps a priority. Null
  /// for no data.
  static JsonServerNode? fromJson(Object? json) {
    if (json == null) {
      return null;
    }
    if (json is List) {
      return fromJson(<String, Object?>{
        for (int i = 0; i < json.length; i++) '$i': json[i],
      });
    }
    if (json is! Map) {
      return JsonServerNode(leaf: json);
    }
    if (json.containsKey('.sv')) {
      return JsonServerNode(leaf: json);
    }
    final Object? priority = json['.priority'];
    final Object? value = json['.value'];
    if (value != null) {
      return JsonServerNode(leaf: value, priority: priority);
    }
    final JsonServerNode node = JsonServerNode(priority: priority);
    for (final MapEntry<Object?, Object?> e in json.entries) {
      final String key = '${e.key}';
      if (key.startsWith('.')) {
        continue;
      }
      final JsonServerNode? child = fromJson(e.value);
      if (child != null) {
        node.children[key] = child;
      }
    }
    return node.isAbsent ? null : node;
  }

  /// The value of a leaf; null for a node with children.
  Object? leaf;

  /// The priority, a number or a string; null for none.
  Object? priority;

  /// The children by key.
  final Map<String, JsonServerNode> children = <String, JsonServerNode>{};

  /// Nothing left: no value, no priority, no child. The server holds no such node.
  bool get isAbsent => leaf == null && priority == null && children.isEmpty;

  /// Whether the node has a value (a leaf, or a child with one).
  bool get hasValue =>
      leaf != null || children.values.any((JsonServerNode c) => c.hasValue);

  /// A deep copy.
  JsonServerNode copy() {
    final JsonServerNode c = JsonServerNode(leaf: leaf, priority: priority);
    children.forEach((String k, JsonServerNode v) => c.children[k] = v.copy());
    return c;
  }

  /// The export JSON: what a reader sees, or with [hidden] what the server sends (an emptied node
  /// as `{".priority": p}`). Children in priority order, as the client's `Node.toJson`. Null for
  /// no data.
  Object? toJson({required bool hidden}) {
    if (leaf != null) {
      return priority == null
          ? leaf
          : <String, Object?>{'.value': leaf, '.priority': priority};
    }
    final Map<String, Object?> m = <String, Object?>{};
    for (final MapEntry<String, JsonServerNode> e in byPriority(children)) {
      final Object? json = e.value.toJson(hidden: hidden);
      if (json != null) {
        m[e.key] = json;
      }
    }
    if (m.isEmpty && (!hidden || priority == null)) {
      return null;
    }
    if (priority != null) {
      m['.priority'] = priority;
    }
    return m;
  }

  /// The JS SDK's hash of the node, kept priorities included.
  String hash() {
    final StringBuffer text = StringBuffer();
    final Object? p = priority;
    if (p != null) {
      text.write('priority:${_hashText(p)}:');
    }
    final Object? value = leaf;
    if (value != null) {
      text.write(_hashText(value));
      return _sha1(text.toString());
    }
    for (final MapEntry<String, JsonServerNode> e in byPriority(children)) {
      final String h = e.value.hash();
      if (h.isNotEmpty) {
        text.write(':${e.key}:$h');
      }
    }
    return text.isEmpty ? '' : _sha1(text.toString());
  }

  /// The database's key order: integer-like keys first, by value, then the others.
  static int compareKeys(String a, String b) {
    if (a == b) {
      return 0;
    }
    final int? x = _intKey(a);
    final int? y = _intKey(b);
    if (x != null && y != null) {
      return x == y ? a.length - b.length : x.compareTo(y);
    }
    if (x != null || y != null) {
      return x != null ? -1 : 1;
    }
    return a.compareTo(b);
  }

  /// The priority order: no priority, numbers, strings.
  static int comparePriority(Object? a, Object? b) {
    int rank(Object? p) => p == null ? 0 : (p is num ? 1 : 2);
    final int byRank = rank(a) - rank(b);
    if (byRank != 0 || a == null) {
      return byRank;
    }
    return a is num ? a.compareTo(b! as num) : '$a'.compareTo('$b');
  }

  /// [children] in priority order, then key order.
  static List<MapEntry<String, JsonServerNode>> byPriority(
    Map<String, JsonServerNode> children,
  ) => children.entries.toList()
    ..sort((
      MapEntry<String, JsonServerNode> a,
      MapEntry<String, JsonServerNode> b,
    ) {
      final int c = comparePriority(a.value.priority, b.value.priority);
      return c != 0 ? c : compareKeys(a.key, b.key);
    });

  static final RegExp _intPattern = RegExp(r'^-?\d{1,10}$');

  static int? _intKey(String key) {
    if (!_intPattern.hasMatch(key)) {
      return null;
    }
    final int value = int.parse(key);
    return value >= -2147483648 && value <= 2147483647 ? value : null;
  }

  static String _sha1(String text) =>
      base64.encode(sha1.convert(utf8.encode(text)).bytes);

  static String _ieee754(num value) {
    final ByteData bytes = ByteData(8)..setFloat64(0, value.toDouble());
    return <String>[
      for (int i = 0; i < 8; i++)
        bytes.getUint8(i).toRadixString(16).padLeft(2, '0'),
    ].join();
  }

  static String _hashText(Object value) => switch (value) {
    final num n => 'number:${_ieee754(n)}',
    final bool b => 'boolean:$b',
    final String s => 'string:$s',
    // A server value placeholder hashes as JS concatenates an object.
    _ => 'string:[object Object]',
  };
}

/// The server's data and its write rules.
final class JsonServerModel {
  /// A server holding [json] (export form).
  JsonServerModel([Object? json]) : root = JsonServerNode.fromJson(json);

  JsonServerModel._(this.root);

  /// The root node; null when the database is empty.
  JsonServerNode? root;

  /// A deep copy.
  JsonServerModel copy() => JsonServerModel._(root?.copy());

  /// The keys of [path] (`a/b`, `/a/b`, `/` or empty for the root).
  static List<String> keysOf(String path) =>
      path.split('/').where((String k) => k.isNotEmpty).toList();

  /// The node at [path], or null.
  JsonServerNode? at(String path) => _get(root, keysOf(path));

  /// The export JSON at [path]: what a reader sees, or with [hidden] what the server sends.
  Object? export(String path, {required bool hidden}) =>
      at(path)?.toJson(hidden: hidden);

  /// The hash of the node at [path] (`''` for none).
  String hash(String path) => at(path)?.hash() ?? '';

  /// Whether a set of [data] at [path] is a null priority that changes nothing: the node is
  /// missing or has no priority. The server answers it ok and pushes it to no listener
  /// (production run 13, 2026-11-26, check 40).
  bool changesNothing(String path, Object? data, {bool merge = false}) {
    final List<String> at = keysOf(path);
    if (merge || data != null || at.isEmpty || at.last != '.priority') {
      return false;
    }
    return _get(root, at.sublist(0, at.length - 1))?.priority == null;
  }

  /// Applies a set (or with [merge] an update of the children in the map [data]) at [path];
  /// false, and nothing changed, when the server refuses it: a priority on a node that does not
  /// exist before the write (check 39 Q12), except a null one, in an update (Q14) or as a set
  /// (check 40).
  bool write(String path, Object? data, {bool merge = false}) {
    final List<String> at = keysOf(path);
    final Map<String, Object?> entries = merge
        ? <String, Object?>{
            for (final MapEntry<Object?, Object?> e
                in (data! as Map<Object?, Object?>).entries)
              '${e.key}': e.value,
          }
        : <String, Object?>{'': data};
    final List<(List<String>, Object?)> children = <(List<String>, Object?)>[];
    final List<(List<String>, Object?)> priorities =
        <(List<String>, Object?)>[];
    for (final MapEntry<String, Object?> e in entries.entries) {
      final List<String> full = <String>[...at, ...keysOf(e.key)];
      if (full.isNotEmpty && full.last == '.priority') {
        final List<String> owner = full.sublist(0, full.length - 1);
        if (e.value != null && _get(root, owner) == null) {
          return false;
        }
        priorities.add((owner, e.value));
      } else {
        children.add((full, e.value));
      }
    }
    for (final (List<String> full, Object? value) in children) {
      root = _put(root, full, 0, JsonServerNode.fromJson(value));
    }
    // Parents first, whatever the key order (check 39 Q10, F1 to F9).
    mergeSort(
      priorities,
      compare: ((List<String>, Object?) a, (List<String>, Object?) b) =>
          a.$1.length - b.$1.length,
    );
    for (final (List<String> owner, Object? value) in priorities) {
      root = _putPriority(root, owner, 0, value);
    }
    return true;
  }

  static JsonServerNode? _get(JsonServerNode? n, List<String> keys) {
    JsonServerNode? at = n;
    for (final String k in keys) {
      at = at?.children[k];
    }
    return at;
  }

  /// [n] with [value] at [keys] from [i]; a node left with nothing is removed.
  static JsonServerNode? _put(
    JsonServerNode? n,
    List<String> keys,
    int i,
    JsonServerNode? value,
  ) {
    if (i == keys.length) {
      return value;
    }
    if ((n == null || n.leaf != null) && value == null) {
      // Nothing to remove below a leaf or below nothing.
      return n;
    }
    final JsonServerNode node = n == null
        ? JsonServerNode()
        // A value below a leaf replaces it with children that keep its priority.
        : n.leaf != null
        ? JsonServerNode(priority: n.priority)
        : n;
    final JsonServerNode? child = _put(
      node.children[keys[i]],
      keys,
      i + 1,
      value,
    );
    if (child == null) {
      node.children.remove(keys[i]);
    } else {
      node.children[keys[i]] = child;
    }
    return node.isAbsent ? null : node;
  }

  /// [n] with [priority] on the node at [keys] from [i], when that node exists (it then has a
  /// value or holds hidden state).
  static JsonServerNode? _putPriority(
    JsonServerNode? n,
    List<String> keys,
    int i,
    Object? priority,
  ) {
    if (n == null) {
      return null;
    }
    if (i == keys.length) {
      n.priority = priority;
      return n.isAbsent ? null : n;
    }
    final JsonServerNode? child = _putPriority(
      n.children[keys[i]],
      keys,
      i + 1,
      priority,
    );
    if (child == null) {
      n.children.remove(keys[i]);
    } else {
      n.children[keys[i]] = child;
    }
    return n.isAbsent ? null : n;
  }
}
