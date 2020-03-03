// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_common/firebase_common.dart';

/// A Timestamp represents a point in time independent of any time zone or calendar, represented as
/// seconds and fractions of seconds at nanosecond resolution in UTC Epoch time. It is encoded using
/// the Proleptic Gregorian Calendar which extends the Gregorian calendar backwards to year one. It
/// is encoded assuming all minutes are 60 seconds long, i.e. leap seconds are 'smeared' so that no
/// leap second table is needed for interpretation. Range is from 0001-01-01T00:00:00Z to
/// 9999-12-31T23:59:59.999999999Z. By restricting to that range, we ensure that we can convert to
/// and from RFC 3339 date strings.
///
/// see [The reference timestamp definition](https://github.com/google/protobuf/blob/master/src/google/protobuf/timestamp.proto)
class Timestamp implements Comparable<Timestamp> {
  Timestamp(this.seconds, this.nanoseconds) {
    validateRange(seconds, nanoseconds);
  }

  factory Timestamp.fromDate(DateTime date) {
    final int millis = date.millisecondsSinceEpoch;
    int seconds = millis ~/ 1000;
    int nanoseconds = millis.remainder(1000) * 1000000;

    if (nanoseconds < 0) {
      seconds -= 1;
      nanoseconds += 1000000000;
    }

    validateRange(seconds, nanoseconds);
    return Timestamp(seconds, nanoseconds);
  }

  /// Creates a new timestamp with the current date, with millisecond precision.
  factory Timestamp.now() {
    return Timestamp.fromDate(DateTime.now());
  }

  final int seconds;
  final int nanoseconds;

  DateTime toDate() {
    return DateTime.fromMillisecondsSinceEpoch((seconds * 1000 + (nanoseconds ~/ 1000000)).toInt());
  }

  @override
  int compareTo(Timestamp other) {
    if (seconds == other.seconds) {
      return (nanoseconds - other.nanoseconds).sign;
    } else {
      return seconds.compareTo(other.seconds);
    }
  }

  static void validateRange(int seconds, int nanoseconds) {
    Preconditions.checkArgument(
        nanoseconds >= 0, 'Timestamp nanoseconds out of range: $nanoseconds');
    Preconditions.checkArgument(
        nanoseconds < 1e9, 'Timestamp nanoseconds out of range: $nanoseconds');
    // Midnight at the beginning of 1/1/1 is the earliest supported timestamp.
    Preconditions.checkArgument(
        seconds >= -62135596800, 'Timestamp seconds out of range: $seconds');
    // This will break in the year 10,000.
    Preconditions.checkArgument(seconds < 253402300800, 'Timestamp seconds out of range: $seconds');
  }

  @override
  String toString() {
    return (ToStringHelper(runtimeType)..add('seconds', seconds)..add('nanoseconds', nanoseconds))
        .toString();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Timestamp &&
          runtimeType == other.runtimeType &&
          seconds == other.seconds &&
          nanoseconds == other.nanoseconds;

  @override
  int get hashCode => seconds.hashCode * 31 ^ nanoseconds.hashCode * 31;
}
