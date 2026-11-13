import 'package:cloud_firestore_dart/src/firebase/firestore/decimal128_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/int32_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/numeric_extremum_transform_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/numeric_increment_transform_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/transform_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

/// Cases of the iOS SDK's `Firestore/core/test/unit/model/mutation_test.cc`
/// that neither the Android nor the JS tests have: 32-bit integer saturation,
/// increments at the 32/64-bit boundary, and a chain of mixed numeric
/// transforms on one field.
///
/// iOS applies the transforms of one field of a document in order
/// (`TransformBaseDoc`); this applies the operations to the field value.
const int _int32Max = 2147483647;
const int _int32Min = -2147483648;

NumberValue _int32(int value) => wrap(Int32Value(value)) as NumberValue;

NumberValue _int64(int value) => IntegerValue.valueOf(value);

/// Applies [ops] in order to [base] and checks that the result is [expected],
/// with the same type.
void _verifyTransforms(
  FieldValue? base,
  List<TransformOperation> ops,
  FieldValue expected,
) {
  FieldValue? value = base;
  for (final TransformOperation op in ops) {
    value = op.applyToLocalView(value, Timestamp.now());
  }
  expect(value, expected);
  expect(value.runtimeType, expected.runtimeType);
}

void main() {
  test('testAppliesIncrementWithoutOverflowOnInt32', () {
    final Map<String, List<Object>> cases = <String, List<Object>>{
      'a': <Object>[_int32Max - 1, 1],
      'b': <Object>[_int32Max - 1, _int32Max],
      'c': <Object>[_int32Max, 1],
      'd': <Object>[_int32Max, _int32Max],
    };
    for (final MapEntry<String, List<Object>> entry in cases.entries) {
      _verifyTransforms(_int32(entry.value[0] as int), <TransformOperation>[
        NumericIncrementTransformOperation(_int32(entry.value[1] as int)),
      ], _int32(_int32Max));
    }
  });

  test('testAppliesIncrementWithoutUnderflowOnInt32', () {
    final Map<String, List<Object>> cases = <String, List<Object>>{
      'a': <Object>[_int32Min + 1, -1],
      'b': <Object>[_int32Min + 1, _int32Min],
      'c': <Object>[_int32Min, -1],
      'd': <Object>[_int32Min, _int32Min],
    };
    for (final MapEntry<String, List<Object>> entry in cases.entries) {
      _verifyTransforms(_int32(entry.value[0] as int), <TransformOperation>[
        NumericIncrementTransformOperation(_int32(entry.value[1] as int)),
      ], _int32(_int32Min));
    }
  });

  test('testAppliesMixedInt32AndInt64IncrementBoundaries', () {
    // int64 max + int32
    _verifyTransforms(_int64(IntegerValue.max), <TransformOperation>[
      NumericIncrementTransformOperation(_int32(10)),
    ], _int64(IntegerValue.max));
    // int64 max + int64
    _verifyTransforms(_int64(IntegerValue.max), <TransformOperation>[
      NumericIncrementTransformOperation(_int64(IntegerValue.max)),
    ], _int64(IntegerValue.max));
    // int64 min + int32
    _verifyTransforms(_int64(IntegerValue.min), <TransformOperation>[
      NumericIncrementTransformOperation(_int32(-10)),
    ], _int64(IntegerValue.min));
    // int64 min + int64
    _verifyTransforms(_int64(IntegerValue.min), <TransformOperation>[
      NumericIncrementTransformOperation(_int64(IntegerValue.min)),
    ], _int64(IntegerValue.min));
    // int32 max + int64: the sum leaves the 32-bit range and becomes an int64.
    _verifyTransforms(_int32(_int32Max), <TransformOperation>[
      NumericIncrementTransformOperation(_int64(1)),
    ], _int64(_int32Max + 1));
    // int32 min + int64
    _verifyTransforms(_int32(_int32Min), <TransformOperation>[
      NumericIncrementTransformOperation(_int64(-1)),
    ], _int64(_int32Min - 1));
  });

  test('testAppliesConsecutiveMixedNumericTransforms', () {
    _verifyTransforms(_int32(10), <TransformOperation>[
      NumericMinimumTransformOperation(_int64(15)), // retains Int32(10)
      NumericMinimumTransformOperation(_int64(5)), // selects 5L
      NumericMaximumTransformOperation(_int64(20)), // selects 20L
      NumericIncrementTransformOperation(_int64(10)), // 20 + 10 = 30L
    ], _int64(30));
  });

  test('testMinimumKeepsInt32WhenItWins', () {
    // The first step of testAppliesConsecutiveMixedNumericTransforms on its
    // own: the previous value keeps its type when it wins.
    _verifyTransforms(_int32(10), <TransformOperation>[
      NumericMinimumTransformOperation(_int64(15)),
    ], _int32(10));
  });

  test('testAppliesIncrementTransformToDocumentWithBsonTypes', () {
    final List<List<Object>> cases = <List<Object>>[
      // base, operand, expected
      <Object>[_int32(10), _int32(5), _int32(15)],
      <Object>[_int32(10), _int64(5), _int64(15)],
      <Object>[_int32(10), DoubleValue.valueOf(1.5), DoubleValue.valueOf(11.5)],
      <Object>[_int64(10), _int32(5), _int64(15)],
      <Object>[DoubleValue.valueOf(10.5), _int32(5), DoubleValue.valueOf(15.5)],
      <Object>[_decimal('10.5'), _int32(5), _decimal('15.5')],
      <Object>[_decimal('10.5'), _int64(5), _decimal('15.5')],
      <Object>[_decimal('10.5'), DoubleValue.valueOf(5.5), _decimal('16')],
      <Object>[_decimal('10.5'), _decimal('5.5'), _decimal('16')],
      <Object>[_int32(10), _decimal('5.5'), _decimal('15.5')],
      <Object>[_int64(10), _decimal('5.5'), _decimal('15.5')],
      <Object>[DoubleValue.valueOf(10.5), _decimal('5.5'), _decimal('16')],
    ];
    for (final List<Object> c in cases) {
      _verifyTransforms(c[0] as FieldValue, <TransformOperation>[
        NumericIncrementTransformOperation(c[1] as NumberValue),
      ], c[2] as FieldValue);
    }
  });
}

NumberValue _decimal(String value) =>
    wrap(Decimal128Value(value)) as NumberValue;
