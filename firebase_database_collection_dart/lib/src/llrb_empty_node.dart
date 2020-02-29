// File created by
// Lung Razvan <long1eu>
// on 19/09/2018

import 'package:firebase_database_collection/src/llrb_node.dart';
import 'package:firebase_database_collection/src/llrb_red_value_node.dart';

class LLRBEmptyNode<K, V> implements LLRBNode<K, V> {
  LLRBEmptyNode()
      : key = null,
        value = null;

  @override
  LLRBNode<K, V> copy(K key, V value, LLRBNodeColor color, LLRBNode<K, V> left,
      LLRBNode<K, V> right) {
    return this;
  }

  @override
  LLRBNode<K, V> insert(K key, V value, Comparator<K> comparator) {
    return LLRBRedValueNode<K, V>(key, value);
  }

  @override
  LLRBNode<K, V> remove(K key, Comparator<K> comparator) => this;

  @override
  bool get isEmpty => true;

  @override
  bool get isRed => false;

  @override
  final K key;

  @override
  final V value;

  @override
  LLRBNode<K, V> get left => this;

  @override
  LLRBNode<K, V> get right => this;

  @override
  LLRBNode<K, V> get min => this;

  @override
  LLRBNode<K, V> get max => this;

  @override
  int get length => 0;

  @override
  void inOrderTraversal(NodeVisitor<K, V> visitor) {
    // No-op
  }

  @override
  bool shortCircuitingInOrderTraversal(
      ShortCircuitingNodeVisitor<K, V> visitor) {
    // No-op
    return true;
  }

  @override
  bool shortCircuitingReverseOrderTraversal(
      ShortCircuitingNodeVisitor<K, V> visitor) {
    // No-op
    return true;
  }
}
