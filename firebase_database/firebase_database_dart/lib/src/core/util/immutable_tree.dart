/// Immutable path-keyed tree. JS: `core/util/ImmutableTree.ts`; Android:
/// `core/utilities/ImmutableTree.java`.
library;

import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/util/sorted_map.dart';
import 'package:meta/meta.dart';

/// A value found on a path: where and what.
typedef PathAndValue<T> = ({Path path, T value});

int _compareKeys(ChildKey a, ChildKey b) => a.compareTo(b);

/// An immutable tree with an optional [value] at every node and children by [ChildKey].
final class ImmutableTree<T> {
  /// Creates a tree with [value] and [children] (empty when null). Outside this package, use
  /// [ImmutableTree.empty] or [ImmutableTree.fromMap].
  @internal
  factory ImmutableTree(
    T? value, [
    SortedMap<ChildKey, ImmutableTree<T>>? children,
  ]) => ImmutableTree<T>._(
    value,
    children ?? SortedMap<ChildKey, ImmutableTree<T>>(_compareKeys),
  );

  /// The empty tree.
  factory ImmutableTree.empty() => ImmutableTree<T>(null);

  /// A tree with each value of [values] at its path.
  factory ImmutableTree.fromMap(Map<Path, T> values) {
    ImmutableTree<T> tree = ImmutableTree<T>.empty();
    for (final MapEntry<Path, T> entry in values.entries) {
      tree = tree.set(entry.key, entry.value);
    }
    return tree;
  }

  ImmutableTree._(this.value, this.children);

  /// The value at the root, or null.
  final T? value;

  /// The children. Outside this package, walk the tree with [getChild], [subtree], [forEach] or
  /// [entries].
  @internal
  final SortedMap<ChildKey, ImmutableTree<T>> children;

  /// Whether there is no value anywhere in the tree.
  bool get isEmpty => value == null && children.isEmpty;

  /// The root-most value on [relativePath] for which [predicate] holds, with its path.
  PathAndValue<T>? findRootMostMatchingPathAndValue(
    Path relativePath,
    bool Function(T value) predicate,
  ) {
    final T? value = this.value;
    if (value != null && predicate(value)) {
      return (path: Path.empty, value: value);
    }
    if (relativePath.isEmpty) {
      return null;
    }
    final ChildKey front = relativePath.front!;
    final ImmutableTree<T>? child = children[front];
    if (child == null) {
      return null;
    }
    final PathAndValue<T>? found = child.findRootMostMatchingPathAndValue(
      relativePath.popFront(),
      predicate,
    );
    if (found == null) {
      return null;
    }
    return (
      path: Path.fromKeys(<ChildKey>[front]).childPath(found.path),
      value: found.value,
    );
  }

  /// The root-most value on [relativePath], with its path.
  PathAndValue<T>? findRootMostValueAndPath(Path relativePath) =>
      findRootMostMatchingPathAndValue(relativePath, (T _) => true);

  /// The root-most value on [relativePath], or null.
  T? rootMostValue(Path relativePath) =>
      rootMostValueMatching(relativePath, (T _) => true);

  /// The root-most value on [relativePath] matching [predicate], or null.
  T? rootMostValueMatching(
    Path relativePath,
    bool Function(T value) predicate,
  ) {
    final T? value = this.value;
    if (value != null && predicate(value)) {
      return value;
    }
    ImmutableTree<T> current = this;
    for (final ChildKey key in relativePath.segments) {
      final ImmutableTree<T>? next = current.children[key];
      if (next == null) {
        return null;
      }
      final T? nextValue = next.value;
      if (nextValue != null && predicate(nextValue)) {
        return nextValue;
      }
      current = next;
    }
    return null;
  }

  /// The leaf-most value on [relativePath], or null.
  T? leafMostValue(Path relativePath) =>
      leafMostValueMatching(relativePath, (T _) => true);

  /// The leaf-most value on [relativePath] matching [predicate], or null.
  T? leafMostValueMatching(
    Path relativePath,
    bool Function(T value) predicate,
  ) {
    final T? value = this.value;
    T? currentValue = (value != null && predicate(value)) ? value : null;
    ImmutableTree<T> current = this;
    for (final ChildKey key in relativePath.segments) {
      final ImmutableTree<T>? next = current.children[key];
      if (next == null) {
        return currentValue;
      }
      final T? nextValue = next.value;
      if (nextValue != null && predicate(nextValue)) {
        currentValue = nextValue;
      }
      current = next;
    }
    return currentValue;
  }

  /// Whether any value in the tree matches [predicate].
  bool containsMatchingValue(bool Function(T value) predicate) {
    final T? value = this.value;
    if (value != null && predicate(value)) {
      return true;
    }
    for (final MapEntry<ChildKey, ImmutableTree<T>> entry in children.entries) {
      if (entry.value.containsMatchingValue(predicate)) {
        return true;
      }
    }
    return false;
  }

  /// The immediate child [key] (empty when absent).
  ImmutableTree<T> getChild(ChildKey key) =>
      children[key] ?? ImmutableTree<T>.empty();

  /// The subtree at [relativePath] (empty when absent).
  ImmutableTree<T> subtree(Path relativePath) {
    if (relativePath.isEmpty) {
      return this;
    }
    final ImmutableTree<T>? child = children[relativePath.front!];
    if (child == null) {
      return ImmutableTree<T>.empty();
    }
    return child.subtree(relativePath.popFront());
  }

  /// A tree with [toSet] at [relativePath].
  ImmutableTree<T> set(Path relativePath, T? toSet) {
    if (relativePath.isEmpty) {
      return ImmutableTree<T>._(toSet, children);
    }
    final ChildKey front = relativePath.front!;
    final ImmutableTree<T> child = children[front] ?? ImmutableTree<T>.empty();
    final ImmutableTree<T> newChild = child.set(relativePath.popFront(), toSet);
    return ImmutableTree<T>._(value, children.insert(front, newChild));
  }

  /// A tree without the value and subtree at [relativePath].
  ImmutableTree<T> remove(Path relativePath) {
    if (relativePath.isEmpty) {
      if (children.isEmpty) {
        return ImmutableTree<T>.empty();
      }
      return ImmutableTree<T>._(null, children);
    }
    final ChildKey front = relativePath.front!;
    final ImmutableTree<T>? child = children[front];
    if (child == null) {
      return this;
    }
    final ImmutableTree<T> newChild = child.remove(relativePath.popFront());
    final SortedMap<ChildKey, ImmutableTree<T>> newChildren = newChild.isEmpty
        ? children.remove(front)
        : children.insert(front, newChild);
    if (value == null && newChildren.isEmpty) {
      return ImmutableTree<T>.empty();
    }
    return ImmutableTree<T>._(value, newChildren);
  }

  /// The value at [relativePath], or null.
  T? get(Path relativePath) {
    if (relativePath.isEmpty) {
      return value;
    }
    final ImmutableTree<T>? child = children[relativePath.front!];
    if (child == null) {
      return null;
    }
    return child.get(relativePath.popFront());
  }

  /// A tree with [newTree] at [relativePath].
  ImmutableTree<T> setTree(Path relativePath, ImmutableTree<T> newTree) {
    if (relativePath.isEmpty) {
      return newTree;
    }
    final ChildKey front = relativePath.front!;
    final ImmutableTree<T> child = children[front] ?? ImmutableTree<T>.empty();
    final ImmutableTree<T> newChild = child.setTree(
      relativePath.popFront(),
      newTree,
    );
    final SortedMap<ChildKey, ImmutableTree<T>> newChildren = newChild.isEmpty
        ? children.remove(front)
        : children.insert(front, newChild);
    return ImmutableTree<T>._(value, newChildren);
  }

  /// Folds the tree bottom-up: [fn] gets each node's path, value and its children's results.
  V fold<V>(V Function(Path path, T? value, Map<ChildKey, V> children) fn) =>
      _fold(Path.empty, fn);

  V _fold<V>(
    Path pathSoFar,
    V Function(Path path, T? value, Map<ChildKey, V> children) fn,
  ) {
    final Map<ChildKey, V> accum = <ChildKey, V>{};
    for (final MapEntry<ChildKey, ImmutableTree<T>> entry in children.entries) {
      accum[entry.key] = entry.value._fold(pathSoFar.child(entry.key), fn);
    }
    return fn(pathSoFar, value, accum);
  }

  /// Folds every value with an accumulator, starting from [initial] (Android's `fold`).
  R foldValues<R>(
    R initial,
    R Function(Path path, T value, R accumulator) fn,
  ) => _foldValues(Path.empty, initial, fn);

  R _foldValues<R>(
    Path relativePath,
    R accum,
    R Function(Path path, T value, R accumulator) fn,
  ) {
    R result = accum;
    for (final MapEntry<ChildKey, ImmutableTree<T>> entry in children.entries) {
      result = entry.value._foldValues(
        relativePath.child(entry.key),
        result,
        fn,
      );
    }
    final T? value = this.value;
    if (value != null) {
      result = fn(relativePath, value, result);
    }
    return result;
  }

  /// Calls [fn] on the values along [path] from the root until it returns non-null.
  V? findOnPath<V>(Path path, V? Function(Path path, T value) fn) =>
      _findOnPath(path, Path.empty, fn);

  V? _findOnPath<V>(
    Path pathToFollow,
    Path pathSoFar,
    V? Function(Path path, T value) fn,
  ) {
    final T? value = this.value;
    final V? result = value != null ? fn(pathSoFar, value) : null;
    if (result != null) {
      return result;
    }
    if (pathToFollow.isEmpty) {
      return null;
    }
    final ChildKey front = pathToFollow.front!;
    final ImmutableTree<T>? next = children[front];
    if (next == null) {
      return null;
    }
    return next._findOnPath(
      pathToFollow.popFront(),
      pathSoFar.child(front),
      fn,
    );
  }

  /// Calls [fn] on the values along [path]; returns the subtree at [path].
  ImmutableTree<T> forEachOnPath(
    Path path,
    void Function(Path path, T value) fn,
  ) => _forEachOnPath(path, Path.empty, fn);

  ImmutableTree<T> _forEachOnPath(
    Path pathToFollow,
    Path currentRelativePath,
    void Function(Path path, T value) fn,
  ) {
    if (pathToFollow.isEmpty) {
      return this;
    }
    final T? value = this.value;
    if (value != null) {
      fn(currentRelativePath, value);
    }
    final ChildKey front = pathToFollow.front!;
    final ImmutableTree<T>? next = children[front];
    if (next == null) {
      return ImmutableTree<T>.empty();
    }
    return next._forEachOnPath(
      pathToFollow.popFront(),
      currentRelativePath.child(front),
      fn,
    );
  }

  /// Calls [fn] on every value, depth first.
  void forEach(void Function(Path path, T value) fn) =>
      _forEach(Path.empty, fn);

  void _forEach(
    Path currentRelativePath,
    void Function(Path path, T value) fn,
  ) {
    for (final MapEntry<ChildKey, ImmutableTree<T>> entry in children.entries) {
      entry.value._forEach(currentRelativePath.child(entry.key), fn);
    }
    final T? value = this.value;
    if (value != null) {
      fn(currentRelativePath, value);
    }
  }

  /// Calls [fn] on the value of every immediate child that has one.
  void forEachChild(void Function(ChildKey key, T value) fn) {
    for (final MapEntry<ChildKey, ImmutableTree<T>> entry in children.entries) {
      final T? value = entry.value.value;
      if (value != null) {
        fn(entry.key, value);
      }
    }
  }

  /// Every value with its path, in order.
  Iterable<MapEntry<Path, T>> get entries {
    final List<MapEntry<Path, T>> list = <MapEntry<Path, T>>[];
    forEach((Path path, T value) => list.add(MapEntry<Path, T>(path, value)));
    return list;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! ImmutableTree<T>) {
      return false;
    }
    if (value != other.value) {
      return false;
    }
    if (children.length != other.children.length) {
      return false;
    }
    for (final MapEntry<ChildKey, ImmutableTree<T>> entry in children.entries) {
      final ImmutableTree<T>? otherChild = other.children[entry.key];
      if (otherChild == null || otherChild != entry.value) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    value,
    Object.hashAll(
      children.entries.map(
        (MapEntry<ChildKey, ImmutableTree<T>> e) => Object.hash(e.key, e.value),
      ),
    ),
  );

  @override
  String toString() {
    final StringBuffer buffer = StringBuffer('ImmutableTree { value=')
      ..write(value)
      ..write(', children={');
    for (final MapEntry<ChildKey, ImmutableTree<T>> entry in children.entries) {
      buffer
        ..write(entry.key.name)
        ..write('=')
        ..write(entry.value);
    }
    buffer.write('} }');
    return buffer.toString();
  }
}
