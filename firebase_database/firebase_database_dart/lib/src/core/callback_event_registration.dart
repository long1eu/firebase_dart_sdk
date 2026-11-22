/// The one concrete registration the public layer uses. JS: `ValueEventRegistration` and
/// `ChildEventRegistration` (`api/Reference_impl.ts`); Android: `core/ValueEventRegistration.java`,
/// `core/ChildEventRegistration.java`.
///
/// One class serves `onValue`, the single-type child getters and `onChildEvents`: the public layer
/// builds its `Stream.multi` per listen and calls `MultiStreamController.addSync` inside
/// [CallbackEventRegistration.onEvent] (`rtdb/research/13_engine_rules.md`, event delivery rule 3).
library;

import 'package:firebase_database_dart/src/core/database_error.dart';
import 'package:firebase_database_dart/src/core/event_registration.dart';
import 'package:firebase_database_dart/src/core/view/change.dart';
import 'package:firebase_database_dart/src/core/view/event.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';

/// A registration on [querySpec] for the event [types], delivering through callbacks.
final class CallbackEventRegistration extends EventRegistration {
  /// Creates the registration; [onEvent] receives every data event of [types], [onCancel] the
  /// cancellation error (server cancel, rules), once.
  CallbackEventRegistration(
    this.querySpec,
    this.types, {
    required this.onEvent,
    required this.onCancel,
  });

  @override
  final QuerySpec querySpec;

  /// The event types delivered.
  final Set<EventType> types;

  /// Receives each data event, synchronously from the top of the dispatcher's drain.
  final void Function(DataEvent event) onEvent;

  /// Receives the cancellation error.
  final void Function(DatabaseError error) onCancel;

  /// Whether [type] is one of [types] (Android `ValueEventRegistration.respondsTo`,
  /// `ChildEventRegistration.respondsTo`).
  @override
  bool respondsTo(EventType type) => types.contains(type);

  /// A value event at the query path, or a child event at the child path with the previous
  /// sibling (Android `ValueEventRegistration.createEvent`, `ChildEventRegistration.createEvent`).
  @override
  DataEvent createEvent(Change change, QuerySpec query) {
    if (change.eventType == EventType.value) {
      return DataEvent(EventType.value, this, query.path, change.node);
    }
    return DataEvent(
      change.eventType,
      this,
      query.path.child(change.childKey!),
      change.node,
      previousName: change.prevName,
    );
  }

  /// Calls [onEvent] unless zombied (Android `ChildEventRegistration.fireEvent`).
  @override
  void fireEvent(DataEvent event) {
    if (isZombied) {
      return;
    }
    onEvent(event);
  }

  /// Calls [onCancel] unless zombied, then zombifies, so the cancellation is the last thing the
  /// listener gets (Android `ValueEventRegistration.fireCancelEvent` calls it unconditionally;
  /// here the view leaves a cancelled registration alive until its cancel event fires).
  @override
  void fireCancelEvent(DatabaseError error) {
    if (isZombied) {
      return;
    }
    onCancel(error);
    zombify();
  }

  /// The same callbacks and [types] on [newQuery] (Android `ValueEventRegistration.clone`).
  @override
  EventRegistration clone(QuerySpec newQuery) => CallbackEventRegistration(
    newQuery,
    types,
    onEvent: onEvent,
    onCancel: onCancel,
  );

  /// Whether [other] is a [CallbackEventRegistration] with the same [onEvent] (identical;
  /// Android `ValueEventRegistration.isSameListener`).
  @override
  bool isSameListener(EventRegistration other) =>
      other is CallbackEventRegistration && identical(other.onEvent, onEvent);

  @override
  String toString() => 'CallbackEventRegistration($types)';
}
