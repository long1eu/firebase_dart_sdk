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
  late SerialQueue serial;
  late RetryableOperationQueue queue;

  setUp(() {
    scheduler = TaskScheduler('retry-test');
    serial = SerialQueue();
    queue = RetryableOperationQueue(scheduler, serial);
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

  test(
    'an operation enqueued by the running operation runs once, after it',
    () async {
      // RemoteStore does this: a retried acknowledgement restarts the network, the write pipeline fails to read the
      // next batch and enqueues a probe of the persistence.
      final List<String> log = <String>[];
      await queue.enqueue(() async {
        log.add('a');
        await queue.enqueue(() async => log.add('b'));
        log.add('a done');
      });
      await runRetry();
      expect(log, <String>['a', 'a done', 'b']);
      expect(queue.hasPendingOperations, isFalse);
    },
  );

  test('an operation enqueued by a retried operation is not lost', () async {
    final List<String> log = <String>[];
    bool failing = true;
    await queue.enqueue(() async {
      log.add('a');
      if (failing) {
        throw TransientDatabaseException('busy');
      }
      await queue.enqueue(() async => log.add('b'));
    });
    await pumpEventQueue();
    failing = false;
    await runRetry();
    // 'b' follows after the reset backoff, which may still be a scheduled task.
    if (scheduler.getTask(TaskId.asyncQueueRetry) != null) {
      await runRetry();
    }
    expect(log.where((String e) => e == 'b'), hasLength(1));
    expect(log.last, 'b');
    expect(queue.hasPendingOperations, isFalse);
  });

  test('a recovery that leads straight into a new failure backs off', () async {
    // A persistence that reads but does not write: each probe succeeds, restarts the network, and the next
    // operation fails and enqueues a new probe. Without a growing backoff this loops without delay.
    int runs = 0;
    Future<void> probe() async {
      runs++;
      await queue.enqueue(probe);
    }

    await queue.enqueue(probe);
    // Real timers: a retry without delay would run again and again while the event queue is pumped.
    await pumpEventQueue(times: 200);
    expect(runs, lessThan(5));
    queue.stop();
  });

  test(
    'a recovery that comes back before it was confirmed waits for the backoff',
    () async {
      int probes = 0;
      await queue.enqueueRecovery(() async => probes++);
      expect(probes, 1, reason: 'the first recovery probes right away');

      // The probe succeeded, but nothing was stored since: the next recovery waits.
      await queue.enqueueRecovery(() async => probes++);
      expect(probes, 1);
      await runRetry();
      expect(probes, 2);

      // Once the persistence stored something, a recovery probes right away again.
      queue.confirmRecovery();
      expect(queue.hasUnconfirmedRecovery, isFalse);
      await queue.enqueueRecovery(() async => probes++);
      expect(probes, 3);
    },
  );

  test('throws an error that is not recoverable to the caller', () async {
    await expectLater(
      queue.enqueue(() async => throw StateError('fatal')),
      throwsStateError,
    );
    expect(queue.hasPendingOperations, isFalse);
  });

  // The tests of `enqueueRetryable` in the JS SDK (packages/firestore/test/unit/util/async_queue.test.ts). The JS
  // `enqueueAndForget` / `enqueue` are runs on the [SerialQueue] the retryable operations share.
  group('JS async_queue.test.ts', () {
    TransientDatabaseException simulatedError() => TransientDatabaseException(
      'Simulated error',
      'Simulated retryable error',
    );

    test('Retries retryable operations', () async {
      final List<int> completedSteps = <int>[];
      await queue.enqueue(() async {
        completedSteps.add(1);
        if (completedSteps.length == 1) {
          throw simulatedError();
        }
      });
      await runRetry();
      expect(completedSteps, <int>[1, 1]);
    });

    test("Doesn't retry internal exceptions", () async {
      // PORTING NOTE: the JS queue fails for good (every later operation is rejected with the error). Here the
      // operation is dropped, its caller gets the error, and nothing is retried.
      int attempts = 0;
      await expectLater(
        queue.enqueue(() async {
          attempts++;
          throw StateError('Simulated test failure');
        }),
        throwsStateError,
      );
      expect(scheduler.getTask(TaskId.asyncQueueRetry), isNull);
      await serial.run<void>(() async {});
      expect(attempts, 1);
    });

    test('Schedules first retryable attempt with no delay', () async {
      final List<int> completedSteps = <int>[];
      final Future<void> done = queue.enqueue(
        () async => completedSteps.add(1),
      );
      expect(scheduler.getTask(TaskId.asyncQueueRetry), isNull);
      await done;
      expect(completedSteps, <int>[1]);
      expect(scheduler.getTask(TaskId.asyncQueueRetry), isNull);
    });

    test('Retries retryable operations with backoff', () async {
      final List<int> completedSteps = <int>[];
      await queue.enqueue(() async {
        completedSteps.add(1);
        if (completedSteps.length == 1) {
          throw simulatedError();
        }
      });

      // Verify that only one attempt has been made: the retry waits for its timer.
      expect(completedSteps, <int>[1]);
      expect(scheduler.getTask(TaskId.asyncQueueRetry), isNotNull);

      // Fast forward all operations.
      await runRetry();
      expect(completedSteps, <int>[1, 1]);
    });

    test('Retries retryable operations in order', () async {
      final List<int> completedSteps = <int>[];
      final Completer<void> blocking = Completer<void>();

      unawaited(
        queue.enqueue(() async {
          completedSteps.add(1);
          if (completedSteps.length == 1) {
            throw simulatedError();
          }
        }),
      );
      unawaited(
        queue.enqueue(() async {
          completedSteps.add(2);
          blocking.complete();
        }),
      );

      await blocking.future;
      expect(completedSteps, <int>[1, 1, 2]);
    });

    test('Does not delay retryable operations that succeed', () async {
      final List<int> completedSteps = <int>[];
      unawaited(queue.enqueue(() async => completedSteps.add(1)));
      unawaited(serial.run<void>(() async => completedSteps.add(2)));
      await serial.run<void>(() async => completedSteps.add(3));
      expect(completedSteps, <int>[1, 2, 3]);
    });

    test('Catches up when retryable operation fails', () async {
      final List<int> completedSteps = <int>[];
      final Completer<void> blocking = Completer<void>();

      unawaited(
        queue.enqueue(() async {
          completedSteps.add(1);
          if (completedSteps.length == 1) {
            throw simulatedError();
          }
        }),
      );
      unawaited(serial.run<void>(() async => completedSteps.add(2)));
      unawaited(
        queue.enqueue(() async {
          completedSteps.add(3);
          blocking.complete();
        }),
      );
      await blocking.future;

      // Once all existing retryable operations succeeded, they are scheduled in the order they are enqueued.
      unawaited(serial.run<void>(() async => completedSteps.add(4)));
      await serial.run<void>(() async => completedSteps.add(5));

      expect(completedSteps, <int>[1, 2, 1, 3, 4, 5]);
    });
  });
}
