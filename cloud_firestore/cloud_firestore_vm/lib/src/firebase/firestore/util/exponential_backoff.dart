// File created by
// Lung Razvan <long1eu>
// on 24/09/2018

import 'dart:math';

import 'package:firebase_core/firebase_core_vm.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/async_queue.dart';

/// Helper for running delayed tasks following an exponential backoff curve between attempts using the [backoffFactor]
/// to determine the extended base delay after each attempt.
///
/// Each delay is made up of a [initialDelay] delay which follows the exponential backoff curve, and a +/- 50%
/// 'jitter' that is calculated and added to the base delay. This prevents clients from accidentally synchronizing
/// their delays causing spikes of load to the backend. All tasks are randed on the [queue] using the [timerId].
///
/// Note that jitter be applied both for the [initialDelay] and for the [maxDelay]. This means that the value can be
/// as little as 0.5 * [initialDelay] and as much as 1.5 * [maxDelay]. After [maxDelay] is reached no further backoff
/// is performed.
class ExponentialBackoff {
  // Initial backoff set to 1s according to https://cloud.google.com/apis/design/errors.
  ExponentialBackoff(
    AsyncQueue queue,
    TimerId timerId, {
    Duration initialDelay = const Duration(seconds: 1),
    double backoffFactor = 1.5,
    Duration maxDelay = const Duration(minutes: 1),
  })  : assert(queue != null),
        assert(timerId != null),
        assert(initialDelay != null),
        assert(backoffFactor != null),
        assert(maxDelay != null),
        _queue = queue,
        _timerId = timerId,
        _initialDelay = initialDelay,
        _backoffFactor = backoffFactor,
        _maxDelay = maxDelay,
        _lastAttemptTime = DateTime.now(),
        _currentBase = Duration.zero;

  final AsyncQueue _queue;
  final TimerId _timerId;
  final Duration _initialDelay;
  final double _backoffFactor;
  final Duration _maxDelay;

  Duration _currentBase;
  DateTime _lastAttemptTime;
  DelayedTask<void> _timerTask;

  /// Resets the backoff delay.
  ///
  /// The very next [backoffAndRun] will have no delay. If it is called again (i.e. due to an error), [_initialDelay]
  /// (plus jitter) will be used, and subsequent ones will increase according to the [_backoffFactor].
  void reset() => _currentBase = Duration.zero;

  /// Resets the backoff delay to the maximum delay (e.g. for use after a RESOURCE_EXHAUSTED error).
  void resetToMax() => _currentBase = _maxDelay;

  /// Waits for [currentDelayMs], increases the delay and runs the specified task. If there was a pending backoff task
  /// waiting to run already, it will be canceled.
  void backoffAndRun(Function task) {
    // Cancel any pending backoff operation.
    cancel();

    // First schedule using the current base (which may be 0 and should be
    // honored as such).
    final Duration desiredDelayWithJitter = _currentBase + _jitterDelay();

    // Guard against lastAttemptTime being in the future due to a clock change.
    final Duration difference = DateTime.now().difference(_lastAttemptTime);
    final Duration delaySoFar = difference < Duration.zero ? Duration.zero : difference;

    // Guard against the backoff delay already being past.
    final Duration remaining = desiredDelayWithJitter - delaySoFar;
    final Duration remainingDelay = remaining < Duration.zero ? Duration.zero : remaining;

    if (_currentBase > Duration.zero) {
      Log.d(
          runtimeType.toString(),
          'Backing off for $remainingDelay (base delay: $_currentBase, delay with jitter: $desiredDelayWithJitter, '
          'last attempt: $delaySoFar ago)');
    }

    _timerTask = _queue.enqueueAfterDelay<void>(_timerId, remainingDelay, () async {
      _lastAttemptTime = DateTime.now();
      task();
    }, 'ExponentialBackoff backoffAndRun');

    // Apply backoff factor to determine next delay and ensure it is within bounds.
    _currentBase = _currentBase * _backoffFactor;
    if (_currentBase < _initialDelay) {
      _currentBase = _initialDelay;
    } else if (_currentBase > _maxDelay) {
      _currentBase = _maxDelay;
    }
  }

  void cancel() {
    if (_timerTask != null) {
      _timerTask.cancel();
      _timerTask = null;
    }
  }

  /// Returns a random value in the range [-currentBaseMs/2, currentBaseMs/2]
  Duration _jitterDelay() {
    final double value = Random().nextDouble() - 0.5;
    return Duration(milliseconds: (value * _currentBase.inMilliseconds).toInt());
  }
}
