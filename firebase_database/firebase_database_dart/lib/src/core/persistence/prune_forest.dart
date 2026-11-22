/// Which cached paths to prune and which to keep. JS: none; Android:
/// `core/persistence/PruneForest.java`.
library;

import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/util/immutable_tree.dart';

/// A tree of prune (true) and keep (false) marks; a mark applies to its whole subtree unless a
/// deeper mark overrides it.
final class PruneForest {
  /// An empty forest (prunes nothing).
  factory PruneForest() => throw UnimplementedError();

  /// Wraps [forest].
  const PruneForest.fromTree(this.forest);

  /// The marks.
  final ImmutableTree<bool> forest;

  /// Whether anything is pruned.
  bool prunesAnything() => throw UnimplementedError();

  /// Whether data below [path] that is not kept should be pruned.
  bool shouldPruneUnkeptDescendants(Path path) => throw UnimplementedError();

  /// Whether [path] is kept.
  bool shouldKeep(Path path) => throw UnimplementedError();

  /// Whether any mark lies on or below [path].
  bool affectsPath(Path path) => throw UnimplementedError();

  /// The forest at child [key].
  PruneForest child(ChildKey key) => throw UnimplementedError();

  /// The forest at [path].
  PruneForest childAtPath(Path path) => throw UnimplementedError();

  /// Folds [fn] over the kept paths.
  R foldKeptNodes<R>(R initial, R Function(Path path, R accumulator) fn) =>
      throw UnimplementedError();

  /// With [path] pruned.
  PruneForest prune(Path path) => throw UnimplementedError();

  /// With [path] kept.
  PruneForest keep(Path path) => throw UnimplementedError();

  /// With each of [children] of [path] kept.
  PruneForest keepAll(Path path, Set<ChildKey> children) =>
      throw UnimplementedError();

  /// With each of [children] of [path] pruned.
  PruneForest pruneAll(Path path, Set<ChildKey> children) =>
      throw UnimplementedError();

  @override
  bool operator ==(Object other) => throw UnimplementedError();

  @override
  int get hashCode => throw UnimplementedError();
}
