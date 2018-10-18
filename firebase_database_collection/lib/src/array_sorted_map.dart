// File created by
// Lung Razvan <long1eu>
// on 19/09/2018

import 'package:firebase_database_collection/src/llrb_node.dart';
import 'package:firebase_database_collection/src/rb_tree_sorted_map.dart';

import 'immutable_sorted_map.dart';

/// This is an array backed implementation of [ImmutableSortedMap]. It uses
/// arrays and linear lookups to achieve good memory efficiency while
/// maintaining good performance for small collections. To avoid degrading
/// performance with increasing collection size it will automatically convert to
/// a [RBTreeSortedMap] after an insert call above a certain threshold.
class ArraySortedMap<K, V> extends ImmutableSortedMap<K, V> {
  ArraySortedMap(this.comparator, [List<K> keys, List<V> values])
      : keys = keys ?? <K>[],
        values = values ?? <V>[];

  factory ArraySortedMap.fromMap(Map<K, V> map, Comparator<K> comparator) {
    return buildFrom<K, K, V>(List<K>.from(map.keys), map,
        ImmutableSortedMap.identityTranslator<K>(), comparator);
  }

  static ArraySortedMap<A, C> buildFrom<A, B, C>(List<A> keys, Map<B, C> values,
      KeyTranslator<A, B> translator, Comparator<A> comparator) {
    keys.sort(comparator);
    final int length = keys.length;
    final List<A> keyArray = List<A>(length);
    final List<C> valueArray = List<C>(length);
    int pos = 0;
    for (A k in keys) {
      keyArray[pos] = k;
      final C value = values[translator(k)];
      valueArray[pos] = value;
      pos++;
    }
    return ArraySortedMap<A, C>(comparator, keyArray, valueArray);
  }

  final List<K> keys;
  final List<V> values;

  @override
  final Comparator<K> comparator;

  @override
  bool containsKey(K key) => findKey(key) != -1;

  @override
  V operator [](K key) {
    final int pos = findKey(key);
    return pos != -1 ? values[pos] : null;
  }

  @override
  ImmutableSortedMap<K, V> remove(K key) {
    final int pos = findKey(key);
    if (pos == -1) {
      return this;
    } else {
      final List<K> keys = _removeFromArray<K>(this.keys, pos);
      final List<V> values = _removeFromArray<V>(this.values, pos);
      return ArraySortedMap<K, V>(comparator, keys, values);
    }
  }

  @override
  ImmutableSortedMap<K, V> insert(K key, V value) {
    final int pos = findKey(key);
    if (pos != -1) {
      if (keys[pos] == key && values[pos] == value) {
        return this;
      } else {
        // The key and/or value might have changed, even though the comparison
        // might still yield 0
        final List<K> newKeys = _replaceInArray<K>(keys, pos, key);
        final List<V> newValues = _replaceInArray<V>(values, pos, value);
        return ArraySortedMap<K, V>(comparator, newKeys, newValues);
      }
    } else {
      if (keys.length > ImmutableSortedMap.arrayToRbTreeSizeThreshold) {
        final Map<K, V> map = <K, V>{};
        for (int i = 0; i < keys.length; i++) {
          map[keys[i]] = values[i];
        }
        map[key] = value;
        return RBTreeSortedMap<K, V>.fromMap(map, comparator);
      } else {
        final int newPos = _findKeyOrInsertPosition(key);
        final List<K> keys = _addToArray<K>(this.keys, newPos, key);
        final List<V> values = _addToArray<V>(this.values, newPos, value);

        return ArraySortedMap<K, V>(comparator, keys, values);
      }
    }
  }

  @override
  K get minKey => keys.isNotEmpty ? keys[0] : null;

  @override
  K get maxKey => keys.isNotEmpty ? keys[keys.length - 1] : null;

  @override
  int get length => keys.length;

  @override
  bool get isEmpty => keys.isEmpty;

  @override
  void inOrderTraversal(NodeVisitor<K, V> visitor) {
    for (int i = 0; i < keys.length; i++) {
      visitor.visitEntry(keys[i], values[i]);
    }
  }

  Iterable<MapEntry<K, V>> _getIterable(int pos, final bool reverse) sync* {
    if (reverse) {
      while (pos >= 0) {
        yield MapEntry<K, V>(keys[pos], values[pos]);
        pos--;
      }
    } else {
      while (pos < keys.length) {
        yield MapEntry<K, V>(keys[pos], values[pos]);
        pos++;
      }
    }
  }

  @override
  Iterator<MapEntry<K, V>> get iterator {
    return _getIterable(0, false).iterator;
  }

  @override
  Iterator<MapEntry<K, V>> get reverseIterator {
    return _getIterable(keys.length - 1, true).iterator;
  }

  @override
  Iterator<MapEntry<K, V>> iteratorFrom(K key) {
    final int pos = _findKeyOrInsertPosition(key);
    return _getIterable(pos, false).iterator;
  }

  @override
  Iterator<MapEntry<K, V>> reverseIteratorFrom(K key) {
    final int pos = _findKeyOrInsertPosition(key);
    // if there's no exact match, findKeyOrInsertPosition will return the index
    // *after* the closest match, but since this is a reverse iterator, we want
    // to start just *before* the closest match.
    if (pos < keys.length && this.comparator(keys[pos], key) == 0) {
      return _getIterable(pos, true).iterator;
    } else {
      return _getIterable(pos - 1, true).iterator;
    }
  }

  @override
  K getPredecessorKey(K key) {
    final int pos = findKey(key);
    if (pos == -1) {
      throw ArgumentError('Can\'t find predecessor of nonexistent key');
    } else {
      return (pos > 0) ? keys[pos - 1] : null;
    }
  }

  @override
  K getSuccessorKey(K key) {
    final int pos = findKey(key);
    if (pos == -1) {
      throw ArgumentError('Can\'t find successor of nonexistent key');
    } else {
      return (pos < keys.length - 1) ? keys[pos + 1] : null;
    }
  }

  @override
  int indexOf(K key) => findKey(key);

  static List<T> _removeFromArray<T>(List<T> arr, int pos) {
    return arr.toList()..removeAt(pos);
  }

  static List<T> _addToArray<T>(List<T> arr, int pos, T value) {
    return arr.toList()..insert(pos, value);
  }

  static List<T> _replaceInArray<T>(List<T> arr, int pos, T value) {
    final List<T> newArray = arr.toList();
    newArray[pos] = value;
    return newArray;
  }

  /// This does a linear scan which is simpler than a binary search. For a small
  /// collection size this still should be as fast a as binary search.
  int _findKeyOrInsertPosition(K key) {
    int newPos = 0;
    while (newPos < keys.length && this.comparator(keys[newPos], key) < 0) {
      newPos++;
    }
    return newPos;
  }

  /// This does a linear scan which is simpler than a binary search. For a small
  /// collection size this still should be as fast a as binary search.
  int findKey(K key) {
    int i = 0;
    for (K otherKey in keys) {
      if (this.comparator(key, otherKey) == 0) {
        return i;
      }
      i++;
    }
    return -1;
  }
}
