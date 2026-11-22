/// A child key with its node. JS: `core/snap/Node.ts` (`NamedNode`); Android:
/// `snapshot/NamedNode.java`.
library;

import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';

/// A [Node] together with its [name]; the element of index sorted maps and of query bounds
/// ("posts").
final class NamedNode {
  /// Creates a named node.
  const NamedNode(this.name, this.node);

  /// The post before every other post.
  static NamedNode get min => throw UnimplementedError();

  /// The post after every other post.
  static NamedNode get max => throw UnimplementedError();

  /// The child key.
  final ChildKey name;

  /// The node.
  final Node node;

  @override
  bool operator ==(Object other) => throw UnimplementedError();

  @override
  int get hashCode => throw UnimplementedError();

  @override
  String toString() => throw UnimplementedError();
}
