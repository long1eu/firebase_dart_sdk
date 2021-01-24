// File created by
// Lung Razvan <long1eu>
// on 24/01/2021

import 'dart:async';

import 'package:cloud_firestore_vm/src/firebase/firestore/core/transaction.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/datastore.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/remote_store.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/async_task.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/exponential_backoff.dart';

typedef TransactionUpdateFunction<TResult> = Future<TResult> Function(Transaction transaction);

/// TransactionRunner encapsulates the logic needed to run and retry transactions with backoff.
class TransactionRunner<TResult> {
  TransactionRunner(AsyncQueue asyncQueue, this._remoteStore, this._updateFunction)
      : _retriesLeft = _kRetryCount,
        _backoff = ExponentialBackoff(asyncQueue, TimerId.retryTransaction);

  static const int _kRetryCount = 5;

  final Completer<TResult> _completer = Completer<TResult>();
  final TransactionUpdateFunction _updateFunction;
  final ExponentialBackoff _backoff;
  final RemoteStore _remoteStore;

  int _retriesLeft;

  /// Runs the transaction and returns a Task containing the result.
  Future<TResult> run() {
    _runWithBackoff();
    return _completer.future;
  }

  void _runWithBackoff() {
    _backoff.backoffAndRun(() async {
      try {
        final Transaction transaction = _remoteStore.createTransaction();
        final TResult result = await _updateFunction(transaction);
        await transaction.commit();
        _completer.complete(result);
      } catch (e) {
        _handleTransactionError(e);
      }
    });
  }

  void _handleTransactionError(Object error) {
    if (_retriesLeft > 0 && _isRetryableTransactionError(error)) {
      _retriesLeft -= 1;
      _runWithBackoff();
    } else {
      _completer.completeError(error);
    }
  }

  static bool _isRetryableTransactionError(Object e) {
    if (e is FirestoreError) {
      // In transactions, the backend will fail outdated reads with FAILED_PRECONDITION and
      // non-matching document versions with ABORTED. These errors should be retried.
      final FirestoreErrorCode code = e.code;
      return code == FirestoreErrorCode.aborted ||
          code == FirestoreErrorCode.failedPrecondition ||
          !Datastore.isPermanentError(code);
    }
    return false;
  }
}
