// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_app_dart/internal.dart';

/// A Timestamp represents a point in time independent of any time zone or calendar, represented as
/// seconds and fractions of seconds at nanosecond resolution in UTC Epoch time. It is encoded using
/// the Proleptic Gregorian Calendar which extends the Gregorian calendar backwards to year one. It
/// is encoded assuming all minutes are 60 seconds long, i.e. leap seconds are 'smeared' so that no
/// leap second table is needed for interpretation. Range is from 0001-01-01T00:00:00Z to
/// 9999-12-31T23:59:59.999999999Z. By restricting to that range, we ensure that we can convert to
/// and from RFC 3339 date strings.
///
/// see [The reference timestamp definition](https://github.com/google/protobuf/blob/master/src/google/protobuf/timestamp.proto)
///
/// A snapshot returns a `Timestamp` for every timestamp field, also through
/// `DocumentSnapshot.getTimestamp` (or `getDate` for a [DateTime]). You can
/// write either a `Timestamp` or a [DateTime].
///
/// ```dart
/// await firestore.doc('events/launch').set(<String, Object?>{
///   'at': Timestamp.fromDate(DateTime.utc(2026, 11, 15, 9)),
/// });
/// final DocumentSnapshot<Map<String, Object?>> snapshot =
///     await firestore.doc('events/launch').get();
/// final DateTime? at = snapshot.getTimestamp('at')?.toDate();
/// ```
///
/// The backend stores microseconds: a write drops the nanoseconds below one
/// microsecond, and the local cache does the same at once, so a value read
/// back can differ from the one written. Timestamps are ordered in time and
/// are equal when [seconds] and [nanoseconds] are equal.
class Timestamp implements Comparable<Timestamp> {
  /// Creates a timestamp from [seconds] since the Unix epoch (UTC) and a non-negative [nanoseconds]
  /// fraction below one second.
  ///
  /// The value must lie between 0001-01-01T00:00:00Z and 9999-12-31T23:59:59.999999999Z.
  ///
  /// The constructor is `const`, so it checks these ranges with asserts only,
  /// which a release build skips. A timestamp out of range is still rejected
  /// when it is written: the write fails with an [ArgumentError].
  ///
  /// ```dart
  /// const Timestamp epochPlusHalfSecond = Timestamp(0, 500000000);
  /// ```
  const Timestamp(this.seconds, this.nanoseconds)
    : assert(
        nanoseconds >= 0,
        'Timestamp nanoseconds out of range: $nanoseconds',
      ),
      assert(
        nanoseconds < 1e9,
        'Timestamp nanoseconds out of range: $nanoseconds',
      ),
      // Midnight at the beginning of 1/1/1 is the earliest supported timestamp.
      assert(
        seconds >= -62135596800,
        'Timestamp seconds out of range: $seconds',
      ),
      // This will break in the year 10,000.
      assert(
        seconds < 253402300800,
        'Timestamp seconds out of range: $seconds',
      );

  /// Creates a new timestamp from [date], with microsecond precision (the
  /// precision of [DateTime] on the Dart VM, and of the Firestore backend).
  ///
  /// Throws an [ArgumentError] if the result is outside the supported range.
  ///
  /// When compiled to JavaScript, a [DateTime] holds only milliseconds, and so
  /// does the timestamp.
  ///
  /// ```dart
  /// final Timestamp t = Timestamp.fromDate(DateTime.now());
  /// ```
  factory Timestamp.fromDate(DateTime date) {
    final int microseconds = date.microsecondsSinceEpoch;
    // Floor division, so that negative values keep non-negative nanoseconds.
    int seconds = microseconds ~/ 1000000;
    int nanoseconds = microseconds.remainder(1000000) * 1000;

    if (nanoseconds < 0) {
      seconds -= 1;
      nanoseconds += 1000000000;
    }

    _validateRange(seconds, nanoseconds);
    return Timestamp(seconds, nanoseconds);
  }

  /// Creates a new timestamp from the given number of [milliseconds] since the
  /// Unix epoch 1970-01-01T00:00:00Z.
  ///
  /// Throws an [ArgumentError] if the result is outside the supported range.
  ///
  /// ```dart
  /// final Timestamp t = Timestamp.fromMillis(1700000000000);
  /// ```
  factory Timestamp.fromMillisecondsSinceEpoch(int milliseconds) {
    // Floor division, so that negative values keep non-negative nanoseconds.
    int seconds = milliseconds ~/ 1000;
    int nanoseconds = milliseconds.remainder(1000) * 1000000;

    if (nanoseconds < 0) {
      seconds -= 1;
      nanoseconds += 1000000000;
    }

    _validateRange(seconds, nanoseconds);
    return Timestamp(seconds, nanoseconds);
  }

  /// Builds a timestamp from a JSON map created by [toJson].
  ///
  /// Throws an [ArgumentError] if [json] does not have that shape or the value
  /// is outside the supported range.
  factory Timestamp.fromJson(Map<String, Object?> json) {
    final Object? seconds = json['seconds'];
    final Object? nanoseconds = json['nanoseconds'];
    if (json['type'] != jsonType || seconds is! int || nanoseconds is! int) {
      throw ArgumentError.value(
        json,
        'json',
        'Not a JSON representation of a Timestamp',
      );
    }
    _validateRange(seconds, nanoseconds);
    return Timestamp(seconds, nanoseconds);
  }

  /// Creates a new timestamp with the current date, with millisecond precision.
  ///
  /// The time comes from this device's clock. To store the time of the server
  /// instead, write `FieldValue.serverTimestamp()`.
  factory Timestamp.now() {
    return Timestamp.fromMillisecondsSinceEpoch(
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Seconds of UTC time since the Unix epoch, 1970-01-01T00:00:00Z.
  final int seconds;

  /// The fraction of a second, in nanoseconds, from 0 to 999,999,999. Always counted forward in
  /// time, also for timestamps before the epoch.
  final int nanoseconds;

  /// The value of the `type` field written by [toJson].
  static const String jsonType = 'firestore/timestamp/1.0';

  /// Converts this timestamp to a [DateTime] in the local time zone, with
  /// microsecond precision. Sub-microsecond precision is truncated toward the
  /// earlier time.
  ///
  /// Call `toUtc()` on the result for a UTC [DateTime]. When compiled to
  /// JavaScript, the microseconds are lost as well.
  DateTime toDate() {
    // Milliseconds first, then the remaining microseconds: seconds * 10^6 is
    // above 2^53 (not exact on the web) for dates after about the year 2255.
    return DateTime.fromMillisecondsSinceEpoch(
      seconds * 1000 + nanoseconds ~/ 1000000,
    ).add(Duration(microseconds: (nanoseconds ~/ 1000) % 1000));
  }

  /// The number of milliseconds since the Unix epoch 1970-01-01T00:00:00Z.
  /// Sub-millisecond precision is truncated toward the earlier time.
  int toMillis() {
    return seconds * 1000 + nanoseconds ~/ 1000000;
  }

  /// A JSON-serializable representation of this timestamp, in the same shape
  /// as the JS SDK's `Timestamp.toJSON()`. Read it back with
  /// [Timestamp.fromJson].
  Map<String, Object> toJson() {
    return <String, Object>{
      'type': jsonType,
      'seconds': seconds,
      'nanoseconds': nanoseconds,
    };
  }

  @override
  int compareTo(Timestamp other) {
    if (seconds == other.seconds) {
      return (nanoseconds - other.nanoseconds).sign;
    } else {
      return seconds.compareTo(other.seconds);
    }
  }

  static void _validateRange(int seconds, int nanoseconds) {
    Preconditions.checkArgument(
      nanoseconds >= 0,
      'Timestamp nanoseconds out of range: $nanoseconds',
    );
    Preconditions.checkArgument(
      nanoseconds < 1e9,
      'Timestamp nanoseconds out of range: $nanoseconds',
    );
    // Midnight at the beginning of 1/1/1 is the earliest supported timestamp.
    Preconditions.checkArgument(
      seconds >= -62135596800,
      'Timestamp seconds out of range: $seconds',
    );
    // This will break in the year 10,000.
    Preconditions.checkArgument(
      seconds < 253402300800,
      'Timestamp seconds out of range: $seconds',
    );
  }

  /// A string with the seconds and the nanoseconds of this timestamp, `Timestamp(seconds=1, nanoseconds=2)`, as in
  /// the JS and Android SDKs. It is meant for logs and messages; use [seconds] and [nanoseconds], or [toDate], to
  /// read the value.
  @override
  String toString() => 'Timestamp(seconds=$seconds, nanoseconds=$nanoseconds)';

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

/// Members of [Timestamp] for the SDK itself. Not exported by the public libraries.
extension TimestampInternal on Timestamp {
  /// Throws an [ArgumentError] unless [seconds] and [nanoseconds] are in the
  /// range a [Timestamp] can hold.
  static void validateRange(int seconds, int nanoseconds) =>
      Timestamp._validateRange(seconds, nanoseconds);
}
