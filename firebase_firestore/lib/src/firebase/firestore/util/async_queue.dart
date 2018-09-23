// File created by
// Lung Razvan <long1eu>
// on 18/09/2018

import 'dart:async';

import 'package:firebase_firestore/src/firebase/firestore/core/version.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';
import 'package:isolate/isolate.dart';
import 'package:meta/meta.dart';

/// Well-known "timer" IDs used when scheduling delayed tasks on the AsyncQueue.
/// These IDs can then be used from tests to check for the presence of tasks or
/// to run them early.
enum TimerId {
  /// ALL can be used with runDelayedTasksUntil() to run all timers.
  ALL,

  /// The following 4 timers are used with the listen and write streams. The
  /// IDLE timer is used to close the stream due to inactivity. The
  /// CONNECTION_BACKOFF timer is used to restart a stream once the appropriate
  /// backoff delay has elapsed.
  LISTEN_STREAM_IDLE,
  LISTEN_STREAM_CONNECTION_BACKOFF,
  WRITE_STREAM_IDLE,
  WRITE_STREAM_CONNECTION_BACKOFF,

  /// A timer used in [OnlineStateTracker] to transition from
  /// [OnlineState.unknown] to [OnlineState.offline] after a set timeout, rather
  /// than waiting indefinitely for success or failure.
  ONLINE_STATE_TIMEOUT,
}

typedef Future<TResult> Task<TResult>();

/// A helper class that allows to schedule/queue [Function]s on a single
/// threaded background queue. */
class AsyncQueue {
  /**
   * The single thread that will be used by the executor. This is created early and managed directly
   * so that it's possible later to make assertions about executing on the correct thread.
   */
  static IsolateRunner _thread;

  /// Executes the given Callable on a specific executor and returns a Task that completes when the
  /// Task returned from the Callable completes. Similar to Tasks.call, but takes a function that
  /// returns a Task.
  ///
  /// @param executor The executor to run the task on.
  /// @param task The Callable to execute.
  /// @return A Task that will be completed when task's Task is complete.
  static Future<TResult> callTask<TResult>(
      IsolateRunner executor, Task<TResult> task) {
    Completer<TResult> tcs = Completer();

    executor.run((_) {
      try {
        task()
            .then((TResult r) => tcs.complete(r))
            .catchError((e, s) => tcs.completeError(e, s));
      } on Error catch (e) {
        tcs.completeError(e);
      } catch (t) {
        StateError e = StateError("Unhandled throwable in callTask. $t");
        tcs.completeError(e);
      }
    }, '');
    return tcs.future;
  }

  // Tasks scheduled to be queued in the future. Tasks are automatically removed after they are run
  // or canceled.
  // NOTE: We disallow duplicates currently, so this could be a Set<> which might have better
  // theoretical removal speed, except this list will always be small so ArrayList is fine.
  final List<DelayedTask> delayedTasks;

  static Future<AsyncQueue> createQueue() async {
    final List<DelayedTask> delayedTasks = List<DelayedTask>();
    _thread ??= await () async {
      final IsolateRunner runner = await IsolateRunner.spawn();
      runner.errors.listen((dynamic e) => panic(e));
      return runner;
    }();

    return AsyncQueue._(delayedTasks);
  }

  const AsyncQueue._(this.delayedTasks);

  /// Queue and run this Callable task immediately after every other already
  /// queued task.
  Future<T> enqueue<T>(Task<T> task) {
    return _thread.run(_enqueue, '');
  }

  static Future<T> _enqueue<T>(task) async {
    final Completer<T> completionSource = Completer<T>();
    try {
      final T result = await task();
      completionSource.complete(result);
    } catch (e) {
      completionSource.completeError(e);
      throw AssertionError(e);
    }
    return completionSource.future;
  }

  /// Queue and run this Runnable task immediately after every other already
  /// queued task. Unlike [enqueue], returns void instead of a [Task] Object for
  /// use when we have no need to "wait" on the task completing.
  void enqueueAndForget(Task task) => enqueue(task);

  /// Schedule a task after the specified delay.
  ///
  /// * The returned [DelayedTask] can be used to cancel the task prior to its
  /// running.
  DelayedTask enqueueAfterDelay<T>(
      TimerId timerId, Duration delay, Task<T> task) {
    // While not necessarily harmful, we currently don't expect to have multiple tasks with the same
    // timer id in the queue, so defensively reject them.
    Assert.hardAssert(!containsDelayedTask(timerId),
        "Attempted to schedule multiple operations with timer id $timerId.");

    DelayedTask delayedTask =
        createAndScheduleDelayedTask(timerId, delay, task);
    delayedTasks.add(delayedTask);

    return delayedTask;
  }

  /**
   * Immediately stops running any scheduled tasks and causes a "panic" (through crashing the app).
   *
   * <p>Should only be used for unrecoverable exceptions.
   *
   * @param t The Throwable that is caused the panic.
   */
  static void panic(dynamic t) {
    _thread.kill();

    if (t is OutOfMemoryError) {
      // OOMs can happen if developers try to load too much data at once. Instead of treating
      // this as an internal error, give a hint that this might be due to excessive queries
      // in Firestore.
      throw OutOfMemoryError();
    } else {
      throw StateError(
          'Internal error in Firestore (${Version.sdkVersion}). $t');
    }
  }

  /** Determines if a delayed task with a particular timerId exists. */
  @visibleForTesting
  bool containsDelayedTask(TimerId timerId) {
    for (DelayedTask delayedTask in delayedTasks) {
      if (delayedTask.timerId == timerId) {
        return true;
      }
    }
    return false;
  }

  /// Runs some or all delayed tasks early, blocking until completion.
  /// [lastTimerId] Only delayed tasks up to and including one that was
  /// scheduled using this TimerId will be run. Method throws if no matching
  /// task exists. Pass TimerId.ALL to run all delayed tasks.
  @visibleForTesting
  void runDelayedTasksUntil(TimerId lastTimerId) {
    Assert.hardAssert(
        lastTimerId == TimerId.ALL || containsDelayedTask(lastTimerId),
        'Attempted to run tasks until missing TimerId: $lastTimerId');

    // NOTE: For performance we could store the tasks sorted, but
    // [runDelayedTasksUntil] is only called from tests, and the size is
    // guaranteed to be small since we don't allow duplicate TimerIds.
    delayedTasks.sort((a, b) => a.targetTimeMs.compareTo(b.targetTimeMs));

    // We copy the list before enumerating to avoid concurrent modification as
    // we remove tasks.
    for (DelayedTask delayedTask in delayedTasks.toList()) {
      delayedTask.skipDelay();
      if (lastTimerId != TimerId.ALL && delayedTask.timerId == lastTimerId) {
        break;
      }
    }
  }

  /// Shuts down the AsyncQueue and releases resources after which no progress
  /// will ever be made again.
  void shutdown() {
    _thread.kill();
    _thread = null;
  }

  /// Creates and returns a DelayedTask that has been scheduled to be executed
  /// on the provided queue after the provided delay.
  DelayedTask<T> createAndScheduleDelayedTask<T>(
      TimerId timerId, Duration delay, Task<T> task) {
    return DelayedTask._<T>(
        timerId, DateTime.now().add(delay), task, _removeDelayedTask)
      ..start(delay);
  }

  /// Called by DelayedTask to remove itself from our list of pending delayed
  /// tasks.
  void _removeDelayedTask(DelayedTask task) {
    bool found = delayedTasks.remove(task);
    Assert.hardAssert(found, "Delayed task not found.");
  }
}

/// Represents a Task scheduled to be run in the future on an AsyncQueue.
/// * Supports cancellation (via [cancel()]) and early execution (via
/// [skipDelay()]).
class DelayedTask<T> implements Comparable<DelayedTask> {
  final TimerId timerId;
  final DateTime targetTimeMs;
  final Task<T> task;
  final void Function(DelayedTask task) removeDelayedTask;

  // It is set to null after the task has been run or canceled.
  Timer scheduledFuture;

  DelayedTask._(
    this.timerId,
    this.targetTimeMs,
    this.task,
    this.removeDelayedTask,
  )   : assert(timerId != null),
        assert(targetTimeMs != null),
        assert(task != null),
        assert(removeDelayedTask != null);

  /// Schedules the DelayedTask. This is called immediately after construction.
  void start(Duration delay) {
    scheduledFuture = Timer(delay, handleDelayElapsed);
  }

  /// Runs the operation immediately (if it hasn't already been run or
  /// canceled).
  void skipDelay() => handleDelayElapsed();

  /// Cancels the task if it hasn't already been executed or canceled.
  ///
  /// * As long as the task has not yet been run, calling [cancel()] (from a
  /// task already running on the AsyncQueue) provides a guarantee that the task
  /// will not be run.
  void cancel() {
    if (scheduledFuture != null) {
      scheduledFuture.cancel();
      markDone();
    }
  }

  void handleDelayElapsed() {
    if (scheduledFuture != null) {
      markDone();
      task();
    }
  }

  /// Marks this delayed task as done, notifying the AsyncQueue that it should
  /// be removed.
  void markDone() {
    Assert.hardAssert(scheduledFuture != null,
        "Caller should have verified scheduledFuture is non-null.");
    scheduledFuture = null;
    removeDelayedTask(this);
  }

  @override
  int compareTo(DelayedTask other) {
    return targetTimeMs.compareTo(other.targetTimeMs);
  }
}
