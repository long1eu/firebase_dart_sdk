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

  test('a failing operation does not block the ones behind it', () async {
    final SerialQueue queue = SerialQueue();

    final Future<void> failing = queue.run<void>(
      () async => throw StateError('boom'),
    );
    final Future<int> next = queue.run<int>(() async => 42);

    await expectLater(failing, throwsStateError);
    expect(await next, 42);
  });

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

  // PORTING NOTE: the JS AsyncQueue enters a failed state on any error of an
  // operation, because every JS operation handles its expected errors itself.
  // Client operations of the port still let expected errors (a persistence
  // error of a cache read, the error of a failed initialization, the
  // non-recoverable error of a retryable operation) reach the queue and their
  // caller, so the queue keeps going after a failure.
  test(
    'handles failures',
    skip:
        'Expected errors of client operations still reach SerialQueue (see '
        'the PORTING NOTE above); the JS AsyncQueue enters a failed state and '
        'rejects every later operation',
    () {},
  );
}
