// File created by
// Lung Razvan <long1eu>
// on 28/09/2018

import 'dart:convert';

import 'package:cloud_firestore_dart/src/firebase/firestore/geo_point.dart';
import 'package:test/test.dart';

import '../../../util/comparator_test.dart';

// ignore_for_file: prefer_const_constructors

void main() {
  GeoPoint gp(double latitude, double longitude) {
    return GeoPoint(latitude, longitude);
  }

  test('rejects NaN and infinite coordinates with a precise message', () {
    expect(
        () => gp(double.nan, 0.0),
        throwsA(isA<AssertionError>().having((AssertionError e) => e.message,
            'message', contains('should not be a NaN'))));
    expect(
        () => gp(0.0, double.nan),
        throwsA(isA<AssertionError>().having((AssertionError e) => e.message,
            'message', contains('should not be a NaN'))));
    expect(() => gp(double.infinity, 0.0), throwsA(isA<AssertionError>()));
    expect(
        () => gp(double.negativeInfinity, 0.0),
        throwsA(isA<AssertionError>().having((AssertionError e) => e.message,
            'message', contains('an infinity'))));
    expect(
        () => gp(0.0, double.infinity),
        throwsA(isA<AssertionError>().having((AssertionError e) => e.message,
            'message', contains('an infinity'))));
    expect(
        () => gp(0.0, double.negativeInfinity), throwsA(isA<AssertionError>()));
    expect(gp(90.0, 180.0).latitude, 90.0);
    expect(gp(-90.0, -180.0).longitude, -180.0);
  });

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

  test('toJson matches the JS shape and round trips through fromJson', () {
    final GeoPoint point = gp(12.5, -45.25);
    expect(point.toJson(), <String, Object>{
      'latitude': 12.5,
      'longitude': -45.25,
      'type': 'firestore/geoPoint/1.0',
    });
    expect(
        GeoPoint.fromJson(
            jsonDecode(jsonEncode(point)) as Map<String, Object?>),
        point);
    // JSON integers are accepted as coordinates.
    expect(
        GeoPoint.fromJson(<String, Object?>{
          'type': 'firestore/geoPoint/1.0',
          'latitude': 1,
          'longitude': 2
        }),
        gp(1.0, 2.0));
  });

  test('fromJson rejects malformed input and out-of-range coordinates', () {
    final Matcher throwsArgumentError = throwsA(isA<ArgumentError>());
    Map<String, Object?> json(Object? latitude, Object? longitude) =>
        <String, Object?>{
          'type': 'firestore/geoPoint/1.0',
          'latitude': latitude,
          'longitude': longitude
        };
    expect(
        () =>
            GeoPoint.fromJson(<String, Object?>{'latitude': 1, 'longitude': 2}),
        throwsArgumentError);
    expect(() => GeoPoint.fromJson(json('1', 2)), throwsArgumentError);
    expect(() => GeoPoint.fromJson(json(90.1, 0)), throwsArgumentError);
    expect(() => GeoPoint.fromJson(json(0, -180.1)), throwsArgumentError);
    expect(() => GeoPoint.fromJson(json(double.nan, 0)), throwsArgumentError);
  });
}
