// Copyright 2024 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Ported from upstream NumericIncrementTransformOperationTest (main). The
// Int32Value / Decimal128Value cases are skipped: the port has no such value
// types.

import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/numeric_increment_transform_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../../../util/equals_tester.dart';
import '../../../../../util/test_util.dart';

NumericIncrementTransformOperation increment(Object operand) =>
    NumericIncrementTransformOperation(wrap(operand) as NumberValue);

FieldValue apply(NumericIncrementTransformOperation op, Object? previous) {
  final FieldValue? prev = previous == null
      ? null
      : (previous is FieldValue ? previous : wrap(previous));
  return op.applyToLocalView(prev, Timestamp.now());
}

void main() {
  const String noInt32 = 'Int32Value is not implemented in the port';
  const String noDecimal = 'Decimal128Value is not implemented in the port';

  test('testConstructorRequiresNumericOperand',
      skip: 'the operand is statically typed as NumberValue in Dart, so '
          'non-numeric operands are rejected by the compiler',
      () {});

  test('testEqualsAndHashCode', () {
    // The Int32Value and Decimal128Value groups are not portable.
    EqualsTester()
        .addEqualityGroup(<Object>[increment(1), increment(1)])
        .addEqualityGroup(<Object>[increment(1.0), increment(1.0)])
        .addEqualityGroup(<Object>[increment(2)])
        .testEquals();
  });

  test('testComputeBaseValue', () {
    final NumericIncrementTransformOperation op = increment(1);

    expect(op.computeBaseValue(wrap(10)), wrap(10));
    expect(op.computeBaseValue(wrap(10.5)), wrap(10.5));

    expect(op.computeBaseValue(null), wrap(0));
    expect(op.computeBaseValue(wrap('hello')), wrap(0));
    expect(op.computeBaseValue(wrap(true)), wrap(0));
    expect(op.computeBaseValue(NullValue.nullValue()), wrap(0));
  });

  test('testIncrementInt32AndInt32', skip: noInt32, () {});
  test('testIncrementInt32Saturation', skip: noInt32, () {});
  test('testIncrementInt32BaseWithOtherOperandTypes', skip: noInt32, () {});
  test('testIncrementIntegerBaseWithInt32Operand', skip: noInt32, () {});
  test('testIncrementDoubleBaseWithInt32Operand', skip: noInt32, () {});
  test('testIncrementDecimal128Approximation', skip: noDecimal, () {});

  test('testIncrementIntegerSaturation', () {
    final NumericIncrementTransformOperation opPositive = increment(1);
    expect(apply(opPositive, IntegerValue.max), wrap(IntegerValue.max));

    final NumericIncrementTransformOperation opNegative = increment(-1);
    expect(apply(opNegative, IntegerValue.min), wrap(IntegerValue.min));

    // The "Integer base + Int32 operand saturation" case is not portable.
  });

  test('testIncrementMissingOrNonNumericBase', () {
    // Missing base -> 0 + operand
    final NumericIncrementTransformOperation opInt = increment(5);
    expect(apply(opInt, null), wrap(5));

    final NumericIncrementTransformOperation opDouble = increment(5.5);
    expect(apply(opDouble, null), wrap(5.5));

    // Non-numeric base -> 0 + operand
    expect(apply(opInt, 'hello'), wrap(5));
    expect(apply(opDouble, 'hello'), wrap(5.5));

    // The Int32Value and Decimal128Value operand cases are not portable.
  });
}
