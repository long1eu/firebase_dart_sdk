// File created by
// Lung Razvan <long1eu>
// on 19/09/2018

import 'package:firebase_database_collection/src/llrb_black_value_node.dart';
import 'package:firebase_database_collection/src/llrb_empty_node.dart';
import 'package:firebase_database_collection/src/llrb_node.dart';
import 'package:firebase_database_collection/src/llrb_red_value_node.dart';

abstract class LLRBValueNode<K, V> implements LLRBNode<K, V> {
  static LLRBNodeColor _oppositeColor(LLRBNode node) {
    return node.isRed ? LLRBNodeColor.black : LLRBNodeColor.red;
  }

  @override
  final K key;
  @override
  final V value;

  @override
  final LLRBNode<K, V> right;

  LLRBNode<K, V> _left;

  LLRBValueNode(this.key, this.value, LLRBNode<K, V> left, LLRBNode<K, V> right)
      : _left = left ?? LLRBEmptyNode<K, V>(),
        right = right ?? LLRBEmptyNode<K, V>();

  LLRBNodeColor get color;

  LLRBValueNode<K, V> copyWith(
      K key, V value, LLRBNode<K, V> left, LLRBNode<K, V> right);

  @override
  LLRBValueNode<K, V> copy(K key, V value, LLRBNodeColor color,
      LLRBNode<K, V> left, LLRBNode<K, V> right) {
    final K newKey = key == null ? this.key : key;
    final V newValue = value == null ? this.value : value;
    final LLRBNode<K, V> newLeft = left == null ? this.left : left;
    final LLRBNode<K, V> newRight = right == null ? this.right : right;
    if (color == LLRBNodeColor.red) {
      return LLRBRedValueNode<K, V>(newKey, newValue, newLeft, newRight);
    } else {
      return LLRBBlackValueNode<K, V>(newKey, newValue, newLeft, newRight);
    }
  }

  @override
  LLRBNode<K, V> insert(K key, V value, Comparator<K> comparator) {
    final int cmp = comparator(key, this.key);
    LLRBValueNode<K, V> n;
    if (cmp < 0) {
      // new key is less than current key
      LLRBNode<K, V> newLeft = this.left.insert(key, value, comparator);
      n = copyWith(null, null, newLeft, null);
    } else if (cmp == 0) {
      // same key
      n = copyWith(key, value, null, null);
    } else {
      // new key is greater than current key
      LLRBNode<K, V> newRight = this.right.insert(key, value, comparator);
      n = copyWith(null, null, null, newRight);
    }
    return n._fixUp();
  }

  @override
  LLRBNode<K, V> remove(K key, Comparator<K> comparator) {
    LLRBValueNode<K, V> n = this;

    if (comparator(key, n.key) < 0) {
      if (!n.left.isEmpty && !n.left.isRed && !n.left.left.isRed) {
        n = n._moveRedLeft();
      }
      n = n.copyWith(null, null, n.left.remove(key, comparator), null);
    } else {
      if (n.left.isRed) {
        n = n._rotateRight();
      }

      if (!n.right.isEmpty &&
          !n.right.isRed &&
          !(n.right as LLRBValueNode<K, V>).left.isRed) {
        n = n._moveRedRight();
      }

      if (comparator(key, n.key) == 0) {
        if (n.right.isEmpty) {
          return LLRBEmptyNode<K, V>();
        } else {
          LLRBNode<K, V> smallest = n.right.min;
          n = n.copyWith(smallest.key, smallest.value, null,
              (n.right as LLRBValueNode<K, V>).removeMin());
        }
      }
      n = n.copyWith(null, null, null, n.right.remove(key, comparator));
    }
    return n._fixUp();
  }

  @override
  final bool isEmpty = false;

  @override
  LLRBNode<K, V> get min {
    if (left.isEmpty) {
      return this;
    } else {
      return left.min;
    }
  }

  @override
  LLRBNode<K, V> get max {
    if (right.isEmpty) {
      return this;
    } else {
      return right.max;
    }
  }

  @override
  void inOrderTraversal(NodeVisitor<K, V> visitor) {
    left.inOrderTraversal(visitor);
    visitor.visitEntry(key, value);
    right.inOrderTraversal(visitor);
  }

  @override
  bool shortCircuitingInOrderTraversal(
      ShortCircuitingNodeVisitor<K, V> visitor) {
    if (left.shortCircuitingInOrderTraversal(visitor)) {
      if (visitor.shouldContinue(key, value)) {
        return right.shortCircuitingInOrderTraversal(visitor);
      }
    }
    return false;
  }

  @override
  bool shortCircuitingReverseOrderTraversal(
      ShortCircuitingNodeVisitor<K, V> visitor) {
    if (right.shortCircuitingReverseOrderTraversal(visitor)) {
      if (visitor.shouldContinue(key, value)) {
        return left.shortCircuitingReverseOrderTraversal(visitor);
      }
    }
    return false;
  }

  // For use by the builder, which is package local
  LLRBNode<K, V> get left => _left;

  set left(LLRBNode<K, V> left) {
    _left = left;
  }

  LLRBNode<K, V> removeMin() {
    if (left.isEmpty) {
      return LLRBEmptyNode<K, V>();
    } else {
      LLRBValueNode<K, V> n = this;
      if (!n.left.isRed && !n.left.left.isRed) {
        n = n._moveRedLeft();
      }

      n = n.copyWith(
          null, null, (n.left as LLRBValueNode<K, V>).removeMin(), null);
      return n._fixUp();
    }
  }

  LLRBValueNode<K, V> _moveRedLeft() {
    LLRBValueNode<K, V> n = _colorFlip();
    if (n.right.left.isRed) {
      n = n.copyWith(
          null, null, null, (n.right as LLRBValueNode<K, V>)._rotateRight());
      n = n._rotateLeft();
      n = n._colorFlip();
    }
    return n;
  }

  LLRBValueNode<K, V> _moveRedRight() {
    LLRBValueNode<K, V> n = _colorFlip();
    if (n.left.left.isRed) {
      n = n._rotateRight();
      n = n._colorFlip();
    }
    return n;
  }

  LLRBValueNode<K, V> _fixUp() {
    LLRBValueNode<K, V> n = this;
    if (n.right.isRed && !n.left.isRed) {
      n = n._rotateLeft();
    }
    if (n.left.isRed && ((n.left) as LLRBValueNode<K, V>).left.isRed) {
      n = n._rotateRight();
    }
    if (n.left.isRed && n.right.isRed) {
      n = n._colorFlip();
    }
    return n;
  }

  LLRBValueNode<K, V> _rotateLeft() {
    LLRBValueNode<K, V> newLeft = this.copy(null, null, LLRBNodeColor.red, null,
        (this.right as LLRBValueNode<K, V>).left);
    return this.right.copy(null, null, this.color, newLeft, null)
        as LLRBValueNode<K, V>;
  }

  LLRBValueNode<K, V> _rotateRight() {
    LLRBValueNode<K, V> newRight = this.copy(null, null, LLRBNodeColor.red,
        (this.left as LLRBValueNode<K, V>).right, null);
    return this.left.copy(null, null, this.color, null, newRight)
        as LLRBValueNode<K, V>;
  }

  LLRBValueNode<K, V> _colorFlip() {
    LLRBNode<K, V> newLeft =
        this.left.copy(null, null, _oppositeColor(this.left), null, null);
    LLRBNode<K, V> newRight =
        this.right.copy(null, null, _oppositeColor(this.right), null, null);

    return this.copy(null, null, _oppositeColor(this), newLeft, newRight);
  }
}
