import 'package:cloud_firestore_dart/src/firebase/firestore/decimal128_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

/// Cases of the iOS SDK's `Firestore/core/test/unit/model/value_util_test.cc`
/// that neither the Android nor the JS tests have.
///
/// `Decimal128LeadingZeroTruncationRounding` is not ported: it compares
/// decimals of more than 34 significant digits, which iOS (like Android and
/// JS) rounds to a 128-bit binary float. The Dart port compares decimals
/// exactly (see `ExactNumber`), so such decimals stay distinct.
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
}
