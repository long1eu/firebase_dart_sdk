/// The reconnect delay (owner K): `rtdb_protocol.md` 8.2 with the lead's 30 s cap and full jitter;
/// threat model T13.
library;

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
  });

  /// The first bound: 1 s (1.3).
  final Duration min;

  /// The cap: 30 s (lead's decision; JS 5 min, 1.3).
  final Duration max;

  /// Growth per failed attempt: 1.3 (1.3).
  final double multiplier;

  /// Connection age after which the bound resets: 30 s (1.3).
  final Duration resetAfter;

  /// The delay before the next attempt, given that the attempt that just ended started at
  /// [attemptStartedAt]; grows the bound for the one after (8.2 pseudo-code).
  Duration nextDelay({required DateTime attemptStartedAt}) {
    throw UnimplementedError();
  }

  /// The connection is established: healthy and at least one request answered `ok` (threat model
  /// T13, stricter than JS's "after the hello"). Starts the [resetAfter] clock.
  void markEstablished() {
    throw UnimplementedError();
  }

  /// Back to [min] at once: `resume`, a connectivity hint (test plan B-8.2c).
  void reset() {
    throw UnimplementedError();
  }

  /// To [max] at once: the invalid-token threshold was reached (8.3).
  void setToMax() {
    throw UnimplementedError();
  }
}
