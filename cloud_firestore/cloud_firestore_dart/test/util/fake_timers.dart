// Timers and a clock that a test drives by hand.

import 'dart:async';

import 'package:test/test.dart';

/// Timers that only fire when the test says so, and a clock that only moves
/// when the test moves it.
class FakeTimers {
  DateTime now = DateTime.utc(2026, 1, 1);
  final List<FakeTimer> timers = <FakeTimer>[];

  Timer create(Duration delay, void Function() callback) {
    final FakeTimer timer = FakeTimer(now.add(delay), callback);
    timers.add(timer);
    return timer;
  }

  int get active => timers.where((FakeTimer t) => t.isActive).length;

  /// Moves the clock by [duration] and fires the timer that is due, once (as a
  /// machine does that slept through several periods of a timer).
  Future<void> elapse(Duration duration) async {
    now = now.add(duration);
    final List<FakeTimer> due = timers
        .where((FakeTimer t) => t.isActive && !t.fireAt.isAfter(now))
        .toList();
    for (final FakeTimer timer in due) {
      timer.fire();
    }
    // Lets the poll read the interfaces.
    await pumpEventQueue();
  }
}

class FakeTimer implements Timer {
  FakeTimer(this.fireAt, this._callback);

  final DateTime fireAt;
  final void Function() _callback;
  bool _active = true;

  void fire() {
    _active = false;
    _callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}
