// File created by
// Lung Razvan <long1eu>
// on 14/03/2020

import 'dart:async';

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:meta/meta.dart';

typedef TaskFunction = FutureOr<void> Function();

class TaskScheduler {
  TaskScheduler(this._name) : _tasks = <TaskId, TimerTask>{};

  final Map<TaskId, TimerTask> _tasks;
  final String _name;

  int _index = 0;

  TimerTask add(TaskId id, Duration delay, TaskFunction function) {
    _log('Adding task $id after $delay');
    if (_tasks.containsKey(id)) {
      throw ArgumentError('The is already a task with this name');
    }

    final TimerTask task = TimerTask._(
      index: ++_index,
      id: id,
      function: function,
      timer: Timer(delay, () => _tasks[id]._execute()),
      scheduler: this,
    );

    _log('Task add with index $_index');
    return _tasks[id] = task;
  }

  TimerTask getTask(TaskId id) {
    return _tasks[id];
  }

  void runUntil(TaskId id) {
    _log('Run until $id');
    (_tasks.values.toList()..sort())
        .takeWhile((TimerTask value) => value._id == id)
        .toList()
        .forEach((TimerTask element) {
      element._timer.cancel();
      element._execute();
    });
  }

  void clearAll() {
    _log('Clear all tasks');
    _tasks.values.toList().forEach((TimerTask element) => element.cancel());
    _tasks.clear();
  }

  void _remove(TaskId id) {
    _tasks.remove(id);
  }

  void _log(String s) {
    Log.d('$runtimeType${_name == null || _name.isEmpty ? '' : '-$_name'}', s);
  }
}

class TimerTask implements Comparable<TimerTask> {
  TimerTask._({
    @required int index,
    @required TaskId id,
    @required Timer timer,
    @required TaskFunction function,
    @required TaskScheduler scheduler,
  })  : assert(index != null),
        assert(id != null),
        assert(timer != null),
        assert(function != null),
        assert(scheduler != null),
        _index = index,
        _id = id,
        _timer = timer,
        _function = function,
        _scheduler = scheduler;

  final int _index;
  final TaskId _id;
  final Timer _timer;
  final TaskFunction _function;
  final TaskScheduler _scheduler;

  void cancel() {
    _log('Canceling task $_id');
    _scheduler._remove(_id);
    _timer.cancel();
  }

  void _execute() {
    _log('Executing task $_id');
    _scheduler._remove(_id);
    _function();
  }

  void _log(String s) {
    Log.d('$runtimeType', '${_scheduler._name}:$_id - $s');
  }

  @override
  int compareTo(TimerTask other) => _index.compareTo(other._index);

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
  ];

  @override
  String toString() => _values[_i];
}
