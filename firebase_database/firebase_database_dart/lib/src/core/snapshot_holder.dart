/// The data of the `.info` tree. JS: `core/SnapshotHolder.ts`; Android: `core/SnapshotHolder.java`.
library;

import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';

/// A mutable holder of one root node.
final class SnapshotHolder {
  /// Creates a holder of the empty node.
  SnapshotHolder();

  Node _rootNode = ChildrenNode.empty;

  /// The node at [path]. Android: `SnapshotHolder.getNode`.
  Node getNode(Path path) => _rootNode.getChild(path);

  /// Replaces the node at [path] with [newSnapshotNode]. Android: `SnapshotHolder.update`.
  void updateSnapshot(Path path, Node newSnapshotNode) {
    _rootNode = _rootNode.updateChild(path, newSnapshotNode);
  }
}
