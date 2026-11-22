/// One event of a query stream. JS: `api/Reference_impl.ts` (callbacks with `(snapshot, previousChildName)`);
/// Android: `ChildEventListener.java`, `ValueEventListener.java`.
library;

import 'package:firebase_database_dart/src/api/data_snapshot.dart';
import 'package:firebase_database_dart/src/api/database_event_type.dart';
import 'package:meta/meta.dart';

/// An event from one of the `on<Thing>` streams of a `Query`, or from `Query.once`.
///
/// One class serves every kind: switch on [type].
///
/// ```dart
/// await for (final DatabaseEvent e in db.ref('rooms/1/messages').onChildEvents) {
///   switch (e.type) {
///     case DatabaseEventType.childAdded:
///       print('added ${e.snapshot.key} after ${e.previousChildKey}');
///     case DatabaseEventType.childRemoved:
///       print('removed ${e.snapshot.key}');
///     default:
///       break;
///   }
/// }
/// ```
@immutable
final class DatabaseEvent {
  /// Creates an event. The client creates them; use a stream of `Query` instead.
  @internal
  const DatabaseEvent.internal(
    this.type,
    this.snapshot, {
    this.previousChildKey,
  });

  /// The kind of event.
  final DatabaseEventType type;

  /// The data of the event.
  ///
  /// For a value event it is the query's location. For a child event it is the child, with the child's own
  /// reference (`snapshot.ref.path` is `/l/a` for child `a` of `/l`) and the child's priority.
  final DataSnapshot snapshot;

  /// The key of the child before [snapshot] in the query's order, for [DatabaseEventType.childAdded],
  /// [DatabaseEventType.childChanged] and [DatabaseEventType.childMoved]; null for the first child and for
  /// every other kind.
  final String? previousChildKey;
}
