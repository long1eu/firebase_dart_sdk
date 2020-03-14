// File created by
// Lung Razvan <long1eu>
// on 18/09/2018

import 'dart:async';
import 'dart:collection';

import 'package:cloud_firestore_vm/src/firebase/firestore/core/online_state.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/version.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/online_state_tracker.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';
import 'package:meta/meta.dart';

/// Well-known 'timer' IDs used when scheduling delayed tasks on the AsyncQueue. These IDs can then
/// be used from tests to check for the presence of tasks or to run them early.
class TimerId implements Comparable<TimerId> {
  const TimerId._(this._i);

  final int _i;

  /// ALL can be used with runDelayedTasksUntil() to run all timers.
  static const TimerId all = TimerId._(0);

  /// The following 4 timers are used with the listen and write streams. The IDLE timer is used to
  /// close the stream due to inactivity. The CONNECTION_BACKOFF timer is used to restart a stream
  /// once the appropriate backoff delay has elapsed.
  static const TimerId listenStreamIdle = TimerId._(1);
  static const TimerId listenStreamConnectionBackoff = TimerId._(2);
  static const TimerId writeStreamIdle = TimerId._(3);
  static const TimerId writeStreamConnectionBackoff = TimerId._(4);

  /// A timer used in [OnlineStateTracker] to transition from [OnlineState.unknown] to
  /// [OnlineState.offline] after a set timeout, rather than waiting indefinitely for success or
  /// failure.
  static const TimerId onlineStateTimeout = TimerId._(5);

  /// A timer used to periodically attempt LRU Garbage collection
  static const TimerId garbageCollection = TimerId._(6);

  @override
  int compareTo(TimerId other) => _i.compareTo(other._i);

  bool operator >(TimerId other) => _i > other._i;

  bool operator >=(TimerId other) => _i >= other._i;

  bool operator <(TimerId other) => _i < other._i;

  bool operator <=(TimerId other) => _i <= other._i;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimerId && runtimeType == other.runtimeType && _i == other._i;

  @override
  int get hashCode => _i.hashCode;

  static const List<String> _values = <String>[
    'all',
    'listenStreamIdle',
    'listenStreamConnectionBackoff',
    'writeStreamIdle',
    'writeStreamConnectionBackoff',
    'onlineStateTimeout',
    'garbageCollection',
  ];

  @override
  String toString() => _values[_i];
}

typedef Task<TResult> = Future<TResult> Function();

class _TaskQueueEntry<T> {
  _TaskQueueEntry(this.function) : completer = Completer<T>();

  Task<T> function;
  Completer<T> completer;
}

/// A helper class that allows to schedule/queue [Function]s on a single queue.
class AsyncQueue {
  factory AsyncQueue() => _instance;

  AsyncQueue._();

  static final AsyncQueue _instance = AsyncQueue._();

  // Tasks scheduled to be queued in the future. Tasks are automatically removed after they are run
  // or canceled.
  //
  // NOTE: We disallow duplicates currently, so this could be a Set which might have better
  // theoretical removal speed, except this list will always be small so List is fine.
  final List<DelayedTask<dynamic>> _delayedTasks = <DelayedTask<dynamic>>[];

  final Queue<_TaskQueueEntry<void>> _tasks = Queue<_TaskQueueEntry<void>>();

  Completer<void> _recentActiveCompleter;

  /// Immediately stops running any scheduled tasks and causes a 'panic' (through crashing the app).
  ///
  /// Should only be used for unrecoverable exceptions.
  static void panic(dynamic t) {
    if (t is OutOfMemoryError) {
      // OOMs can happen if developers try to load too much data at once.
      // Instead of treating this as an internal error, give a hint that this
      // might be due to excessive queries in Firestore.
      throw t;
    } else {
      throw StateError(
          'Internal error in Firestore (${Version.sdkVersion}). $t');
    }
  }

  /// Schedules a task and returns a [Future] which will complete when the task has been finished.
  ///
  /// The task will be append to the queue and run after every task added before has been executed.
  Future<T> enqueue<T>(Task<T> function, [String caller]) async {
    //print('----QUEUE => strt $caller');
    final _TaskQueueEntry<T> taskEntry = _TaskQueueEntry<T>(function);

    final bool listWasEmpty = _tasks.isEmpty;
    _tasks.add(taskEntry);

    // Only run the just added task in case the queue hasn't been used yet or the last task has been
    // executed
    if (_recentActiveCompleter == null ||
        _recentActiveCompleter.isCompleted && listWasEmpty) {
      _runNext();
    }

    return taskEntry.completer.future;
    //print('----QUEUE => done $caller');
  }

  /// Queue and run this Runnable task immediately after every other already queued task. Unlike [enqueue], returns void
  /// instead of a Future for use when we have no need to 'wait' on the task completing.
  void enqueueAndForget<T>(Task<T> task, [String caller = '']) =>
      enqueue<T>(task, '$caller-enqueueAndForget');

  /// Schedule a task after the specified delay.
  ///
  /// The returned [DelayedTask] can be used to cancel the task prior to its running.
  DelayedTask<T> enqueueAfterDelay<T>(
      TimerId timerId, Duration delay, Task<T> task,
      [String caller]) {
    // todo since this is a singleton decide if we should keep it this way and removed the assert below or remove the
    //  singleton implementation and uncomment this. Having this as a singleton is not necessary a very good idea in
    //  case of multiple Firestore instances.

    // While not necessarily harmful, we currently don't expect to have multiple tasks with the
    // same timer id in the queue, so defensively reject them.
    // hardAssert(!containsDelayedTask(timerId), 'Attempted to schedule multiple operations with timer id $timerId.');

    final DelayedTask<T> delayedTask =
        _createAndScheduleDelayedTask(timerId, delay, task, caller);
    _delayedTasks.add(delayedTask);

    return delayedTask;
  }

  /// Determines if a delayed task with a particular timerId exists. */
  @visibleForTesting
  bool containsDelayedTask(TimerId timerId) {
    for (DelayedTask<dynamic> delayedTask in _delayedTasks) {
      if (delayedTask.timerId == timerId) {
        return true;
      }
    }
    return false;
  }

  /// Runs some or all delayed tasks early, blocking until completion. [lastTimerId] Only delayed tasks up to and
  /// including one that was scheduled using this [TimerId] will be run. Method throws if no matching task exists.
  /// Pass [TimerId.all] to run all delayed tasks.
  @visibleForTesting
  Future<void> runDelayedTasksUntil(TimerId lastTimerId) async {
    hardAssert(lastTimerId == TimerId.all || containsDelayedTask(lastTimerId),
        'Attempted to run tasks until missing TimerId: $lastTimerId');

    // NOTE: For performance we could store the tasks sorted, but [runDelayedTasksUntil] is only called from tests, and
    // the size is guaranteed to be small since we don't allow duplicate TimerIds.
    _delayedTasks.sort();

    // We copy the list before enumerating to avoid concurrent modification as we remove tasks
    final List<DelayedTask<dynamic>> result = <DelayedTask<dynamic>>[];

    for (DelayedTask<dynamic> task in _delayedTasks.toList()) {
      task.cancel();
      result.add(task);
      if (lastTimerId != TimerId.all && task.timerId == lastTimerId) {
        break;
      }
    }

    await Future.wait<dynamic>(result.map(
        (DelayedTask<dynamic> it) => enqueue<dynamic>(it.task, it.caller)));
  }

  /// Runs the next available [Task] in the queue.
  void _runNext() {
    if (_tasks.isNotEmpty) {
      final _TaskQueueEntry<dynamic> taskEntry = _tasks.first;
      _recentActiveCompleter = taskEntry.completer;

      taskEntry.function().then((dynamic value) {
        Future<void>(() {
          _tasks.removeFirst();
          _runNext();
        });
        taskEntry.completer.complete(value);
      }).catchError((dynamic error, StackTrace s) {
        Future<void>(() {
          _tasks.removeFirst();
          _runNext();
        });

        taskEntry.completer.completeError(error, s);
        //panic(error);
      });
    }
  }

  /// Creates and returns a DelayedTask that has been scheduled to be executed on the provided queue after the provided
  /// delay.
  DelayedTask<T> _createAndScheduleDelayedTask<T>(
      TimerId timerId, Duration delay, Task<T> task, String caller) {
    return DelayedTask<T>._(
      caller,
      timerId,
      DateTime.now().add(delay),
      task,
      this,
      _removeDelayedTask,
    );
  }

  /// Called by DelayedTask to remove itself from our list of pending delayed tasks.
  void _removeDelayedTask(DelayedTask<dynamic> task) {
    final bool found = _delayedTasks.remove(task);
    hardAssert(found, 'Delayed task not found.');
  }
}

/// Represents a Task scheduled to be run in the future on an AsyncQueue. Supports cancellation.
class DelayedTask<T> implements Comparable<DelayedTask<T>> {
  DelayedTask._(
    this.caller,
    this.timerId,
    this.targetTimeMs,
    this.task,
    this.queue,
    this.removeDelayedTask,
  )   : assert(timerId != null),
        assert(targetTimeMs != null),
        assert(task != null),
        assert(removeDelayedTask != null) {
    scheduledFuture =
        Timer(targetTimeMs.difference(DateTime.now()), _handleDelayElapsed);
  }

  final String caller;
  final TimerId timerId;
  final DateTime targetTimeMs;
  final Task<T> task;
  final AsyncQueue queue;
  final void Function(DelayedTask<T> task) removeDelayedTask;

  // It is set to null after the task has been run or canceled.
  Timer scheduledFuture;

  /// Cancels the task if it hasn't already been executed or canceled.
  ///
  /// As long as the task has not yet been run, calling [cancel()] (from a task already running on
  /// the AsyncQueue) provides a guarantee that the task will not be run.
  void cancel() {
    if (scheduledFuture != null) {
      _markDone();
    }
  }

  Future<void> _handleDelayElapsed() async {
    if (scheduledFuture != null) {
      _markDone();
      await queue.enqueue(task, '$caller-delayed').catchError(print);
    }

    return;
  }

  /// Marks this delayed task as done, notifying the AsyncQueue that it should be removed.
  void _markDone() {
    hardAssert(scheduledFuture != null,
        'Caller should have verified scheduledFuture is non-null.');
    scheduledFuture.cancel();
    scheduledFuture = null;
    removeDelayedTask(this);
  }

  @override
  int compareTo(DelayedTask<T> other) {
    return targetTimeMs.compareTo(other.targetTimeMs);
  }
}
