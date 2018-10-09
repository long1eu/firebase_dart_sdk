// File created by
// Lung Razvan <long1eu>
// on 24/09/2018

import 'dart:math';

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/async_queue.dart';

/// Helper to implement exponential backoff.
class ExponentialBackoff {
  final AsyncQueue _queue;
  final TimerId _timerId;
  final int _initialDelayMs;
  final double _backoffFactor;
  final int _maxDelayMs;

  int _currentBaseMs;
  int _lastAttemptTime;
  DelayedTask<void> _timerTask;

  /// Creates and returns a helper for running delayed tasks following an
  /// exponential backoff curve between attempts.
  ///
  /// * Each delay is made up of a "base" delay which follows the exponential
  /// backoff curve, and a +/- 50% "jitter" that is calculated and added to the
  /// base delay. This prevents clients from accidentally synchronizing their
  /// delays causing spikes of load to the backend.
  ///
  /// The async [queue] to run tasks on. [timerId] to use when queuing backoff
  /// tasks in the [AsyncQueue]. [initialDelayMs] is the initial delay (used as
  /// the base delay on the first retry attempt). Note that jitter will still be
  /// applied, so the actual delay could be as little as 0.5*[initialDelayMs].
  /// [backoffFactor] is the multiplier to use to determine the extended base
  /// delay after each attempt. [maxDelayMs] is the maximum base delay after
  /// which no further backoff is performed. Note that jitter will still be
  /// applied, so the actual delay could be as much as 1.5*[maxDelayMs].
  ExponentialBackoff(this._queue, this._timerId, this._initialDelayMs,
      this._backoffFactor, this._maxDelayMs) {
    _lastAttemptTime = DateTime.now().millisecondsSinceEpoch;

    reset();
  }

  /// Resets the backoff delay.
  ///
  /// * The very next [backoffAndRun] will have no delay. If it is called again
  /// (i.e. due to an error), [initialDelayMs] (plus jitter) will be used, and
  /// subsequent ones will increase according to the [backoffFactor].
  void reset() => _currentBaseMs = 0;

  /// Resets the backoff delay to the maximum delay (e.g. for use after a
  /// RESOURCE_EXHAUSTED error).
  void resetToMax() => _currentBaseMs = _maxDelayMs;

  /// Waits for [currentDelayMs], increases the delay and runs the specified
  /// task. If there was a pending backoff task waiting to run already, it will
  /// be canceled.
  void backoffAndRun(Function task) {
    // Cancel any pending backoff operation.
    cancel();

    // First schedule using the current base (which may be 0 and should be
    // honored as such).
    final int desiredDelayWithJitterMs = _currentBaseMs + _jitterDelayMs();

    // Guard against lastAttemptTime being in the future due to a clock change.
    final int delaySoFarMs =
        max(0, DateTime.now().millisecondsSinceEpoch - _lastAttemptTime);

    // Guard against the backoff delay already being past.
    final int remainingDelayMs =
        max(0, desiredDelayWithJitterMs - delaySoFarMs);

    if (_currentBaseMs > 0) {
      Log.d(runtimeType.toString(),
          'Backing off for $remainingDelayMs ms (base delay: $_currentBaseMs ms, delay with jitter: $desiredDelayWithJitterMs ms, last attempt: $delaySoFarMs ms ago)');
    }

    _timerTask = _queue.enqueueAfterDelay<void>(
        _timerId, Duration(milliseconds: remainingDelayMs), () async {
      _lastAttemptTime = DateTime.now().millisecondsSinceEpoch;
      task();
    }, 'ExponentialBackoff backoffAndRun');

    // Apply backoff factor to determine next delay and ensure it is within
    // bounds.
    _currentBaseMs = (_currentBaseMs * _backoffFactor).toInt();
    if (_currentBaseMs < _initialDelayMs) {
      _currentBaseMs = _initialDelayMs;
    } else if (_currentBaseMs > _maxDelayMs) {
      _currentBaseMs = _maxDelayMs;
    }
  }

  void cancel() {
    if (_timerTask != null) {
      _timerTask.cancel();
      _timerTask = null;
    }
  }

  /// Returns a random value in the range [-currentBaseMs/2, currentBaseMs/2]
  int _jitterDelayMs() {
    return ((Random().nextDouble() - 0.5) * _currentBaseMs).toInt();
  }
}
