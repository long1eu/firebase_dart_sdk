// File created by
// Lung Razvan <long1eu>
// on 19/09/2018

import 'dart:collection';

import 'package:firebase_database_collection/src/llrb_node.dart';
import 'package:firebase_database_collection/src/lltb_value_node.dart';

class ImmutableSortedMapIterator<K, V> implements Iterator<MapEntry<K, V>> {
  final Queue<LLRBValueNode<K, V>> nodeStack;

  final bool isReverse;

  ImmutableSortedMapIterator(
      LLRBNode<K, V> root, K startKey, Comparator<K> comparator, this.isReverse)
      : nodeStack = new Queue<LLRBValueNode<K, V>>() {
    LLRBNode<K, V> node = root;
    while (!node.isEmpty) {
      int cmp;
      if (startKey != null) {
        cmp = isReverse
            ? comparator(startKey, node.key)
            : comparator(node.key, startKey);
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
        // This node is exactly equal to our start key. Push it on the stack, but stop iterating;
        this.nodeStack.add(node as LLRBValueNode<K, V>);
        break;
      } else {
        this.nodeStack.add(node as LLRBValueNode<K, V>);
        if (isReverse) {
          node = node.right;
        } else {
          node = node.left;
        }
      }
    }
  }

  @override
  MapEntry<K, V> get current {
    final LLRBValueNode<K, V> node = nodeStack.removeLast();
    MapEntry<K, V> entry = MapEntry<K, V>(node.key, node.value);
    if (this.isReverse) {
      LLRBNode<K, V> next = node.left;
      while (!next.isEmpty) {
        this.nodeStack.add(next as LLRBValueNode<K, V>);
        next = next.right;
      }
    } else {
      LLRBNode<K, V> next = node.right;
      while (!next.isEmpty) {
        this.nodeStack.add(next as LLRBValueNode<K, V>);
        next = next.left;
      }
    }
    return entry;
  }

  @override
  bool moveNext() => nodeStack.isNotEmpty;
}
