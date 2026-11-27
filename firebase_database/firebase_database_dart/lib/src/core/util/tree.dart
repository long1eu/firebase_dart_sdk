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

  /// The subtree at [path], created on demand: missing nodes are not attached until a value is
  /// set below them. Android `Tree.subTree`; JS `treeSubTree`.
  Tree<T> subTree(Path path) {
    Tree<T> child = this;
    Path rest = path;
    ChildKey? next = rest.front;
    while (next != null) {
      final TreeNode<T> childNode = child.node.children[next] ?? TreeNode<T>();
      child = Tree<T>(name: next, parent: child, node: childNode);
      rest = rest.popFront();
      next = rest.front;
    }
    return child;
  }

  /// The value, or null. Android `Tree.getValue`; JS `treeGetValue`.
  T? get value => node.value;

  /// Sets the value and updates the parents. Android `Tree.setValue`; JS `treeSetValue`.
  set value(T? value) {
    node.value = value;
    _updateParents();
  }

  /// Whether there are children. Android `Tree.hasChildren`; JS `treeHasChildren`.
  bool get hasChildren => node.children.isNotEmpty;

  /// Whether there is no value and no child. Android `Tree.isEmpty`; JS `treeIsEmpty`.
  bool get isEmpty => node.value == null && node.children.isEmpty;

  /// Calls [action] on each child, over a copy of the children so [action] may change them.
  /// Android `Tree.forEachChild`; JS `treeForEachChild`.
  void forEachChild(void Function(Tree<T> child) action) {
    final List<MapEntry<ChildKey, TreeNode<T>>> entries = node.children.entries
        .toList();
    for (final MapEntry<ChildKey, TreeNode<T>> entry in entries) {
      action(Tree<T>(name: entry.key, parent: this, node: entry.value));
    }
  }

  /// Calls [action] on each descendant, depth first; with [includeSelf] on this tree too, before
  /// its children or, with [childrenFirst], after them. Android `Tree.forEachDescendant`; JS
  /// `treeForEachDescendant`.
  void forEachDescendant(
    void Function(Tree<T> tree) action, {
    bool includeSelf = false,
    bool childrenFirst = false,
  }) {
    if (includeSelf && !childrenFirst) {
      action(this);
    }
    forEachChild(
      (Tree<T> child) => child.forEachDescendant(
        action,
        includeSelf: true,
        childrenFirst: childrenFirst,
      ),
    );
    if (includeSelf && childrenFirst) {
      action(this);
    }
  }

  /// Calls [action] on each ancestor (from the parent, or this tree with [includeSelf], up to the
  /// root) until it returns true; returns whether it did. Android `Tree.forEachAncestor`; JS
  /// `treeForEachAncestor`.
  bool forEachAncestor(
    bool Function(Tree<T> tree) action, {
    bool includeSelf = false,
  }) {
    Tree<T>? tree = includeSelf ? this : parent;
    while (tree != null) {
      if (action(tree)) {
        return true;
      }
      tree = tree.parent;
    }
    return false;
  }

  /// Calls [action] on the nearest descendants that have a value (not below them). JS
  /// `treeForEachImmediateDescendantWithValue` (Android has none).
  void forEachImmediateDescendantWithValue(void Function(Tree<T> tree) action) {
    forEachChild((Tree<T> child) {
      if (child.value != null) {
        action(child);
      } else {
        child.forEachImmediateDescendantWithValue(action);
      }
    });
  }

  /// The path from the root. Android `Tree.getPath`; JS `treeGetPath`.
  Path get path {
    final List<ChildKey> keys = <ChildKey>[];
    Tree<T>? tree = this;
    while (tree != null && tree.name != null) {
      keys.add(tree.name!);
      tree = tree.parent;
    }
    return Path.fromKeys(keys.reversed.toList(growable: false));
  }

  void _updateParents() {
    parent?._updateChild(name!, this);
  }

  void _updateChild(ChildKey childName, Tree<T> child) {
    final bool childEmpty = child.isEmpty;
    final bool childExists = node.children.containsKey(childName);
    if (childEmpty && childExists) {
      node.children.remove(childName);
      _updateParents();
    } else if (!childEmpty && !childExists) {
      node.children[childName] = child.node;
      _updateParents();
    }
  }
}
