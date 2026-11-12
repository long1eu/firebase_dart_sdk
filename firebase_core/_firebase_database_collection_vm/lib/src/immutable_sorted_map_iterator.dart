// File created by
// Lung Razvan <long1eu>
// on 19/09/2018

import 'dart:collection';

import 'package:_firebase_database_collection_vm/src/llrb_node.dart';
import 'package:_firebase_database_collection_vm/src/lltb_value_node.dart';

class ImmutableSortedMapIterator<K, V> implements Iterator<MapEntry<K, V>> {
  ImmutableSortedMapIterator(
      LLRBNode<K, V> root, K? startKey, Comparator<K> comparator, this.isReverse)
      : nodeStack = Queue<LLRBValueNode<K, V>>() {
    LLRBNode<K, V> node = root;
    while (!node.isEmpty) {
      final int cmp;
      if (startKey != null) {
        cmp = isReverse
            ? comparator(startKey, node.key as K)
            : comparator(node.key as K, startKey);
      } else {
        cmp = 1;
      }
      if (cmp < 0) {
        // This node is less than our start key. ignore it
        if (isReverse) {
          node = node.left;
        } else {
          node = node.right;
        }
      } else if (cmp == 0) {
        // This node is exactly equal to our start key. Push it on the stack,
        // but stop iterating;
        nodeStack.add(node as LLRBValueNode<K, V>);
        break;
      } else {
        nodeStack.add(node as LLRBValueNode<K, V>);
        if (isReverse) {
          node = node.right;
        } else {
          node = node.left;
        }
      }
    }
  }

  final Queue<LLRBValueNode<K, V>> nodeStack;

  final bool isReverse;

  MapEntry<K, V>? _current;

  /// The entry the iterator is positioned on. Reading it has no side effects;
  /// it is only valid after [moveNext] returned true.
  @override
  MapEntry<K, V> get current {
    final MapEntry<K, V>? entry = _current;
    if (entry == null) {
      throw StateError('No current element: call moveNext() first.');
    }
    return entry;
  }

  @override
  bool moveNext() {
    if (nodeStack.isEmpty) {
      _current = null;
      return false;
    }

    final LLRBValueNode<K, V> node = nodeStack.removeLast();
    _current = MapEntry<K, V>(node.key, node.value);
    if (isReverse) {
      LLRBNode<K, V> next = node.left;
      while (!next.isEmpty) {
        nodeStack.add(next as LLRBValueNode<K, V>);
        next = next.right;
      }
    } else {
      LLRBNode<K, V> next = node.right;
      while (!next.isEmpty) {
        nodeStack.add(next as LLRBValueNode<K, V>);
        next = next.left;
      }
    }
    return true;
  }
}
