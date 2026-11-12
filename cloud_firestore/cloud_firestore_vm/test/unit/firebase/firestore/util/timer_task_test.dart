import 'dart:async';

import 'package:cloud_firestore_vm/src/firebase/firestore/util/timer_task.dart';
import 'package:test/test.dart';

void main() {
  late TaskScheduler scheduler;
  late List<String> ran;

  setUp(() {
    scheduler = TaskScheduler('test');
    ran = <String>[];
  });

  const Duration long = Duration(minutes: 10);

  test('runUntil(all) runs every task in target-time order', () {
    scheduler.add(TaskId.writeStreamIdle, long * 2, () => ran.add('write'));
    scheduler.add(TaskId.listenStreamIdle, long, () => ran.add('listen'));
    scheduler.add(TaskId.garbageCollection, long * 3, () => ran.add('gc'));

    scheduler.runUntil(TaskId.all);
    expect(ran, <String>['listen', 'write', 'gc']);
    expect(scheduler.getTask(TaskId.writeStreamIdle), isNull);
  });

  test('runUntil(id) runs earlier tasks of other ids, up to and including id',
      () {
    scheduler.add(TaskId.listenStreamIdle, long, () => ran.add('listen'));
    scheduler.add(TaskId.writeStreamIdle, long * 2, () => ran.add('write'));
    scheduler.add(TaskId.garbageCollection, long * 3, () => ran.add('gc'));

    scheduler.runUntil(TaskId.writeStreamIdle);
    expect(ran, <String>['listen', 'write']);
    expect(scheduler.getTask(TaskId.garbageCollection), isNotNull);
    expect(scheduler.getTask(TaskId.listenStreamIdle), isNull);
  });

  test('runUntil orders by target time, not insertion order', () {
    scheduler.add(TaskId.garbageCollection, long * 3, () => ran.add('gc'));
    scheduler.add(TaskId.writeStreamIdle, long, () => ran.add('write'));

    scheduler.runUntil(TaskId.writeStreamIdle);
    expect(ran, <String>['write']);
    expect(scheduler.getTask(TaskId.garbageCollection), isNotNull);
  });

  test('runUntil for a missing timer fails', () {
    scheduler.add(TaskId.listenStreamIdle, long, () => ran.add('listen'));
    expect(() => scheduler.runUntil(TaskId.writeStreamIdle), throwsA(anything));
    expect(ran, isEmpty);
  });

  test('runUntil(all) with nothing scheduled is fine', () {
    scheduler.runUntil(TaskId.all);
  });

  test('a stale handle does not cancel a newer task with the same id', () {
    final TimerTask first =
        scheduler.add(TaskId.listenStreamIdle, long, () => ran.add('first'));
    scheduler.runUntil(TaskId.listenStreamIdle);
    expect(ran, <String>['first']);

    final TimerTask second =
        scheduler.add(TaskId.listenStreamIdle, long, () => ran.add('second'));
    first.cancel();
    expect(scheduler.getTask(TaskId.listenStreamIdle), same(second));

    scheduler.runUntil(TaskId.listenStreamIdle);
    expect(ran, <String>['first', 'second']);
  });

  test('a cancelled task never runs', () async {
    final TimerTask task = scheduler
        .add(TaskId.listenStreamIdle, const Duration(milliseconds: 10), () {
      ran.add('x');
    });
    task.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(ran, isEmpty);
  });

  test('a task fires by itself after its delay and only once', () async {
    scheduler.add(TaskId.listenStreamIdle, const Duration(milliseconds: 10),
        () => ran.add('x'));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(ran, <String>['x']);
    expect(scheduler.getTask(TaskId.listenStreamIdle), isNull);
  });
}
