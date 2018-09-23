// File created by
// Lung Razvan <long1eu>
// on 19/09/2018

import 'package:firebase_database_collection/src/immutable_sorted_map.dart';

class ImmutableSortedSet<T> extends Iterable<T> {
  final ImmutableSortedMap<T, void> _map;

  factory ImmutableSortedSet([List<T> elems, Comparator<T> comparator]) {
    return ImmutableSortedSet._(ImmutableSortedMap.buildFrom(
      elems ?? <T>[],
      <T, void>{},
      ImmutableSortedMap.identityTranslator(),
      comparator ?? (a, b) => (a as dynamic).compareTo(b),
    ));
  }

  ImmutableSortedSet._(this._map);

  @override
  bool contains(entry) => this._map.containsKey(entry);

  ImmutableSortedSet<T> remove(T entry) {
    ImmutableSortedMap<T, void> newMap = this._map.remove(entry);
    return (newMap == this._map) ? this : new ImmutableSortedSet<T>._(newMap);
  }

  ImmutableSortedSet<T> insert(T entry) {
    return new ImmutableSortedSet<T>._(_map.insert(entry, null));
  }

  T get minEntry => _map.minKey;

  T get maxEntry => this._map.maxKey;

  @override
  int get length => this._map.length;

  bool get isEmpty => this._map.isEmpty;

  @override
  Iterator<T> get iterator {
    return new _WrappedEntryIterator<T>(this._map.iterator);
  }

  Iterator<T> get reverseIterator {
    return new _WrappedEntryIterator<T>(this._map.reverseIterator);
  }

  Iterator<T> iteratorFrom(T entry) {
    return new _WrappedEntryIterator<T>(this._map.iteratorFrom(entry));
  }

  Iterator<T> reverseIteratorFrom(T entry) {
    return new _WrappedEntryIterator<T>(this._map.reverseIteratorFrom(entry));
  }

  T getPredecessorEntry(T entry) {
    return this._map.getPredecessorKey(entry);
  }

  int indexOf(T entry) {
    return this._map.indexOf(entry);
  }
}

class _WrappedEntryIterator<T> implements Iterator<T> {
  final Iterator<MapEntry<T, void>> iterator;

  const _WrappedEntryIterator(this.iterator);

  @override
  T get current => iterator.current.key;

  @override
  bool moveNext() => iterator.moveNext();
}
