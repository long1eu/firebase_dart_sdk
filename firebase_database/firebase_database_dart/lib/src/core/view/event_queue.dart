/// Orders and raises events. JS: `core/view/EventQueue.ts`; Android: `core/view/EventRaiser.java`
/// (dispatch only; ordering there comes from the run loop).
library;

import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/view/event.dart';

/// Runs event callbacks; Repo passes one that schedules them (microtask or synchronous).
typedef EventTarget = void Function(void Function() callback);

/// Queues events grouped by path and raises those at or related to a changed path, keeping the
/// order in which they were queued.
final class EventQueue {
  /// Creates a queue that raises through [eventTarget].
  EventQueue(this.eventTarget);

  /// Where events run.
  final EventTarget eventTarget;

  /// Queues [events] without raising them.
  void queueEvents(List<Event> events) => throw UnimplementedError();

  /// Queues [events] and raises the queued events whose path is exactly [path].
  void raiseEventsAtPath(Path path, List<Event> events) =>
      throw UnimplementedError();

  /// Queues [events] and raises the queued events at, above or below [changedPath].
  void raiseEventsForChangedPath(Path changedPath, List<Event> events) =>
      throw UnimplementedError();
}
