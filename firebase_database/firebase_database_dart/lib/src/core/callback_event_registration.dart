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

  @override
  bool respondsTo(EventType type) => throw UnimplementedError();

  @override
  DataEvent createEvent(Change change, QuerySpec query) =>
      throw UnimplementedError();

  /// Calls [onEvent] unless zombied.
  @override
  void fireEvent(DataEvent event) => throw UnimplementedError();

  /// Calls [onCancel] unless zombied.
  @override
  void fireCancelEvent(DatabaseError error) => throw UnimplementedError();

  /// The same callbacks and [types] on [newQuery].
  @override
  EventRegistration clone(QuerySpec newQuery) => throw UnimplementedError();

  /// Whether [other] is a [CallbackEventRegistration] with the same [onEvent] (identical).
  @override
  bool isSameListener(EventRegistration other) => throw UnimplementedError();
}
