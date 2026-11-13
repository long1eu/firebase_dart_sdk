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

  /// Marks the zone the operation at the head runs in, to tell the operations it enqueues (directly or through what it
  /// calls) from the ones that other code enqueues meanwhile.
  static final Object _headZoneKey = Object();
  Object? _headToken;

  /// How many operations the running head enqueued.
  int _addedByHead = 0;

  /// Whether the operation at the head is running and the code calling this belongs to it.
  bool get _calledByRunningHead =>
      _running &&
      _headToken != null &&
      identical(Zone.current[_headZoneKey], _headToken);

  /// A recovery of the persistence started ([enqueueRecovery]) and was not confirmed yet ([confirmRecovery]): its probe
  /// may have succeeded, but nothing showed yet that the persistence stores data again.
  bool _unconfirmedRecovery = false;

  /// Whether an operation is waiting to be retried.
  bool get hasPendingOperations => _operations.isNotEmpty;

  /// Adds [operation] to the queue and tries the operation at its head (which is [operation] when nothing is pending)
  /// after the operations already on [queue]. Completes after that attempt, also when it failed with a recoverable
  /// error (the operation is then retried later). Code that runs on [queue] must not wait for it.
  ///
  /// Requested while the operation at the head runs (by that operation), it only adds [operation], which runs after
  /// it.
  Future<void> enqueue(Future<void> Function() operation) {
    // Added right away, as in JS: the operation at the head sees that it enqueued another one (see [_retryNext]).
    _operations.add(operation);
    final bool addedByRunning = _calledByRunningHead;
    if (addedByRunning) {
      _addedByHead++;
    }
    return _queue.run<void>(() async {
      if (addedByRunning || _running) {
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
    final bool repeated = _unconfirmedRecovery;
    _unconfirmedRecovery = true;
    _operations.add(probe);
    final bool addedByRunning = _calledByRunningHead;
    if (addedByRunning) {
      _addedByHead++;
    }
    final bool alone = _operations.length == 1;
    return _queue.run<void>(() async {
      if (addedByRunning || _running) {
        return;
      }
      if (repeated && alone) {
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
    _addedByHead = 0;
    _running = true;
    try {
      final Object token = _headToken = Object();
      await Zone.current
          .fork(zoneValues: <Object, Object>{_headZoneKey: token})
          .run(operation);
      _remove(operation);
      // An operation that enqueued another one ran into the persistence again (RemoteStore probes the persistence
      // with a read, restarts the network, and the next write fails): the backoff keeps growing, otherwise a
      // persistence that reads but does not write would be retried in a loop without delay.
      if (_addedByHead == 0 && !_unconfirmedRecovery) {
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
