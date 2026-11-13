import 'package:cloud_firestore_dart/src/firebase/firestore/decimal128_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

/// Cases of the iOS SDK's `Firestore/core/test/unit/model/value_util_test.cc`
/// that neither the Android nor the JS tests have.

FieldValue _decimal(String value) => wrap(Decimal128Value(value));

void main() {
  test('testDecimal128Comparison', () {
    expect(_decimal('NaN').compareTo(wrap(double.nan)), 0);
    expect(_decimal('NaN').compareTo(_decimal('NaN')), 0);
    expect(_decimal('NaN').compareTo(_decimal('-Infinity')), lessThan(0));
    expect(_decimal('NaN').compareTo(_decimal('+Infinity')), lessThan(0));
    expect(_decimal('NaN').compareTo(_decimal('-1.2e-3')), lessThan(0));
    expect(_decimal('1').compareTo(_decimal('2e-4')), greaterThan(0));
    expect(_decimal('-1').compareTo(_decimal('-2e-4')), lessThan(0));
    expect(_decimal('-0.0').compareTo(_decimal('0.0')), 0);
    expect(_decimal('-0.0').compareTo(_decimal('+0.0')), 0);
    expect(_decimal('-0').compareTo(_decimal('0')), 0);
    expect(_decimal('1500e-3').compareTo(wrap(1.5)), 0);
    expect(_decimal('-1000e-3').compareTo(wrap(-1)), 0);
    expect(_decimal('3.4e-5').compareTo(wrap(2.0)), lessThan(0));
    // And the other way around.
    expect(wrap(1.5).compareTo(_decimal('1500e-3')), 0);
    expect(wrap(-1).compareTo(_decimal('-1000e-3')), 0);
    expect(wrap(2.0).compareTo(_decimal('3.4e-5')), greaterThan(0));
  });

  test('Decimal128LeadingZeroTruncationRounding', () {
    // iOS: Quadruple::Parse keeps 59 significant digits, also after leading
    // zeroes, so `below` equals 1 and `above` is 1 + 2^-128. Both have 61
    // significant digits, which decimal128 can not hold: the backend rejects
    // them, and so does Decimal128Value in the port.
    const String belowThresholdWithLeadingZeroes =
        '0.0100000000000000000000000000000000000000146936793852785936830e2';
    const String aboveThresholdWithLeadingZeroes =
        '0.0100000000000000000000000000000000000000146936793852785936835e2';
    expect(
      () => Decimal128Value(belowThresholdWithLeadingZeroes),
      throwsFormatException,
    );
    expect(
      () => Decimal128Value(aboveThresholdWithLeadingZeroes),
      throwsFormatException,
    );
    // The leading zeroes do not count: 34 significant digits after them are
    // fine, 35 are not.
    expect(_decimal('0.01${'0' * 32}1e2'), _decimal('1.${'0' * 32}1'));
    expect(() => Decimal128Value('0.01${'0' * 33}1e2'), throwsFormatException);
  });
}
