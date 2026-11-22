/// A listener registered on a query. JS: `core/view/EventRegistration.ts` (`EventRegistration`);
/// Android: `core/EventRegistration.java`, `core/EventRegistrationZombieListener.java`.
///
/// The public API later implements it for value and child listeners (Android
/// `ValueEventRegistration`, `ChildEventRegistration`; JS `ValueEventRegistration`,
/// `ChildEventRegistration` in `api/Reference_impl.ts`).
library;

import 'package:firebase_database_dart/src/core/database_error.dart';
import 'package:firebase_database_dart/src/core/view/change.dart';
import 'package:firebase_database_dart/src/core/view/event.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';

/// Called once when a registration is zombified (removed while events for it may be queued).
typedef ZombieListener = void Function(EventRegistration registration);

/// A listener on [querySpec] that turns changes into events and delivers them.
abstract class EventRegistration {
  /// Constructor for subclasses.
  EventRegistration();

  /// The query listened to.
  QuerySpec get querySpec;

  /// Whether this registration wants events of [type].
  bool respondsTo(EventType type);

  /// The event for [change] on [query].
  DataEvent createEvent(Change change, QuerySpec query);

  /// Delivers [event] to the listener (skipped once zombified).
  void fireEvent(DataEvent event);

  /// Delivers the cancellation [error] to the listener.
  void fireCancelEvent(DatabaseError error);

  /// The same listener on [newQuery].
  EventRegistration clone(QuerySpec newQuery);

  /// Whether [other] is the same listener (the same callback); used to remove listeners.
  bool isSameListener(EventRegistration other);

  /// Marks the registration removed; queued events for it are dropped.
  void zombify() => throw UnimplementedError();

  /// Whether [zombify] was called.
  bool get isZombied => throw UnimplementedError();

  /// Sets the listener called on [zombify].
  set onZombied(ZombieListener? listener) => throw UnimplementedError();

  /// Whether the user added it (false for internal ones such as keepSynced).
  bool get isUserInitiated => throw UnimplementedError();

  /// Sets [isUserInitiated].
  set isUserInitiated(bool value) => throw UnimplementedError();
}
