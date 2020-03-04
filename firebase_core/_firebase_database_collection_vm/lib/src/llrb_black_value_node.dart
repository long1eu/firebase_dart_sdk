// File created by
// Lung Razvan <long1eu>
// on 19/09/2018

import 'package:_firebase_database_collection_vm/src/llrb_node.dart';
import 'package:_firebase_database_collection_vm/src/lltb_value_node.dart';

class LLRBBlackValueNode<K, V> extends LLRBValueNode<K, V> {
  LLRBBlackValueNode(K key, V value, LLRBNode<K, V> left, LLRBNode<K, V> right)
      : super(key, value, left, right);

  /// Only memoize size on black nodes, not on red nodes. This saves memory
  /// while guaranteeing that size will still have an amortized constant
  /// runtime. The first time [length] may have to traverse the entire tree.
  /// However, the red black tree algorithm guarantees that every red node has
  /// two black children. So future invocations of the [length] function will
  /// have to go at most 2 levels deep if the child is a red node.
  ///
  /// Needs to be mutable because left node can be updated via [setLeft].
  int size = -1;

  @override
  final LLRBNodeColor color = LLRBNodeColor.black;

  @override
  final bool isRed = false;

  @override
  int get length {
    if (size == -1) {
      size = left.length + 1 + right.length;
    }
    return size;
  }

  @override
  set left(LLRBNode<K, V> left) {
    if (size != -1) {
      // Modifying left node after invoking size
      throw StateError('Can\'t set left after using size');
    }
    super.left = left;
  }

  @override
  LLRBValueNode<K, V> copyWith(
      K key, V value, LLRBNode<K, V> left, LLRBNode<K, V> right) {
    final K newKey = key ?? this.key;
    final V newValue = value ?? this.value;
    final LLRBNode<K, V> newLeft = left ?? this.left;
    final LLRBNode<K, V> newRight = right ?? this.right;
    return LLRBBlackValueNode<K, V>(newKey, newValue, newLeft, newRight);
  }
}
