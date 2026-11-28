import 'dart:math' as math;

import 'package:firebase_app_check_dart/src/clocks.dart';
import 'package:meta/meta.dart';

/// The longest window after a failure of the "refused" class.
const Duration _refusedCap = Duration(hours: 4);

/// The longest window after a failure of the "unreachable" class.
const Duration _unreachableCap = Duration(minutes: 5);

/// The exponent past which every wait is over the 4 h cap whatever the jitter: 2^15 s × 0.5 is
/// already longer.
const int _maxExponent = 15;

/// Refuses exchanges for a while after one failed. In memory only; one per kind of exchange.
///
/// An exchange calls [begin] when it starts and reports its end with [succeeded] or [failed],
/// giving back the generation it noted. An outcome of an older generation is ignored, so a burst
/// of exchanges that fail together sets one window and counts one failure, and a success that
/// started before a window was set cannot erase it.
@internal
final class ExchangeGate {
  /// A gate that measures its windows on [clocks]' monotonic source and draws its jitter from
  /// [random], which returns a number in [0, 1).
  ExchangeGate({required Clocks clocks, required double Function() random})
    : _clocks = clocks,
      _random = random;

  final Clocks _clocks;
  final double Function() _random;

  int _generation = 0;
  int _failures = 0;
  Duration? _windowEnd;
  DateTime? _retryAfter;
  int? _httpStatus;

  /// The current generation: an exchange notes it when it starts.
  int begin() => _generation;

  /// True while a window is set and has not passed, on the monotonic source only. A closed gate
  /// refuses the exchange.
  bool get isClosed => remaining > Duration.zero;

  /// The monotonic time left in the window; zero for an open gate.
  Duration get remaining {
    final Duration? end = _windowEnd;
    if (end == null) {
      return Duration.zero;
    }
    final Duration left = end - _clocks.monoNow();
    return left > Duration.zero ? left : Duration.zero;
  }

  /// The wall-clock time at which the window was expected to end when it was set, while the gate
  /// is closed; null for an open gate. Information for the caller: the gate does not use it.
  DateTime? get retryAfter => isClosed ? _retryAfter : null;

  /// The HTTP status of the failure that set the window, if it had one, while the gate is closed.
  int? get httpStatus => isClosed ? _httpStatus : null;

  /// The number of consecutive failures counted.
  @visibleForTesting
  int get failures => _failures;

  /// An exchange that noted [generation] succeeded: the count and the window are cleared, unless
  /// another outcome advanced the generation since.
  void succeeded(int generation) {
    if (generation != _generation) {
      return;
    }
    _generation += 1;
    _failures = 0;
    _windowEnd = null;
    _retryAfter = null;
    _httpStatus = null;
  }

  /// An exchange that noted [generation] failed. Returns the wait it set, or null when the outcome
  /// was ignored because another outcome advanced the generation since.
  ///
  /// [refused] is true when the server answered (a status other than 200, or a body that breaks a
  /// rule): the wait is capped at 4 h. Otherwise (no answer, or a custom provider failing) it is
  /// capped at 5 min. [httpStatus] is the status of the failure, when it had one.
  Duration? failed(int generation, {required bool refused, int? httpStatus}) {
    if (generation != _generation) {
      return null;
    }
    _generation += 1;
    _failures += 1;
    final Duration wait = _wait(
      _failures,
      refused ? _refusedCap : _unreachableCap,
    );
    _windowEnd = _clocks.monoNow() + wait;
    _retryAfter = _clocks.wallNow().add(wait);
    _httpStatus = httpStatus;
    return wait;
  }

  /// `min(1 s × 2^(n−1) × (0.5 + random), cap)`: the cap is applied after the jitter. A draw
  /// outside [0, 1) (a broken injected source) counts as 0.5.
  Duration _wait(int failures, Duration cap) {
    final double drawn = _random();
    final double draw = drawn >= 0 && drawn < 1 ? drawn : 0.5;
    final int exponent = math.min(failures - 1, _maxExponent);
    final double microseconds =
        Duration.microsecondsPerSecond * math.pow(2, exponent) * (0.5 + draw);
    if (microseconds >= cap.inMicroseconds) {
      return cap;
    }
    return Duration(microseconds: microseconds.round());
  }

  @override
  String toString() =>
      'ExchangeGate(failures: $_failures, remaining: ${remaining.inSeconds} s)';
}
