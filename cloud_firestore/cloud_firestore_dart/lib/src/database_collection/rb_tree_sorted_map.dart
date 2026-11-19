// File created by
// Lung Razvan <long1eu>
// on 19/09/2018

import 'dart:math';

import 'package:cloud_firestore_dart/src/database_collection/immutable_sorted_map.dart';
import 'package:cloud_firestore_dart/src/database_collection/immutable_sorted_map_iterator.dart';
import 'package:cloud_firestore_dart/src/database_collection/llrb_black_value_node.dart';
import 'package:cloud_firestore_dart/src/database_collection/llrb_empty_node.dart';
import 'package:cloud_firestore_dart/src/database_collection/llrb_node.dart';
import 'package:cloud_firestore_dart/src/database_collection/llrb_red_value_node.dart';
import 'package:cloud_firestore_dart/src/database_collection/lltb_value_node.dart';

/// This is a red-black tree backed implementation of ImmutableSortedMap. This
/// has better asymptotic complexity for large collections, but performs worse
/// in practice than an ArraySortedMap for small collections. It also uses about
/// twice as much memory.
class RBTreeSortedMap<K, V> extends ImmutableSortedMap<K, V> {
  RBTreeSortedMap(this.comparator, [LLRBNode<K, V>? root])
    : _root = root ?? LLRBEmptyNode<K, V>();

  factory RBTreeSortedMap.fromMap(Map<K, V> values, Comparator<K> comparator) {
    // One pass over the entries instead of a lookup of every key in the map; already sorted entries (a scan by key)
    // are not sorted again.
    final List<MapEntry<K, V>> entries = values.entries.toList(growable: false);
    if (!isSortedBy(entries, (MapEntry<K, V> e) => e.key, comparator)) {
      entries.sort(
        (MapEntry<K, V> a, MapEntry<K, V> b) => comparator(a.key, b.key),
      );
    }
    return RBTreeSortedMapBuilder.buildFromSorted(
      <K>[for (final MapEntry<K, V> e in entries) e.key],
      <V>[for (final MapEntry<K, V> e in entries) e.value],
      comparator,
    );
  }

  /// A map of [keys] (sorted by [comparator], distinct) to the [values] at the same positions, built in linear time.
  factory RBTreeSortedMap.fromSortedLists(
    List<K> keys,
    List<V> values,
    Comparator<K> comparator,
  ) {
    return RBTreeSortedMapBuilder.buildFromSorted(keys, values, comparator);
  }

  LLRBNode<K, V> _root;
  @override
  Comparator<K> comparator;

  static RBTreeSortedMap<A, C> buildFrom<A, B, C>(
    List<A> keys,
    Map<B, C> values,
    KeyTranslator<A, B> translator,
    Comparator<A> comparator,
  ) {
    return RBTreeSortedMapBuilder.buildFrom(
      keys,
      values,
      translator,
      comparator,
    );
  }

  // For testing purposes
  LLRBNode<K, V> get root => _root;

  // private
  LLRBNode<K, V>? getNode(K key) {
    LLRBNode<K, V> node = _root;
    while (!node.isEmpty) {
      final int cmp = comparator(key, node.key as K);
      if (cmp < 0) {
        node = node.left;
      } else if (cmp == 0) {
        return node;
      } else {
        node = node.right;
      }
    }
    return null;
  }

  @override
  bool containsKey(K key) => getNode(key) != null;

  @override
  V? operator [](K key) {
    final LLRBNode<K, V>? node = getNode(key);
    return node?.value;
  }

  @override
  ImmutableSortedMap<K, V> remove(K key) {
    if (!containsKey(key)) {
      return this;
    } else {
      final LLRBNode<K, V> newRoot = _root
          .remove(key, comparator)
          .copy(null, null, LLRBNodeColor.black, null, null);
      return RBTreeSortedMap<K, V>(comparator, newRoot);
    }
  }

  @override
  ImmutableSortedMap<K, V> insert(K key, V value) {
    final LLRBNode<K, V> newRoot = _root
        .insert(key, value, comparator)
        .copy(null, null, LLRBNodeColor.black, null, null);
    return RBTreeSortedMap<K, V>(comparator, newRoot);
  }

  @override
  K? get minKey => _root.min.key;

  @override
  K? get maxKey => _root.max.key;

  @override
  int get length => _root.length;

  @override
  bool get isEmpty => _root.isEmpty;

  @override
  void inOrderTraversal(NodeVisitor<K, V> visitor) {
    _root.inOrderTraversal(visitor);
  }

  @override
  Iterator<MapEntry<K, V>> get iterator {
    return ImmutableSortedMapIterator<K, V>(_root, null, comparator, false);
  }

  @override
  Iterator<MapEntry<K, V>> iteratorFrom(K key) {
    return ImmutableSortedMapIterator<K, V>(_root, key, comparator, false);
  }

  @override
  Iterator<MapEntry<K, V>> reverseIteratorFrom(K key) {
    return ImmutableSortedMapIterator<K, V>(_root, key, comparator, true);
  }

  @override
  Iterator<MapEntry<K, V>> get reverseIterator {
    return ImmutableSortedMapIterator<K, V>(_root, null, comparator, true);
  }

  @override
  K? getPredecessorKey(K key) {
    LLRBNode<K, V> node = _root;
    LLRBNode<K, V>? rightParent;
    while (!node.isEmpty) {
      final int cmp = comparator(key, node.key as K);
      if (cmp == 0) {
        if (!node.left.isEmpty) {
          node = node.left;
          while (!node.right.isEmpty) {
            node = node.right;
          }
          return node.key;
        } else if (rightParent != null) {
          return rightParent.key;
        } else {
          return null;
        }
      } else if (cmp < 0) {
        node = node.left;
      } else {
        rightParent = node;
        node = node.right;
      }
    }
    throw ArgumentError(
      'Couldn\'t find predecessor key of non-present key: $key',
    );
  }

  @override
  K? getSuccessorKey(K key) {
    LLRBNode<K, V> node = _root;
    LLRBNode<K, V>? leftParent;
    while (!node.isEmpty) {
      final int cmp = comparator(node.key as K, key);
      if (cmp == 0) {
        if (!node.right.isEmpty) {
          node = node.right;
          while (!node.left.isEmpty) {
            node = node.left;
          }
          return node.key;
        } else if (leftParent != null) {
          return leftParent.key;
        } else {
          return null;
        }
      } else if (cmp < 0) {
        node = node.right;
      } else {
        leftParent = node;
        node = node.left;
      }
    }
    throw ArgumentError(
      'Couldn\'t find successor key of non-present key: $key',
    );
  }

  @override
  int indexOf(K key) {
    // Number of nodes that were pruned when descending right
    int prunedNodes = 0;
    LLRBNode<K, V> node = _root;
    while (!node.isEmpty) {
      final int cmp = comparator(key, node.key as K);
      if (cmp == 0) {
        return prunedNodes + node.left.length;
      } else if (cmp < 0) {
        node = node.left;
      } else {
        // Count all nodes left of the node plus the node itself
        prunedNodes += node.left.length + 1;
        node = node.right;
      }
    }
    // Node not found
    return -1;
  }
}

class RBTreeSortedMapBuilder<A, C> {
  RBTreeSortedMapBuilder(this.keys, this.values);

  /// Sorted.
  final List<A> keys;

  /// The value of every key, at the same position.
  final List<C> values;

  LLRBValueNode<A, C>? _root;
  LLRBValueNode<A, C>? _leaf;

  void _buildPennant(LLRBNodeColor color, int chunkSize, int start) {
    final LLRBNode<A, C> treeRoot = _buildBalancedTree(
      start + 1,
      chunkSize - 1,
    );
    final A key = keys[start];
    LLRBValueNode<A, C> node;
    if (color == LLRBNodeColor.red) {
      node = LLRBRedValueNode<A, C>(key, values[start], null, treeRoot);
    } else {
      node = LLRBBlackValueNode<A, C>(key, values[start], null, treeRoot);
    }
    if (_root == null) {
      _root = node;
      _leaf = node;
    } else {
      _leaf!.left = node;
      _leaf = node;
    }
  }

  LLRBNode<A, C> _buildBalancedTree(int start, int size) {
    if (size == 0) {
      return LLRBEmptyNode<A, C>();
    } else if (size == 1) {
      return LLRBBlackValueNode<A, C>(keys[start], values[start], null, null);
    } else {
      final int half = size ~/ 2;
      final int middle = start + half;
      final LLRBNode<A, C> left = _buildBalancedTree(start, half);
      final LLRBNode<A, C> right = _buildBalancedTree(middle + 1, half);
      return LLRBBlackValueNode<A, C>(
        keys[middle],
        values[middle],
        left,
        right,
      );
    }
  }

  static RBTreeSortedMap<A, C> buildFrom<A, B, C>(
    List<A> keys,
    Map<B, C> values,
    KeyTranslator<A, B> translator,
    Comparator<A> comparator,
  ) {
    keys.sort(comparator);
    return buildFromSorted<A, C>(keys, <C>[
      for (final A key in keys) values[translator(key)] as C,
    ], comparator);
  }

  /// Builds the tree of [keys], which are sorted by [comparator], with the [values] at the same positions.
  static RBTreeSortedMap<A, C> buildFromSorted<A, C>(
    List<A> keys,
    List<C> values,
    Comparator<A> comparator,
  ) {
    final RBTreeSortedMapBuilder<A, C> builder = RBTreeSortedMapBuilder<A, C>(
      keys,
      values,
    );
    final Iterator<BooleanChunk> it = Base1_2(keys.length).iterator;
    int index = keys.length;
    while (it.moveNext()) {
      final BooleanChunk next = it.current;
      index -= next.chunkSize;
      if (next.isOne) {
        builder._buildPennant(LLRBNodeColor.black, next.chunkSize, index);
      } else {
        builder._buildPennant(LLRBNodeColor.black, next.chunkSize, index);
        index -= next.chunkSize;
        builder._buildPennant(LLRBNodeColor.red, next.chunkSize, index);
      }
    }
    return RBTreeSortedMap<A, C>(
      comparator,
      builder._root ?? LLRBEmptyNode<A, C>(),
    );
  }
}

class BooleanChunk {
  late bool isOne;
  late int chunkSize;
}

// ignore: camel_case_types
class Base1_2 extends Iterable<BooleanChunk> {
  factory Base1_2(int size) {
    final int toCalc = size + 1;
    final int length = (log(toCalc) / log(2)).floor();

    final int mask = (1 << length) - 1;
    final int value = toCalc & mask;

    return Base1_2._(length, value);
  }

  Base1_2._(this.length, this.value);

  @override
  final int length;
  int value;

  /// Iterates over bools for whether or not a particular digit is a '1' in
  /// base {1, 2}
  /// Returns a reverse iterator over the base {1, 2} number
  @override
  Iterator<BooleanChunk> get iterator {
    return (int length) sync* {
      int currentPosition = length - 1;

      while (currentPosition >= 0) {
        final int result = value & (1 << currentPosition);
        final BooleanChunk next = BooleanChunk();
        next.isOne = result == 0;
        next.chunkSize = pow(2, currentPosition).toInt();
        currentPosition--;
        yield next;
      }
    }(length).iterator;
  }
}
