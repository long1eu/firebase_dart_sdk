// File created by
// Lung Razvan <long1eu>
// on 26/09/2018

import 'package:cloud_firestore_vm/src/firebase/timestamp.dart';
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
    }, throwsA(isA<AssertionError>()));

    expect(() {
      return Timestamp.fromDate(
          DateTime.fromMillisecondsSinceEpoch(300000000000000));
    }, throwsA(isA<AssertionError>()));

    expect(() => Timestamp(0, -1), throwsA(isA<AssertionError>()));
    expect(() => Timestamp(0, 1000000000), throwsA(isA<AssertionError>()));
  });
}
