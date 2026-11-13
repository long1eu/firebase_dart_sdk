// File created by
// Lung Razvan <long1eu>
// on 12/11/2026

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/core/transaction.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/datastore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/exponential_backoff.dart';

/// Runs a transaction and retries it, with an exponential backoff between the attempts, as long as it fails with an
/// error that a new attempt can fix and there are attempts left.
class TransactionRunner<TResult> {
  TransactionRunner({
    required Transaction Function() createTransaction,
    required int maxAttempts,
    required ExponentialBackoff backoff,
    required Future<TResult> Function(Transaction) updateFunction,
    bool Function()? isTerminated,
  }) : _createTransaction = createTransaction,
       _isTerminated = isTerminated,
       _attemptsRemaining = maxAttempts,
       _backoff = backoff,
       _updateFunction = updateFunction;

  final Transaction Function() _createTransaction;
  final ExponentialBackoff _backoff;
  final Future<TResult> Function(Transaction) _updateFunction;
  int _attemptsRemaining;

  /// Whether the client that runs this transaction was terminated; a terminated client can't succeed, so the
  /// transaction is not retried (upstream stops retrying because its queue no longer runs).
  final bool Function()? _isTerminated;

  /// Runs the transaction and returns the result of the update function.
  Future<TResult> run() async {
    while (true) {
      _attemptsRemaining -= 1;
      await _waitForBackoff();

      Transaction? transaction;
      try {
        transaction = _createTransaction();
        final TResult result = await _updateFunction(transaction);
        await transaction.commit();
        return result;
      } catch (error) {
        // A read-only transaction that failed is still open on the backend.
        await transaction?.release();
        if (_attemptsRemaining > 0 &&
            !(_isTerminated?.call() ?? false) &&
            _isRetryableTransactionError(
              error,
              readOnly: transaction?.readOnly ?? false,
            )) {
          continue;
        }
        rethrow;
      }
    }
  }

  Future<void> _waitForBackoff() {
    final Completer<void> turn = Completer<void>();
    _backoff.backoffAndRun(turn.complete);
    return turn.future;
  }

  static bool _isRetryableTransactionError(
    Object error, {
    required bool readOnly,
  }) {
    if (error is FirestoreError && readOnly) {
      // A read-only transaction takes no locks and commits nothing: it has no conflicts to retry. Only failures of
      // the connection are worth another attempt.
      return !Datastore.isPermanentError(error.code);
    }
    if (error is FirestoreError) {
      // In transactions, the backend will fail outdated reads with FAILED_PRECONDITION, non-matching document versions
      // with ABORTED, and attempts to create already exists with ALREADY_EXISTS. These errors should be retried.
      final FirestoreErrorCode code = error.code;
      return code == FirestoreErrorCode.aborted ||
          code == FirestoreErrorCode.alreadyExists ||
          code == FirestoreErrorCode.failedPrecondition ||
          !Datastore.isPermanentError(error.code);
    }
    return false;
  }
}
