/// Immutable path-keyed tree. JS: `core/util/ImmutableTree.ts`; Android:
/// `core/utilities/ImmutableTree.java`.
library;

import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/util/sorted_map.dart';

/// A value found on a path: where and what.
typedef PathAndValue<T> = ({Path path, T value});

/// An immutable tree with an optional [value] at every node and children by [ChildKey].
final class ImmutableTree<T> {
  /// Creates a tree with [value] and [children] (empty when null).
  factory ImmutableTree(
    T? value, [
    SortedMap<ChildKey, ImmutableTree<T>>? children,
  ]) => throw UnimplementedError();

  /// The empty tree.
  factory ImmutableTree.empty() => throw UnimplementedError();

  /// A tree with each value of [values] at its path.
  factory ImmutableTree.fromMap(Map<Path, T> values) =>
      throw UnimplementedError();

  /// The value at the root, or null.
  T? get value => throw UnimplementedError();

  /// The children.
  SortedMap<ChildKey, ImmutableTree<T>> get children =>
      throw UnimplementedError();

  /// Whether there is no value anywhere in the tree.
  bool get isEmpty => throw UnimplementedError();

  /// The root-most value on [relativePath] for which [predicate] holds, with its path.
  PathAndValue<T>? findRootMostMatchingPathAndValue(
    Path relativePath,
    bool Function(T value) predicate,
  ) => throw UnimplementedError();

  /// The root-most value on [relativePath], with its path.
  PathAndValue<T>? findRootMostValueAndPath(Path relativePath) =>
      throw UnimplementedError();

  /// The root-most value on [relativePath], or null.
  T? rootMostValue(Path relativePath) => throw UnimplementedError();

  /// The root-most value on [relativePath] matching [predicate], or null.
  T? rootMostValueMatching(
    Path relativePath,
    bool Function(T value) predicate,
  ) => throw UnimplementedError();

  /// The leaf-most value on [relativePath], or null.
  T? leafMostValue(Path relativePath) => throw UnimplementedError();

  /// The leaf-most value on [relativePath] matching [predicate], or null.
  T? leafMostValueMatching(
    Path relativePath,
    bool Function(T value) predicate,
  ) => throw UnimplementedError();

  /// Whether any value in the tree matches [predicate].
  bool containsMatchingValue(bool Function(T value) predicate) =>
      throw UnimplementedError();

  /// The immediate child [key] (empty when absent).
  ImmutableTree<T> getChild(ChildKey key) => throw UnimplementedError();

  /// The subtree at [relativePath] (empty when absent).
  ImmutableTree<T> subtree(Path relativePath) => throw UnimplementedError();

  /// A tree with [toSet] at [relativePath].
  ImmutableTree<T> set(Path relativePath, T? toSet) =>
      throw UnimplementedError();

  /// A tree without the value and subtree at [relativePath].
  ImmutableTree<T> remove(Path relativePath) => throw UnimplementedError();

  /// The value at [relativePath], or null.
  T? get(Path relativePath) => throw UnimplementedError();

  /// A tree with [newTree] at [relativePath].
  ImmutableTree<T> setTree(Path relativePath, ImmutableTree<T> newTree) =>
      throw UnimplementedError();

  /// Folds the tree bottom-up: [fn] gets each node's path, value and its children's results.
  V fold<V>(V Function(Path path, T? value, Map<ChildKey, V> children) fn) =>
      throw UnimplementedError();

  /// Folds every value with an accumulator, starting from [initial] (Android's `fold`).
  R foldValues<R>(
    R initial,
    R Function(Path path, T value, R accumulator) fn,
  ) => throw UnimplementedError();

  /// Calls [fn] on the values along [path] from the root until it returns non-null.
  V? findOnPath<V>(Path path, V? Function(Path path, T value) fn) =>
      throw UnimplementedError();

  /// Calls [fn] on the values along [path]; returns the subtree at [path].
  ImmutableTree<T> forEachOnPath(
    Path path,
    void Function(Path path, T value) fn,
  ) => throw UnimplementedError();

  /// Calls [fn] on every value, depth first.
  void forEach(void Function(Path path, T value) fn) =>
      throw UnimplementedError();

  /// Calls [fn] on the value of every immediate child that has one.
  void forEachChild(void Function(ChildKey key, T value) fn) =>
      throw UnimplementedError();

  /// Every value with its path, in order.
  Iterable<MapEntry<Path, T>> get entries => throw UnimplementedError();

  @override
  bool operator ==(Object other) => throw UnimplementedError();

  @override
  int get hashCode => throw UnimplementedError();
}
