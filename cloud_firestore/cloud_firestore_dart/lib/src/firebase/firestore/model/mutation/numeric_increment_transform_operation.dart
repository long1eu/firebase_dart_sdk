// File created by
// Lung Razvan <int1eu>
// on 13/03/2020

import 'package:cloud_firestore_dart/src/firebase/firestore/decimal128_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/int32_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/numeric_transform_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';

/// Implements the backend semantics for locally computed NUMERIC_ADD
/// (increment) transforms. Converts all field values to ints or doubles and
/// resolves overflows to [IntegerValue.max]/[IntegerValue.min].
class NumericIncrementTransformOperation extends NumericTransformOperation {
  NumericIncrementTransformOperation(super.operand);

  @override
  FieldValue applyToLocalView(
    FieldValue? previousValue,
    Timestamp localWriteTime,
  ) {
    final NumberValue baseValue = computeBaseValue(previousValue);

    final NumberValue operand = this.operand;

    // If either is a Decimal128, approximate the sum as a double and return a
    // Decimal128. The backend computes the precise sum.
    if (baseValue is Decimal128FieldValue || operand is Decimal128FieldValue) {
      final double base = baseValue is Decimal128FieldValue
          ? baseValue.doubleValue
          : baseValue is Int32FieldValue
          ? baseValue.intValue.toDouble()
          : (baseValue.value as num).toDouble();
      return Decimal128FieldValue.valueOf(
        Decimal128Value(_decimalString(base + operandAsDouble())),
      );
    }

    if (baseValue is Int32FieldValue) {
      if (operand is DoubleValue) {
        return DoubleValue.valueOf(baseValue.intValue + operand.value);
      } else if (operand is Int32FieldValue) {
        // The sum of two 32-bit integers is a 32-bit integer, which saturates.
        final int sum = (baseValue.intValue + operand.intValue).clamp(
          Int32Value.minValue,
          Int32Value.maxValue,
        );
        return Int32FieldValue.valueOf(Int32Value(sum));
      } else {
        return IntegerValue.valueOf(
          _safeIncrement(baseValue.intValue, operandAsInt()),
        );
      }
    }

    // Return an integer value only if the previous value and the operand is an
    // integer.
    if (baseValue is IntegerValue &&
        (operand is IntegerValue || operand is Int32FieldValue)) {
      final int sum = _safeIncrement(baseValue.value, operandAsInt());
      return IntegerValue.valueOf(sum);
    } else if (baseValue is IntegerValue) {
      final double sum = baseValue.value + operandAsDouble();
      return DoubleValue.valueOf(sum);
    } else {
      // Every other number type is handled above: this is a double.
      final double sum = (baseValue as DoubleValue).value + operandAsDouble();
      return DoubleValue.valueOf(sum);
    }
  }

  /// The decimal string of a locally computed sum.
  static String _decimalString(double sum) {
    if (sum.isNaN) {
      return 'NaN';
    } else if (sum == double.infinity) {
      return 'Infinity';
    } else if (sum == double.negativeInfinity) {
      return '-Infinity';
    } else if (sum == 0) {
      return sum.isNegative ? '-0' : '0';
    } else if (sum == sum.truncateToDouble() && sum.abs() < 9.2e18) {
      return sum.toInt().toString();
    }
    return sum.toString();
  }

  /// Inspects the provided value, returning the provided value if it is already
  /// a [NumberValue], otherwise returning a coerced [IntegerValue] of 0.
  @override
  NumberValue computeBaseValue(FieldValue? previousValue) {
    return previousValue is NumberValue
        ? previousValue
        : IntegerValue.valueOf(0);
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
}
