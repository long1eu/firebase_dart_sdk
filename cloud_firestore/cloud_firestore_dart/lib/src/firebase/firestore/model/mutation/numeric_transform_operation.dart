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

import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/transform_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';

/// Base class for the numeric transforms (increment, minimum and maximum). It
/// holds the numeric [operand] and the shared helpers and equality.
abstract class NumericTransformOperation implements TransformOperation {
  NumericTransformOperation(this.operand);

  final NumberValue operand;

  @override
  FieldValue applyToRemoteDocument(
      FieldValue? previousValue, FieldValue transformResult) {
    return transformResult;
  }

  /// Returns null since minimum and maximum operations do not require a base
  /// value. [NumericIncrementTransformOperation] overrides this.
  @override
  FieldValue? computeBaseValue(FieldValue? previousValue) => null;

  double operandAsDouble() {
    final NumberValue operand = this.operand;
    if (operand is DoubleValue) {
      return operand.value;
    } else if (operand is IntegerValue) {
      return operand.value.toDouble();
    } else if (operand is Int32FieldValue) {
      return operand.intValue.toDouble();
    } else if (operand is Decimal128FieldValue) {
      return operand.doubleValue;
    } else {
      throw fail(
          "Expected 'operand' to be of Number type, but was ${operand.runtimeType}");
    }
  }

  int operandAsInt() {
    final NumberValue operand = this.operand;
    if (operand is DoubleValue) {
      return operand.value.toInt();
    } else if (operand is IntegerValue) {
      return operand.value;
    } else if (operand is Int32FieldValue) {
      return operand.intValue;
    } else if (operand is Decimal128FieldValue) {
      return operand.doubleValue.toInt();
    } else {
      throw fail(
          "Expected 'operand' to be of Number type, but was ${operand.runtimeType}");
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NumericTransformOperation &&
          runtimeType == other.runtimeType &&
          operand == other.operand;

  @override
  int get hashCode => Object.hash(runtimeType, operand);
}
