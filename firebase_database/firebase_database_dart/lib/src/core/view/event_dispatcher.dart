/// Delivers the events of one database in order. JS: `core/view/EventQueue.ts` (replaced: no
/// raise by path); Android: `core/view/EventRaiser.java` (dispatch onto the run loop).
///
/// Decided design (`rtdb/research/13_engine_rules.md`, event delivery rules 2 to 6): one FIFO per
/// database, every Repo entry point appends the events its operation produced, one microtask
/// drains it, never re-entrantly.
library;

import 'dart:async';

import 'package:firebase_database_dart/src/core/event_registration.dart';
import 'package:firebase_database_dart/src/core/view/event.dart';

/// The number of events after which a drain yields to the event loop (`Timer.run`) at the next
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
/// - After `yieldEvery` events the drain yields to the event loop, but only between changes:
///   the events of one change are always delivered together.
final class EventDispatcher {
  /// Creates a dispatcher that schedules its drain with [schedule] and yields after [yieldEvery]
  /// events.
  factory EventDispatcher({
    void Function(void Function()) schedule = scheduleMicrotask,
    int yieldEvery = eventsPerDrainSlice,
  }) => throw UnimplementedError();

  /// Appends the events of one change and schedules a drain if none is pending.
  void enqueue(List<Event> events) => throw UnimplementedError();
}
