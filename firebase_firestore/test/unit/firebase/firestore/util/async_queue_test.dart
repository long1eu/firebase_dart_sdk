// File created by
// Lung Razvan <long1eu>
// on 08/10/2018

import 'dart:async';

import 'package:firebase_firestore/src/firebase/firestore/util/async_queue.dart';
import 'package:test/test.dart';

void main() {
  // In these generic tests the specific TimerIDs don't matter.
  const TimerId TIMER_ID_1 = TimerId.listenStreamConnectionBackoff;
  const TimerId TIMER_ID_2 = TimerId.listenStreamIdle;
  const TimerId TIMER_ID_3 = TimerId.writeStreamConnectionBackoff;

  AsyncQueue queue;
  List<int> completedSteps;
  List<int> expectedSteps;

  setUp(() {
    queue = AsyncQueue();
    completedSteps = <int>[];
  });

  /// Helper that returns a Function that adds `n` to [completedSteps] and
  /// resolves the Future if the completedSteps match the expectedSteps.
  Future<int> Function() runnableForStep(int n) {
    return () async {
      if (expectedSteps != null &&
          completedSteps.length >= expectedSteps.length) {
        expect(completedSteps, containsAllInOrder(expectedSteps));
      }

      await Future<void>.delayed(const Duration(seconds: 1));
      completedSteps.add(n);
      return n;
    };
  }

  test('canScheduleTasksInTheFuture', () async {
    expectedSteps = <int>[1, 2, 3, 4];

    queue.enqueueAndForget(runnableForStep(1));
    queue.enqueueAfterDelay(
        TIMER_ID_1, const Duration(milliseconds: 5), runnableForStep(4));
    queue.enqueueAndForget(runnableForStep(2));
    queue.enqueueAfterDelay(
        TIMER_ID_2, const Duration(milliseconds: 1), runnableForStep(3));

    await Future<void>.delayed(const Duration(seconds: 5));
  });

  test('canCancelDelayedTasks', () async {
    expectedSteps = <int>[1, 3];
    // Queue everything from the queue to ensure nothing completes before we
    // cancel.
    queue.enqueueAndForget(() async {
      queue.enqueueAndForget(runnableForStep(1));

      final DelayedTask<void> step2Timer = queue.enqueueAfterDelay<void>(
          TIMER_ID_1, const Duration(milliseconds: 1), runnableForStep(2));

      queue.enqueueAfterDelay(
          TIMER_ID_3, const Duration(milliseconds: 3), runnableForStep(3));

      expect(queue.containsDelayedTask(TIMER_ID_1), isTrue);
      step2Timer.cancel();
      expect(queue.containsDelayedTask(TIMER_ID_1), isFalse);
    });

    await Future<void>.delayed(const Duration(seconds: 5));
  });

  test('canManuallyDrainAllDelayedTasksForTesting', () async {
    queue.enqueueAndForget(runnableForStep(1));
    queue.enqueueAfterDelay(
        TIMER_ID_1, const Duration(milliseconds: 20), runnableForStep(4));
    queue.enqueueAfterDelay(
        TIMER_ID_2, const Duration(milliseconds: 10), runnableForStep(3));
    queue.enqueueAndForget(runnableForStep(2));

    await queue.runDelayedTasksUntil(TimerId.all);
    expect(completedSteps, <int>[1, 2, 3, 4]);
  });

  test('canManuallyDrainSpecificDelayedTasksForTesting', () async {
    queue.enqueueAndForget(runnableForStep(1));
    queue.enqueueAfterDelay(
        TIMER_ID_1, const Duration(milliseconds: 20), runnableForStep(5));
    queue.enqueueAfterDelay(
        TIMER_ID_2, const Duration(milliseconds: 10), runnableForStep(3));
    queue.enqueueAfterDelay(
        TIMER_ID_3, const Duration(milliseconds: 15), runnableForStep(4));
    queue.enqueueAndForget(runnableForStep(2));

    await queue.runDelayedTasksUntil(TIMER_ID_3);
    expect(completedSteps, <int>[1, 2, 3, 4]);
  });
}
