/// The data of the `.info` tree. JS: `core/SnapshotHolder.ts`; Android: `core/SnapshotHolder.java`.
library;

import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';

/// A mutable holder of one root node.
final class SnapshotHolder {
  /// Creates a holder of the empty node.
  SnapshotHolder();

  /// The node at [path].
  Node getNode(Path path) => throw UnimplementedError();

  /// Replaces the node at [path] with [newSnapshotNode].
  void updateSnapshot(Path path, Node newSnapshotNode) => throw UnimplementedError();
}
