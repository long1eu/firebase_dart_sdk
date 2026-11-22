/// The node interface. JS: `core/snap/Node.ts` (`Node`); Android: `snapshot/Node.java`.
///
/// Nodes are immutable. The only implementations are [LeafNode] and [ChildrenNode] (with its
/// `MaxNode` sentinel).
library;

import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/index.dart';
import 'package:firebase_database_dart/src/core/snap/leaf_node.dart';

/// Visits a child; returning true stops the iteration.
typedef ChildVisitor = bool Function(ChildKey key, Node child);

/// An immutable database value: a leaf or a set of children, each with a priority.
abstract interface class Node implements Comparable<Node> {
  /// Whether this is a leaf.
  bool get isLeafNode;

  /// The priority node (empty when there is none).
  Node get priority;

  /// This node with [newPriority].
  Node updatePriority(Node newPriority);

  /// The child [key] (empty when absent); `.priority` gives the priority.
  Node getImmediateChild(ChildKey key);

  /// The node at [path] below this one (empty when absent).
  Node getChild(Path path);

  /// The key of the child before [key] (whose node is [child]) in [index] order, or null.
  ChildKey? getPredecessorChildKey(ChildKey key, Node child, Index index);

  /// This node with child [key] replaced by [newChild] (removed when empty).
  Node updateImmediateChild(ChildKey key, Node newChild);

  /// This node with the node at [path] replaced by [newChild].
  Node updateChild(Path path, Node newChild);

  /// Whether child [key] exists.
  bool hasChild(ChildKey key);

  /// Whether this node is empty (no value, no children).
  bool get isEmpty;

  /// The number of children.
  int get numChildren;

  /// Visits the children in [index] order until [action] returns true; returns whether it did.
  bool forEachChild(Index index, ChildVisitor action);

  /// The JSON value: maps, numbers ([num] as `int` or `double` per the number rules), strings,
  /// booleans or null. With [exportFormat], priorities appear as `.priority` and leaves with a
  /// priority as `{'.value': v, '.priority': p}` (the put wire form).
  Object? toJson({bool exportFormat = false});

  /// The base64 SHA-1 hash of the node, equal to the JS SDK's for the same data.
  String hash();

  /// This node with an index on [index] added (children nodes only).
  Node withIndex(Index index);

  /// Whether [index] is already built.
  bool isIndexed(Index index);
}
