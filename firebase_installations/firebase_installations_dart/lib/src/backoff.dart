import 'dart:math' as math;

/// The in-memory backoff of create and generate requests (iOS,
/// `IOS-FIS/InstallationsIDController/FIRInstallationsBackoffController.m:19-130`).
///
/// An unrecoverable failure (400 or 403) allows no request for 24 h. The n-th consecutive recoverable
/// failure (a 3xx, 429, 5xx, another 4xx, or 401, 404 or 409 on create) waits `min(2^n + random, 1800)`
/// seconds. A success resets it. The caller decides which of the three a response is, per endpoint: 401
/// and 404 on generate count as a success here, and a transport error is not reported.
final class InstallationsBackoff {
  static const Duration _unrecoverable = Duration(hours: 24);
  static const int _maxRecoverableSeconds = 1800;

  int _recoverableCount = 0;
  DateTime? _retryAfter;

  /// When requests are allowed again, or null when they are allowed.
  DateTime? get retryAfter => _retryAfter;

  /// Whether a request may be sent at [now].
  bool isAllowed(DateTime now) {
    final DateTime? until = _retryAfter;
    return until == null || !now.isBefore(until);
  }

  /// Records an unrecoverable failure (400 or 403) at [now]: no request for 24 h.
  void afterUnrecoverableFailure(DateTime now) {
    _recoverableCount = 0;
    _retryAfter = now.add(_unrecoverable);
  }

  /// Records a recoverable failure at [now]; [random] is in [0, 1).
  void afterRecoverableFailure(DateTime now, double random) {
    _recoverableCount++;
    final double seconds = math.min(
      math.pow(2, math.min(_recoverableCount, 11)) + random,
      _maxRecoverableSeconds.toDouble(),
    );
    _retryAfter = now.add(Duration(milliseconds: (seconds * 1000).round()));
  }

  /// Records a successful request.
  void afterSuccess() {
    _recoverableCount = 0;
    _retryAfter = null;
  }
}
