// File created by
// Lung Razvan <long1eu>
// on 19/09/2018

import 'package:firebase_database_collection/src/llrb_empty_node.dart';
import 'package:firebase_database_collection/src/llrb_node.dart';
import 'package:firebase_database_collection/src/lltb_value_node.dart';

class LLRBRedValueNode<K, V> extends LLRBValueNode<K, V> {
  LLRBRedValueNode(K key, V value, [LLRBNode<K, V> left, LLRBNode<K, V> right])
      : super(key, value, left ?? LLRBEmptyNode<K, V>(),
            right ?? LLRBEmptyNode<K, V>());

  @override
  final LLRBNodeColor color = LLRBNodeColor.red;

  @override
  bool get isRed => true;

  @override
  int get length => left.length + 1 + right.length;

  @override
  LLRBValueNode<K, V> copyWith(
      K key, V value, LLRBNode<K, V> left, LLRBNode<K, V> right) {
    final K newKey = key == null ? this.key : key;
    final V newValue = value == null ? this.value : value;
    final LLRBNode<K, V> newLeft = left == null ? this.left : left;
    final LLRBNode<K, V> newRight = right == null ? this.right : right;
    return LLRBRedValueNode<K, V>(newKey, newValue, newLeft, newRight);
  }
}
