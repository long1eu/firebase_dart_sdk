// Ported from FlutterFire firebase_data_connect 0.4.2 (commit 6a80b1b),
// lib/src/timestamp.dart. Apache License 2.0; see NOTICE.

final RegExp _timestampPattern = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{0,9})?(Z|[+-]\d{2}:\d{2})$',
);

/// A point in time with nanoseconds: the GraphQL `Timestamp` type.
class Timestamp {
  /// A timestamp of [seconds] since the epoch plus [nanoseconds].
  Timestamp(this.nanoseconds, this.seconds);

  /// Parses an RFC 3339 timestamp such as `2024-01-02T03:04:05.123456789Z`.
  ///
  /// Throws an [Exception] for any other text.
  Timestamp.fromJson(String date) {
    if (!_timestampPattern.hasMatch(date)) {
      throw Exception('Invalid Date provided!');
    }
    final DateTime dateTime = DateTime.parse(date);
    seconds = dateTime.millisecondsSinceEpoch ~/ 1000;
    final int dot = date.indexOf('.');
    if (dot < 0) {
      return;
    }
    final StringBuffer digits = StringBuffer();
    for (int i = dot + 1; i < date.length; i++) {
      if (int.tryParse(date[i]) == null) {
        break;
      }
      digits.write(date[i]);
    }
    if (digits.isNotEmpty) {
      nanoseconds = int.parse(digits.toString().padRight(9, '0'));
    }
  }

  /// The nanoseconds within the second.
  int nanoseconds = 0;

  /// The seconds since the epoch.
  int seconds = 0;

  /// The timestamp in UTC, as RFC 3339 text, with nine fraction digits when [nanoseconds] is not
  /// zero.
  String toJson() {
    final String secondsText = DateTime.fromMillisecondsSinceEpoch(
      seconds * 1000,
      isUtc: true,
    ).toIso8601String();
    if (nanoseconds == 0) {
      return secondsText;
    }
    final String nanosText = nanoseconds.toString().padRight(9, '0');
    return '${secondsText.substring(0, 19)}.${nanosText}Z';
  }

  /// The timestamp as a [DateTime] (microsecond precision).
  DateTime toDateTime() => DateTime.parse(toJson());
}
