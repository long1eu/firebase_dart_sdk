// File created by
// Lung Razvan <long1eu>
// on 12/11/2026

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/core/transaction.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/transaction_runner.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/datastore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/exponential_backoff.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:mockito/mockito.dart' show Fake;
import 'package:test/test.dart';


class _FakeTransactionClient extends Fake implements TransactionClient {
  @override
  Future<List<MutationResult>> commit(List<Mutation> mutations) async =>
      <MutationResult>[];
}

void main() {
  final TaskScheduler scheduler = TaskScheduler('');

  TransactionRunner<String> runner(
    int maxAttempts,
    Future<String> Function(Transaction) updateFunction, {
    Duration initialDelay = const Duration(milliseconds: 1),
  }) {
    return TransactionRunner<String>(
      createTransaction: () => Transaction(_FakeTransactionClient()),
      maxAttempts: maxAttempts,
      backoff: ExponentialBackoff(scheduler, TaskId.retryTransaction,
          initialDelay: initialDelay),
      updateFunction: updateFunction,
    );
  }

  test('returns the result of the update function', () async {
    int attempts = 0;
    final String result = await runner(5, (Transaction transaction) async {
      attempts++;
      return 'done';
    }).run();

    expect(result, 'done');
    expect(attempts, 1);
  });

  test('retries retryable errors until it succeeds', () async {
    int attempts = 0;
    final String result = await runner(5, (Transaction transaction) async {
      attempts++;
      if (attempts < 3) {
        throw FirestoreError('aborted', FirestoreErrorCode.aborted);
      }
      return 'done';
    }).run();

    expect(result, 'done');
    expect(attempts, 3);
  });

  test('retries ALREADY_EXISTS and FAILED_PRECONDITION', () async {
    for (FirestoreErrorCode code in <FirestoreErrorCode>[
      FirestoreErrorCode.alreadyExists,
      FirestoreErrorCode.failedPrecondition,
    ]) {
      int attempts = 0;
      await runner(2, (Transaction transaction) async {
        attempts++;
        if (attempts == 1) {
          throw FirestoreError('retry', code);
        }
        return 'done';
      }).run();
      expect(attempts, 2, reason: '$code');
    }
  });

  test('does not retry once the client is terminated', () async {
    bool terminated = false;
    int attempts = 0;
    final Future<String> result = TransactionRunner<String>(
      createTransaction: () => Transaction(_FakeTransactionClient()),
      maxAttempts: 5,
      backoff: ExponentialBackoff(scheduler, TaskId.retryTransaction,
          initialDelay: const Duration(milliseconds: 1)),
      isTerminated: () => terminated,
      updateFunction: (Transaction transaction) async {
        attempts++;
        // The client is terminated while the attempt runs: its calls fail with a retryable code.
        terminated = true;
        throw FirestoreError('unavailable', FirestoreErrorCode.unavailable);
      },
    ).run();

    await expectLater(
        result,
        throwsA(isA<FirestoreError>().having((FirestoreError e) => e.code,
            'code', FirestoreErrorCode.unavailable)));
    expect(attempts, 1);
  });

  test('gives up after the maximum number of attempts', () async {
    int attempts = 0;
    final Future<String> result = runner(3, (Transaction transaction) async {
      attempts++;
      throw FirestoreError('aborted', FirestoreErrorCode.aborted);
    }).run();

    await expectLater(
        result,
        throwsA(isA<FirestoreError>().having(
            (FirestoreError e) => e.code, 'code', FirestoreErrorCode.aborted)));
    expect(attempts, 3);
  });

  test('does not retry errors that cannot succeed', () async {
    int attempts = 0;
    final Future<String> result = runner(5, (Transaction transaction) async {
      attempts++;
      throw FirestoreError('invalid', FirestoreErrorCode.invalidArgument);
    }).run();

    await expectLater(result, throwsA(isA<FirestoreError>()));
    expect(attempts, 1);
  });

  test('does not retry errors that are not Firestore errors', () async {
    int attempts = 0;
    final Future<String> result = runner(5, (Transaction transaction) async {
      attempts++;
      throw StateError('bug in the update function');
    }).run();

    await expectLater(result, throwsStateError);
    expect(attempts, 1);
  });

  test('waits with an exponential backoff before a retry', () async {
    const Duration initialDelay = Duration(milliseconds: 200);
    final List<DateTime> attemptTimes = <DateTime>[];

    await runner(3, (Transaction transaction) async {
      attemptTimes.add(DateTime.now());
      if (attemptTimes.length < 3) {
        throw FirestoreError('aborted', FirestoreErrorCode.aborted);
      }
      return 'done';
    }, initialDelay: initialDelay)
        .run();

    // The first attempt starts right away, the next ones wait (the delay has some jitter).
    final Duration firstWait = attemptTimes[1].difference(attemptTimes[0]);
    final Duration secondWait = attemptTimes[2].difference(attemptTimes[1]);
    expect(firstWait, greaterThanOrEqualTo(initialDelay * 0.4));
    expect(secondWait, greaterThan(firstWait * 0.5));
    expect(secondWait, greaterThanOrEqualTo(initialDelay * 0.6));
  });
}
