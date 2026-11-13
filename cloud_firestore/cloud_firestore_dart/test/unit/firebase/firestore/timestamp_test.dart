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
      Timestamp(12346, 0),
    ];

    for (int i = 0; i < timestamps.length - 1; ++i) {
      expect(timestamps[i].compareTo(timestamps[i + 1]), -1);
      expect(timestamps[i + 1].compareTo(timestamps[i]), 1);
    }
  });

  test('testRejectBadDates', () {
    expect(() {
      return Timestamp.fromDate(
        DateTime.fromMillisecondsSinceEpoch(-70000000000000),
      );
    }, throwsA(isA<ArgumentError>()));

    expect(() {
      return Timestamp.fromDate(
        DateTime.fromMillisecondsSinceEpoch(300000000000000),
      );
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
    expect(
      Timestamp.fromMillis(1700000000123),
      Timestamp.fromDate(DateTime.fromMillisecondsSinceEpoch(1700000000123)),
    );
  });

  test('toMillis truncates sub-millisecond precision toward the past', () {
    expect(const Timestamp(1, 999999).toMillis(), 1000);
    expect(const Timestamp(-1, 999999).toMillis(), -1000);
    // toDate keeps the microseconds (it used to truncate to milliseconds).
    expect(
      const Timestamp(-1, 999999).toDate(),
      DateTime.fromMicrosecondsSinceEpoch(-999001),
    );
    expect(const Timestamp(-1, 999999).toDate().millisecondsSinceEpoch, -1000);
  });

  test('fromMillis rejects out-of-range values', () {
    expect(
      () => Timestamp.fromMillis(-70000000000000),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => Timestamp.fromMillis(300000000000000),
      throwsA(isA<ArgumentError>()),
    );
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
        jsonDecode(jsonEncode(timestamp)) as Map<String, Object?>,
      ),
      timestamp,
    );
  });

  test('fromJson rejects malformed input', () {
    final Matcher throwsArgumentError = throwsA(isA<ArgumentError>());
    expect(
      () =>
          Timestamp.fromJson(<String, Object?>{'seconds': 1, 'nanoseconds': 0}),
      throwsArgumentError,
    );
    expect(
      () => Timestamp.fromJson(<String, Object?>{
        'type': 'firestore/geoPoint/1.0',
        'seconds': 1,
        'nanoseconds': 0,
      }),
      throwsArgumentError,
    );
    expect(
      () => Timestamp.fromJson(<String, Object?>{
        'type': 'firestore/timestamp/1.0',
        'seconds': '1',
        'nanoseconds': 0,
      }),
      throwsArgumentError,
    );
    expect(
      () => Timestamp.fromJson(<String, Object?>{
        'type': 'firestore/timestamp/1.0',
        'seconds': 1,
        'nanoseconds': 1000000000,
      }),
      throwsArgumentError,
    );
  });

  test('fromDate and toDate keep microseconds', () {
    final DateTime date = DateTime.fromMicrosecondsSinceEpoch(22501123);
    final Timestamp timestamp = Timestamp.fromDate(date);
    expect(timestamp, const Timestamp(22, 501123000));
    expect(timestamp.toDate(), date);
    expect(timestamp.toDate().microsecondsSinceEpoch, 22501123);

    // Negative values round toward the past and keep nanoseconds in range.
    expect(
      Timestamp.fromDate(DateTime.fromMicrosecondsSinceEpoch(-1)),
      const Timestamp(-1, 999999000),
    );
    expect(
      Timestamp.fromDate(DateTime.fromMicrosecondsSinceEpoch(-1250001)),
      const Timestamp(-2, 749999000),
    );
    expect(
      Timestamp.fromDate(DateTime.fromMicrosecondsSinceEpoch(-1000000)),
      const Timestamp(-1, 0),
    );
    for (final int micros in <int>[
      0,
      1,
      -1,
      999999,
      -999999,
      -1000000,
      -1250001,
      1700000000123456,
      -62135596800000000, // 0001-01-01T00:00:00Z
      253402300799999999, // 9999-12-31T23:59:59.999999Z
    ]) {
      final Timestamp value = Timestamp.fromDate(
        DateTime.fromMicrosecondsSinceEpoch(micros),
      );
      expect(value.nanoseconds, inInclusiveRange(0, 999999999));
      expect(value.toDate().microsecondsSinceEpoch, micros, reason: '$micros');
    }
  });

  test('fromDate and toDate are unchanged for millisecond inputs', () {
    for (final int millis in <int>[0, 1, -1, 22501, -1250, 1700000000123]) {
      final DateTime date = DateTime.fromMillisecondsSinceEpoch(millis);
      expect(Timestamp.fromDate(date), Timestamp.fromMillis(millis));
      expect(Timestamp.fromMillis(millis).toDate(), date);
      expect(Timestamp.fromDate(date).toMillis(), millis);
    }
  });

  test('toDate truncates sub-microsecond precision toward the past', () {
    expect(const Timestamp(1, 999).toDate().microsecondsSinceEpoch, 1000000);
    expect(const Timestamp(-1, 999).toDate().microsecondsSinceEpoch, -1000000);
    expect(const Timestamp(-1, 999999999).toDate().microsecondsSinceEpoch, -1);
  });

  test('fromDate accepts UTC and local dates for the same instant', () {
    final DateTime utc = DateTime.utc(2024, 2, 29, 12, 30, 15, 123, 456);
    expect(Timestamp.fromDate(utc), Timestamp.fromDate(utc.toLocal()));
    expect(Timestamp.fromDate(utc).toDate().isAtSameMomentAs(utc), isTrue);
  });

  test('now has millisecond precision', () {
    expect(Timestamp.now().nanoseconds % 1000000, 0);
  });

  // Ported from the JS SDK's test/unit/api/timestamp.test.ts. The constructor
  // validates with asserts like Android, and the relational operators of the
  // JS tests are compareTo here. Not ported: valueOf() and the Temporal
  // conversions (no such API in Dart), and fromMillis() with a fraction
  // (fromMillis takes an int).
  group('Timestamp', () {
    Matcher throwsMentioning(String argument) => throwsA(
      isA<AssertionError>().having(
        (AssertionError e) => '${e.message}',
        'message',
        contains(argument),
      ),
    );

    test('constructor should validate the "seconds" argument and store it', () {
      expect(const Timestamp(1, 0).seconds, 1);
      expect(const Timestamp(-62135596800, 0).seconds, -62135596800);
      expect(const Timestamp(253402300799, 0).seconds, 253402300799);

      expect(() => Timestamp(-62135596801, 0), throwsMentioning('seconds'));
      expect(() => Timestamp(253402300800, 0), throwsMentioning('seconds'));
    });

    test(
      'constructor should validate the "nanoseconds" argument and store it',
      () {
        expect(const Timestamp(0, 1).nanoseconds, 1);
        expect(const Timestamp(0, 0).nanoseconds, 0);
        expect(const Timestamp(0, 999999999).nanoseconds, 999999999);

        expect(() => Timestamp(0, -1), throwsMentioning('nanoseconds'));
        expect(() => Timestamp(0, 1000000000), throwsMentioning('nanoseconds'));
      },
    );

    test('fromDate', () {
      final Timestamp t1 = Timestamp.fromDate(
        DateTime.fromMillisecondsSinceEpoch(1488872578916),
      );
      expect(t1.seconds, 1488872578);
      expect(t1.nanoseconds, 916000000);

      final Timestamp t2 = Timestamp.fromDate(
        DateTime.fromMillisecondsSinceEpoch(-1250),
      );
      expect(t2.seconds, -2);
      expect(t2.nanoseconds, 750000000);
    });

    void expectOrder(Timestamp t1, Timestamp t2, int expected) {
      final int order = t1.compareTo(t2);
      expect(order < 0, expected < 0);
      expect(order <= 0, expected <= 0);
      expect(order > 0, expected > 0);
      expect(order >= 0, expected >= 0);
    }

    test('arithmetic comparison of a Timestamp object to itself', () {
      const Timestamp timestamp = Timestamp(1, 1);
      expectOrder(timestamp, timestamp, 0);
    });

    test(
      'arithmetic comparison of equivalent, but distinct, Timestamp objects',
      () {
        // Not const: const instances would be the same object.
        // ignore: prefer_const_constructors
        final Timestamp t1 = Timestamp(1, 1);
        // ignore: prefer_const_constructors
        final Timestamp t2 = Timestamp(1, 1);
        expect(identical(t1, t2), isFalse);
        expectOrder(t1, t2, 0);
      },
    );

    test(
      'arithmetic comparison of Timestamp objects whose nanoseconds differ',
      () {
        expectOrder(const Timestamp(1, 1), const Timestamp(1, 2), -1);
      },
    );

    test('arithmetic comparison of Timestamp objects whose seconds differ', () {
      expectOrder(const Timestamp(100, 0), const Timestamp(200, 0), -1);
    });

    test(
      'arithmetic comparison of the smallest and largest Timestamp objects',
      () {
        expectOrder(
          const Timestamp(-62135596800, 0),
          const Timestamp(253402300799, 999999999),
          -1,
        );
      },
    );

    test('serializes to JSON', () {
      expect(const Timestamp(123, 456).toJson(), <String, Object>{
        'seconds': 123,
        'nanoseconds': 456,
        'type': 'firestore/timestamp/1.0',
      });
      expect(const Timestamp(0, 0).toJson(), <String, Object>{
        'seconds': 0,
        'nanoseconds': 0,
        'type': 'firestore/timestamp/1.0',
      });
      expect(const Timestamp(-123, 456).toJson(), <String, Object>{
        'seconds': -123,
        'nanoseconds': 456,
        'type': 'firestore/timestamp/1.0',
      });
    });

    test('fromJSON does not throw', () {
      const Timestamp timestamp = Timestamp(123, 456);
      expect(() => Timestamp.fromJson(timestamp.toJson()), returnsNormally);
    });

    test('fromJSON reconstructs seconds and nanoseconds', () {
      const Timestamp timestamp = Timestamp(123, 456);
      final Timestamp deserializedTimestamp = Timestamp.fromJson(
        timestamp.toJson(),
      );
      expect(timestamp.nanoseconds, deserializedTimestamp.nanoseconds);
      expect(timestamp.seconds, deserializedTimestamp.seconds);
    });

    test('toJSON -> fromJSON timestamp comparison', () {
      const Timestamp timestamp = Timestamp(123, 456);
      final Timestamp deserializedTimestamp = Timestamp.fromJson(
        timestamp.toJson(),
      );
      expect(deserializedTimestamp, timestamp);
    });

    test('fromJSON parameter order does not matter', () {
      const String type = 'firestore/timestamp/1.0';
      const int seconds = 123;
      const int nanoseconds = 456;
      const Timestamp control = Timestamp(seconds, nanoseconds);
      expect(
        Timestamp.fromJson(<String, Object?>{
          'seconds': seconds,
          'nanoseconds': nanoseconds,
          'type': type,
        }),
        control,
      );
      expect(
        Timestamp.fromJson(<String, Object?>{
          'nanoseconds': nanoseconds,
          'type': type,
          'seconds': seconds,
        }),
        control,
      );
      expect(
        Timestamp.fromJson(<String, Object?>{
          'type': type,
          'seconds': seconds,
          'nanoseconds': nanoseconds,
        }),
        control,
      );
      expect(
        Timestamp.fromJson(<String, Object?>{
          'seconds': seconds,
          'type': type,
          'nanoseconds': nanoseconds,
        }),
        control,
      );
    });

    test('fromJSON missing fields throws', () {
      const String type = 'firestore/timestamp/1.0';
      const int seconds = 123;
      const int nanoseconds = 456;

      expect(
        () => Timestamp.fromJson(<String, Object?>{
          'type': type,
          'seconds': seconds,
        }),
        throwsArgumentError,
      );
      expect(
        () => Timestamp.fromJson(<String, Object?>{
          'type': type,
          'nanoseconds': nanoseconds,
        }),
        throwsArgumentError,
      );
      expect(
        () => Timestamp.fromJson(<String, Object?>{
          'seconds': seconds,
          'nanoseconds': nanoseconds,
        }),
        throwsArgumentError,
      );
    });

    test('fromJSON field errant field type throws', () {
      const String type = 'firestore/timestamp/1.0';
      const int seconds = 123;
      const int nanoseconds = 456;

      expect(
        () => Timestamp.fromJson(<String, Object?>{
          'type': type,
          'seconds': seconds,
          'nanoseconds': 'wrong',
        }),
        throwsArgumentError,
      );
      expect(
        () => Timestamp.fromJson(<String, Object?>{
          'type': type,
          'nanoseconds': nanoseconds,
          'seconds': 'wrong',
        }),
        throwsArgumentError,
      );
      expect(
        () => Timestamp.fromJson(<String, Object?>{
          'seconds': seconds,
          'nanoseconds': nanoseconds,
          'type': 1,
        }),
        throwsArgumentError,
      );
      expect(
        () => Timestamp.fromJson(<String, Object?>{
          'seconds': seconds,
          'nanoseconds': nanoseconds,
          'type': 'firestore/wrong/1.0',
        }),
        throwsArgumentError,
      );
    });
  });
}
