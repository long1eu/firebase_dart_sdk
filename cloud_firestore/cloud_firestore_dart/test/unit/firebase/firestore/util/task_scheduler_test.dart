// Copyright 2018 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Ported from upstream AsyncQueueTest. The Dart port has no AsyncQueue (it is
// single threaded); the delayed task part of it is TaskScheduler/TimerTask, so
// the delayed task tests are ported against it. "enqueueAndForget" of an
// immediate task is a direct call, which preserves the ordering the upstream
// test relies on.

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:test/test.dart';

void main() {
  // In these generic tests the specific TaskIds don't matter.
  const TaskId timerId1 = TaskId.listenStreamConnectionBackoff;
  const TaskId timerId2 = TaskId.listenStreamIdle;
  const TaskId timerId3 = TaskId.writeStreamConnectionBackoff;

  late TaskScheduler queue;
  late List<int> completedSteps;
  List<int>? expectedSteps;
  late Completer<void> expectedStepsCompleted;

  setUp(() {
    queue = TaskScheduler('test');
    completedSteps = <int>[];
    expectedSteps = null;
    expectedStepsCompleted = Completer<void>();
  });

  /// Returns a function that adds [n] to completedSteps and completes
  /// expectedStepsCompleted if the completedSteps match the expectedSteps.
  void Function() runnableForStep(int n) {
    return () {
      completedSteps.add(n);
      if (expectedSteps != null &&
          completedSteps.length >= expectedSteps!.length) {
        expect(completedSteps, expectedSteps);
        expect(
          expectedStepsCompleted.isCompleted,
          isFalse,
          reason: 'Expected steps already completed.',
        );
        expectedStepsCompleted.complete();
      }
    };
  }

  Future<void> waitForExpectedSteps() =>
      expectedStepsCompleted.future.timeout(const Duration(seconds: 10));

  test('canScheduleTasksInTheFuture', () async {
    expectedSteps = <int>[1, 2, 3, 4];
    runnableForStep(1)();
    queue.add(timerId1, const Duration(milliseconds: 5), runnableForStep(4));
    runnableForStep(2)();
    queue.add(timerId2, const Duration(milliseconds: 1), runnableForStep(3));
    await waitForExpectedSteps();
  });

  test('canCancelDelayedTasks', () async {
    expectedSteps = <int>[1, 3];
    runnableForStep(1)();
    final TimerTask step2Timer = queue.add(
      timerId1,
      const Duration(milliseconds: 1),
      runnableForStep(2),
    );
    queue.add(timerId3, const Duration(milliseconds: 5), runnableForStep(3));

    expect(queue.getTask(timerId1), isNotNull);
    step2Timer.cancel();
    expect(queue.getTask(timerId1), isNull);

    await waitForExpectedSteps();
  });

  test('canManuallyDrainAllDelayedTasksForTesting', () {
    runnableForStep(1)();
    queue.add(timerId1, const Duration(milliseconds: 20), runnableForStep(4));
    queue.add(timerId2, const Duration(milliseconds: 10), runnableForStep(3));
    runnableForStep(2)();

    queue.runUntil(TaskId.all);
    expect(completedSteps, <int>[1, 2, 3, 4]);
  });

  test('canManuallyDrainSpecificDelayedTasksForTesting', () {
    runnableForStep(1)();
    queue.add(timerId1, const Duration(milliseconds: 20), runnableForStep(5));
    queue.add(timerId2, const Duration(milliseconds: 10), runnableForStep(3));
    queue.add(timerId3, const Duration(milliseconds: 15), runnableForStep(4));
    runnableForStep(2)();

    queue.runUntil(timerId3);
    expect(completedSteps, <int>[1, 2, 3, 4]);
  });

  test('a manual task runs only through runUntil', () async {
    // A list of its own: timers of the tests before may still fire into completedSteps.
    final List<int> steps = <int>[];
    void Function() step(int n) =>
        () => steps.add(n);
    final TaskScheduler manual = TaskScheduler(
      'manual',
      manualTasks: <TaskId>{TaskId.asyncQueueRetry},
    );
    manual.add(TaskId.asyncQueueRetry, Duration.zero, step(1));
    manual.add(TaskId.indexBackfill, Duration.zero, step(2));

    await Future<void>.delayed(const Duration(milliseconds: 20));
    // The other task ran on its own, the manual one waits.
    expect(steps, <int>[2]);
    expect(manual.getTask(TaskId.asyncQueueRetry), isNotNull);

    manual.runUntil(TaskId.asyncQueueRetry);
    expect(steps, <int>[2, 1]);
    expect(manual.getTask(TaskId.asyncQueueRetry), isNull);

    // A canceled manual task does not run.
    manual.add(TaskId.asyncQueueRetry, Duration.zero, step(3)).cancel();
    expect(manual.getTask(TaskId.asyncQueueRetry), isNull);
  });

  test(
    'tasksAreScheduledWithRespectToShutdown',
    skip:
        'The port has no AsyncQueue and no shutdown concept '
        '(enqueueAndInitiateShutdown / enqueueAndForgetEvenAfterShutdown)',
    () {},
  );
}
