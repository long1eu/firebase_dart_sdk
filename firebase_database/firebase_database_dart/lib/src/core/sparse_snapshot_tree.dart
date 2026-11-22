/// A sparse tree of nodes, for the local onDisconnect writes. JS: `core/SparseSnapshotTree.ts`;
/// Android: `core/SparseSnapshotTree.java`.
library;

import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/priority_index.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';

/// A mutable tree where a node remembered at a path covers everything below it.
final class SparseSnapshotTree {
  /// Creates an empty tree.
  SparseSnapshotTree();

  Node? _value;

  final Map<ChildKey, SparseSnapshotTree> _children =
      <ChildKey, SparseSnapshotTree>{};

  /// The node at [path], or null when nothing covers it. JS: `sparseSnapshotTreeFind` (Android
  /// has no equivalent).
  Node? find(Path path) {
    final Node? value = _value;
    if (value != null) {
      return value.getChild(path);
    } else if (!path.isEmpty && _children.isNotEmpty) {
      final SparseSnapshotTree? childTree = _children[path.front!];
      return childTree?.find(path.popFront());
    }
    return null;
  }

  /// Remembers [data] at [path], replacing what was below. Android:
  /// `SparseSnapshotTree.remember`.
  void remember(Path path, Node data) {
    final Node? value = _value;
    if (path.isEmpty) {
      _value = data;
      _children.clear();
    } else if (value != null) {
      _value = value.updateChild(path, data);
    } else {
      _children
          .putIfAbsent(path.front!, SparseSnapshotTree.new)
          .remember(path.popFront(), data);
    }
  }

  /// Forgets [path] and below; returns whether the tree became empty. Android:
  /// `SparseSnapshotTree.forget`, re-remembering the children of a split value at their own
  /// key as JS `sparseSnapshotTreeForget` does.
  bool forget(Path path) {
    if (path.isEmpty) {
      _value = null;
      _children.clear();
      return true;
    }
    final Node? value = _value;
    if (value != null) {
      if (value.isLeafNode) {
        // A non-empty path below a leaf leads nowhere.
        return false;
      }
      _value = null;
      value.forEachChild(priorityIndex, (ChildKey key, Node child) {
        remember(Path.fromKeys(<ChildKey>[key]), child);
        return false;
      });
      // The value is split into children; forget again to hit the next case.
      return forget(path);
    } else if (_children.isNotEmpty) {
      final ChildKey childKey = path.front!;
      final SparseSnapshotTree? child = _children[childKey];
      if (child != null) {
        final bool safeToRemove = child.forget(path.popFront());
        if (safeToRemove) {
          _children.remove(childKey);
        }
      }
      return _children.isEmpty;
    }
    return true;
  }

  /// Calls [fn] with each remembered node and its path (prefixed with [prefixPath]). Android:
  /// `SparseSnapshotTree.forEachTree`.
  void forEachTree(Path prefixPath, void Function(Path path, Node node) fn) {
    final Node? value = _value;
    if (value != null) {
      fn(prefixPath, value);
    } else {
      forEachChild((ChildKey key, SparseSnapshotTree tree) {
        tree.forEachTree(prefixPath.child(key), fn);
      });
    }
  }

  /// Calls [fn] with each immediate child tree. Android: `SparseSnapshotTree.forEachChild`.
  void forEachChild(void Function(ChildKey key, SparseSnapshotTree tree) fn) {
    _children.forEach(fn);
  }
}
