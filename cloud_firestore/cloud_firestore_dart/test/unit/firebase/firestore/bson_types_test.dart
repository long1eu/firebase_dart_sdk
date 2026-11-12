// Ported from the Android SDK's BsonTypesTest (src/test), with the cases of
// the number comparison helper added.

import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/exact_number.dart';
import 'package:test/test.dart';

Uint8List _bytes(List<int> bytes) => Uint8List.fromList(bytes);

void main() {
  test('testBsonObjectIdEquality', () {
    final BsonObjectId a = BsonObjectId('507f191e810c19729de860ea');
    final BsonObjectId b = BsonObjectId('507f191e810c19729de860ea');
    final BsonObjectId c = BsonObjectId('507f191e810c19729de860eb');
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(c));
    expect(a.value, '507f191e810c19729de860ea');
  });

  test('testBsonTimestampEquality', () {
    final BsonTimestamp a = BsonTimestamp(1, 2);
    expect(a, BsonTimestamp(1, 2));
    expect(a.hashCode, BsonTimestamp(1, 2).hashCode);
    expect(a, isNot(BsonTimestamp(2, 2)));
    expect(a, isNot(BsonTimestamp(1, 3)));
    expect(a.seconds, 1);
    expect(a.increment, 2);
  });

  test('testBsonTimestampRejectsValuesOutsideOfUint32', () {
    expect(() => BsonTimestamp(-1, 0), throwsArgumentError);
    expect(() => BsonTimestamp(4294967296, 0), throwsArgumentError);
    expect(() => BsonTimestamp(0, -1), throwsArgumentError);
    expect(() => BsonTimestamp(0, 4294967296), throwsArgumentError);
    expect(BsonTimestamp(4294967295, 4294967295).seconds, 4294967295);
  });

  test('testRegexEquality', () {
    const RegexValue a = RegexValue('^foo', 'i');
    expect(a, const RegexValue('^foo', 'i'));
    expect(a.hashCode, const RegexValue('^foo', 'i').hashCode);
    expect(a, isNot(const RegexValue('^foo', 'x')));
    expect(a, isNot(const RegexValue('^bar', 'i')));
  });

  test('testInt32Equality', () {
    expect(Int32Value(1), Int32Value(1));
    expect(Int32Value(1).hashCode, Int32Value(1).hashCode);
    expect(Int32Value(1), isNot(Int32Value(2)));
    expect(Int32Value(-2147483648).value, -2147483648);
    expect(Int32Value(2147483647).value, 2147483647);
  });

  test('testInt32RejectsValuesOutsideOfInt32', () {
    expect(() => Int32Value(2147483648), throwsArgumentError);
    expect(() => Int32Value(-2147483649), throwsArgumentError);
  });

  test('testDecimal128Equality', () {
    void expectEqual(String a, String b) {
      expect(Decimal128Value(a), Decimal128Value(b), reason: '$a == $b');
      expect(Decimal128Value(a).hashCode, Decimal128Value(b).hashCode,
          reason: 'hashCode of $a and $b');
    }

    expectEqual('1.2e3', '1.2e3');
    expectEqual('1.2e3', '12e2');
    expectEqual('1.2e3', '0.12e4');
    expectEqual('1.2e3', '12000e-1');
    expectEqual('1.2e3', '1200');
    expectEqual('1.2', '1.20');
    expectEqual('1', '1.0');
    expectEqual('NaN', 'NaN');
    expectEqual('Infinity', '+Infinity');
    expectEqual('-Infinity', '-Infinity');
    // All the zeros are equal.
    for (final String zero in <String>[
      '0',
      '0.0',
      '-0',
      '-0.0',
      '+0',
      '+0.0',
      '0e5',
      '-0e-3'
    ]) {
      expectEqual('0', zero);
    }

    expect(Decimal128Value('1.2e3'), isNot(Decimal128Value('1.2e4')));
    expect(Decimal128Value('1'), isNot(Decimal128Value('-1')));
    expect(Decimal128Value('NaN'), isNot(Decimal128Value('Infinity')));
    expect(Decimal128Value('Infinity'), isNot(Decimal128Value('-Infinity')));
    expect(Decimal128Value('0'), isNot(Decimal128Value('1e-6176')));
    // The string is kept as it was provided.
    expect(Decimal128Value('1.20').stringValue, '1.20');
  });

  test('testDecimal128RejectsInvalidStrings', () {
    for (final String invalid in <String>[
      '',
      'abc',
      '1.2.3',
      '1e',
      '1e+',
      '-',
      '.',
      'nan',
      ' 1',
      '1 ',
      '0x10',
      '1e1234567890'
    ]) {
      expect(() => Decimal128Value(invalid), throwsFormatException,
          reason: "'$invalid'");
    }
  });

  test('testMinKeyAndMaxKeyAreSingletons', () {
    expect(identical(MinKey.instance, MinKey.instance), isTrue);
    expect(identical(MaxKey.instance, MaxKey.instance), isTrue);
    expect(MinKey.instance, MinKey.instance);
    expect(MaxKey.instance, MaxKey.instance);
  });

  test('testMinKeyMaxKeyNullNotEqual', () {
    expect(MinKey.instance, isNot(MaxKey.instance));
    expect(MinKey.instance, isNot(null));
    expect(MaxKey.instance, isNot(null));
  });

  test('testBsonBinaryDataValuesAndEquality', () {
    final Blob a = Blob.bsonBinary(1, _bytes(<int>[1, 2, 3]));
    expect(a.subtype, 1);
    expect(a.bytes, <int>[1, 2, 3]);
    expect(a, Blob.bsonBinary(1, _bytes(<int>[1, 2, 3])));
    expect(a.hashCode, Blob.bsonBinary(1, _bytes(<int>[1, 2, 3])).hashCode);
    expect(a, isNot(Blob.bsonBinary(128, _bytes(<int>[1, 2, 3]))));
    expect(a, isNot(Blob.bsonBinary(1, _bytes(<int>[1, 2, 4]))));
    expect(() => Blob.bsonBinary(256, _bytes(<int>[1])), throwsArgumentError);
    expect(() => Blob.bsonBinary(-1, _bytes(<int>[1])), throwsArgumentError);
  });

  test('testBlobEqualityWithSubtypes', () {
    final Blob regular = Blob(_bytes(<int>[1, 2, 3]));
    expect(regular.subtype, 0);
    // A subtype of 0 is a regular blob.
    expect(Blob.bsonBinary(0, _bytes(<int>[1, 2, 3])), regular);
    expect(
        Blob.bsonBinary(0, _bytes(<int>[1, 2, 3])).hashCode, regular.hashCode);
    expect(Blob.bsonBinary(1, _bytes(<int>[1, 2, 3])), isNot(regular));
  });

  test('testBlobsSortBySubtypeFirst', () {
    final Blob regular = Blob(_bytes(<int>[9]));
    final Blob one = Blob.bsonBinary(1, _bytes(<int>[]));
    final Blob oneLonger = Blob.bsonBinary(1, _bytes(<int>[0]));
    final Blob five = Blob.bsonBinary(5, _bytes(<int>[]));
    expect(regular.compareTo(one), lessThan(0));
    expect(one.compareTo(oneLonger), lessThan(0));
    expect(oneLonger.compareTo(five), lessThan(0));
    expect(five.compareTo(regular), greaterThan(0));
    expect(one.compareTo(Blob.bsonBinary(1, _bytes(<int>[]))), 0);
  });

  test('testRegularBlobStringIsUnchanged', () {
    // Part of the canonical id of persisted queries.
    expect(Blob(_bytes(<int>[1, 2, 3])).toString(), 'Blob { bytes= 010203 }');
  });

  group('ExactNumber', () {
    int compare(ExactNumber a, ExactNumber b) => a.compareTo(b).sign;
    ExactNumber dec(String s) => ExactNumber.parse(s);

    test('compares decimals with doubles exactly', () {
      // 0.1 has no exact double, the closest double is slightly larger.
      expect(compare(dec('0.1'), ExactNumber.fromDouble(0.1)), -1);
      expect(
          compare(
              dec('0.1000000000000000055511151231257827021181583404541015625'),
              ExactNumber.fromDouble(0.1)),
          0);
      expect(compare(dec('0.5'), ExactNumber.fromDouble(0.5)), 0);
      expect(compare(dec('-1.5'), ExactNumber.fromDouble(-1.5)), 0);
      expect(compare(dec('1.1'), ExactNumber.fromDouble(1.1)), -1);
      expect(compare(dec('4.9e-324'), ExactNumber.fromDouble(5e-324)), -1);
      expect(compare(dec('5e-324'), ExactNumber.fromDouble(5e-324)), 1);
      expect(
          compare(dec('1.7976931348623157e308'),
              ExactNumber.fromDouble(double.maxFinite)),
          -1);
      expect(
          compare(dec('1e309'), ExactNumber.fromDouble(double.maxFinite)), 1);
    });

    test('compares decimals with integers exactly', () {
      expect(
          compare(dec('9223372036854775807'),
              ExactNumber.fromInt(9223372036854775807)),
          0);
      expect(
          compare(dec('9223372036854775807.5'),
              ExactNumber.fromInt(9223372036854775807)),
          1);
      expect(
          compare(dec('-9223372036854775808'),
              ExactNumber.fromInt(-9223372036854775808)),
          0);
      expect(
          compare(dec('-9223372036854775808.5'),
              ExactNumber.fromInt(-9223372036854775808)),
          -1);
      expect(compare(dec('2.147483647e9'), ExactNumber.fromInt(2147483647)), 0);
    });

    test('keeps 34 significant digits apart', () {
      expect(
          compare(dec('9.000000000000000000000000000000001'),
              dec('9.000000000000000000000000000000002')),
          -1);
      expect(compare(dec('1.000000000000000000000000000000001'), dec('1')), 1);
    });

    test('handles the extremes of the decimal128 exponent range', () {
      expect(
          compare(
              dec('9.999999999999999999999999999999999E+6144'), dec('1E-6176')),
          1);
      expect(
          compare(dec('-9.999999999999999999999999999999999E+6144'),
              dec('1E-6176')),
          -1);
      expect(compare(dec('1E-6176'), ExactNumber.fromDouble(5e-324)), -1);
      expect(
          compare(dec('1E+6144'), ExactNumber.fromDouble(double.maxFinite)), 1);
      expect(compare(dec('1e999999999'), dec('1e-999999999')), 1);
    });

    test('orders NaN first, the zeros together and the infinities last', () {
      final ExactNumber nan = dec('NaN');
      expect(compare(nan, ExactNumber.fromDouble(double.nan)), 0);
      expect(compare(nan, dec('-Infinity')), -1);
      expect(compare(dec('-Infinity'), nan), 1);
      expect(
          compare(dec('-Infinity'),
              ExactNumber.fromDouble(double.negativeInfinity)),
          0);
      expect(compare(dec('-Infinity'), dec('-1e6144')), -1);
      expect(
          compare(dec('Infinity'), ExactNumber.fromDouble(double.infinity)), 0);
      expect(compare(dec('Infinity'), dec('1e6144')), 1);
      expect(compare(dec('-0'), ExactNumber.fromDouble(0)), 0);
      expect(compare(dec('0'), ExactNumber.fromDouble(-0.0)), 0);
      expect(compare(dec('-0.0'), ExactNumber.fromInt(0)), 0);
      expect(compare(dec('0'), dec('1e-6176')), -1);
      expect(compare(dec('0'), dec('-1e-6176')), 1);
    });

    test('converts to the closest double', () {
      expect(dec('1.5').toDouble(), 1.5);
      expect(dec('-1.2e3').toDouble(), -1200.0);
      expect(dec('1e400').toDouble(), double.infinity);
      expect(dec('-1e400').toDouble(), double.negativeInfinity);
      expect(dec('1e-400').toDouble(), 0.0);
      expect(dec('-0').toDouble().isNegative, isTrue);
      expect(dec('NaN').toDouble().isNaN, isTrue);
      expect(dec('Infinity').toDouble(), double.infinity);
      expect(dec('1e999999999').toDouble(), double.infinity);
    });
  });
}
