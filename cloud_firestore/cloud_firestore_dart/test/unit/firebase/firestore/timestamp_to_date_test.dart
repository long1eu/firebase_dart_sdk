// Review L5: Timestamp.toDate multiplied the seconds by 10^6 first, which is
// above 2^53 after about the year 2255 and lost the microseconds on the web.
// Kept apart from timestamp_test.dart, which has integer literals that dart2js
// rejects, so that this file also runs with `-p chrome`.

import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:test/test.dart';

List<int> _fields(DateTime date) {
  final DateTime utc = date.toUtc();
  return <int>[
    utc.year,
    utc.month,
    utc.day,
    utc.hour,
    utc.minute,
    utc.second,
    utc.millisecond,
    utc.microsecond,
  ];
}

void main() {
  test('toDate keeps microseconds at the end of the range', () {
    final DateTime max = const Timestamp(253402300799, 999999999).toDate();
    expect(max.isUtc, isFalse);
    expect(_fields(max), <int>[9999, 12, 31, 23, 59, 59, 999, 999]);
  });

  test('toDate keeps microseconds at the start of the range', () {
    expect(_fields(const Timestamp(-62135596800, 1000).toDate()), <int>[
      1,
      1,
      1,
      0,
      0,
      0,
      0,
      1,
    ]);
  });

  test('toDate keeps microseconds after the year 2255', () {
    expect(_fields(const Timestamp(10000000000, 123456789).toDate()), <int>[
      2286,
      11,
      20,
      17,
      46,
      40,
      123,
      456,
    ]);
  });

  test('toDate truncates toward the past before the epoch', () {
    expect(_fields(const Timestamp(-1, 999).toDate()), <int>[
      1969,
      12,
      31,
      23,
      59,
      59,
      0,
      0,
    ]);
    expect(_fields(const Timestamp(-1, 999999999).toDate()), <int>[
      1969,
      12,
      31,
      23,
      59,
      59,
      999,
      999,
    ]);
  });
}
