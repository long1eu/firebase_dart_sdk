// File created by
// Lung Razvan <long1eu>
// on 19/09/2018

import 'dart:math';

import 'package:firebase_database_collection/src/immutable_sorted_map.dart';
import 'package:firebase_database_collection/src/immutable_sorted_map_iterator.dart';
import 'package:firebase_database_collection/src/llrb_black_value_node.dart';
import 'package:firebase_database_collection/src/llrb_empty_node.dart';
import 'package:firebase_database_collection/src/llrb_node.dart';
import 'package:firebase_database_collection/src/llrb_red_value_node.dart';
import 'package:firebase_database_collection/src/lltb_value_node.dart';

/// This is a red-black tree backed implementation of ImmutableSortedMap. This
/// has better asymptotic complexity for large collections, but performs worse
/// in practice than an ArraySortedMap for small collections. It also uses about
/// twice as much memory.
class RBTreeSortedMap<K, V> extends ImmutableSortedMap<K, V> {
  LLRBNode<K, V> _root;
  Comparator<K> comparator;

  static RBTreeSortedMap<A, C> buildFrom<A, B, C>(
      List<A> keys,
      Map<B, C> values,
      KeyTranslator<A, B> translator,
      Comparator<A> comparator) {
    return RBTreeSortedMapBuilder.buildFrom(
      keys,
      values,
      translator,
      comparator,
    );
  }

  factory RBTreeSortedMap.fromMap(Map<K, V> values, Comparator<K> comparator) {
    return RBTreeSortedMapBuilder.buildFrom(
      values.keys.toList(),
      values,
      ImmutableSortedMap.identityTranslator(),
      comparator,
    );
  }

  RBTreeSortedMap(this.comparator, [LLRBNode<K, V> root])
      : _root = root ?? LLRBEmptyNode<K, V>();

  // For testing purposes
  LLRBNode<K, V> get root => _root;

  // private
  LLRBNode<K, V> getNode(K key) {
    LLRBNode<K, V> node = _root;
    while (!node.isEmpty) {
      int cmp = this.comparator(key, node.key);
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
  V operator [](K key) {
    final LLRBNode<K, V> node = getNode(key);
    return node != null ? node.value : null;
  }

  @override
  ImmutableSortedMap<K, V> remove(K key) {
    if (!this.containsKey(key)) {
      return this;
    } else {
      LLRBNode<K, V> newRoot = _root
          .remove(key, this.comparator)
          .copy(null, null, LLRBNodeColor.black, null, null);
      return RBTreeSortedMap<K, V>(this.comparator, newRoot);
    }
  }

  @override
  ImmutableSortedMap<K, V> insert(K key, V value) {
    LLRBNode<K, V> newRoot = _root
        .insert(key, value, this.comparator)
        .copy(null, null, LLRBNodeColor.black, null, null);
    return RBTreeSortedMap<K, V>(this.comparator, newRoot);
  }

  @override
  K get minKey => _root.min.key;

  @override
  K get maxKey => _root.max.key;

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
    return ImmutableSortedMapIterator<K, V>(
        _root, null, this.comparator, false);
  }

  @override
  Iterator<MapEntry<K, V>> iteratorFrom(K key) {
    return ImmutableSortedMapIterator<K, V>(_root, key, this.comparator, false);
  }

  @override
  Iterator<MapEntry<K, V>> reverseIteratorFrom(K key) {
    return ImmutableSortedMapIterator<K, V>(_root, key, this.comparator, true);
  }

  @override
  Iterator<MapEntry<K, V>> get reverseIterator {
    return ImmutableSortedMapIterator<K, V>(_root, null, this.comparator, true);
  }

  @override
  K getPredecessorKey(K key) {
    LLRBNode<K, V> node = _root;
    LLRBNode<K, V> rightParent = null;
    while (!node.isEmpty) {
      int cmp = this.comparator(key, node.key);
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
    throw new ArgumentError(
        'Couldn\'t find predecessor key of non-present key: $key');
  }

  @override
  K getSuccessorKey(K key) {
    LLRBNode<K, V> node = _root;
    LLRBNode<K, V> leftParent = null;
    while (!node.isEmpty) {
      final int cmp = this.comparator(node.key, key);
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
    throw new ArgumentError(
        'Couldn\'t find successor key of non-present key: $key');
  }

  @override
  int indexOf(K key) {
    // Number of nodes that were pruned when descending right
    int prunedNodes = 0;
    LLRBNode<K, V> node = _root;
    while (!node.isEmpty) {
      int cmp = this.comparator(key, node.key);
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

class RBTreeSortedMapBuilder<A, B, C> {
  final List<A> keys;
  final Map<B, C> values;
  final KeyTranslator<A, B> keyTranslator;

  LLRBValueNode<A, C> _root;
  LLRBValueNode<A, C> _leaf;

  RBTreeSortedMapBuilder(this.keys, this.values, this.keyTranslator);

  C getValue(A key) {
    return values[keyTranslator(key)];
  }

  void _buildPennant(LLRBNodeColor color, int chunkSize, int start) {
    LLRBNode<A, C> treeRoot = _buildBalancedTree(start + 1, chunkSize - 1);
    A key = this.keys[start];
    LLRBValueNode<A, C> node;
    if (color == LLRBNodeColor.red) {
      node = LLRBRedValueNode<A, C>(key, getValue(key), null, treeRoot);
    } else {
      node = new LLRBBlackValueNode<A, C>(key, getValue(key), null, treeRoot);
    }
    if (_root == null) {
      _root = node;
      _leaf = node;
    } else {
      _leaf.left = node;
      _leaf = node;
    }
  }

  LLRBNode<A, C> _buildBalancedTree(int start, int size) {
    if (size == 0) {
      return LLRBEmptyNode<A, C>();
    } else if (size == 1) {
      final A key = this.keys[start];
      return new LLRBBlackValueNode<A, C>(key, getValue(key), null, null);
    } else {
      final int half = size ~/ 2;
      final int middle = start + half;
      LLRBNode<A, C> left = _buildBalancedTree(start, half);
      LLRBNode<A, C> right = _buildBalancedTree(middle + 1, half);
      final A key = keys[middle];
      return new LLRBBlackValueNode<A, C>(key, getValue(key), left, right);
    }
  }

  static RBTreeSortedMap<A, C> buildFrom<A, B, C>(
      List<A> keys,
      Map<B, C> values,
      KeyTranslator<A, B> translator,
      Comparator<A> comparator) {
    RBTreeSortedMapBuilder<A, B, C> builder =
        new RBTreeSortedMapBuilder<A, B, C>(keys, values, translator);
    keys.sort(comparator);
    Iterator<BooleanChunk> iter = (new Base1_2(keys.length)).iterator;
    int index = keys.length;
    while (iter.moveNext()) {
      BooleanChunk next = iter.current;
      index -= next.chunkSize;
      if (next.isOne) {
        builder._buildPennant(LLRBNodeColor.black, next.chunkSize, index);
      } else {
        builder._buildPennant(LLRBNodeColor.black, next.chunkSize, index);
        index -= next.chunkSize;
        builder._buildPennant(LLRBNodeColor.red, next.chunkSize, index);
      }
    }
    return new RBTreeSortedMap<A, C>(
      comparator,
      builder._root == null ? LLRBEmptyNode<A, C>() : builder._root,
    );
  }
}

class BooleanChunk {
  bool isOne;
  int chunkSize;
}

class Base1_2 extends Iterable<BooleanChunk> {
  final int length;
  int value;

  factory Base1_2(int size) {
    int toCalc = size + 1;
    final length = (log(toCalc) / log(2)).floor();

    int mask = pow(2, length) - 1;
    final int value = toCalc & mask;

    return Base1_2._(length, value);
  }

  Base1_2._(this.length, this.value);

  /// Iterates over bools for whether or not a particular digit is a '1' in
  /// base {1, 2}
  /// Returns a reverse iterator over the base {1, 2} number
  @override
  Iterator<BooleanChunk> get iterator {
    return (int length) sync* {
      int currentPosition = length - 1;

      while (currentPosition >= 0) {
        final int result = value & (1 << currentPosition);
        final BooleanChunk next = new BooleanChunk();
        next.isOne = result == 0;
        next.chunkSize = pow(2, currentPosition);
        currentPosition--;
        yield next;
      }
    }(length)
        .iterator;
  }
}
