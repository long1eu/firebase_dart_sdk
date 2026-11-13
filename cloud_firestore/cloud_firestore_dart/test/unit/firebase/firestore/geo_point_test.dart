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
      throwsA(
        isA<AssertionError>().having(
          (AssertionError e) => e.message,
          'message',
          contains('should not be a NaN'),
        ),
      ),
    );
    expect(
      () => gp(0.0, double.nan),
      throwsA(
        isA<AssertionError>().having(
          (AssertionError e) => e.message,
          'message',
          contains('should not be a NaN'),
        ),
      ),
    );
    expect(() => gp(double.infinity, 0.0), throwsA(isA<AssertionError>()));
    expect(
      () => gp(double.negativeInfinity, 0.0),
      throwsA(
        isA<AssertionError>().having(
          (AssertionError e) => e.message,
          'message',
          contains('an infinity'),
        ),
      ),
    );
    expect(
      () => gp(0.0, double.infinity),
      throwsA(
        isA<AssertionError>().having(
          (AssertionError e) => e.message,
          'message',
          contains('an infinity'),
        ),
      ),
    );
    expect(
      () => gp(0.0, double.negativeInfinity),
      throwsA(isA<AssertionError>()),
    );
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
        .addEqualityGroup(<GeoPoint>[gp(-90.0, -180.0), gp(-90.0, -180.0)])
        .addEqualityGroup(<GeoPoint>[gp(-90.0, 0.0), gp(-90.0, 0.0)])
        .addEqualityGroup(<GeoPoint>[gp(-90.0, 180.0), gp(-90.0, 180.0)])
        .addEqualityGroup(<GeoPoint>[gp(-89.0, -180.0), gp(-89.0, -180.0)])
        .addEqualityGroup(<GeoPoint>[gp(-89.0, 0.0), gp(-89.0, 0.0)])
        .addEqualityGroup(<GeoPoint>[gp(-89.0, 180.0), gp(-89.0, 180.0)])
        .addEqualityGroup(<GeoPoint>[gp(0.0, -180.0), gp(0.0, -180.0)])
        .addEqualityGroup(<GeoPoint>[gp(0.0, 0.0), gp(0.0, 0.0)])
        .addEqualityGroup(<GeoPoint>[gp(0.0, 180.0), gp(0.0, 180.0)])
        .addEqualityGroup(<GeoPoint>[gp(89.0, -180.0), gp(89.0, -180.0)])
        .addEqualityGroup(<GeoPoint>[gp(89.0, 0.0), gp(89.0, 0.0)])
        .addEqualityGroup(<GeoPoint>[gp(89.0, 180.0), gp(89.0, 180.0)])
        .addEqualityGroup(<GeoPoint>[gp(90.0, -180.0), gp(90.0, -180.0)])
        .addEqualityGroup(<GeoPoint>[gp(90.0, 0.0), gp(90.0, 0.0)])
        .addEqualityGroup(<GeoPoint>[gp(90.0, 180.0), gp(90.0, 180.0)])
        .testCompare();
  });

  test('testThrows', () {
    final Matcher throwsAssertionError = throwsA(
      const TypeMatcher<AssertionError>(),
    );
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
      GeoPoint.fromJson(jsonDecode(jsonEncode(point)) as Map<String, Object?>),
      point,
    );
    // JSON integers are accepted as coordinates.
    expect(
      GeoPoint.fromJson(<String, Object?>{
        'type': 'firestore/geoPoint/1.0',
        'latitude': 1,
        'longitude': 2,
      }),
      gp(1.0, 2.0),
    );
  });

  test('fromJson rejects malformed input and out-of-range coordinates', () {
    final Matcher throwsArgumentError = throwsA(isA<ArgumentError>());
    Map<String, Object?> json(Object? latitude, Object? longitude) =>
        <String, Object?>{
          'type': 'firestore/geoPoint/1.0',
          'latitude': latitude,
          'longitude': longitude,
        };
    expect(
      () => GeoPoint.fromJson(<String, Object?>{'latitude': 1, 'longitude': 2}),
      throwsArgumentError,
    );
    expect(() => GeoPoint.fromJson(json('1', 2)), throwsArgumentError);
    expect(() => GeoPoint.fromJson(json(90.1, 0)), throwsArgumentError);
    expect(() => GeoPoint.fromJson(json(0, -180.1)), throwsArgumentError);
    expect(() => GeoPoint.fromJson(json(double.nan, 0)), throwsArgumentError);
  });

  // Ported from the JS SDK's test/unit/api/geo_point.test.ts. The constructor
  // validates with asserts and Android's messages, see GeoPoint.
  group('GeoPoint', () {
    void expectGeoPointEquals(GeoPoint geoPoint, List<double> value) {
      expect(geoPoint.latitude, value[0]);
      expect(geoPoint.longitude, value[1]);
      expect(geoPoint, GeoPoint(value[0], value[1]));
    }

    test('constructs values', () {
      expectGeoPointEquals(GeoPoint(0, 0), <double>[0, 0]);
      expectGeoPointEquals(GeoPoint(0, 180), <double>[0, 180]);
      expectGeoPointEquals(GeoPoint(0, -180), <double>[0, -180]);
      expectGeoPointEquals(GeoPoint(-90, 0), <double>[-90, 0]);
      expectGeoPointEquals(GeoPoint(0, 0), <double>[0, 0]);
      expectGeoPointEquals(GeoPoint(90, 0), <double>[90, 0]);
    });

    test('GeoPoints throw on invalid values', () {
      Matcher throwsFor(String coordinate) => throwsA(
        isA<AssertionError>().having(
          (AssertionError e) => '${e.message}',
          'message',
          startsWith(coordinate),
        ),
      );

      const List<List<double>> invalidLats = <List<double>>[
        <double>[-91, 0],
        <double>[91, 0],
        <double>[double.nan, 0],
        <double>[double.negativeInfinity, 0],
        <double>[double.infinity, 0],
      ];
      for (final List<double> latLong in invalidLats) {
        expect(
          () => GeoPoint(latLong[0], latLong[1]),
          throwsFor('Latitude'),
          reason: '$latLong',
        );
      }

      const List<List<double>> invalidLongs = <List<double>>[
        <double>[0, -181],
        <double>[0, 181],
        <double>[0, double.nan],
        <double>[0, double.negativeInfinity],
        <double>[0, double.infinity],
      ];
      for (final List<double> latLong in invalidLongs) {
        expect(
          () => GeoPoint(latLong[0], latLong[1]),
          throwsFor('Longitude'),
          reason: '$latLong',
        );
      }
    });

    test('compares correctly', () {
      final List<GeoPoint> values = <GeoPoint>[
        GeoPoint(-90, -90),
        GeoPoint(-90, -89),
        GeoPoint(-89, -90),
        GeoPoint(-89, 0),
        GeoPoint(0, -90),
        GeoPoint(0, -89),
        GeoPoint(0, 0),
        GeoPoint(0, 89),
        GeoPoint(0, 90),
        GeoPoint(89, -90),
        GeoPoint(89, 0),
        GeoPoint(89, 90),
        GeoPoint(90, 89),
        GeoPoint(90, 90),
      ];

      for (int i = 0; i < values.length; i++) {
        for (int j = 0; j < values.length; j++) {
          expect(
            values[i].compareTo(values[j]).sign,
            i.compareTo(j),
            reason: '${values[i]} vs ${values[j]}',
          );
        }
      }
    });

    test('support equality checking with isEqual()', () {
      expect(GeoPoint(1, 2), GeoPoint(1, 2));
      expect(GeoPoint(1, 2), isNot(GeoPoint(2, 2)));
      expect(GeoPoint(1, 2), isNot(GeoPoint(1, 1)));
      expect(GeoPoint(1, 2), isNot(GeoPoint(2, 1)));
    });

    test('serializes to JSON', () {
      expect(GeoPoint(1, 2).toJson(), <String, Object>{
        'latitude': 1,
        'longitude': 2,
        'type': GeoPoint.jsonType,
      });
      expect(GeoPoint(0, 0).toJson(), <String, Object>{
        'latitude': 0,
        'longitude': 0,
        'type': GeoPoint.jsonType,
      });
      expect(GeoPoint(90, 180).toJson(), <String, Object>{
        'latitude': 90,
        'longitude': 180,
        'type': GeoPoint.jsonType,
      });
    });

    test('fromJSON does not throw', () {
      final GeoPoint geoPoint = GeoPoint(1, 2);
      expect(() => GeoPoint.fromJson(geoPoint.toJson()), returnsNormally);
    });

    test('fromJSON reconstructs seconds and nanoseconds', () {
      final GeoPoint geoPoint = GeoPoint(1, 2);
      final GeoPoint deserializedGeoPoint = GeoPoint.fromJson(
        geoPoint.toJson(),
      );
      expect(geoPoint.latitude, deserializedGeoPoint.latitude);
      expect(geoPoint.longitude, deserializedGeoPoint.longitude);
    });

    test('toJSON -> fromJSON timestamp comparison', () {
      final GeoPoint geoPoint = GeoPoint(1, 2);
      final GeoPoint deserializedGeoPoint = GeoPoint.fromJson(
        geoPoint.toJson(),
      );
      expect(deserializedGeoPoint, geoPoint);
    });

    // The JS test spells the type 'firestore/geopoint/1.0' and never invokes
    // its `to.not.throw` assertions; the SDK's type is 'firestore/geoPoint/1.0'.
    test('fromJSON parameter order does not matter', () {
      const String type = GeoPoint.jsonType;
      const int latitude = 90;
      const int longitude = 180;
      final GeoPoint control = GeoPoint(90, 180);
      expect(
        GeoPoint.fromJson(<String, Object?>{
          'latitude': latitude,
          'longitude': longitude,
          'type': type,
        }),
        control,
      );
      expect(
        GeoPoint.fromJson(<String, Object?>{
          'longitude': longitude,
          'type': type,
          'latitude': latitude,
        }),
        control,
      );
      expect(
        GeoPoint.fromJson(<String, Object?>{
          'type': type,
          'latitude': latitude,
          'longitude': longitude,
        }),
        control,
      );
      expect(
        GeoPoint.fromJson(<String, Object?>{
          'latitude': latitude,
          'type': type,
          'longitude': longitude,
        }),
        control,
      );
    });

    test('fromJSON missing fields throws', () {
      const String type = GeoPoint.jsonType;
      const int latitude = 90;
      const int longitude = 180;

      expect(
        () => GeoPoint.fromJson(<String, Object?>{
          'type': type,
          'latitude': latitude,
        }),
        throwsArgumentError,
      );
      expect(
        () => GeoPoint.fromJson(<String, Object?>{
          'type': type,
          'longitude': longitude,
        }),
        throwsArgumentError,
      );
      expect(
        () => GeoPoint.fromJson(<String, Object?>{
          'latitude': latitude,
          'longitude': longitude,
        }),
        throwsArgumentError,
      );
    });

    test('fromJSON field errant field type throws', () {
      const String type = GeoPoint.jsonType;
      const int latitude = 90;
      const int longitude = 180;

      expect(
        () => GeoPoint.fromJson(<String, Object?>{
          'type': type,
          'latitude': latitude,
          'longitude': 'wrong',
        }),
        throwsArgumentError,
      );
      expect(
        () => GeoPoint.fromJson(<String, Object?>{
          'type': type,
          'longitude': longitude,
          'latitude': 'wrong',
        }),
        throwsArgumentError,
      );
      expect(
        () => GeoPoint.fromJson(<String, Object?>{
          'latitude': latitude,
          'longitude': longitude,
          'type': 1,
        }),
        throwsArgumentError,
      );
      expect(
        () => GeoPoint.fromJson(<String, Object?>{
          'latitude': latitude,
          'longitude': longitude,
          'type': 'firestore/wrong/1.0',
        }),
        throwsArgumentError,
      );
    });
  });
}
