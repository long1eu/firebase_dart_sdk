// File created by
// Lung Razvan <int1eu>
// on 13/03/2020

import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/transform_operation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/values.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/util.dart';
import 'package:cloud_firestore_vm/src/firebase/timestamp.dart';
import 'package:cloud_firestore_vm/src/proto/google/firestore/v1/index.dart';
import 'package:fixnum/fixnum.dart';

/// Implements the backend semantics for locally computed NUMERIC_ADD
/// (increment) transforms. Converts all field values to ints or doubles and
/// resolves overflows to [IntegerValue.max]/[IntegerValue.min].
class NumericIncrementTransformOperation implements TransformOperation {
  NumericIncrementTransformOperation(this.operand) {
    hardAssert(isNumber(operand), 'NumericIncrementTransformOperation expects a NumberValue operand');
  }

  final Value operand;

  @override
  Value applyToLocalView(Value previousValue, Timestamp localWriteTime) {
    final Value baseValue = computeBaseValue(previousValue);

    // Return an integer value only if the previous value and the operand is an
    // integer.
    if (isInteger(baseValue) && isInteger(operand)) {
      final int sum = _safeIncrement(baseValue.integerValue.toInt(), _operandAsInt());
      return Value(integerValue: Int64(sum));
    } else if (isInteger(baseValue)) {
      final double sum = baseValue.integerValue.toDouble() + _operandAsDouble();
      return Value(doubleValue: sum);
    } else {
      hardAssert(isDouble(baseValue), 'Expected NumberValue to be of type DoubleValue, but was $previousValue');

      final double sum = baseValue.doubleValue + _operandAsDouble();
      return Value(doubleValue: sum);
    }
  }

  @override
  Value applyToRemoteDocument(Value previousValue, Value transformResult) {
    return transformResult;
  }

  /// Inspects the provided value, returning the provided value if it is already
  /// a [NumberValue], otherwise returning a coerced [IntegerValue] of 0.
  @override
  Value computeBaseValue(Value previousValue) {
    return isNumber(previousValue) ? previousValue : Value(integerValue: Int64(0));
  }

  int _safeIncrement(int x, int y) {
    final int r = x + y;

    // See "Hacker's Delight" 2-12: Overflow if both arguments have the opposite
    // sign of the result
    if (((x ^ r) & (y ^ r)) >= 0) {
      return r;
    }

    return r >= 0 ? kMinInt : kMaxInt;
  }

  double _operandAsDouble() {
    if (isDouble(operand)) {
      return operand.doubleValue;
    } else if (isInteger(operand)) {
      return operand.integerValue.toDouble();
    } else {
      throw fail("Expected 'operand' to be of Number type, but was ${operand.runtimeType}");
    }
  }

  int _operandAsInt() {
    if (isDouble(operand)) {
      return operand.doubleValue.toInt();
    } else if (isInteger(operand)) {
      return operand.integerValue.toInt();
    } else {
      throw fail("Expected 'operand' to be of Number type, but was ${operand.runtimeType}");
    }
  }
}
