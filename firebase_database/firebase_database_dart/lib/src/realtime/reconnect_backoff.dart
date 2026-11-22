/// The reconnect delay (owner K): `rtdb_protocol.md` 8.2 with the lead's 30 s cap and full jitter;
/// threat model T13.
library;

import 'dart:math' as math;

/// The delay before the next connection attempt.
///
/// The bound starts at [min] and grows by [multiplier] per failed attempt up to [max]; the delay is
/// `random() * max(0, bound - time spent in the failed attempt)` (JS full jitter, 8.2). The bound
/// goes back to [min] after a connection established longer than [resetAfter] ago, and on [reset].
final class ReconnectBackoff {
  /// Creates the backoff. [now] and [random] replace the clock and `Random().nextDouble`
  /// (test plan 2.4); the production values are in `ConnectionTimings`.
  ReconnectBackoff({
    required this.min,
    required this.max,
    required this.multiplier,
    required this.resetAfter,
    required DateTime Function() now,
    required double Function() random,
  }) : _now = now,
       _random = random,
       _boundMicros = min.inMicroseconds.toDouble();

  /// The first bound: 1 s (1.3).
  final Duration min;

  /// The cap: 30 s (lead's decision; JS 5 min, 1.3).
  final Duration max;

  /// Growth per failed attempt: 1.3 (1.3).
  final double multiplier;

  /// Connection age after which the bound resets: 30 s (1.3).
  final Duration resetAfter;

  final DateTime Function() _now;
  final double Function() _random;

  /// The upper bound of the next delay, in microseconds (JS `reconnectDelay_`).
  double _boundMicros;

  /// When the current connection became established, or null (JS `lastConnectionEstablishedTime_`).
  DateTime? _establishedAt;

  /// The delay before the next attempt, given that the attempt that just ended started at
  /// [attemptStartedAt]; grows the bound for the one after (8.2 pseudo-code).
  ///
  /// PersistentConnection.ts:785-817: the reset after an established connection comes first, then
  /// the jitter over the bound minus the time the attempt took, then the growth. A random value
  /// outside `[0, 1]` is clamped.
  Duration nextDelay({required DateTime attemptStartedAt}) {
    final DateTime now = _now();
    final DateTime? establishedAt = _establishedAt;
    if (establishedAt != null) {
      if (now.difference(establishedAt) > resetAfter) {
        _boundMicros = min.inMicroseconds.toDouble();
      }
      _establishedAt = null;
    }
    final int sinceAttempt = math.max(
      0,
      now.difference(attemptStartedAt).inMicroseconds,
    );
    final double window = math.max(0.0, _boundMicros - sinceAttempt);
    final double delay = _random().clamp(0.0, 1.0) * window;
    _boundMicros = math.min(
      max.inMicroseconds.toDouble(),
      _boundMicros * multiplier,
    );
    return Duration(microseconds: delay.round());
  }

  /// The connection is established: healthy and at least one request answered `ok` (threat model
  /// T13, stricter than JS's "after the hello"). Starts the [resetAfter] clock.
  void markEstablished() {
    _establishedAt = _now();
  }

  /// Back to [min] at once: `resume`, a connectivity hint (test plan B-8.2c).
  void reset() {
    _boundMicros = min.inMicroseconds.toDouble();
  }

  /// To [max] at once: the invalid-token threshold was reached (8.3).
  ///
  /// Also forgets [markEstablished]: in JS the 30 s reset of the next disconnect undoes the raise
  /// when the revoked connection had lasted 30 s (PersistentConnection.ts:785-790 after :994-998);
  /// here the cap holds for the next delay.
  void setToMax() {
    _boundMicros = max.inMicroseconds.toDouble();
    _establishedAt = null;
  }
}
