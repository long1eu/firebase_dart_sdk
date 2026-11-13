// File created by
// Lung Razvan <long1eu>
// on 13/11/2026

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/core/serial_queue.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/database.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/retryable_operation_queue.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:test/test.dart';

/// [RetryableOperationQueue] (the JS `AsyncQueue.enqueueRetryable`): operations run in order, one that fails with a
/// recoverable persistence error is retried with a backoff and holds back the ones after it.
void main() {
  late TaskScheduler scheduler;
  late RetryableOperationQueue queue;

  setUp(() {
    scheduler = TaskScheduler('retry-test');
    queue = RetryableOperationQueue(scheduler, SerialQueue());
  });

  tearDown(() => queue.stop());

  /// Runs the scheduled retry now (the backoff after a failure is at least half a second).
  Future<void> runRetry() async {
    scheduler.runUntil(TaskId.asyncQueueRetry);
    await pumpEventQueue();
  }

  test('runs an operation right away when nothing is pending', () async {
    final List<String> log = <String>[];
    await queue.enqueue(() async => log.add('a'));
    expect(log, <String>['a']);
    expect(queue.hasPendingOperations, isFalse);
    expect(scheduler.getTask(TaskId.asyncQueueRetry), isNull);
  });

  test('retries a recoverable failure and keeps the order', () async {
    bool failing = true;
    final List<String> log = <String>[];

    await queue.enqueue(() async {
      log.add('a');
      if (failing) {
        throw TransientDatabaseException('busy');
      }
    });
    // The first retry has no delay and fails again; the next one waits for the backoff.
    await pumpEventQueue();
    await queue.enqueue(() async => log.add('b'));
    expect(log.where((String e) => e == 'b'), isEmpty);
    expect(queue.hasPendingOperations, isTrue);

    failing = false;
    await runRetry();
    // 'a' succeeded; 'b' follows after a reset backoff (no delay).
    await pumpEventQueue();
    expect(log.last, 'b');
    expect(log.where((String e) => e == 'a').length, greaterThan(1));
    expect(queue.hasPendingOperations, isFalse);
  });

  test(
    'drops an operation that fails with another error and runs the next',
    () async {
      final List<String> log = <String>[];
      bool failing = true;
      await queue.enqueue(() async {
        if (failing) {
          throw TransientDatabaseException('busy');
        }
        log.add('a');
      });
      await pumpEventQueue();
      // While 'a' waits, 'b' is queued behind it.
      unawaited(
        queue
            .enqueue(() async => throw StateError('fatal'))
            .catchError((Object _) {}),
      );
      await queue.enqueue(() async => log.add('c'));

      failing = false;
      final List<Object> uncaught = <Object>[];
      await runZonedGuarded(() async {
        await runRetry();
        await pumpEventQueue();
      }, (Object error, StackTrace _) => uncaught.add(error));

      expect(log, <String>['a', 'c']);
      expect(uncaught.single, isA<StateError>());
      expect(queue.hasPendingOperations, isFalse);
    },
  );

  test('throws an error that is not recoverable to the caller', () async {
    await expectLater(
      queue.enqueue(() async => throw StateError('fatal')),
      throwsStateError,
    );
    expect(queue.hasPendingOperations, isFalse);
  });
}
