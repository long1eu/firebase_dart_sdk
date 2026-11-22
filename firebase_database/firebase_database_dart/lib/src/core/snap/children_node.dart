/// Nodes with children, the empty node and the max sentinel. JS: `core/snap/ChildrenNode.ts`
/// (`ChildrenNode`, `MaxNode`, `MAX_NODE`, `EMPTY_NODE`); Android: `snapshot/ChildrenNode.java`,
/// `snapshot/EmptyNode.java`, `snapshot/IndexedNode.java` (whose role [IndexMap] takes here).
library;

import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/index_map.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/index.dart';
import 'package:firebase_database_dart/src/core/snap/named_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/util/sorted_map.dart';

/// A node with children (or none: the empty node), a priority and lazily built indexes.
class ChildrenNode implements Node {
  /// Creates a node of [children] with [priorityNode] (empty when null) and [indexMap].
  factory ChildrenNode(
    SortedMap<ChildKey, Node> children,
    Node? priorityNode,
    IndexMap indexMap,
  ) => throw UnimplementedError();

  ChildrenNode._();

  /// The empty node (no value, no children, no priority).
  static ChildrenNode get empty => throw UnimplementedError();

  /// The children by key.
  SortedMap<ChildKey, Node> get children => throw UnimplementedError();

  /// The built indexes.
  IndexMap get indexMap => throw UnimplementedError();

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

  /// The key of the first child in [index] order, or null.
  ChildKey? firstChildKey(Index index) => throw UnimplementedError();

  /// The first child in [index] order, or null.
  NamedNode? firstChild(Index index) => throw UnimplementedError();

  /// The key of the last child in [index] order, or null.
  ChildKey? lastChildKey(Index index) => throw UnimplementedError();

  /// The last child in [index] order, or null.
  NamedNode? lastChild(Index index) => throw UnimplementedError();

  /// The children in [index] order.
  Iterable<NamedNode> childrenInOrder(Index index) => throw UnimplementedError();

  /// The children in [index] order starting at the first post not smaller than [start].
  Iterable<NamedNode> childrenFrom(NamedNode start, Index index) => throw UnimplementedError();

  /// The children in reverse [index] order.
  Iterable<NamedNode> reverseChildren(Index index) => throw UnimplementedError();

  /// The children in reverse [index] order starting at the last post not greater than [start].
  Iterable<NamedNode> reverseChildrenFrom(NamedNode start, Index index) =>
      throw UnimplementedError();

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

/// The node that sorts after every other node; used for the max post of indexes.
final class MaxNode extends ChildrenNode {
  MaxNode._() : super._();

  /// The single instance.
  static MaxNode get instance => throw UnimplementedError();

  @override
  int compareTo(Node other) => throw UnimplementedError();

  @override
  bool operator ==(Object other) => throw UnimplementedError();

  @override
  int get hashCode => throw UnimplementedError();

  @override
  Node get priority => throw UnimplementedError();

  @override
  Node getImmediateChild(ChildKey key) => throw UnimplementedError();

  @override
  bool get isEmpty => throw UnimplementedError();
}
