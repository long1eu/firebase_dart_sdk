// File created by
// Lung Razvan <long1eu>
// on 19/09/2018

import 'dart:async';

import 'package:firebase_firestore/src/firebase/firestore/util/async_queue.dart';
import 'package:test/test.dart';

void main() {
  // In these generic tests the specific TimerIDs don't matter.
  final TimerId timerId1 = TimerId.LISTEN_STREAM_CONNECTION_BACKOFF;
  final TimerId timerId2 = TimerId.LISTEN_STREAM_IDLE;
  final TimerId timmeId3 = TimerId.WRITE_STREAM_CONNECTION_BACKOFF;

  AsyncQueue queue;
  List<int> completedSteps;
  List<int> expectedSteps;

  setUp(
    () async {
      queue = await AsyncQueue.createQueue();
      completedSteps = <int>[];
      expectedSteps = null;
    },
  );

  Task runnableForStep(int n) {
    return () {
      completedSteps.add(n);
      if (completedSteps != null &&
          completedSteps.length >= expectedSteps.length) {
        expect(expectedSteps, completedSteps);
      }
    };
  }

  Future<void> waitForExpectedSteps() {
    return Future.delayed(const Duration(seconds: 1));
  }

  test('canScheduleTasksInTheFuture', () async {
    expectedSteps = [1, 2, 3, 4];
    queue.enqueueAndForget(runnableForStep(1));
    queue.enqueueAfterDelay(
        timerId1, Duration(milliseconds: 5), runnableForStep(4));
    queue.enqueueAndForget(runnableForStep(2));
    queue.enqueueAfterDelay(
        timerId2, Duration(milliseconds: 1), runnableForStep(3));

    await waitForExpectedSteps();
  });

  test('canCancelDelayedTasks', () async {
    expectedSteps = [1, 3];
    // Queue everything from the queue to ensure nothing completes before we cancel.
    queue.enqueueAndForget(() {
      queue.enqueueAndForget(runnableForStep(1));
      DelayedTask step2Timer = queue.enqueueAfterDelay(
          timerId1, Duration(milliseconds: 1), runnableForStep(2));
      queue.enqueueAfterDelay(
          timmeId3, Duration(milliseconds: 5), runnableForStep(3));

      expect(queue.containsDelayedTask(timerId1), isTrue);
      step2Timer.cancel();
      expect(queue.containsDelayedTask(timerId1), isTrue);
    });

    await waitForExpectedSteps();
  });
}
