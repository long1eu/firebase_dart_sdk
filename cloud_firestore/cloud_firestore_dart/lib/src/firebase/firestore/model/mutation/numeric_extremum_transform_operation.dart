// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:math' as math;

import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/numeric_transform_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';

/// Shared local-view logic of the minimum and maximum transforms.
///
/// If the previous value is not a number the result is the operand. If both
/// values are integers the result is an integer. Otherwise the values are
/// compared as doubles and the winner keeps its own type; on a tie the
/// previous value is kept; NaN wins over any other number.
abstract class _NumericExtremumTransformOperation
    extends NumericTransformOperation {
  _NumericExtremumTransformOperation(super.operand);

  /// Picks between two integers.
  int _pickInt(int previous, int operand);

  /// Whether [previous] should win over [operand] when they differ and neither
  /// is NaN.
  bool _choosePrevious(double previous, double operand);

  @override
  FieldValue applyToLocalView(
    FieldValue? previousValue,
    Timestamp localWriteTime,
  ) {
    final NumberValue operand = this.operand;
    if (previousValue is! NumberValue) {
      return operand;
    }

    if (_isBsonNumber(previousValue) || _isBsonNumber(operand)) {
      // NaN wins over any other number, otherwise the numbers are compared by
      // their exact value and the winner keeps its own type.
      if (_isNaN(previousValue)) {
        return previousValue;
      }
      if (_isNaN(operand)) {
        return operand;
      }
      final int cmp = operand.compareTo(previousValue);
      return cmp == 0 || _choosePrevious(0, cmp.toDouble())
          ? previousValue
          : operand;
    }

    if (previousValue is IntegerValue && operand is IntegerValue) {
      return IntegerValue.valueOf(
        _pickInt(previousValue.value, operandAsInt()),
      );
    }

    final double prevDouble = (previousValue.value as num).toDouble();
    final double operDouble = operandAsDouble();

    if (prevDouble.isNaN) {
      return previousValue;
    }
    if (operDouble.isNaN) {
      return operand;
    }
    if (prevDouble == operDouble) {
      return previousValue;
    }
    return _choosePrevious(prevDouble, operDouble) ? previousValue : operand;
  }

  static bool _isBsonNumber(NumberValue value) =>
      value is Int32FieldValue || value is Decimal128FieldValue;

  static bool _isNaN(NumberValue value) =>
      value is DoubleValue && value.value.isNaN ||
      value is Decimal128FieldValue && value.isNaN;
}

/// Implements the backend semantics for locally computed NUMERIC_MIN (minimum)
/// transforms.
class NumericMinimumTransformOperation
    extends _NumericExtremumTransformOperation {
  NumericMinimumTransformOperation(super.operand);

  @override
  int _pickInt(int previous, int operand) => math.min(previous, operand);

  @override
  bool _choosePrevious(double previous, double operand) => previous < operand;
}

/// Implements the backend semantics for locally computed NUMERIC_MAX (maximum)
/// transforms.
class NumericMaximumTransformOperation
    extends _NumericExtremumTransformOperation {
  NumericMaximumTransformOperation(super.operand);

  @override
  int _pickInt(int previous, int operand) => math.max(previous, operand);

  @override
  bool _choosePrevious(double previous, double operand) => previous > operand;
}
