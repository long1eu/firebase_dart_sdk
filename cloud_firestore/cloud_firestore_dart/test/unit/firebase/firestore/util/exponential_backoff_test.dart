// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'package:cloud_firestore_dart/src/firebase/firestore/util/exponential_backoff.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

/// Unit tests for [ExponentialBackoff] in virtual time (package:fake_async):
/// the timers of the scheduler and the clock of the backoff only move when
/// the test moves them, so the delays are measured exactly, whatever the load
/// of the machine. Jitter makes every delay lie in [0.5 * base, 1.5 * base],
/// so the assertions only use those bounds.
/// Makes a backoff on the scheduler of the test.
typedef NewBackoff =
    ExponentialBackoff Function({int initialMs, double factor, int maxMs});

void main() {
  const TaskId taskId = TaskId.listenStreamConnectionBackoff;

  /// Runs [body] in virtual time with a fresh scheduler.
  void inVirtualTime(
    void Function(
      FakeAsync async,
      TaskScheduler scheduler,
      NewBackoff newBackoff,
    )
    body,
  ) {
    fakeAsync((FakeAsync async) {
      final DateTime start = DateTime.utc(2026);
      final TaskScheduler scheduler = TaskScheduler('backoff-test');
      ExponentialBackoff newBackoff({
        int initialMs = 100,
        double factor = 2,
        int maxMs = 400,
      }) => ExponentialBackoff(
        scheduler,
        taskId,
        initialDelay: Duration(milliseconds: initialMs),
        backoffFactor: factor,
        maxDelay: Duration(milliseconds: maxMs),
        now: () => start.add(async.elapsed),
      );
      body(async, scheduler, newBackoff);
      scheduler.getTask(taskId)?.cancel();
    });
  }

  /// Runs one backoff and returns the virtual time until the task ran. Moves
  /// the clock only up to that moment: the backoff counts the time since the
  /// last attempt.
  Duration runOnce(FakeAsync async, ExponentialBackoff backoff) {
    final Duration start = async.elapsed;
    Duration? ranAt;
    backoff.backoffAndRun(() => ranAt = async.elapsed);
    expect(ranAt, isNull, reason: 'the task never runs synchronously');
    async.flushTimers();
    expect(ranAt, isNotNull);
    return ranAt! - start;
  }

  test('the first attempt runs without delay', () {
    inVirtualTime((FakeAsync async, TaskScheduler _, NewBackoff newBackoff) {
      expect(runOnce(async, newBackoff()), Duration.zero);
    });
  });

  test('the second attempt waits at least half of the initial delay', () {
    inVirtualTime((FakeAsync async, TaskScheduler _, NewBackoff newBackoff) {
      final ExponentialBackoff backoff = newBackoff();
      runOnce(async, backoff);
      final Duration elapsed = runOnce(async, backoff);
      expect(elapsed, greaterThanOrEqualTo(const Duration(milliseconds: 45)));
      expect(elapsed, lessThan(const Duration(milliseconds: 400)));
    });
  });

  test('the delay grows with the backoff factor', () {
    inVirtualTime((FakeAsync async, TaskScheduler _, NewBackoff newBackoff) {
      final ExponentialBackoff backoff = newBackoff(initialMs: 40, maxMs: 2000);
      runOnce(async, backoff); // base 0
      runOnce(async, backoff); // base 40 -> [20, 60]
      final Duration third = runOnce(async, backoff); // base 80 -> [40, 120]
      expect(third, greaterThanOrEqualTo(const Duration(milliseconds: 35)));
      final Duration fourth = runOnce(async, backoff); // base 160 -> [80, 240]
      expect(fourth, greaterThanOrEqualTo(const Duration(milliseconds: 75)));
    });
  });

  test('the time since the last attempt counts towards the delay', () {
    inVirtualTime((FakeAsync async, TaskScheduler _, NewBackoff newBackoff) {
      final ExponentialBackoff backoff = newBackoff();
      runOnce(async, backoff);
      // Longer than the largest delay of the next attempt (150 ms).
      async.elapse(const Duration(milliseconds: 200));
      expect(runOnce(async, backoff), Duration.zero);
    });
  });

  test('reset makes the next attempt immediate again', () {
    inVirtualTime((FakeAsync async, TaskScheduler _, NewBackoff newBackoff) {
      final ExponentialBackoff backoff = newBackoff();
      runOnce(async, backoff);
      runOnce(async, backoff);
      backoff.reset();
      expect(runOnce(async, backoff), Duration.zero);
    });
  });

  test('resetToMax makes the next attempt wait the maximum delay', () {
    inVirtualTime((FakeAsync async, TaskScheduler _, NewBackoff newBackoff) {
      final ExponentialBackoff backoff = newBackoff(initialMs: 10, maxMs: 200);
      runOnce(async, backoff);
      backoff.resetToMax();
      final Duration elapsed = runOnce(async, backoff);
      expect(elapsed, greaterThanOrEqualTo(const Duration(milliseconds: 95)));
    });
  });

  test('cancel prevents a pending task from running', () {
    inVirtualTime((
      FakeAsync async,
      TaskScheduler scheduler,
      NewBackoff newBackoff,
    ) {
      final ExponentialBackoff backoff = newBackoff(initialMs: 50);
      runOnce(async, backoff);
      bool ran = false;
      backoff.backoffAndRun(() => ran = true);
      expect(scheduler.getTask(taskId), isNotNull);
      backoff.cancel();
      expect(scheduler.getTask(taskId), isNull);
      async.elapse(const Duration(milliseconds: 200));
      expect(ran, isFalse);
    });
  });

  test('a new backoffAndRun replaces a pending task', () {
    inVirtualTime((FakeAsync async, TaskScheduler _, NewBackoff newBackoff) {
      final ExponentialBackoff backoff = newBackoff(initialMs: 50);
      runOnce(async, backoff);
      final List<String> runs = <String>[];
      backoff
        ..backoffAndRun(() => runs.add('first'))
        ..backoffAndRun(() => runs.add('second'));
      async.elapse(const Duration(milliseconds: 400));
      expect(runs, <String>['second']);
    });
  });

  test('cancel without a pending task is a no-op', () {
    inVirtualTime((
      FakeAsync async,
      TaskScheduler scheduler,
      NewBackoff newBackoff,
    ) {
      newBackoff()
        ..cancel()
        ..cancel();
      expect(scheduler.getTask(taskId), isNull);
    });
  });
}
