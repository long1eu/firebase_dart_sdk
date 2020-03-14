// File created by
// Lung Razvan <int1eu>
// on 13/03/2020

import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/transform_operation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/value/double_value.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/value/integer_value.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/value/number_value.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_vm/src/firebase/timestamp.dart';

/// Implements the backend semantics for locally computed NUMERIC_ADD
/// (increment) transforms. Converts all field values to ints or doubles and
/// resolves overflows to [IntegerValue.max]/[IntegerValue.min].
class NumericIncrementTransformOperation implements TransformOperation {
  NumericIncrementTransformOperation(this.operand);

  final NumberValue operand;

  @override
  FieldValue applyToLocalView(
      FieldValue previousValue, Timestamp localWriteTime) {
    // Return an integer value only if the previous value and the operand is an
    // integer.
    if (previousValue is IntegerValue && operand is IntegerValue) {
      final int sum = _safeIncrement(previousValue.value, _operandAsInt());
      return IntegerValue.valueOf(sum);
    } else if (previousValue is IntegerValue) {
      final double sum = previousValue.value + _operandAsDouble();
      return DoubleValue.valueOf(sum);
    } else if (previousValue is DoubleValue) {
      final double sum = previousValue.value + _operandAsDouble();
      return DoubleValue.valueOf(sum);
    }

    // If the existing value is not a number, use the value of the transform as
    // the new base value.
    return operand;
  }

  int _safeIncrement(int x, int y) {
    final int r = x + y;

    // See "Hacker's Delight" 2-12: Overflow if both arguments have the opposite
    // sign of the result
    if (((x ^ r) & (y ^ r)) >= 0) {
      return r;
    }

    if (r >= 0) {
      return IntegerValue.min;
    } else {
      return IntegerValue.max;
    }
  }

  double _operandAsDouble() {
    if (operand is DoubleValue) {
      return operand.value;
    } else if (operand is IntegerValue) {
      return operand.value.toDouble();
    } else {
      throw fail(
          "Expected 'operand' to be of Number type, but was ${operand.runtimeType}");
    }
  }

  int _operandAsInt() {
    if (operand is DoubleValue) {
      return operand.value.toInt();
    } else if (operand is IntegerValue) {
      return operand.value;
    } else {
      throw fail(
          "Expected 'operand' to be of Number type, but was ${operand.runtimeType}");
    }
  }

  @override
  FieldValue applyToRemoteDocument(
      FieldValue previousValue, FieldValue transformResult) {
    return transformResult;
  }

  @override
  bool get isIdempotent => false;
}
