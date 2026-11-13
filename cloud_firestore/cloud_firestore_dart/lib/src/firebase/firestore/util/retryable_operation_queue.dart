// File created by
// Lung Razvan <long1eu>
// on 13/11/2026

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/core/serial_queue.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/exponential_backoff.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:firebase_app_dart/internal.dart';

/// Operations that are retried with a backoff while they fail because the persistence is not available (the
/// `enqueueRetryable` part of the JS `AsyncQueue`).
///
/// The operations run in the order they were added, on [queue], and an operation only runs once every operation
/// before it succeeded. An operation that fails with a recoverable persistence error (see
/// [isRecoverablePersistenceError]) stays at the head of the queue and is tried again after a backoff
/// ([TaskId.asyncQueueRetry]); any other error removes it from the queue and is thrown to the caller of [enqueue] (the
/// JS queue fails the whole client instead).
class RetryableOperationQueue {
  RetryableOperationQueue(TaskScheduler scheduler, this._queue)
    : _backoff = ExponentialBackoff(scheduler, TaskId.asyncQueueRetry);

  static const String _tag = 'RetryableOperationQueue';

  final SerialQueue _queue;
  final ExponentialBackoff _backoff;
  final List<Future<void> Function()> _operations = <Future<void> Function()>[];

  bool _stopped = false;

  /// Whether an operation is waiting to be retried.
  bool get hasPendingOperations => _operations.isNotEmpty;

  /// Adds [operation] to the queue and tries the operation at its head right away (which is [operation] when nothing
  /// is pending). Completes after that attempt, also when it failed with a recoverable error (the operation is then
  /// retried later).
  Future<void> enqueue(Future<void> Function() operation) {
    return _queue.run<void>(() {
      _operations.add(operation);
      return _retryNext();
    });
  }

  /// Drops the pending operations and the scheduled retry.
  void stop() {
    _stopped = true;
    _operations.clear();
    _backoff.cancel();
  }

  Future<void> _retryNext() async {
    if (_operations.isEmpty || _stopped) {
      return;
    }

    try {
      await _operations.first();
      _operations.removeAt(0);
      _backoff.reset();
    } catch (error) {
      if (isRecoverablePersistenceError(error)) {
        Log.d(_tag, 'Operation failed with a retryable error: $error');
      } else {
        // Not a reason to wait: the operations behind it run without delay.
        _operations.removeAt(0);
        _backoff.reset();
        _scheduleRetry();
        rethrow;
      }
    }
    _scheduleRetry();
  }

  /// Schedules the next attempt while operations are pending. `backoffAndRun` cancels a retry that is already
  /// scheduled, so there is only ever one.
  void _scheduleRetry() {
    if (_operations.isEmpty || _stopped) {
      return;
    }
    _backoff.backoffAndRun(() {
      _queue.run<void>(_retryNext).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        Zone.current.handleUncaughtError(error, stackTrace);
      });
    });
  }
}
