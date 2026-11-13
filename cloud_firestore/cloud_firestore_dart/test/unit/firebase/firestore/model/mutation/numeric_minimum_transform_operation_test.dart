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

// Ported from upstream NumericMinimumTransformOperationTest (Android main).

import 'package:cloud_firestore_dart/src/firebase/firestore/decimal128_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/int32_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/numeric_extremum_transform_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../../../util/equals_tester.dart';
import '../../../../../util/test_util.dart';

NumericMinimumTransformOperation minimum(Object operand) =>
    NumericMinimumTransformOperation(wrap(operand) as NumberValue);

FieldValue apply(NumericMinimumTransformOperation op, Object? previous) {
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
        .addEqualityGroup(<Object>[minimum(1), minimum(1)])
        .addEqualityGroup(<Object>[minimum(1.0), minimum(1.0)])
        .addEqualityGroup(<Object>[
          minimum(Int32Value(1)),
          minimum(Int32Value(1)),
        ])
        .addEqualityGroup(<Object>[
          minimum(Decimal128Value('1')),
          minimum(Decimal128Value('1')),
        ])
        .addEqualityGroup(<Object>[minimum(2)])
        .testEquals();
  });

  test('testComputeBaseValueReturnsNull', () {
    final NumericMinimumTransformOperation op = minimum(5);
    expect(op.computeBaseValue(wrap(10)), isNull);
    expect(op.computeBaseValue(null), isNull);
  });

  test('testMinimumInt32AndInt32', () {
    final NumericMinimumTransformOperation op5 = minimum(Int32Value(5));
    expect(apply(op5, Int32Value(10)), wrap(Int32Value(5)));

    final NumericMinimumTransformOperation op15 = minimum(Int32Value(15));
    expect(apply(op15, Int32Value(10)), wrap(Int32Value(10)));

    // Equal values return previousValue
    expect(apply(op5, Int32Value(5)), wrap(Int32Value(5)));
  });

  test('testMinimumAcrossTypes', () {
    // Int32 and Integer
    final NumericMinimumTransformOperation opInt32_5 = minimum(Int32Value(5));
    expect(apply(opInt32_5, 10), wrap(Int32Value(5)));

    final NumericMinimumTransformOperation opInt5 = minimum(5);
    expect(apply(opInt5, Int32Value(10)), wrap(5));

    // Int32 and Double
    expect(apply(opInt32_5, 10.5), wrap(Int32Value(5)));
    final NumericMinimumTransformOperation opDouble5 = minimum(5.0);
    expect(apply(opDouble5, Int32Value(10)), wrap(5.0));

    // Int32 and Decimal128
    final NumericMinimumTransformOperation opDec5 = minimum(
      Decimal128Value('5'),
    );
    expect(apply(opDec5, Int32Value(10)), wrap(Decimal128Value('5')));
    expect(apply(opInt32_5, Decimal128Value('10')), wrap(Int32Value(5)));

    // Double and Decimal128
    expect(apply(opDec5, 10.5), wrap(Decimal128Value('5')));
    expect(apply(opDouble5, Decimal128Value('10')), wrap(5.0));

    // Integer and Decimal128
    expect(apply(opDec5, 10), wrap(Decimal128Value('5')));
    expect(apply(opInt5, Decimal128Value('10')), wrap(5));
  });

  test('testMinimumWithNaN', () {
    // NaN is smaller than all numbers in Firestore ordering
    final NumericMinimumTransformOperation opNaN = minimum(double.nan);
    expect(apply(opNaN, 10), wrap(double.nan));
    expect(apply(opNaN, Int32Value(10)), wrap(double.nan));
    expect(apply(opNaN, Decimal128Value('10')), wrap(double.nan));

    final NumericMinimumTransformOperation opDecNaN = minimum(
      Decimal128Value('NaN'),
    );
    expect(apply(opDecNaN, 10), wrap(Decimal128Value('NaN')));
    expect(apply(opDecNaN, Int32Value(10)), wrap(Decimal128Value('NaN')));

    final NumericMinimumTransformOperation opInt = minimum(10);
    expect(apply(opInt, double.nan), wrap(double.nan));
    expect(apply(opInt, Decimal128Value('NaN')), wrap(Decimal128Value('NaN')));
  });

  test('testMinimumNonNumericOrMissingBaseSelectsOperand', () {
    final NumericMinimumTransformOperation op = minimum(Int32Value(5));
    expect(apply(op, null), wrap(Int32Value(5)));
    expect(apply(op, 'hello'), wrap(Int32Value(5)));
    expect(apply(op, true), wrap(Int32Value(5)));
    expect(apply(op, NullValue.nullValue()), wrap(Int32Value(5)));

    final NumericMinimumTransformOperation opDec = minimum(
      Decimal128Value('5'),
    );
    expect(apply(opDec, null), wrap(Decimal128Value('5')));
    expect(apply(opDec, 'hello'), wrap(Decimal128Value('5')));
  });
}
