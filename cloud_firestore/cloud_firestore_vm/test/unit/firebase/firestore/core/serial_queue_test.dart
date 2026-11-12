// File created by
// Lung Razvan <long1eu>
// on 12/11/2026

import 'dart:async';

import 'package:cloud_firestore_vm/src/firebase/firestore/core/serial_queue.dart';
import 'package:test/test.dart';

void main() {
  test('runs operations one at a time, in the order they were requested',
      () async {
    final SerialQueue queue = SerialQueue();
    final List<String> events = <String>[];

    Future<void> task(String name, int millis) => queue.run<void>(() async {
          events.add('$name:start');
          await Future<void>.delayed(Duration(milliseconds: millis));
          events.add('$name:end');
        });

    await Future.wait(
        <Future<void>>[task('a', 30), task('b', 1), task('c', 1)]);

    expect(events,
        <String>['a:start', 'a:end', 'b:start', 'b:end', 'c:start', 'c:end']);
  });

  test('a failing operation does not block the ones behind it', () async {
    final SerialQueue queue = SerialQueue();

    final Future<void> failing =
        queue.run<void>(() async => throw StateError('boom'));
    final Future<int> next = queue.run<int>(() async => 42);

    await expectLater(failing, throwsStateError);
    expect(await next, 42);
  });

  test('a task running on the queue can call run again without deadlocking',
      () async {
    final SerialQueue queue = SerialQueue();
    final List<String> events = <String>[];

    await queue.run<void>(() async {
      events.add('outer:start');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await queue.run<void>(() async => events.add('inner'));
      events.add('outer:end');
    }).timeout(const Duration(seconds: 2));

    expect(events, <String>['outer:start', 'inner', 'outer:end']);
  });

  test('work that outlives its task is queued again instead of running inline',
      () async {
    final SerialQueue queue = SerialQueue();
    final List<String> events = <String>[];
    final Completer<void> release = Completer<void>();
    late Future<void> leaked;

    final Future<void> first = queue.run<void>(() async {
      // Continues after the task completed, like a timer started by the task.
      leaked = release.future.then((_) => queue.run<void>(() async {
            events.add('leaked:start');
            await Future<void>.delayed(const Duration(milliseconds: 20));
            events.add('leaked:end');
          }));
    });
    await first;

    final Future<void> second = queue.run<void>(() async {
      events.add('second:start');
      release.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      events.add('second:end');
    });

    await Future.wait(<Future<void>>[second, leaked]);

    expect(events,
        <String>['second:start', 'second:end', 'leaked:start', 'leaked:end']);
  });
}
