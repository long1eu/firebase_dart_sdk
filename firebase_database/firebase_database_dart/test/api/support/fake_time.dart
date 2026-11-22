// A small fake clock for the API tests, in the manner of package:fake_async (which this package does not
// depend on): code run inside [fakeTime] gets its timers and microtasks from the fake, and [FakeTime.elapse]
// moves time forward, running what falls due. Switching to package:fake_async is a dev_dependencies line.

import 'dart:async';
import 'dart:collection';

/// Runs [body] in a zone whose timers and microtasks are driven by a [FakeTime].
T fakeTime<T>(T Function(FakeTime time) body) {
  final FakeTime time = FakeTime._();
  return runZoned(
    () => body(time),
    zoneSpecification: ZoneSpecification(
      scheduleMicrotask:
          (Zone self, ZoneDelegate parent, Zone zone, void Function() f) =>
              time._microtasks.add(f),
      createTimer:
          (
            Zone self,
            ZoneDelegate parent,
            Zone zone,
            Duration d,
            void Function() f,
          ) => time._addTimer(d, (Timer _) => f(), periodic: false),
      createPeriodicTimer:
          (
            Zone self,
            ZoneDelegate parent,
            Zone zone,
            Duration d,
            void Function(Timer) f,
          ) => time._addTimer(d, f, periodic: true),
    ),
  );
}

/// The fake clock of [fakeTime].
final class FakeTime {
  FakeTime._();

  final Queue<void Function()> _microtasks = Queue<void Function()>();
  final List<_FakeTimer> _timers = <_FakeTimer>[];
  Duration _now = Duration.zero;
  int _nextId = 0;

  /// The time elapsed since [fakeTime] started.
  Duration get elapsed => _now;

  Timer _addTimer(
    Duration duration,
    void Function(Timer) callback, {
    required bool periodic,
  }) {
    final Duration d = duration.isNegative ? Duration.zero : duration;
    final _FakeTimer timer = _FakeTimer(
      this,
      d,
      callback,
      periodic,
      _now + d,
      _nextId++,
    );
    _timers.add(timer);
    return timer;
  }

  /// Runs every pending microtask, including the ones they schedule.
  void flushMicrotasks() {
    while (_microtasks.isNotEmpty) {
      _microtasks.removeFirst()();
    }
  }

  /// Moves time forward by [duration], running microtasks, then each timer that falls due in order
  /// (followed by the microtasks it scheduled).
  void elapse(Duration duration) {
    final Duration target = _now + duration;
    flushMicrotasks();
    while (true) {
      _FakeTimer? next;
      for (final _FakeTimer timer in _timers) {
        if (timer.due <= target &&
            (next == null ||
                timer.due < next.due ||
                (timer.due == next.due && timer.id < next.id))) {
          next = timer;
        }
      }
      if (next == null) {
        break;
      }
      _now = next.due;
      if (next.periodic) {
        next
          ..due = _now + next.duration
          ..id = _nextId++;
        next.ticks++;
      } else {
        _timers.remove(next);
      }
      next.callback(next);
      flushMicrotasks();
    }
    _now = target;
  }
}

final class _FakeTimer implements Timer {
  _FakeTimer(
    this._time,
    this.duration,
    this.callback,
    this.periodic,
    this.due,
    this.id,
  );

  final FakeTime _time;
  final Duration duration;
  final void Function(Timer) callback;
  final bool periodic;
  Duration due;
  int id;
  int ticks = 0;

  @override
  void cancel() => _time._timers.remove(this);

  @override
  bool get isActive => _time._timers.contains(this);

  @override
  int get tick => ticks;
}
