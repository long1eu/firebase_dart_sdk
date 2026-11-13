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

// Ported from upstream NumericMaximumTransformOperationTest (Android main).

import 'package:cloud_firestore_dart/src/firebase/firestore/decimal128_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/int32_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/numeric_extremum_transform_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../../../util/equals_tester.dart';
import '../../../../../util/test_util.dart';

NumericMaximumTransformOperation maximum(Object operand) =>
    NumericMaximumTransformOperation(wrap(operand) as NumberValue);

FieldValue apply(NumericMaximumTransformOperation op, Object? previous) {
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
        .addEqualityGroup(<Object>[maximum(1), maximum(1)])
        .addEqualityGroup(<Object>[maximum(1.0), maximum(1.0)])
        .addEqualityGroup(<Object>[
          maximum(Int32Value(1)),
          maximum(Int32Value(1)),
        ])
        .addEqualityGroup(<Object>[
          maximum(Decimal128Value('1')),
          maximum(Decimal128Value('1')),
        ])
        .addEqualityGroup(<Object>[maximum(2)])
        .testEquals();
  });

  test('testComputeBaseValueReturnsNull', () {
    final NumericMaximumTransformOperation op = maximum(5);
    expect(op.computeBaseValue(wrap(10)), isNull);
    expect(op.computeBaseValue(null), isNull);
  });

  test('testMaximumInt32AndInt32', () {
    final NumericMaximumTransformOperation op15 = maximum(Int32Value(15));
    expect(apply(op15, Int32Value(10)), wrap(Int32Value(15)));

    final NumericMaximumTransformOperation op5 = maximum(Int32Value(5));
    expect(apply(op5, Int32Value(10)), wrap(Int32Value(10)));

    // Equal values return previousValue
    expect(apply(op5, Int32Value(5)), wrap(Int32Value(5)));
  });

  test('testMaximumAcrossTypes', () {
    // Int32 and Integer
    final NumericMaximumTransformOperation opInt32_15 = maximum(Int32Value(15));
    expect(apply(opInt32_15, 10), wrap(Int32Value(15)));

    final NumericMaximumTransformOperation opInt15 = maximum(15);
    expect(apply(opInt15, Int32Value(10)), wrap(15));

    // Int32 and Double
    expect(apply(opInt32_15, 10.5), wrap(Int32Value(15)));
    final NumericMaximumTransformOperation opDouble15 = maximum(15.0);
    expect(apply(opDouble15, Int32Value(10)), wrap(15.0));

    // Int32 and Decimal128
    final NumericMaximumTransformOperation opDec15 = maximum(
      Decimal128Value('15'),
    );
    expect(apply(opDec15, Int32Value(10)), wrap(Decimal128Value('15')));
    expect(apply(opInt32_15, Decimal128Value('10')), wrap(Int32Value(15)));

    // Double and Decimal128
    expect(apply(opDec15, 10.5), wrap(Decimal128Value('15')));
    expect(apply(opDouble15, Decimal128Value('10')), wrap(15.0));

    // Integer and Decimal128
    expect(apply(opDec15, 10), wrap(Decimal128Value('15')));
    expect(apply(opInt15, Decimal128Value('10')), wrap(15));
  });

  test('testMaximumWithNaN', () {
    // The maximum of any numeric value x and NaN is NaN
    final NumericMaximumTransformOperation opNaN = maximum(double.nan);
    expect(apply(opNaN, 10), wrap(double.nan));
    expect(apply(opNaN, Int32Value(10)), wrap(double.nan));
    expect(apply(opNaN, Decimal128Value('10')), wrap(double.nan));

    final NumericMaximumTransformOperation opDecNaN = maximum(
      Decimal128Value('NaN'),
    );
    expect(apply(opDecNaN, 10), wrap(Decimal128Value('NaN')));
    expect(apply(opDecNaN, Int32Value(10)), wrap(Decimal128Value('NaN')));

    final NumericMaximumTransformOperation opInt = maximum(10);
    expect(apply(opInt, double.nan), wrap(double.nan));
    expect(apply(opInt, Decimal128Value('NaN')), wrap(Decimal128Value('NaN')));

    // max(NaN, NaN) returns previousValue
    expect(apply(opNaN, double.nan), wrap(double.nan));
  });

  test('testMaximumNonNumericOrMissingBaseSelectsOperand', () {
    final NumericMaximumTransformOperation op = maximum(Int32Value(5));
    expect(apply(op, null), wrap(Int32Value(5)));
    expect(apply(op, 'hello'), wrap(Int32Value(5)));
    expect(apply(op, true), wrap(Int32Value(5)));
    expect(apply(op, NullValue.nullValue()), wrap(Int32Value(5)));

    final NumericMaximumTransformOperation opDec = maximum(
      Decimal128Value('5'),
    );
    expect(apply(opDec, null), wrap(Decimal128Value('5')));
    expect(apply(opDec, 'hello'), wrap(Decimal128Value('5')));
  });
}
