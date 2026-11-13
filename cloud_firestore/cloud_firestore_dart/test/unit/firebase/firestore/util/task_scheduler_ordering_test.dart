// ignore_for_file: cascade_invocations

import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:test/test.dart';

void main() {
  late TaskScheduler scheduler;
  late List<String> ran;

  setUp(() {
    scheduler = TaskScheduler('test');
    ran = <String>[];
  });

  tearDown(() => scheduler.runUntil(TaskId.all));

  test('a second task with the same id is rejected', () {
    scheduler.add(TaskId.writeStreamIdle, const Duration(hours: 1), () {});
    expect(
      () => scheduler.add(
        TaskId.writeStreamIdle,
        const Duration(hours: 1),
        () {},
      ),
      throwsArgumentError,
    );
  });

  test('runUntil runs due-first and stops after the requested task', () {
    scheduler
      ..add(
        TaskId.garbageCollection,
        const Duration(hours: 3),
        () => ran.add('gc'),
      )
      ..add(
        TaskId.listenStreamIdle,
        const Duration(hours: 1),
        () => ran.add('listen'),
      )
      ..add(
        TaskId.writeStreamIdle,
        const Duration(hours: 2),
        () => ran.add('write'),
      );

    scheduler.runUntil(TaskId.writeStreamIdle);
    expect(ran, <String>['listen', 'write']);
    expect(scheduler.getTask(TaskId.listenStreamIdle), isNull);
    expect(scheduler.getTask(TaskId.garbageCollection), isNotNull);

    scheduler.runUntil(TaskId.all);
    expect(ran, <String>['listen', 'write', 'gc']);
    expect(scheduler.getTask(TaskId.garbageCollection), isNull);
  });

  test('tasks due at the same time run in the order they were added', () {
    scheduler
      ..add(TaskId.retryTransaction, Duration.zero, () => ran.add('a'))
      ..add(TaskId.indexBackfill, Duration.zero, () => ran.add('b'));
    final List<TimerTask> tasks = <TimerTask>[
      scheduler.getTask(TaskId.indexBackfill)!,
      scheduler.getTask(TaskId.retryTransaction)!,
    ]..sort();
    expect(tasks.first, scheduler.getTask(TaskId.retryTransaction));
    scheduler.runUntil(TaskId.all);
    expect(ran, <String>['a', 'b']);
  });

  test('runUntil a missing id is an error', () {
    expect(
      () => scheduler.runUntil(TaskId.onlineStateTimeout),
      throwsA(isA<AssertionError>()),
    );
  });

  test('a cancelled task never runs and frees its id', () {
    final TimerTask task = scheduler.add(
      TaskId.onlineStateTimeout,
      const Duration(hours: 1),
      () => ran.add('x'),
    );
    task.cancel();
    expect(scheduler.getTask(TaskId.onlineStateTimeout), isNull);
    scheduler.add(
      TaskId.onlineStateTimeout,
      const Duration(hours: 1),
      () => ran.add('y'),
    );
    // Cancelling the stale handle again leaves the new task alone.
    task.cancel();
    expect(scheduler.getTask(TaskId.onlineStateTimeout), isNotNull);
    scheduler.runUntil(TaskId.onlineStateTimeout);
    expect(ran, <String>['y']);
  });

  test('a task runs on its own when its delay passes', () async {
    scheduler.add(
      TaskId.listenStreamConnectionBackoff,
      const Duration(milliseconds: 1),
      () => ran.add('timer'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(ran, <String>['timer']);
    expect(scheduler.getTask(TaskId.listenStreamConnectionBackoff), isNull);
  });

  test('task ids are ordered', () {
    expect(TaskId.all < TaskId.listenStreamIdle, isTrue);
    expect(TaskId.indexBackfill > TaskId.retryTransaction, isTrue);
    expect(TaskId.writeStreamIdle >= TaskId.writeStreamIdle, isTrue);
    expect(TaskId.writeStreamIdle <= TaskId.listenStreamIdle, isFalse);
    expect(
      TaskId.garbageCollection.compareTo(TaskId.onlineStateTimeout),
      greaterThan(0),
    );
  });

  test('equality of tasks is by id', () {
    final TimerTask task = scheduler.add(
      TaskId.garbageCollection,
      const Duration(hours: 1),
      () {},
    );
    expect(task, scheduler.getTask(TaskId.garbageCollection));
    expect(task.hashCode, TaskId.garbageCollection.hashCode);
    expect(task.toString(), contains('index'));
  });
}
