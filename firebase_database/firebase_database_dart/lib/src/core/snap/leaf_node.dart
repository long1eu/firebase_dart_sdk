/// Leaf values. JS: `core/snap/LeafNode.ts`; Android: `snapshot/LeafNode.java` and its subclasses
/// `BooleanNode`, `LongNode`, `DoubleNode`, `StringNode`, `DeferredValueNode` (one class here).
library;

import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/index.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/priority.dart';
import 'package:firebase_database_dart/src/core/util/hash.dart';
import 'package:firebase_database_dart/src/core/util/numbers.dart';

/// The kind of a leaf, in sort order: deferred server values, booleans, numbers, strings.
enum LeafType {
  /// A server value map such as `{'.sv': 'timestamp'}`.
  deferredValue,

  /// A boolean.
  boolean,

  /// A number (`num`, see `numbers.dart`).
  number,

  /// A string.
  string,
}

/// The read form of a stored number, see [normalizeNumber].
num _readNumber(num value) => normalizeNumber(value);

/// A leaf: a boolean, a number, a string or an unresolved server value map, with a priority.
final class LeafNode implements Node {
  /// Creates a leaf of [value] (`bool`, `num`, `String` or a server value `Map`) with
  /// [priorityNode] (empty by default).
  ///
  /// Numbers are kept as given (the server keeps `1.0`, `-0.0` and large integers); [value] reads
  /// them in the normalised form and [hash] goes through the double form, so `1` and `1.0` hash
  /// the same.
  factory LeafNode(Object value, [Node? priorityNode]) {
    final Node priority = priorityNode ?? ChildrenNode.empty;
    if (value is Map) {
      validatePriorityNode(priority);
      return _DeferredLeafNode(value, priority);
    }
    if (value is! bool && value is! num && value is! String) {
      throw ArgumentError.value(value, 'value', 'Unsupported leaf value type');
    }
    validatePriorityNode(priority);
    return LeafNode._(value, priority);
  }

  LeafNode._(this._raw, this._priority);

  // Three fields: a large snapshot is mostly leaves, and every field here is 8 bytes in each
  // of them. The kind is read from the value, the hash code is computed on demand, and only a
  // server value (its own class below) keeps a second form of its value.

  /// The value as stored (numbers as given).
  final Object _raw;

  final Node _priority;

  String? _lazyHash;

  /// The value: numbers in the read form (`int` when integral within 2^53, negative zero kept),
  /// a server value map unmodifiable at every depth (the same object on every read).
  @override
  Object get value {
    final Object raw = _raw;
    return raw is num ? _readNumber(raw) : raw;
  }

  static Object? _freeze(Object? json) => switch (json) {
    final Map<Object?, Object?> m =>
      Map<String, Object?>.unmodifiable(<String, Object?>{
        for (final MapEntry<Object?, Object?> e in m.entries)
          '${e.key}': _freeze(e.value),
      }),
    final List<Object?> l => List<Object?>.unmodifiable(l.map(_freeze)),
    _ => json,
  };

  static Object? _copy(Object? json) => switch (json) {
    final Map<Object?, Object?> m => <String, Object?>{
      for (final MapEntry<Object?, Object?> e in m.entries)
        '${e.key}': _copy(e.value),
    },
    final List<Object?> l => <Object?>[for (final Object? e in l) _copy(e)],
    _ => json,
  };

  /// The kind of [value].
  LeafType get leafType {
    final Object raw = _raw;
    if (raw is String) {
      return LeafType.string;
    } else if (raw is num) {
      return LeafType.number;
    } else if (raw is bool) {
      return LeafType.boolean;
    }
    return LeafType.deferredValue;
  }

  @override
  bool get isLeafNode => true;

  @override
  Node get priority => _priority;

  @override
  Node updatePriority(Node newPriority) => LeafNode(_raw, newPriority);

  @override
  Node getImmediateChild(ChildKey key) =>
      key.isPriorityKey ? _priority : ChildrenNode.empty;

  @override
  Node getChild(Path path) {
    if (path.isEmpty) {
      return this;
    } else if (path.front!.isPriorityKey) {
      return _priority;
    } else {
      return ChildrenNode.empty;
    }
  }

  @override
  ChildKey? getPredecessorChildKey(ChildKey key, Node child, Index index) =>
      null;

  @override
  Node updateImmediateChild(ChildKey key, Node newChild) {
    if (key.isPriorityKey) {
      return updatePriority(newChild);
    } else if (newChild.isEmpty) {
      return this;
    } else {
      return ChildrenNode.empty
          .updateImmediateChild(key, newChild)
          .updatePriority(_priority);
    }
  }

  @override
  Node updateChild(Path path, Node newChild) {
    final ChildKey? front = path.front;
    if (front == null) {
      return newChild;
    } else if (newChild.isEmpty && !front.isPriorityKey) {
      return this;
    } else {
      assert(
        !front.isPriorityKey || path.length == 1,
        '.priority must be the last token in a path',
      );
      return updateImmediateChild(
        front,
        ChildrenNode.empty.updateChild(path.popFront(), newChild),
      );
    }
  }

  @override
  bool hasChild(ChildKey key) => false;

  @override
  bool get isEmpty => false;

  @override
  int get numChildren => 0;

  @override
  bool forEachChild(Index index, ChildVisitor action) => false;

  @override
  Object? toJson({bool exportFormat = false}) {
    if (exportFormat && !_priority.isEmpty) {
      return <String, Object?>{
        '.value': _copyRaw(),
        '.priority': _priority.toJson(exportFormat: true),
      };
    }
    if (exportFormat) {
      return _copyRaw();
    }
    return switch (_raw) {
      final num n => _readNumber(n),
      _ => _copy(_raw),
    };
  }

  Object _copyRaw() => _copy(_raw)!;

  @override
  String hash() => _lazyHash ??= sha1Base64(hashText());

  /// The text the hash is computed from (`number:<ieee754>`, `string:<s>`, with the priority
  /// prefix); the compound hash reuses it.
  String hashText() {
    final StringBuffer toHash = StringBuffer();
    if (!_priority.isEmpty) {
      toHash
        ..write('priority:')
        ..write(priorityHashText(_priority.value!))
        ..write(':');
    }
    final Object raw = _raw;
    switch (leafType) {
      case LeafType.number:
        toHash
          ..write('number:')
          ..write(doubleToIeee754String((raw as num).toDouble()));
      case LeafType.string:
        toHash
          ..write('string:')
          ..write(raw);
      case LeafType.boolean:
        toHash
          ..write('boolean:')
          ..write(raw);
      case LeafType.deferredValue:
        // JS `typeof {}` and `'' + {}`.
        toHash.write('object:[object Object]');
    }
    return toHash.toString();
  }

  @override
  int compareTo(Node other) {
    if (other.isEmpty) {
      return 1;
    } else if (other is ChildrenNode) {
      return -1;
    }
    final LeafNode otherLeaf = other as LeafNode;
    if (leafType != otherLeaf.leafType) {
      return leafType.index - otherLeaf.leafType.index;
    }
    switch (leafType) {
      case LeafType.deferredValue:
        // Deferred values are all equal.
        return 0;
      case LeafType.boolean:
        final bool a = _raw as bool;
        final bool b = otherLeaf._raw as bool;
        return a == b ? 0 : (a ? 1 : -1);
      case LeafType.number:
        // -0.0 equals 0 (num.compareTo would order them); exact for large ints, as the server.
        return compareNumbers(_raw as num, otherLeaf._raw as num);
      case LeafType.string:
        final int cmp = (_raw as String).compareTo(otherLeaf._raw as String);
        return cmp < 0 ? -1 : (cmp == 0 ? 0 : 1);
    }
  }

  @override
  Node withIndex(Index index) => this;

  @override
  bool isIndexed(Index index) => true;

  /// JS `equals`: the same value (`===`, so server value maps only by identity) and an equal
  /// priority.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is LeafNode &&
        leafType == other.leafType &&
        (_raw is num
            ? compareNumbers(_raw, other._raw as num) == 0
            : _raw == other._raw) &&
        _priority == other._priority;
  }

  @override
  int get hashCode => Object.hash(
    _raw is num ? _raw.toDouble() : _raw,
    _priority.isEmpty ? 0 : _priority.hashCode,
  );

  @override
  String toString() => _priority.isEmpty
      ? 'LeafNode($_raw)'
      : 'LeafNode($_raw, priority: $_priority)';
}

/// A leaf holding a server value map; [value] is its unmodifiable form, made once.
final class _DeferredLeafNode extends LeafNode {
  _DeferredLeafNode(Map<Object?, Object?> super.raw, super.priority)
    : super._();

  Object? _lazyValue;

  @override
  Object get value =>
      _lazyValue ??= LeafNode._freeze(_raw as Map<Object?, Object?>)!;
}
