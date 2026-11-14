// File created by
// Lung Razvan <long1eu>
// on 12/11/2026

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/core/serial_queue.dart';
import 'package:test/test.dart';

void main() {
  test(
    'runs operations one at a time, in the order they were requested',
    () async {
      final SerialQueue queue = SerialQueue();
      final List<String> events = <String>[];

      Future<void> task(String name, int millis) => queue.run<void>(() async {
        events.add('$name:start');
        await Future<void>.delayed(Duration(milliseconds: millis));
        events.add('$name:end');
      });

      await Future.wait(<Future<void>>[
        task('a', 30),
        task('b', 1),
        task('c', 1),
      ]);

      expect(events, <String>[
        'a:start',
        'a:end',
        'b:start',
        'b:end',
        'c:start',
        'c:end',
      ]);
    },
  );

  test('a run requested by the running task runs after it', () async {
    final SerialQueue queue = SerialQueue();
    final List<String> events = <String>[];
    late Future<void> inner;

    await queue.run<void>(() async {
      events.add('outer:start');
      inner = queue.run<void>(() async => events.add('inner'));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      events.add('outer:end');
    });
    await inner;

    expect(events, <String>['outer:start', 'outer:end', 'inner']);
  });

  test(
    'work that outlives its task is queued again instead of running inline',
    () async {
      final SerialQueue queue = SerialQueue();
      final List<String> events = <String>[];
      final Completer<void> release = Completer<void>();
      late Future<void> leaked;

      final Future<void> first = queue.run<void>(() async {
        // Continues after the task completed, like a timer started by the task.
        leaked = release.future.then(
          (_) => queue.run<void>(() async {
            events.add('leaked:start');
            await Future<void>.delayed(const Duration(milliseconds: 20));
            events.add('leaked:end');
          }),
        );
      });
      await first;

      final Future<void> second = queue.run<void>(() async {
        events.add('second:start');
        release.complete();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        events.add('second:end');
      });

      await Future.wait(<Future<void>>[second, leaked]);

      expect(events, <String>[
        'second:start',
        'second:end',
        'leaked:start',
        'leaked:end',
      ]);
    },
  );

  // Ported from the JS SDK test/unit/util/async_queue.test.ts. The delayed
  // operation cases are ported against TaskScheduler in
  // util/task_scheduler_test.dart, the retryable ones against
  // RetryableOperationQueue in util/retryable_operation_queue_test.dart.
  Future<T> defer<T>(T Function() op) => Future<T>(op);

  test('schedules ops in right order', () async {
    final SerialQueue queue = SerialQueue();
    final List<String> results = <String>[];

    void pushResult(String result) {
      results.add(result);
    }

    final Future<void> op1 = queue.run<void>(() {
      return defer(
        () => 'Hello',
      ).then((String result) => defer(() => '$result world!')).then(pushResult);
    });

    final Future<void> op2 = queue.run<void>(() {
      return defer(() => 'Bye bye.').then(pushResult);
    });

    final Completer<void> op4 = Completer<void>();
    final Future<void> op3 = queue.run<void>(() {
      unawaited(
        queue.run<void>(() {
          return Future<String>.value(
            'Bye for good.',
          ).then(pushResult).then((_) => op4.complete());
        }),
      );

      return Future<String>.value('Welcome back.').then(pushResult);
    });

    await Future.wait(<Future<void>>[op1, op2, op3]);
    expect(results[0], 'Hello world!');
    expect(results[1], 'Bye bye.');
    expect(results[2], 'Welcome back.');
    await op4.future;
    expect(results[3], 'Bye for good.');
  });

  // PORTING NOTE: the JS `enqueue` throws synchronously on a failed queue;
  // `run` returns a future that fails, and `enqueueAndForget` drops the
  // operation (see SerialQueue).
  test('handles failures', () async {
    final SerialQueue queue = SerialQueue();
    final StateError expected = StateError('Firestore Test Simulated Error');

    // Schedule a failing operation and make sure it's handled correctly.
    final Future<void> op1Promise = queue
        .run<void>(() {
          // This future represents something that is rejected.
          return defer<void>(() => throw expected);
        })
        .then<void>(
          (_) => fail('expected op1 to fail'),
          onError: (Object err) {
            expect(err, same(expected));
          },
        )
        .then<void>((_) {
          expect(queue.failure, same(expected));
        });

    // Schedule a second failing operation (before the first one has actually
    // executed and failed). It should not be run.
    final Future<void> op2Promise = queue
        .run<void>(() {
          return defer<void>(() => fail('op2 should not be executed.'));
        })
        .then<void>(
          (_) => fail('expected op2 to fail'),
          onError: (Object err) {
            // should be the original failure still.
            expect(err, same(expected));
            expect(queue.failure, same(expected));
          },
        );

    await Future.wait(<Future<void>>[op1Promise, op2Promise]);

    // Once the queue is failed, trying to queue new operations fails with
    // the "already failed" error.
    bool dummyRan = false;
    Future<void> dummyOp() async => dummyRan = true;
    await expectLater(
      queue.run<void>(dummyOp),
      throwsA(
        isA<AssertionError>().having(
          (AssertionError e) => '${e.message}',
          'message',
          matches(RegExp('already failed.*Simulated Error', dotAll: true)),
        ),
      ),
    );
    await queue.enqueueAndForget(dummyOp);
    expect(dummyRan, isFalse, reason: 'dummyOp should not be run');
  });

  test('an operation that must run on a failed queue still runs', () async {
    final SerialQueue queue = SerialQueue();
    final StateError expected = StateError('boom');
    await expectLater(
      queue.run<void>(() async => throw expected),
      throwsA(same(expected)),
    );

    expect(await queue.run<int>(() async => 42, evenIfFailed: true), 42);
    // Its error does not replace the failure of the queue.
    await expectLater(
      queue.run<void>(
        () async => throw StateError('later'),
        evenIfFailed: true,
      ),
      throwsStateError,
    );
    expect(queue.failure, same(expected));
  });

  test(
    'enqueueAndForget reports the error that fails the queue once',
    () async {
      final SerialQueue queue = SerialQueue();
      final List<Object> uncaught = <Object>[];
      final StateError expected = StateError('boom');
      bool ranAfter = false;

      await runZonedGuarded(() async {
        final Future<void> failing = queue.enqueueAndForget(
          () async => throw expected,
        );
        // Requested before the failure: it is dropped, and nothing is reported.
        final Future<void> waiting = queue.enqueueAndForget(
          () async => ranAfter = true,
        );
        await failing;
        await waiting;
        await queue.enqueueAndForget(() async => ranAfter = true);
      }, (Object error, StackTrace _) => uncaught.add(error));

      expect(uncaught, <Object>[expected]);
      expect(ranAfter, isFalse);
      expect(queue.failure, same(expected));
    },
  );
}
