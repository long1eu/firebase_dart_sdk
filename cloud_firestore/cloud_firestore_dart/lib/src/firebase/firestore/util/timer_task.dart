// File created by
// Lung Razvan <long1eu>
// on 14/03/2020

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';
import 'package:firebase_app_dart/internal.dart';

typedef TaskFunction = FutureOr<void> Function();

class TaskScheduler {
  /// Tasks whose id is in [manualTasks] never run on their own: only [runUntil] runs them. Tests use it to hold back
  /// a timer that the JS spec runner would still see pending when it checks a step (a timer with no delay that the
  /// event loop would otherwise run while the step settles), e.g. [TaskId.asyncQueueRetry].
  TaskScheduler(this._name, {Set<TaskId> manualTasks = const <TaskId>{}})
    : _tasks = <TaskId, TimerTask>{},
      _manualTasks = manualTasks;

  final Map<TaskId, TimerTask> _tasks;
  final Set<TaskId> _manualTasks;
  final String _name;

  int _index = 0;

  TimerTask add(TaskId id, Duration delay, TaskFunction function) {
    _log('Adding task $id after $delay');
    if (_tasks.containsKey(id)) {
      throw ArgumentError('The is already a task with this name');
    }

    late final TimerTask task;
    task = TimerTask._(
      index: ++_index,
      id: id,
      function: function,
      targetTime: DateTime.now().add(delay),
      timer: _manualTasks.contains(id)
          ? null
          : Timer(delay, () => task._execute()),
      scheduler: this,
    );

    _log('Task add with index $_index');
    return _tasks[id] = task;
  }

  TimerTask? getTask(TaskId id) {
    return _tasks[id];
  }

  /// Runs, without waiting for their delay, all scheduled tasks in order of
  /// their target time, up to and including the task with [id]. With
  /// [TaskId.all] every scheduled task is run. Throws if [id] is not
  /// [TaskId.all] and no such task is scheduled.
  void runUntil(TaskId id) {
    _log('Run until $id');
    hardAssert(
      id == TaskId.all || _tasks.containsKey(id),
      'Attempted to run tasks until missing id: $id',
    );

    final List<TimerTask> pending = _tasks.values.toList()..sort();
    for (final TimerTask task in pending) {
      task._timer?.cancel();
      task._execute();
      if (id != TaskId.all && task._id == id) {
        break;
      }
    }
  }

  void _remove(TimerTask task) {
    // Only remove the entry if it still belongs to this task: a handle that
    // outlived its task must not unschedule a newer task with the same id.
    if (identical(_tasks[task._id], task)) {
      _tasks.remove(task._id);
    }
  }

  void _log(String s) {
    Log.d('$runtimeType${_name.isEmpty ? '' : '-$_name'}', s);
  }
}

class TimerTask implements Comparable<TimerTask> {
  TimerTask._({
    required int index,
    required TaskId id,
    required DateTime targetTime,
    required Timer? timer,
    required TaskFunction function,
    required TaskScheduler scheduler,
  }) : _index = index,
       _id = id,
       _targetTime = targetTime,
       _timer = timer,
       _function = function,
       _scheduler = scheduler;

  final int _index;
  final TaskId _id;
  final DateTime _targetTime;
  final Timer? _timer;
  final TaskFunction _function;
  final TaskScheduler _scheduler;

  /// Set once the task ran or was canceled; a finished task is never run again.
  bool _finished = false;

  void cancel() {
    _log('Canceling task $_id');
    _finished = true;
    _scheduler._remove(this);
    _timer?.cancel();
  }

  void _execute() {
    if (_finished) {
      return;
    }
    _log('Executing task $_id');
    _finished = true;
    _scheduler._remove(this);
    _function();
  }

  void _log(String s) {
    Log.d('$runtimeType', '${_scheduler._name}:$_id - $s');
  }

  @override
  int compareTo(TimerTask other) {
    final int byTime = _targetTime.compareTo(other._targetTime);
    return byTime != 0 ? byTime : _index.compareTo(other._index);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimerTask &&
          runtimeType == other.runtimeType &&
          _id == other._id;

  @override
  int get hashCode => _id.hashCode;

  @override
  String toString() {
    return (ToStringHelper(TimerTask) //
          ..add('index', _index)
          ..add('name', _id))
        .toString();
  }
}

/// Well-known 'timer' IDs used when scheduling delayed tasks on the
/// [TaskScheduler]. These IDs can then be used from tests to check for the
/// presence of tasks or to run them early.
class TaskId implements Comparable<TaskId> {
  const TaskId._(this._i);

  final int _i;

  /// ALL can be used with [TaskScheduler.runUntil] to run all timers.
  static const TaskId all = TaskId._(0);

  static const TaskId listenStreamIdle = TaskId._(1);
  static const TaskId listenStreamConnectionBackoff = TaskId._(2);
  static const TaskId writeStreamIdle = TaskId._(3);
  static const TaskId writeStreamConnectionBackoff = TaskId._(4);

  /// A timer used in [OnlineStateTracker] to transition from
  /// [OnlineState.unknown] to [OnlineState.offline] after a set timeout, rather
  /// than waiting indefinitely for success or failure.
  static const TaskId onlineStateTimeout = TaskId._(5);

  /// A timer used to periodically attempt LRU Garbage collection
  static const TaskId garbageCollection = TaskId._(6);

  /// A timer used to retry transactions with a backoff.
  static const TaskId retryTransaction = TaskId._(7);

  /// A timer used to periodically attempt index backfill.
  static const TaskId indexBackfill = TaskId._(8);

  /// A timer used to refresh the metadata and the primary lease of a client of a persistent cache.
  static const TaskId clientMetadataRefresh = TaskId._(9);

  /// A timer used to retry operations that failed because the persistence was not available (the JS
  /// `TimerId.AsyncQueueRetry`), see [RetryableOperationQueue].
  static const TaskId asyncQueueRetry = TaskId._(10);

  /// Timers that mark a listen (write) stream healthy once it has been open
  /// for 10 seconds (the Android `TimerId.HEALTH_CHECK_TIMEOUT`, one per stream
  /// here because a scheduler runs one task per id).
  static const TaskId listenStreamHealthCheck = TaskId._(11);
  static const TaskId writeStreamHealthCheck = TaskId._(12);

  @override
  int compareTo(TaskId other) => _i.compareTo(other._i);

  bool operator >(TaskId other) => _i > other._i;

  bool operator >=(TaskId other) => _i >= other._i;

  bool operator <(TaskId other) => _i < other._i;

  bool operator <=(TaskId other) => _i <= other._i;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskId && runtimeType == other.runtimeType && _i == other._i;

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
    'retryTransaction',
    'indexBackfill',
    'clientMetadataRefresh',
    'asyncQueueRetry',
    'listenStreamHealthCheck',
    'writeStreamHealthCheck',
  ];

  @override
  String toString() => _values[_i];
}
