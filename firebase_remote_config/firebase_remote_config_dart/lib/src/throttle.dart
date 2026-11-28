import 'dart:math' as math;

import 'package:firebase_remote_config_dart/src/records.dart';

/// The throttle of 5.5 (Android, `AND-RC/internal/ConfigFetchHandler.java:72-73,487-526`): pure functions
/// over a [ThrottleRecord].
abstract final class Throttle {
  /// The waits, in minutes, of the n-th consecutive throttling failure (entry `min(n, 8)`).
  static const List<int> waitMinutes = <int>[2, 4, 8, 16, 32, 64, 128, 256];

  /// True for the statuses that start or extend the window: 429, 502, 503 and 504.
  static bool isThrottlingStatus(int status) =>
      status == 429 || status == 502 || status == 503 || status == 504;

  /// True while [record] has a window that ends after [now].
  static bool isThrottled(ThrottleRecord record, DateTime now) {
    final DateTime? until = record.until;
    return until != null && now.isBefore(until);
  }

  /// The record after one more throttling failure at [now]; [random] is uniform in [0, 1). The window
  /// ends at the later of its current end and the new wait.
  static ThrottleRecord afterFailure(
    ThrottleRecord record,
    DateTime now,
    double random,
  ) {
    final int count = math.min(record.count + 1, ThrottleRecord.maxCount);
    final int minutes = waitMinutes[math.min(count, waitMinutes.length) - 1];
    final Duration wait = Duration(
      milliseconds: (minutes * 60000 * (0.5 + random)).round(),
    );
    DateTime until = now.add(wait);
    final DateTime? current = record.until;
    if (current != null && current.isAfter(until)) {
      until = current;
    }
    return ThrottleRecord(count: count, until: until);
  }
}
