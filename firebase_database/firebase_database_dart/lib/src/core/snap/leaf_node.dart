/// Leaf values. JS: `core/snap/LeafNode.ts`; Android: `snapshot/LeafNode.java` and its subclasses
/// `BooleanNode`, `LongNode`, `DoubleNode`, `StringNode`, `DeferredValueNode` (one class here).
library;

import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/index.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';

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

/// A leaf: a boolean, a number, a string or an unresolved server value map, with a priority.
final class LeafNode implements Node {
  /// Creates a leaf of [value] (`bool`, `num`, `String` or a server value `Map`) with
  /// [priorityNode] (empty by default).
  factory LeafNode(Object value, [Node? priorityNode]) => throw UnimplementedError();

  /// The value; numbers are `num` normalised by `normalizeNumber`.
  Object get value => throw UnimplementedError();

  /// The kind of [value].
  LeafType get leafType => throw UnimplementedError();

  @override
  bool get isLeafNode => throw UnimplementedError();

  @override
  Node get priority => throw UnimplementedError();

  @override
  Node updatePriority(Node newPriority) => throw UnimplementedError();

  @override
  Node getImmediateChild(ChildKey key) => throw UnimplementedError();

  @override
  Node getChild(Path path) => throw UnimplementedError();

  @override
  ChildKey? getPredecessorChildKey(ChildKey key, Node child, Index index) =>
      throw UnimplementedError();

  @override
  Node updateImmediateChild(ChildKey key, Node newChild) => throw UnimplementedError();

  @override
  Node updateChild(Path path, Node newChild) => throw UnimplementedError();

  @override
  bool hasChild(ChildKey key) => throw UnimplementedError();

  @override
  bool get isEmpty => throw UnimplementedError();

  @override
  int get numChildren => throw UnimplementedError();

  @override
  bool forEachChild(Index index, ChildVisitor action) => throw UnimplementedError();

  @override
  Object? toJson({bool exportFormat = false}) => throw UnimplementedError();

  @override
  String hash() => throw UnimplementedError();

  /// The text the hash is computed from (`number:<ieee754>`, `string:<s>`, with the priority
  /// prefix); the compound hash reuses it.
  String hashText() => throw UnimplementedError();

  @override
  int compareTo(Node other) => throw UnimplementedError();

  @override
  Node withIndex(Index index) => throw UnimplementedError();

  @override
  bool isIndexed(Index index) => throw UnimplementedError();

  @override
  bool operator ==(Object other) => throw UnimplementedError();

  @override
  int get hashCode => throw UnimplementedError();

  @override
  String toString() => throw UnimplementedError();
}
