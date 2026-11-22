/// A sparse tree of nodes, for the local onDisconnect writes. JS: `core/SparseSnapshotTree.ts`;
/// Android: `core/SparseSnapshotTree.java`.
library;

import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';

/// A mutable tree where a node remembered at a path covers everything below it.
final class SparseSnapshotTree {
  /// Creates an empty tree.
  SparseSnapshotTree();

  /// The node at [path], or null when nothing covers it.
  Node? find(Path path) => throw UnimplementedError();

  /// Remembers [data] at [path], replacing what was below.
  void remember(Path path, Node data) => throw UnimplementedError();

  /// Forgets [path] and below; returns whether the tree became empty.
  bool forget(Path path) => throw UnimplementedError();

  /// Calls [fn] with each remembered node and its path (prefixed with [prefixPath]).
  void forEachTree(Path prefixPath, void Function(Path path, Node node) fn) =>
      throw UnimplementedError();

  /// Calls [fn] with each immediate child tree.
  void forEachChild(void Function(ChildKey key, SparseSnapshotTree tree) fn) =>
      throw UnimplementedError();
}
