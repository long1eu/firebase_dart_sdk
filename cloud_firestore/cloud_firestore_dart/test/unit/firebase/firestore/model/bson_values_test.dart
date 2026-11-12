// Ported from the BSON cases of the Android SDK's ValuesTest, MutationTest,
// NumericIncrementTransformOperationTest and
// Numeric{Minimum,Maximum}TransformOperationTest.

import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart' hide FieldValue;
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/numeric_extremum_transform_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/numeric_increment_transform_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:test/test.dart';

import '../../../../util/comparator_test.dart';
import '../../../../util/equals_tester.dart';
import '../../../../util/test_util.dart';

Blob _binary(int subtype, [List<int> bytes = const <int>[]]) =>
    Blob.bsonBinary(subtype, Uint8List.fromList(bytes));

FieldValue _dec(String value) => wrap(Decimal128Value(value));

FieldValue _int32(int value) => wrap(Int32Value(value));

void main() {
  final DateTime date1 = DateTime.utc(2016, 5, 20, 10, 20);
  final DateTime date2 = DateTime.utc(2016, 10, 21, 15, 32);

  test('testValueEquality', () {
    EqualsTester().addEqualityGroup(<Object>[wrap(1), wrap(1)]).addEqualityGroup(<Object>[wrap(1.0), wrap(1.0)]).addEqualityGroup(<Object>[
      wrap(blob(<int>[1, 2])),
      wrap(_binary(0, <int>[1, 2]))
    ]).addEqualityGroup(<Object>[
      wrap(BsonObjectId('507f191e810c19729de860ea')),
      wrap(BsonObjectId('507f191e810c19729de860ea'))
    ]).addEqualityGroup(<Object>[wrap(BsonObjectId('507f191e810c19729de860eb'))]).addEqualityGroup(<Object>[
      wrap(_binary(1, <int>[1, 2])),
      wrap(_binary(1, <int>[1, 2]))
    ]).addEqualityGroup(<Object>[
      wrap(_binary(1, <int>[1, 2, 3]))
    ]).addEqualityGroup(<Object>[
      wrap(_binary(2, <int>[1, 2]))
    ]).addEqualityGroup(<Object>[wrap(BsonTimestamp(1, 2)), wrap(BsonTimestamp(1, 2))]).addEqualityGroup(<Object>[wrap(BsonTimestamp(1, 3))]).addEqualityGroup(
            <Object>[wrap(BsonTimestamp(2, 2))])
        // PORTING NOTE: like in the JS SDK, numbers of different types are not
        // equal, even if they compare as equal.
        .addEqualityGroup(<Object>[_int32(1), _int32(1)]).addEqualityGroup(<Object>[_int32(2)]).addEqualityGroup(<Object>[_dec('-1.2e3'), _dec('-1.2e3'), _dec('-1200')]).addEqualityGroup(<Object>[_dec('0.0'), _dec('0'), _dec('-0')]).addEqualityGroup(
            <Object>[_dec('1.2e-3'), _dec('0.0012')]).addEqualityGroup(<Object>[_dec('1'), _dec('1.0')]).addEqualityGroup(<Object>[
      wrap(const RegexValue('^foo', 'i')),
      wrap(const RegexValue('^foo', 'i'))
    ]).addEqualityGroup(<Object>[wrap(const RegexValue('^foo', 'm'))]).addEqualityGroup(<Object>[wrap(const RegexValue('^bar', 'i'))]).addEqualityGroup(
            <Object>[wrap(MinKey.instance), wrap(MinKey.instance)]).addEqualityGroup(<Object>[wrap(MaxKey.instance), wrap(MaxKey.instance)])
        // A map in the model is not the BSON value it has the shape of. (A
        // query value, which wrap() parses, is resolved to the BSON value, see
        // bson_shaped_maps_test.dart.)
        .addEqualityGroup(<Object>[
      ObjectValue.fromMap(<String, FieldValue>{'__int__': wrap(1)}),
      ObjectValue.fromMap(<String, FieldValue>{'__int__': wrap(1)})
    ])
        // A map that only looks like a BSON type is a map.
        .addEqualityGroup(<Object>[
      wrap(<String, Object?>{'__int__': 'a'})
    ]).testEquals();
    expect(wrap(<String, Object?>{'__int__': 1}), _int32(1));
  });

  test('testValueOrdering', () {
    ComparatorTester<dynamic>()
        // do not test for compatibility with equals(): +0/-0 break it.
        .permitInconsistencyWithEquals()

        // null first
        .addItem(wrap(null))

        // MinKey is after null
        .addItem(wrap(MinKey.instance))

        // booleans
        .addItem(wrap(false))
        .addItem(wrap(true))

        // 64-bit and 32-bit numbers order together numerically.
        .addEqualityGroup(<Object>[wrap(double.nan), _dec('NaN')])
        .addEqualityGroup(
            <Object>[wrap(double.negativeInfinity), _dec('-Infinity')])
        .addItem(wrap(-double.maxFinite))
        .addEqualityGroup(
            <Object>[wrap(IntegerValue.min), _dec('-9223372036854775808')])
        .addEqualityGroup(<Object>[
          _int32(-2147483648),
          wrap(-2147483648),
          _dec('-2147483648')
        ])
        .addEqualityGroup(<Object>[wrap(-1.5), _dec('-1.5')])
        .addEqualityGroup(<Object>[wrap(-1.0), _dec('-1.0')])
        .addItem(wrap(-DoubleValue.minNormal))
        .addItem(wrap(-double.minPositive))
        // Zeros all compare the same.
        .addEqualityGroup(<Object>[
          wrap(-0.0),
          wrap(0.0),
          wrap(0),
          _int32(0),
          _dec('0'),
          _dec('0.0'),
          _dec('-0'),
          _dec('-0.0'),
          _dec('+0'),
          _dec('+0.0')
        ])
        .addItem(wrap(double.minPositive))
        .addItem(wrap(DoubleValue.minNormal))
        .addEqualityGroup(<Object>[wrap(0.5), _dec('0.5')])
        // Doubles, Longs, Int32Values compareTo() the same.
        .addEqualityGroup(
            <Object>[wrap(1.0), wrap(1), _int32(1), _dec('1'), _dec('1.0')])
        // A decimal without an exact double is not equal to the closest double.
        .addItem(_dec('1.1'))
        .addItem(wrap(1.1))
        .addEqualityGroup(<Object>[
          _int32(2147483647),
          wrap(2147483647),
          _dec('2.147483647e9')
        ])
        .addItem(wrap(IntegerValue.max))
        .addItem(wrap(double.maxFinite))
        .addEqualityGroup(<Object>[wrap(double.infinity), _dec('Infinity')])

        // dates
        .addItem(wrap(date1))
        .addItem(wrap(date2))

        // bson timestamps
        .addItem(wrap(BsonTimestamp(123, 4)))
        .addItem(wrap(BsonTimestamp(123, 5)))
        .addItem(wrap(BsonTimestamp(124, 0)))

        // server timestamps come after all concrete timestamps.
        .addItem(ServerTimestampValue(Timestamp.fromDate(date1), null))
        .addItem(ServerTimestampValue(Timestamp.fromDate(date2), null))

        // strings
        .addItem(wrap(''))
        .addItem(wrap('a'))
        .addItem(wrap('\u00e9a'))

        // blobs
        .addEqualityGroup(<Object>[wrap(blob()), wrap(_binary(0))])
        .addEqualityGroup(<Object>[
          wrap(blob(<int>[0])),
          wrap(_binary(0, <int>[0]))
        ])
        .addItem(wrap(blob(<int>[0, 1, 2, 3, 4])))
        .addItem(wrap(blob(<int>[0, 1, 2, 4, 3])))
        .addItem(wrap(blob(<int>[255])))

        // bson binary data
        .addEqualityGroup(<Object>[wrap(_binary(1)), wrap(_binary(1))])
        .addItem(wrap(_binary(1, <int>[0])))
        .addItem(wrap(_binary(5, <int>[1, 2])))
        .addItem(wrap(_binary(5, <int>[1, 2, 3])))
        .addItem(wrap(_binary(7, <int>[1])))

        // resource names
        .addItem(ReferenceValue.valueOf(dbId('p1', 'd1'), key('c1/doc1')))
        .addItem(ReferenceValue.valueOf(dbId('p2', 'd1'), key('c1/doc1')))

        // bson object id
        .addItem(wrap(BsonObjectId('507f191e810c19729de860ea')))
        .addItem(wrap(BsonObjectId('507f191e810c19729de860eb')))
        // latin small letter e + combining acute accent + latin small letter b
        .addItem(wrap(BsonObjectId('e\u0301b')))
        .addItem(wrap(BsonObjectId('æ')))
        // latin small letter e with acute accent + latin small letter a
        .addItem(wrap(BsonObjectId('\u00e9a')))

        // geo points
        .addItem(wrap(GeoPoint(-90.0, -180.0)))
        .addItem(wrap(GeoPoint(90.0, 180.0)))

        // regex
        .addItem(wrap(const RegexValue('^foo', 'i')))
        .addItem(wrap(const RegexValue('^foo', 'm')))
        .addItem(wrap(const RegexValue('^zoo', 'i')))
        // latin small letter e + combining acute accent + latin small letter b
        .addItem(wrap(const RegexValue('e\u0301b', 'i')))
        .addItem(wrap(const RegexValue('æ', 'i')))
        // latin small letter e with acute accent + latin small letter a
        .addItem(wrap(const RegexValue('\u00e9a', 'i')))

        // arrays
        .addItem(wrap(<Object>['bar']))
        .addItem(wrap(<Object>['foo', 1]))

        // vector
        .addItem(wrap(VectorValue(<double>[])))
        .addItem(wrap(VectorValue(<double>[100])))

        // objects
        .addItem(wrap(<String, Object?>{'bar': 0}))
        // A map that only looks like a BSON type sorts as a map.
        .addItem(wrap(<String, Object?>{'foo': 1}))

        // MaxKey is last
        .addItem(wrap(MaxKey.instance))
        .testCompare();
  });

  test('testCanonicalIds', () {
    expect(wrap(const RegexValue('a', 'b')).toString(),
        '{__regex__:{options:b,pattern:a}}');
    expect(wrap(BsonObjectId('foo')).toString(), '{__oid__:foo}');
    expect(wrap(BsonTimestamp(1, 2)).toString(),
        '{__request_timestamp__:{increment:2,seconds:1}}');
    expect(_int32(1).toString(), '{__int__:1}');
    expect(_dec('1.2e3').toString(), '{__decimal128__:1.2e3}');
    expect(wrap(MinKey.instance).toString(), '{__min__:null}');
    expect(wrap(MaxKey.instance).toString(), '{__max__:null}');
    // Persisted with the queries, the ids of the existing types must not
    // change.
    expect(wrap(blob(<int>[1, 2, 3])).toString(), 'Blob { bytes= 010203 }');
    expect(wrap(1).toString(), '1');
    expect(wrap(1.0).toString(), '1.0');
    expect(wrap(_binary(1, <int>[1, 2, 3])).toString(),
        isNot(wrap(blob(<int>[1, 2, 3])).toString()));
    expect(filter('a', '==', Int32Value(1)).canonicalId,
        isNot(filter('a', '==', 1).canonicalId));
  });

  test('testConvertsToThePublicTypes', () {
    expect(wrap(MinKey.instance).value, MinKey.instance);
    expect(wrap(MaxKey.instance).value, MaxKey.instance);
    expect(_int32(7).value, Int32Value(7));
    expect((_dec('1.20').value! as Decimal128Value).stringValue, '1.20');
    expect(wrap(BsonObjectId('foo')).value, BsonObjectId('foo'));
    expect(wrap(BsonTimestamp(1, 2)).value, BsonTimestamp(1, 2));
    expect(wrap(const RegexValue('a', 'i')).value, const RegexValue('a', 'i'));
    expect(wrap(_binary(9, <int>[1])).value, _binary(9, <int>[1]));
  });

  group('filters', () {
    test('compare the numbers of all types by their value', () {
      for (final Object five in <Object>[
        5,
        5.0,
        Int32Value(5),
        Decimal128Value('5.0')
      ]) {
        for (final Object other in <Object>[
          5,
          5.0,
          Int32Value(5),
          Decimal128Value('5')
        ]) {
          expect(
              filter('v', '==', five)
                  .matches(doc('c/d', 0, <String, Object?>{'v': other})),
              isTrue,
              reason: '$other == $five');
        }
        expect(
            filter('v', '<', five).matches(
                doc('c/d', 0, <String, Object?>{'v': Decimal128Value('4.9')})),
            isTrue);
        expect(
            filter('v', '>', five)
                .matches(doc('c/d', 0, <String, Object?>{'v': Int32Value(4)})),
            isFalse);
      }
    });

    test('only match values of the same type', () {
      final Map<String, Object?> types = <String, Object?>{
        'minKey': MinKey.instance,
        'maxKey': MaxKey.instance,
        'oid': BsonObjectId('507f191e810c19729de860ea'),
        'timestamp': BsonTimestamp(1, 2),
        'regex': const RegexValue('^foo', 'i'),
        'binary': _binary(1, <int>[1, 2]),
        'null': null,
        'string': 'a',
        'map': <String, Object?>{'a': 1},
      };
      for (final MapEntry<String, Object?> value in types.entries) {
        if (value.value == null) {
          continue;
        }
        for (final MapEntry<String, Object?> other in types.entries) {
          expect(
              filter('v', '==', value.value)
                  .matches(doc('c/d', 0, <String, Object?>{'v': other.value})),
              value.key == other.key,
              reason: '${other.key} == ${value.key}');
          expect(
              filter('v', '>=', value.value)
                  .matches(doc('c/d', 0, <String, Object?>{'v': other.value})),
              value.key == other.key,
              reason: '${other.key} >= ${value.key}');
        }
      }
    });

    test('a blob does not match binary data with a subtype', () {
      expect(
          filter('v', '==', blob(<int>[1, 2]))
              .matches(doc('c/d', 0, <String, Object?>{
            'v': _binary(1, <int>[1, 2])
          })),
          isFalse);
      expect(
          filter('v', '>', blob(<int>[255]))
              .matches(doc('c/d', 0, <String, Object?>{'v': _binary(1)})),
          isTrue);
    });

    // KNOWN DIVERGENCE from the backend, the same the JS SDK has: `in`,
    // `not-in` and the array filters use equality, which is strict about the
    // type of a number, while the backend matches numbers by value. The same is
    // true for an integer and a double.
    test('membership filters are strict about the type of a number', () {
      final Document int32Doc =
          doc('c/d', 0, <String, Object?>{'v': Int32Value(5)});
      expect(filter('v', 'in', <Object>[5]).matches(int32Doc), isFalse);
      expect(
          filter('v', 'in', <Object>[Int32Value(5)]).matches(int32Doc), isTrue);
      expect(
          filter('v', 'array-contains', Int32Value(5))
              .matches(doc('c/d', 0, <String, Object?>{
            'v': <Object>[5]
          })),
          isFalse);
      expect(
          filter('v', 'array-contains', Decimal128Value('5.0'))
              .matches(doc('c/d', 0, <String, Object?>{
            'v': <Object>[Decimal128Value('5')]
          })),
          isTrue);
    });
  });

  group('increment', () {
    final Timestamp now = Timestamp.now();

    FieldValue increment(Object? base, Object operand) {
      return NumericIncrementTransformOperation(wrap(operand) as NumberValue)
          .applyToLocalView(base == null ? null : wrap(base), now);
    }

    test('testIncrementInt32AndInt32', () {
      expect(increment(Int32Value(1), Int32Value(2)), _int32(3));
    });

    test('testIncrementInt32Saturation', () {
      expect(
          increment(Int32Value(2147483647), Int32Value(1)), _int32(2147483647));
      expect(increment(Int32Value(-2147483648), Int32Value(-1)),
          _int32(-2147483648));
    });

    test('testIncrementInt32BaseWithOtherOperandTypes', () {
      expect(increment(Int32Value(1), 2), wrap(3));
      expect(increment(Int32Value(2147483647), 1), wrap(2147483648));
      expect(
          increment(Int32Value(1), IntegerValue.max), wrap(IntegerValue.max));
      expect(increment(Int32Value(1), 2.5), wrap(3.5));
    });

    test('testIncrementIntegerBaseWithInt32Operand', () {
      expect(increment(1, Int32Value(2)), wrap(3));
      expect(
          increment(IntegerValue.max, Int32Value(1)), wrap(IntegerValue.max));
    });

    test('testIncrementDoubleBaseWithInt32Operand', () {
      expect(increment(1.5, Int32Value(2)), wrap(3.5));
    });

    test('testIncrementMissingOrNonNumericBase', () {
      expect(increment(null, Int32Value(2)), wrap(2));
      expect(increment('a', Int32Value(2)), wrap(2));
      expect(increment(null, Decimal128Value('1.5')), _dec('1.5'));
    });

    test('testIncrementDecimal128Approximation', () {
      expect(increment(Decimal128Value('1.5'), 1), _dec('2.5'));
      expect(increment(Decimal128Value('1.5'), 1.25), _dec('2.75'));
      expect(increment(Decimal128Value('1.5'), Int32Value(1)), _dec('2.5'));
      expect(increment(1, Decimal128Value('1.5')), _dec('2.5'));
      expect(increment(1.5, Decimal128Value('1.5')), _dec('3'));
      expect(increment(Int32Value(1), Decimal128Value('1.5')), _dec('2.5'));
      expect(
          increment(Decimal128Value('1.5'), Decimal128Value('1.5')), _dec('3'));
      // The local sum is computed with doubles and loses precision.
      expect(
          increment(Decimal128Value('1.000000000000000000000000000000001'), 1),
          _dec('2'));
    });

    test('formats the locally computed decimal', () {
      String sum(String base, Object operand) =>
          (increment(Decimal128Value(base), operand).value! as Decimal128Value)
              .stringValue;
      expect(sum('1.5', 1.5), '3');
      expect(sum('1.5', 1), '2.5');
      expect(sum('NaN', 1), 'NaN');
      expect(sum('Infinity', 1), 'Infinity');
      expect(sum('-Infinity', 1), '-Infinity');
      expect(sum('-0', -0.0), '-0');
      expect(sum('1e300', 1), '1e+300');
    });
  });

  group('minimum and maximum', () {
    final Timestamp now = Timestamp.now();

    FieldValue maximum(Object? base, Object operand) {
      return NumericMaximumTransformOperation(wrap(operand) as NumberValue)
          .applyToLocalView(base == null ? null : wrap(base), now);
    }

    FieldValue minimum(Object? base, Object operand) {
      return NumericMinimumTransformOperation(wrap(operand) as NumberValue)
          .applyToLocalView(base == null ? null : wrap(base), now);
    }

    test('testMaximumInt32AndInt32', () {
      expect(maximum(Int32Value(1), Int32Value(2)), _int32(2));
      expect(maximum(Int32Value(2), Int32Value(1)), _int32(2));
      expect(minimum(Int32Value(1), Int32Value(2)), _int32(1));
      expect(minimum(Int32Value(2), Int32Value(1)), _int32(1));
    });

    test('testMaximumAcrossTypes', () {
      // The winner keeps its own type.
      expect(maximum(Int32Value(1), 2), wrap(2));
      expect(maximum(3, Int32Value(2)), wrap(3));
      expect(maximum(1.5, Int32Value(2)), _int32(2));
      expect(maximum(Int32Value(1), Decimal128Value('1.5')), _dec('1.5'));
      expect(maximum(Decimal128Value('2.5'), Int32Value(2)), _dec('2.5'));
      expect(maximum(1, Decimal128Value('0.5')), wrap(1));
      expect(maximum(2.5, Decimal128Value('2.6')), _dec('2.6'));
      expect(maximum(Decimal128Value('1'), Decimal128Value('2')), _dec('2'));
      expect(minimum(Int32Value(1), 2), _int32(1));
      expect(minimum(3, Int32Value(2)), _int32(2));
      expect(minimum(Int32Value(1), Decimal128Value('1.5')), _int32(1));
      expect(minimum(2.5, Decimal128Value('2.4')), _dec('2.4'));
      expect(minimum(Decimal128Value('1'), Decimal128Value('2')), _dec('1'));
      // Decimals are compared exactly, not as doubles.
      expect(
          maximum(Decimal128Value('1.000000000000000000000000000000001'), 1.0),
          _dec('1.000000000000000000000000000000001'));
      expect(
          minimum(Decimal128Value('1.000000000000000000000000000000001'), 1.0),
          wrap(1.0));
    });

    test('keeps the previous value on a tie', () {
      expect(maximum(Int32Value(1), 1), _int32(1));
      expect(minimum(1, Int32Value(1)), wrap(1));
      expect(maximum(Decimal128Value('1.0'), Int32Value(1)), _dec('1.0'));
      expect(
          (maximum(Decimal128Value('1.0'), Decimal128Value('1')).value!
                  as Decimal128Value)
              .stringValue,
          '1.0');
    });

    test('testMaximumNonNumericOrMissingBaseSelectsOperand', () {
      expect(maximum(null, Int32Value(1)), _int32(1));
      expect(maximum('a', Decimal128Value('1')), _dec('1'));
      expect(minimum(null, Int32Value(1)), _int32(1));
      expect(minimum('a', Decimal128Value('1')), _dec('1'));
    });

    test('testMaximumWithNaN', () {
      expect(maximum(Decimal128Value('NaN'), Int32Value(1)), _dec('NaN'));
      expect(maximum(Int32Value(1), Decimal128Value('NaN')), _dec('NaN'));
      expect(maximum(double.nan, Int32Value(1)), wrap(double.nan));
      expect(maximum(Int32Value(1), double.nan), wrap(double.nan));
      expect(minimum(Decimal128Value('NaN'), Int32Value(1)), _dec('NaN'));
      expect(minimum(Int32Value(1), Decimal128Value('NaN')), _dec('NaN'));
      expect(minimum(1.5, Decimal128Value('NaN')), _dec('NaN'));
    });
  });
}
