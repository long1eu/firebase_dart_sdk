// File created by
// Lung Razvan <long1eu>
// on 28/09/2018

import 'package:cloud_firestore_vm/src/firebase/firestore/geo_point.dart';
import 'package:test/test.dart';

import '../../../util/comparator_test.dart';

// ignore_for_file: prefer_const_constructors

void main() {
  GeoPoint gp(double latitude, double longitude) {
    return GeoPoint(latitude, longitude);
  }

  test('testEquals', () {
    final GeoPoint foo = gp(1.23, 4.56);
    final GeoPoint fooDup = gp(1.23, 4.56);
    final GeoPoint differentLatitude = gp(0.0, 4.56);
    final GeoPoint differentLongitude = gp(1.23, 0.0);
    expect(fooDup, foo);
    expect(differentLatitude, isNot(foo));
    expect(differentLongitude, isNot(foo));

    expect(foo.hashCode, fooDup.hashCode);
    expect(differentLatitude.hashCode, isNot(foo.hashCode));
    expect(differentLongitude.hashCode, isNot(foo.hashCode));
  });

  test('testComparison', () {
    ComparatorTester<GeoPoint>()
        .permitInconsistencyWithEquals()
        .addEqualityGroup(<GeoPoint>[gp(-90.0, -180.0), gp(-90.0, -180.0)]).addEqualityGroup(<GeoPoint>[gp(-90.0, 0.0), gp(-90.0, 0.0)]).addEqualityGroup(<GeoPoint>[gp(-90.0, 180.0), gp(-90.0, 180.0)]).addEqualityGroup(<GeoPoint>[
      gp(-89.0, -180.0),
      gp(-89.0, -180.0)
    ]).addEqualityGroup(<GeoPoint>[gp(-89.0, 0.0), gp(-89.0, 0.0)]).addEqualityGroup(<GeoPoint>[gp(-89.0, 180.0), gp(-89.0, 180.0)]).addEqualityGroup(<GeoPoint>[gp(0.0, -180.0), gp(0.0, -180.0)]).addEqualityGroup(<GeoPoint>[gp(0.0, 0.0), gp(0.0, 0.0)]).addEqualityGroup(<GeoPoint>[gp(0.0, 180.0), gp(0.0, 180.0)]).addEqualityGroup(<GeoPoint>[gp(89.0, -180.0), gp(89.0, -180.0)]).addEqualityGroup(<GeoPoint>[gp(89.0, 0.0), gp(89.0, 0.0)]).addEqualityGroup(
            <GeoPoint>[gp(89.0, 180.0), gp(89.0, 180.0)]).addEqualityGroup(<GeoPoint>[
      gp(90.0, -180.0),
      gp(90.0, -180.0)
    ]).addEqualityGroup(<GeoPoint>[gp(90.0, 0.0), gp(90.0, 0.0)]).addEqualityGroup(<GeoPoint>[gp(90.0, 180.0), gp(90.0, 180.0)]).testCompare();
  });

  test('testThrows', () {
    final Matcher throwsAssertionError =
        throwsA(const TypeMatcher<AssertionError>());
    expect(() => GeoPoint(double.nan, 0.0), throwsAssertionError);
    expect(() => GeoPoint(double.negativeInfinity, 0.0), throwsAssertionError);
    expect(() => GeoPoint(double.infinity, 0.0), throwsAssertionError);
    expect(() => GeoPoint(-90.1, 0.0), throwsAssertionError);
    expect(() => GeoPoint(90.1, 0.0), throwsAssertionError);
    expect(() => GeoPoint(0.0, double.nan), throwsAssertionError);
    expect(() => GeoPoint(0.0, double.negativeInfinity), throwsAssertionError);
    expect(() => GeoPoint(0.0, double.infinity), throwsAssertionError);
    expect(() => GeoPoint(0.0, -180.1), throwsAssertionError);
    expect(() => GeoPoint(0.0, 180.1), throwsAssertionError);
  });
}
