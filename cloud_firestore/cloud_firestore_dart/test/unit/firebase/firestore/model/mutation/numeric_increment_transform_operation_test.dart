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

// Ported from upstream NumericIncrementTransformOperationTest (Android main).

import 'package:cloud_firestore_dart/src/firebase/firestore/decimal128_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/int32_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/numeric_increment_transform_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../../../util/equals_tester.dart';
import '../../../../../util/test_util.dart';

const int _int32Max = 2147483647;
const int _int32Min = -2147483648;

NumericIncrementTransformOperation increment(Object operand) =>
    NumericIncrementTransformOperation(wrap(operand) as NumberValue);

FieldValue apply(NumericIncrementTransformOperation op, Object? previous) {
  final FieldValue? prev = previous == null
      ? null
      : (previous is FieldValue ? previous : wrap(previous));
  return op.applyToLocalView(prev, Timestamp.now());
}

void main() {
  test(
    'testConstructorRequiresNumericOperand',
    skip:
        'the operand is statically typed as NumberValue in Dart, so '
        'non-numeric operands are rejected by the compiler',
    () {},
  );

  test('testEqualsAndHashCode', () {
    EqualsTester()
        .addEqualityGroup(<Object>[increment(1), increment(1)])
        .addEqualityGroup(<Object>[increment(1.0), increment(1.0)])
        .addEqualityGroup(<Object>[
          increment(Int32Value(1)),
          increment(Int32Value(1)),
        ])
        .addEqualityGroup(<Object>[
          increment(Decimal128Value('1')),
          increment(Decimal128Value('1')),
        ])
        .addEqualityGroup(<Object>[increment(2)])
        .testEquals();
  });

  test('testComputeBaseValue', () {
    final NumericIncrementTransformOperation op = increment(1);

    expect(op.computeBaseValue(wrap(10)), wrap(10));
    expect(op.computeBaseValue(wrap(10.5)), wrap(10.5));
    expect(op.computeBaseValue(wrap(Int32Value(10))), wrap(Int32Value(10)));
    expect(
      op.computeBaseValue(wrap(Decimal128Value('10'))),
      wrap(Decimal128Value('10')),
    );

    expect(op.computeBaseValue(null), wrap(0));
    expect(op.computeBaseValue(wrap('hello')), wrap(0));
    expect(op.computeBaseValue(wrap(true)), wrap(0));
    expect(op.computeBaseValue(NullValue.nullValue()), wrap(0));
  });

  test('testIncrementInt32AndInt32', () {
    final NumericIncrementTransformOperation op = increment(Int32Value(5));
    expect(apply(op, Int32Value(10)), wrap(Int32Value(15)));
    expect(apply(op, Int32Value(0)), wrap(Int32Value(5)));
    expect(apply(op, Int32Value(-5)), wrap(Int32Value(0)));
  });

  test('testIncrementInt32Saturation', () {
    final NumericIncrementTransformOperation opPositive = increment(
      Int32Value(1),
    );
    expect(
      apply(opPositive, Int32Value(_int32Max)),
      wrap(Int32Value(_int32Max)),
    );
    expect(
      apply(increment(Int32Value(100)), Int32Value(_int32Max - 10)),
      wrap(Int32Value(_int32Max)),
    );

    final NumericIncrementTransformOperation opNegative = increment(
      Int32Value(-1),
    );
    expect(
      apply(opNegative, Int32Value(_int32Min)),
      wrap(Int32Value(_int32Min)),
    );
    expect(
      apply(increment(Int32Value(-100)), Int32Value(_int32Min + 10)),
      wrap(Int32Value(_int32Min)),
    );
  });

  test('testIncrementInt32BaseWithOtherOperandTypes', () {
    // Int32 base + Integer operand -> Integer
    final NumericIncrementTransformOperation opInt = increment(5);
    expect(apply(opInt, Int32Value(10)), wrap(15));

    // Int32 base + Double operand -> Double
    final NumericIncrementTransformOperation opDouble = increment(2.5);
    expect(apply(opDouble, Int32Value(10)), wrap(12.5));

    // Int32 base + Decimal128 operand -> Decimal128
    final NumericIncrementTransformOperation opDec = increment(
      Decimal128Value('5'),
    );
    expect(apply(opDec, Int32Value(10)), wrap(Decimal128Value('15')));
  });

  test('testIncrementIntegerBaseWithInt32Operand', () {
    final NumericIncrementTransformOperation op = increment(Int32Value(5));
    expect(apply(op, 10), wrap(15));
  });

  test('testIncrementIntegerSaturation', () {
    final NumericIncrementTransformOperation opPositive = increment(1);
    expect(apply(opPositive, IntegerValue.max), wrap(IntegerValue.max));

    final NumericIncrementTransformOperation opNegative = increment(-1);
    expect(apply(opNegative, IntegerValue.min), wrap(IntegerValue.min));

    // Integer base + Int32 operand saturation
    final NumericIncrementTransformOperation opInt32 = increment(Int32Value(1));
    expect(apply(opInt32, IntegerValue.max), wrap(IntegerValue.max));
  });

  test('testIncrementDoubleBaseWithInt32Operand', () {
    final NumericIncrementTransformOperation op = increment(Int32Value(5));
    expect(apply(op, 10.5), wrap(15.5));
  });

  test('testIncrementDecimal128Approximation', () {
    // Decimal128 base + Integer operand -> Decimal128
    final NumericIncrementTransformOperation opInt = increment(5);
    expect(apply(opInt, Decimal128Value('10')), wrap(Decimal128Value('15')));

    // Decimal128 base + Double operand -> Decimal128
    final NumericIncrementTransformOperation opDouble = increment(5.5);
    expect(
      apply(opDouble, Decimal128Value('10')),
      wrap(Decimal128Value('15.5')),
    );

    // Decimal128 base + Int32 operand -> Decimal128
    final NumericIncrementTransformOperation opInt32 = increment(Int32Value(5));
    expect(apply(opInt32, Decimal128Value('10')), wrap(Decimal128Value('15')));

    // Decimal128 base + Decimal128 operand -> Decimal128
    final NumericIncrementTransformOperation opDec = increment(
      Decimal128Value('5'),
    );
    expect(apply(opDec, Decimal128Value('10')), wrap(Decimal128Value('15')));

    // Integer base + Decimal128 operand -> Decimal128
    expect(apply(opDec, 10), wrap(Decimal128Value('15')));

    // Double base + Decimal128 operand -> Decimal128
    expect(apply(opDec, 10.5), wrap(Decimal128Value('15.5')));

    // Decimal128 with NaN
    final NumericIncrementTransformOperation opNan = increment(
      Decimal128Value('NaN'),
    );
    expect(apply(opNan, 10), wrap(Decimal128Value('NaN')));
    expect(apply(opInt, Decimal128Value('NaN')), wrap(Decimal128Value('NaN')));

    // Decimal128 with Infinity
    final NumericIncrementTransformOperation opInf = increment(
      Decimal128Value('Infinity'),
    );
    expect(apply(opInf, 10), wrap(Decimal128Value('Infinity')));

    // Decimal128 with -Infinity
    final NumericIncrementTransformOperation opNegInf = increment(
      Decimal128Value('-Infinity'),
    );
    expect(apply(opNegInf, 10), wrap(Decimal128Value('-Infinity')));
  });

  test('testIncrementMissingOrNonNumericBase', () {
    // Missing base -> 0 + operand
    final NumericIncrementTransformOperation opInt = increment(5);
    expect(apply(opInt, null), wrap(5));

    final NumericIncrementTransformOperation opDouble = increment(5.5);
    expect(apply(opDouble, null), wrap(5.5));

    final NumericIncrementTransformOperation opInt32 = increment(Int32Value(5));
    expect(apply(opInt32, null), wrap(5));

    final NumericIncrementTransformOperation opDec = increment(
      Decimal128Value('5'),
    );
    expect(apply(opDec, null), wrap(Decimal128Value('5')));

    // Non-numeric base -> 0 + operand
    expect(apply(opInt, 'hello'), wrap(5));
    expect(apply(opDouble, 'hello'), wrap(5.5));
    expect(apply(opInt32, 'hello'), wrap(5));
    expect(apply(opDec, 'hello'), wrap(Decimal128Value('5')));
  });
}
