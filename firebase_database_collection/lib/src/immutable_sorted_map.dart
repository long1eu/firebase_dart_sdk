// File created by
// Lung Razvan <long1eu>
// on 19/09/2018

import 'package:firebase_database_collection/src/array_sorted_map.dart';
import 'package:firebase_database_collection/src/llrb_node.dart';
import 'package:firebase_database_collection/src/rb_tree_sorted_map.dart';

typedef D KeyTranslator<C, D>(C key);

abstract class ImmutableSortedMap<K, V> extends Iterable<MapEntry<K, V>> {
  /// The size threshold where we use a tree backed sorted map instead of an
  /// array backed sorted map. This is a more or less arbitrary chosen value,
  /// that was chosen to be large enough to fit most of object kind of Database
  /// data, but small enough to not notice degradation in performance for
  /// inserting and lookups. Feel free to empirically determine this constant,
  /// but don't expect much gain in real world performance.
  static const int arrayToRbTreeSizeThreshold = 25;

  const ImmutableSortedMap();

  factory ImmutableSortedMap.emptyMap(Comparator<K> comparator) {
    return ArraySortedMap<K, V>(comparator);
  }

  factory ImmutableSortedMap.fromMap(
      Map<K, V> values, Comparator<K> comparator) {
    if (values.length < arrayToRbTreeSizeThreshold) {
      return ArraySortedMap<K, V>.fromMap(values, comparator);
    } else {
      return RBTreeSortedMap<K, V>.fromMap(values, comparator);
    }
  }

  static ImmutableSortedMap<A, C> buildFrom<A, B, C>(
      List<A> keys,
      Map<B, C> values,
      KeyTranslator<A, B> translator,
      Comparator<A> comparator) {
    if (keys.length < arrayToRbTreeSizeThreshold) {
      return ArraySortedMap.buildFrom(keys, values, translator, comparator);
    } else {
      return RBTreeSortedMap.buildFrom(keys, values, translator, comparator);
    }
  }

  static KeyTranslator<A, A> identityTranslator<A>() => (A key) => key;

  bool containsKey(K key);

  V operator [](K key);

  ImmutableSortedMap<K, V> remove(K key);

  ImmutableSortedMap<K, V> insert(K key, V value);

  K get minKey;

  K get maxKey;

  @override
  int get length;

  @override
  bool get isEmpty;

  void inOrderTraversal(NodeVisitor<K, V> visitor);

  @override
  Iterator<MapEntry<K, V>> get iterator;

  Iterator<MapEntry<K, V>> get reverseIterator;

  Iterator<MapEntry<K, V>> iteratorFrom(K key);

  Iterator<MapEntry<K, V>> reverseIteratorFrom(K key);

  K getPredecessorKey(K key);

  K getSuccessorKey(K key);

  int indexOf(K key);

  Comparator<K> get comparator;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    if (other is! ImmutableSortedMap) {
      return false;
    }

    final ImmutableSortedMap<K, V> that = other;

    if (comparator != that.comparator) {
      return false;
    }
    if (length != that.length) {
      return false;
    }

    final Iterator<MapEntry<K, V>> thisIterator = iterator;
    final Iterator<MapEntry<K, V>> thatIterator = that.iterator;
    while (thisIterator.moveNext()) {
      thatIterator.moveNext();

      if (!_areEqual(thisIterator.current, thatIterator.current)) {
        return false;
      }
    }

    return true;
  }

  @override
  int get hashCode {
    int result = comparator.hashCode;
    for (MapEntry<K, V> entry in this) {
      result = 31 * result + entry.hashCode;
    }

    return result;
  }

  @override
  String toString() {
    final StringBuffer b = StringBuffer();
    b..write(runtimeType)..write('{');
    bool first = true;
    for (MapEntry<K, V> entry in this) {
      if (first) {
        first = false;
      } else {
        b
          ..write(', ')
          ..write('(')
          ..write(entry.key)
          ..write('=>')
          ..write(entry.value)
          ..write(')');
      }
    }
    b.write('};');
    return b.toString();
  }

  static bool _areEqual<K, V>(MapEntry<K, V> a, MapEntry<K, V> b) {
    return a.key == b.key && a.value == b.value;
  }
}
