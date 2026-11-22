/// Delivers the events of one database in order. JS: `core/view/EventQueue.ts` (replaced: no
/// raise by path); Android: `core/view/EventRaiser.java` (dispatch onto the run loop).
///
/// Decided design (`rtdb/research/13_engine_rules.md`, event delivery rules 2 to 6): one FIFO per
/// database, every Repo entry point appends the events its operation produced, one microtask
/// drains it, never re-entrantly.
library;

import 'dart:async';
import 'dart:collection';

import 'package:firebase_database_dart/src/core/event_registration.dart';
import 'package:firebase_database_dart/src/core/view/event.dart';
import 'package:firebase_database_dart/src/core/view/macrotask_web.dart'
    if (dart.library.io) 'package:firebase_database_dart/src/core/view/macrotask_io.dart';

/// The number of events after which a drain yields to the event loop (a macrotask) at the next
/// change boundary, so a listener that writes on every event cannot starve I/O.
const int eventsPerDrainSlice = 1000;

/// The event FIFO of one database (one per Repo).
///
/// - [enqueue] appends the events of one change (one sync tree operation) at the tail and, when
///   no drain is pending, schedules one with the injected `schedule` (a microtask by default).
/// - The drain fires events in FIFO order, synchronously, from the top of the drain; it is never
///   re-entered: events a listener's own write produces are appended to the tail.
/// - An event whose [EventRegistration] is zombied (cancelled) is skipped, including events
///   already in the current drain.
/// - A listener that throws does not stop the drain; the error is reported to the zone.
/// - After `yieldEvery` events the drain yields to the event loop with the injected `macrotask`
///   (a `MessageChannel` post in a browser, which a hidden tab does not delay; `Timer.run`
///   elsewhere), but only between changes: the events of one change are always delivered
///   together.
final class EventDispatcher {
  /// Creates a dispatcher that schedules its drain with [schedule] and, after [yieldEvery]
  /// events, goes on in a later task scheduled with [macrotask]. Replaces JS `EventQueue` and
  /// Android `EventRaiser`.
  factory EventDispatcher({
    void Function(void Function()) schedule = scheduleMicrotask,
    int yieldEvery = eventsPerDrainSlice,
    void Function(void Function()) macrotask = scheduleMacrotask,
  }) => EventDispatcher._(schedule, yieldEvery, macrotask);

  EventDispatcher._(this._schedule, this._yieldEvery, this._macrotask);

  final void Function(void Function()) _schedule;
  final int _yieldEvery;
  final void Function(void Function()) _macrotask;

  /// The changes not delivered yet, oldest first; each change is delivered whole.
  final Queue<List<Event>> _changes = Queue<List<Event>>();

  /// Whether a drain (the first microtask or a yield's macrotask) is scheduled.
  bool _scheduled = false;

  /// Whether a drain is running (events a listener causes are appended, never fired nested).
  bool _draining = false;

  /// Appends the events of one change and schedules a drain if none is pending. Android
  /// `EventRaiser.raiseEvents`; JS `eventQueueQueueEvents`.
  void enqueue(List<Event> events) {
    if (events.isEmpty) {
      return;
    }
    _changes.add(List<Event>.of(events));
    if (!_scheduled && !_draining) {
      _scheduled = true;
      _schedule(_drain);
    }
  }

  void _drain() {
    _scheduled = false;
    if (_draining) {
      return;
    }
    _draining = true;
    int delivered = 0;
    try {
      while (_changes.isNotEmpty) {
        if (delivered >= _yieldEvery) {
          // Only between changes: let rendering, input and I/O run, then go on with the next
          // change.
          _scheduled = true;
          _macrotask(_drain);
          return;
        }
        final List<Event> change = _changes.removeFirst();
        for (final Event event in change) {
          _fire(event);
          delivered++;
        }
      }
    } finally {
      _draining = false;
    }
  }

  static void _fire(Event event) {
    // A cancel event always goes out: the view leaves a cancelled registration alive until its
    // cancel event fires, and the registration ignores it once zombied by its own listener.
    if (event is DataEvent && event.eventRegistration.isZombied) {
      return;
    }
    try {
      event.fire();
    } on Object catch (error, stackTrace) {
      Zone.current.handleUncaughtError(error, stackTrace);
    }
  }
}
