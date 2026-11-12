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

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/util/exponential_backoff.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:test/test.dart';

/// Unit tests for [ExponentialBackoff] using real (short) timers. Jitter makes
/// every delay lie in [0.5 * base, 1.5 * base], so the assertions only use
/// those bounds, with generous margins on the upper side.
void main() {
  const TaskId taskId = TaskId.listenStreamConnectionBackoff;
  late TaskScheduler scheduler;

  setUp(() => scheduler = TaskScheduler('backoff-test'));

  tearDown(() => scheduler.getTask(taskId)?.cancel());

  ExponentialBackoff newBackoff({
    int initialMs = 100,
    double factor = 2,
    int maxMs = 400,
  }) =>
      ExponentialBackoff(
        scheduler,
        taskId,
        initialDelay: Duration(milliseconds: initialMs),
        backoffFactor: factor,
        maxDelay: Duration(milliseconds: maxMs),
      );

  /// Runs one backoff and returns the time it took until the task ran.
  Future<Duration> runOnce(ExponentialBackoff backoff) {
    final Completer<Duration> completer = Completer<Duration>();
    final Stopwatch stopwatch = Stopwatch()..start();
    backoff.backoffAndRun(() => completer.complete(stopwatch.elapsed));
    return completer.future;
  }

  test('the first attempt runs without delay', () async {
    final Duration elapsed = await runOnce(newBackoff());
    expect(elapsed, lessThan(const Duration(milliseconds: 50)));
  });

  test('the second attempt waits at least half of the initial delay', () async {
    final ExponentialBackoff backoff = newBackoff();
    await runOnce(backoff);
    final Duration elapsed = await runOnce(backoff);
    expect(elapsed, greaterThanOrEqualTo(const Duration(milliseconds: 45)));
    expect(elapsed, lessThan(const Duration(milliseconds: 400)));
  });

  test('the delay grows with the backoff factor', () async {
    final ExponentialBackoff backoff = newBackoff(initialMs: 40, maxMs: 2000);
    await runOnce(backoff); // base 0
    await runOnce(backoff); // base 40 -> [20, 60]
    final Duration third = await runOnce(backoff); // base 80 -> [40, 120]
    expect(third, greaterThanOrEqualTo(const Duration(milliseconds: 35)));
    final Duration fourth = await runOnce(backoff); // base 160 -> [80, 240]
    expect(fourth, greaterThanOrEqualTo(const Duration(milliseconds: 75)));
  });

  test('reset makes the next attempt immediate again', () async {
    final ExponentialBackoff backoff = newBackoff();
    await runOnce(backoff);
    await runOnce(backoff);
    backoff.reset();
    final Duration elapsed = await runOnce(backoff);
    expect(elapsed, lessThan(const Duration(milliseconds: 50)));
  });

  test('resetToMax makes the next attempt wait the maximum delay', () async {
    final ExponentialBackoff backoff = newBackoff(initialMs: 10, maxMs: 200);
    await runOnce(backoff);
    backoff.resetToMax();
    final Duration elapsed = await runOnce(backoff);
    expect(elapsed, greaterThanOrEqualTo(const Duration(milliseconds: 95)));
  });

  test('cancel prevents a pending task from running', () async {
    final ExponentialBackoff backoff = newBackoff(initialMs: 50);
    await runOnce(backoff);
    bool ran = false;
    backoff.backoffAndRun(() => ran = true);
    expect(scheduler.getTask(taskId), isNotNull);
    backoff.cancel();
    expect(scheduler.getTask(taskId), isNull);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(ran, isFalse);
  });

  test('a new backoffAndRun replaces a pending task', () async {
    final ExponentialBackoff backoff = newBackoff(initialMs: 50);
    await runOnce(backoff);
    final List<String> runs = <String>[];
    backoff
      ..backoffAndRun(() => runs.add('first'))
      ..backoffAndRun(() => runs.add('second'));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(runs, <String>['second']);
  });

  test('cancel without a pending task is a no-op', () {
    newBackoff()
      ..cancel()
      ..cancel();
    expect(scheduler.getTask(taskId), isNull);
  });
}
