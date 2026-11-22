/// A child key with its node. JS: `core/snap/Node.ts` (`NamedNode`); Android:
/// `snapshot/NamedNode.java`.
library;

import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';

/// A [Node] together with its [name]; the element of index sorted maps and of query bounds
/// ("posts").
final class NamedNode {
  /// Creates a named node.
  const NamedNode(this.name, this.node);

  /// The post before every other post.
  static NamedNode get min => _min;

  static final NamedNode _min = NamedNode(ChildKey.min, ChildrenNode.empty);

  /// The post after every other post.
  static NamedNode get max => _max;

  static final NamedNode _max = NamedNode(ChildKey.max, MaxNode.instance);

  /// The child key.
  final ChildKey name;

  /// The node.
  final Node node;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NamedNode && name == other.name && node == other.node;

  @override
  int get hashCode => Object.hash(name, node);

  @override
  String toString() => 'NamedNode(${name.name}, $node)';
}
