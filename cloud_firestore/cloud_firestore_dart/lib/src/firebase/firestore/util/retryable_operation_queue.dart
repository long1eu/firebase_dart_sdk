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

  /// Whether the operation at the head is running. An operation that enqueues another one (directly or through what
  /// it calls) must not start the head again: it would run twice, and the one it enqueued would be removed in its
  /// place.
  bool _running = false;

  /// A recovery of the persistence started ([enqueueRecovery]) and was not confirmed yet ([confirmRecovery]): its probe
  /// may have succeeded, but nothing showed yet that the persistence stores data again.
  bool _unconfirmedRecovery = false;

  /// Whether an operation is waiting to be retried.
  bool get hasPendingOperations => _operations.isNotEmpty;

  /// Adds [operation] to the queue and tries the operation at its head right away (which is [operation] when nothing
  /// is pending). Completes after that attempt, also when it failed with a recoverable error (the operation is then
  /// retried later).
  ///
  /// Called while the operation at the head runs (by that operation), it only adds [operation], which runs after it.
  Future<void> enqueue(Future<void> Function() operation) {
    return _queue.run<void>(() async {
      _operations.add(operation);
      if (_running) {
        return;
      }
      await _retryNext();
    });
  }

  /// Like [enqueue], for the [probe] of a recovery of the persistence (RemoteStore goes offline until it succeeds).
  ///
  /// The first recovery probes right away. A recovery that starts again before the last one was confirmed
  /// ([confirmRecovery]) waits for the backoff, which keeps growing meanwhile: a probe that succeeds says little when
  /// the persistence reads but does not write (a full disk), and the network would otherwise come back, fail to store
  /// what it receives and go offline again in a loop without delay.
  Future<void> enqueueRecovery(Future<void> Function() probe) {
    return _queue.run<void>(() async {
      final bool repeated = _unconfirmedRecovery;
      _unconfirmedRecovery = true;
      _operations.add(probe);
      if (_running) {
        return;
      }
      if (repeated && _operations.length == 1) {
        _scheduleRetry();
        return;
      }
      await _retryNext();
    });
  }

  /// Records that the persistence stored data again (a remote event or an acknowledgement): the next recovery
  /// probes right away again, and the backoff starts from the beginning.
  void confirmRecovery() {
    if (_unconfirmedRecovery) {
      _unconfirmedRecovery = false;
      _backoff.reset();
    }
  }

  /// Whether a recovery waits for its confirmation (see [enqueueRecovery]).
  bool get hasUnconfirmedRecovery => _unconfirmedRecovery;

  /// Drops the pending operations and the scheduled retry.
  void stop() {
    _stopped = true;
    _operations.clear();
    _backoff.cancel();
  }

  Future<void> _retryNext() async {
    if (_operations.isEmpty || _stopped || _running) {
      return;
    }

    final Future<void> Function() operation = _operations.first;
    final int pending = _operations.length;
    _running = true;
    try {
      await operation();
      _remove(operation);
      // An operation that enqueued another one ran into the persistence again (RemoteStore probes the persistence
      // with a read, restarts the network, and the next write fails): the backoff keeps growing, otherwise a
      // persistence that reads but does not write would be retried in a loop without delay.
      if (_operations.length < pending && !_unconfirmedRecovery) {
        _backoff.reset();
      }
    } catch (error) {
      if (isRecoverablePersistenceError(error)) {
        Log.d(_tag, 'Operation failed with a retryable error: $error');
      } else {
        // Not a reason to wait: the operations behind it run without delay.
        _remove(operation);
        _backoff.reset();
        _running = false;
        _scheduleRetry();
        rethrow;
      }
    } finally {
      _running = false;
    }
    _scheduleRetry();
  }

  /// Removes [operation] from the head; [stop] may have emptied the list meanwhile.
  void _remove(Future<void> Function() operation) {
    if (_operations.isNotEmpty && identical(_operations.first, operation)) {
      _operations.removeAt(0);
    }
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
