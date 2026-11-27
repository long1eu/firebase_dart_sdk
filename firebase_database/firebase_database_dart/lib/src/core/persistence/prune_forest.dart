/// Which cached paths to prune and which to keep. JS: none; Android:
/// `core/persistence/PruneForest.java`.
library;

import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/util/immutable_tree.dart';
import 'package:firebase_database_dart/src/core/util/sorted_map.dart';

/// A tree of prune (true) and keep (false) marks; a mark applies to its whole subtree unless a
/// deeper mark overrides it.
final class PruneForest {
  /// An empty forest (prunes nothing).
  factory PruneForest() => PruneForest.fromTree(ImmutableTree<bool>.empty());

  /// Wraps [forest].
  const PruneForest.fromTree(this.forest);

  /// The marks.
  final ImmutableTree<bool> forest;

  static bool _keepPredicate(bool prune) => !prune;

  static bool _prunePredicate(bool prune) => prune;

  static final ImmutableTree<bool> _pruneTree = ImmutableTree<bool>(true);
  static final ImmutableTree<bool> _keepTree = ImmutableTree<bool>(false);

  /// Whether anything is pruned.
  bool prunesAnything() => forest.containsMatchingValue(_prunePredicate);

  /// Whether data below [path] that is not kept should be pruned.
  bool shouldPruneUnkeptDescendants(Path path) =>
      forest.leafMostValue(path) ?? false;

  /// Whether [path] is kept.
  bool shouldKeep(Path path) {
    final bool? shouldPrune = forest.leafMostValue(path);
    return shouldPrune != null && !shouldPrune;
  }

  /// Whether any mark lies on or below [path].
  bool affectsPath(Path path) =>
      forest.rootMostValue(path) != null || !forest.subtree(path).isEmpty;

  /// The forest at child [key].
  PruneForest child(ChildKey key) {
    ImmutableTree<bool>? childPruneTree = forest.children[key];
    if (childPruneTree == null) {
      childPruneTree = ImmutableTree<bool>(forest.value);
    } else if (childPruneTree.value == null && forest.value != null) {
      childPruneTree = childPruneTree.set(Path.empty, forest.value);
    }
    return PruneForest.fromTree(childPruneTree);
  }

  /// The forest at [path].
  PruneForest childAtPath(Path path) {
    if (path.isEmpty) {
      return this;
    }
    return child(path.front!).childAtPath(path.popFront());
  }

  /// Folds [fn] over the kept paths.
  R foldKeptNodes<R>(R initial, R Function(Path path, R accumulator) fn) =>
      forest.foldValues<R>(
        initial,
        (Path relativePath, bool prune, R accumulator) =>
            prune ? accumulator : fn(relativePath, accumulator),
      );

  /// With [path] pruned.
  PruneForest prune(Path path) {
    if (forest.rootMostValueMatching(path, _keepPredicate) != null) {
      throw ArgumentError("Can't prune path that was kept previously!");
    }
    if (forest.rootMostValueMatching(path, _prunePredicate) != null) {
      // This path will already be pruned.
      return this;
    }
    return PruneForest.fromTree(forest.setTree(path, _pruneTree));
  }

  /// With [path] kept.
  PruneForest keep(Path path) {
    if (forest.rootMostValueMatching(path, _keepPredicate) != null) {
      // This path will already be kept.
      return this;
    }
    return PruneForest.fromTree(forest.setTree(path, _keepTree));
  }

  /// With each of [children] of [path] kept.
  PruneForest keepAll(Path path, Set<ChildKey> children) {
    if (forest.rootMostValueMatching(path, _keepPredicate) != null) {
      // This path will already be kept.
      return this;
    }
    return _doAll(path, children, _keepTree);
  }

  /// With each of [children] of [path] pruned.
  PruneForest pruneAll(Path path, Set<ChildKey> children) {
    if (forest.rootMostValueMatching(path, _keepPredicate) != null) {
      throw ArgumentError("Can't prune path that was kept previously!");
    }
    if (forest.rootMostValueMatching(path, _prunePredicate) != null) {
      // This path will already be pruned.
      return this;
    }
    return _doAll(path, children, _pruneTree);
  }

  PruneForest _doAll(
    Path path,
    Set<ChildKey> children,
    ImmutableTree<bool> keepOrPruneTree,
  ) {
    final ImmutableTree<bool> subtree = forest.subtree(path);
    SortedMap<ChildKey, ImmutableTree<bool>> childrenMap = subtree.children;
    for (final ChildKey key in children) {
      childrenMap = childrenMap.insert(key, keepOrPruneTree);
    }
    return PruneForest.fromTree(
      forest.setTree(path, ImmutableTree<bool>(subtree.value, childrenMap)),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is PruneForest && other.forest == forest;

  @override
  int get hashCode => forest.hashCode;

  @override
  String toString() => '{PruneForest:$forest}';
}
