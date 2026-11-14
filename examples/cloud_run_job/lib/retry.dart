import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

/// The Firestore errors that may go away when the same request is sent again
/// later: the backend could not be reached, was overloaded, or gave up.
const Set<FirestoreErrorCode> retryableCodes = <FirestoreErrorCode>{
  FirestoreErrorCode.unavailable,
  FirestoreErrorCode.deadlineExceeded,
  FirestoreErrorCode.resourceExhausted,
  FirestoreErrorCode.aborted,
  FirestoreErrorCode.internal,
};

/// Thrown by [withRetries] when the last attempt failed with a retryable
/// error too.
class RetriesExhausted implements Exception {
  RetriesExhausted(this.operation, this.attempts, this.lastError);

  final String operation;
  final int attempts;
  final Object lastError;

  @override
  String toString() =>
      '$operation failed $attempts times; the last error: $lastError';
}

/// Runs [operation] and runs it again, after an exponential backoff with
/// jitter, while it fails with one of [retryableCodes] or does not finish
/// within [attemptTimeout]; at most [maxAttempts] times in all. Any other
/// error is thrown at once.
///
/// Only retry operations that are safe to run twice: a write whose
/// acknowledgement was lost may have been applied.
Future<T> withRetries<T>(
  String operation,
  Future<T> Function() run, {
  int maxAttempts = 5,
  Duration initialDelay = const Duration(seconds: 1),
  Duration maxDelay = const Duration(seconds: 30),
  Duration attemptTimeout = const Duration(seconds: 60),
  void Function(String message)? log,
  Random? random,
  Future<void> Function(Duration delay)? sleep,
}) async {
  final Random jitter = random ?? Random();
  final Future<void> Function(Duration) wait =
      sleep ?? (Duration delay) => Future<void>.delayed(delay);
  Duration delay = initialDelay;
  for (int attempt = 1; ; attempt++) {
    try {
      return await run().timeout(attemptTimeout);
    } on Object catch (error) {
      final bool retryable =
          error is TimeoutException ||
          (error is FirestoreError && retryableCodes.contains(error.code));
      if (!retryable) {
        rethrow;
      }
      if (attempt >= maxAttempts) {
        throw RetriesExhausted(operation, attempt, error);
      }
      // Full jitter: a random delay up to the current backoff, so that many
      // tasks that failed together do not retry together.
      final Duration pause = delay * jitter.nextDouble();
      log?.call(
        '$operation: attempt $attempt failed ($error); '
        'trying again in ${pause.inMilliseconds} ms',
      );
      await wait(pause);
      delay = delay * 2 > maxDelay ? maxDelay : delay * 2;
    }
  }
}
