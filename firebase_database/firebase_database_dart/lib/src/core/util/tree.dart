/// A mutable tree with parent links, for the transaction queues. JS: `core/util/Tree.ts` (`Tree`,
/// `TreeNode`); Android: `core/utilities/Tree.java`, `core/utilities/TreeNode.java`.
library;

import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';

/// The storage of one tree node: children by key and an optional value.
final class TreeNode<T> {
  /// Creates an empty node.
  TreeNode();

  /// The children.
  final Map<ChildKey, TreeNode<T>> children = <ChildKey, TreeNode<T>>{};

  /// The value, or null.
  T? value;
}

/// A view of a [TreeNode] with its [name] and [parent], so changes propagate up (empty subtrees
/// are removed from their parent).
final class Tree<T> {
  /// Creates a tree; the root has no name and no parent.
  Tree({this.name, this.parent, TreeNode<T>? node})
    : node = node ?? TreeNode<T>();

  /// The key under the parent, or null for the root.
  final ChildKey? name;

  /// The parent, or null for the root.
  final Tree<T>? parent;

  /// The storage.
  final TreeNode<T> node;

  /// The subtree at [path], created on demand.
  Tree<T> subTree(Path path) => throw UnimplementedError();

  /// The value, or null.
  T? get value => throw UnimplementedError();

  /// Sets the value and updates the parents.
  set value(T? value) => throw UnimplementedError();

  /// Whether there are children.
  bool get hasChildren => throw UnimplementedError();

  /// Whether there is no value and no child.
  bool get isEmpty => throw UnimplementedError();

  /// Calls [action] on each child.
  void forEachChild(void Function(Tree<T> child) action) =>
      throw UnimplementedError();

  /// Calls [action] on each descendant, depth first.
  void forEachDescendant(
    void Function(Tree<T> tree) action, {
    bool includeSelf = false,
    bool childrenFirst = false,
  }) => throw UnimplementedError();

  /// Calls [action] on each ancestor until it returns true; returns whether it did.
  bool forEachAncestor(
    bool Function(Tree<T> tree) action, {
    bool includeSelf = false,
  }) => throw UnimplementedError();

  /// Calls [action] on the nearest descendants that have a value.
  void forEachImmediateDescendantWithValue(
    void Function(Tree<T> tree) action,
  ) => throw UnimplementedError();

  /// The path from the root.
  Path get path => throw UnimplementedError();
}
