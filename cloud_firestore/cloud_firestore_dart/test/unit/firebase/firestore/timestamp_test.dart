// File created by
// Lung Razvan <long1eu>
// on 26/09/2018

import 'dart:convert';

import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:fixnum/fixnum.dart';
import 'package:test/test.dart';

void main() {
  test('testFromDate', () {
    // Very carefully construct a Date that won't lose precision with
    // milliseconds.
    DateTime input = DateTime.fromMillisecondsSinceEpoch(22501);
    Timestamp actual = Timestamp.fromDate(input);
    expect(actual.seconds, Int64(22));
    expect(actual.nanoseconds, 501000000);

    Timestamp expected = const Timestamp(22, 501000000);
    expect(actual, expected);

    // And with a negative millis.
    input = DateTime.fromMillisecondsSinceEpoch(-1250);
    actual = Timestamp.fromDate(input);

    expect(actual.seconds, -2);
    expect(actual.nanoseconds, 750000000);

    expected = const Timestamp(-2, 750000000);
    expect(actual, expected);
  });

  test('testCompare', () {
    const List<Timestamp> timestamps = <Timestamp>[
      Timestamp(12344, 999999999),
      Timestamp(12345, 0),
      Timestamp(12345, 1),
      Timestamp(12345, 99999999),
      Timestamp(12345, 100000000),
      Timestamp(12345, 100000001),
      Timestamp(12346, 0)
    ];

    for (int i = 0; i < timestamps.length - 1; ++i) {
      expect(timestamps[i].compareTo(timestamps[i + 1]), -1);
      expect(timestamps[i + 1].compareTo(timestamps[i]), 1);
    }
  });

  test('testRejectBadDates', () {
    expect(() {
      return Timestamp.fromDate(
          DateTime.fromMillisecondsSinceEpoch(-70000000000000));
    }, throwsA(isA<ArgumentError>()));

    expect(() {
      return Timestamp.fromDate(
          DateTime.fromMillisecondsSinceEpoch(300000000000000));
    }, throwsA(isA<ArgumentError>()));

    expect(() => Timestamp(0, -1), throwsA(isA<AssertionError>()));
    expect(() => Timestamp(0, 1000000000), throwsA(isA<AssertionError>()));
  });

  test('fromMillis and toMillis round trip, including negative values', () {
    expect(Timestamp.fromMillis(22501), const Timestamp(22, 501000000));
    expect(Timestamp.fromMillis(-1250), const Timestamp(-2, 750000000));
    expect(Timestamp.fromMillis(-1000), const Timestamp(-1, 0));
    expect(Timestamp.fromMillis(0), const Timestamp(0, 0));
    for (final int millis in <int>[0, 1, -1, 22501, -1250, 1700000000123]) {
      expect(Timestamp.fromMillis(millis).toMillis(), millis);
    }
    expect(Timestamp.fromMillis(1700000000123),
        Timestamp.fromDate(DateTime.fromMillisecondsSinceEpoch(1700000000123)));
  });

  test('toMillis truncates sub-millisecond precision toward the past', () {
    expect(const Timestamp(1, 999999).toMillis(), 1000);
    expect(const Timestamp(-1, 999999).toMillis(), -1000);
    expect(const Timestamp(-1, 999999).toDate(),
        DateTime.fromMillisecondsSinceEpoch(-1000));
  });

  test('fromMillis rejects out-of-range values', () {
    expect(() => Timestamp.fromMillis(-70000000000000),
        throwsA(isA<ArgumentError>()));
    expect(() => Timestamp.fromMillis(300000000000000),
        throwsA(isA<ArgumentError>()));
  });

  test('toJson matches the JS shape and round trips through fromJson', () {
    const Timestamp timestamp = Timestamp(-2, 750000000);
    final Map<String, Object> json = timestamp.toJson();
    expect(json, <String, Object>{
      'type': 'firestore/timestamp/1.0',
      'seconds': -2,
      'nanoseconds': 750000000,
    });
    expect(
        Timestamp.fromJson(
            jsonDecode(jsonEncode(timestamp)) as Map<String, Object?>),
        timestamp);
  });

  test('fromJson rejects malformed input', () {
    final Matcher throwsArgumentError = throwsA(isA<ArgumentError>());
    expect(
        () => Timestamp.fromJson(
            <String, Object?>{'seconds': 1, 'nanoseconds': 0}),
        throwsArgumentError);
    expect(
        () => Timestamp.fromJson(<String, Object?>{
              'type': 'firestore/geoPoint/1.0',
              'seconds': 1,
              'nanoseconds': 0
            }),
        throwsArgumentError);
    expect(
        () => Timestamp.fromJson(<String, Object?>{
              'type': 'firestore/timestamp/1.0',
              'seconds': '1',
              'nanoseconds': 0
            }),
        throwsArgumentError);
    expect(
        () => Timestamp.fromJson(<String, Object?>{
              'type': 'firestore/timestamp/1.0',
              'seconds': 1,
              'nanoseconds': 1000000000
            }),
        throwsArgumentError);
  });
}
