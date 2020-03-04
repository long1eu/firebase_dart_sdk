// File created by
// Lung Razvan <long1eu>
// on 19/09/2018

import 'package:_firebase_database_collection_vm/src/llrb_empty_node.dart';
import 'package:_firebase_database_collection_vm/src/llrb_node.dart';
import 'package:_firebase_database_collection_vm/src/lltb_value_node.dart';

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
    final K newKey = key ?? this.key;
    final V newValue = value ?? this.value;
    final LLRBNode<K, V> newLeft = left ?? this.left;
    final LLRBNode<K, V> newRight = right ?? this.right;
    return LLRBRedValueNode<K, V>(newKey, newValue, newLeft, newRight);
  }
}
