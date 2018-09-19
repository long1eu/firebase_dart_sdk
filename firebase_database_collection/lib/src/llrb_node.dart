// File created by
// Lung Razvan <long1eu>
// on 19/09/2018

abstract class ShortCircuitingNodeVisitor<K, V> {
  bool shouldContinue(K key, V value);
}

abstract class NodeVisitor<K, V> implements ShortCircuitingNodeVisitor<K, V> {
  @override
  bool shouldContinue(K key, V value) {
    visitEntry(key, value);
    return true;
  }

  void visitEntry(K key, V value);
}

enum LLRBNodeColor { red, black }

abstract class LLRBNode<K, V> {
  const LLRBNode();

  LLRBNode<K, V> copy(K key, V value, LLRBNodeColor color, LLRBNode<K, V> left,
      LLRBNode<K, V> right);

  LLRBNode<K, V> insert(K key, V value, Comparator<K> comparator);

  LLRBNode<K, V> remove(K key, Comparator<K> comparator);

  bool get isEmpty;

  bool get isRed;

  K get key;

  V get value;

  LLRBNode<K, V> get left;

  LLRBNode<K, V> get right;

  LLRBNode<K, V> get min;

  LLRBNode<K, V> get max;

  int get length;

  void inOrderTraversal(NodeVisitor<K, V> visitor);

  bool shortCircuitingInOrderTraversal(
      ShortCircuitingNodeVisitor<K, V> visitor);

  bool shortCircuitingReverseOrderTraversal(
      ShortCircuitingNodeVisitor<K, V> visitor);
}
