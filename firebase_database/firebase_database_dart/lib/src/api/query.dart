/// A sorted, filtered view of a location. JS: `api/Reference_impl.ts` (`QueryImpl`, query constraints);
/// Android: `Query.java`.
library;

import 'package:firebase_database_dart/src/api/data_snapshot.dart';
import 'package:firebase_database_dart/src/api/database_event.dart';
import 'package:firebase_database_dart/src/api/database_event_type.dart';
import 'package:firebase_database_dart/src/api/database_reference.dart';
import 'package:firebase_database_dart/src/api/firebase_database.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:meta/meta.dart';

/// A location with an optional order, range and limit. Immutable: every modifier returns a new query.
///
/// ```dart
/// final Query top = db.ref('scores').orderByValue().limitToLast(10);
/// top.onValue.listen((DatabaseEvent e) {
///   for (final DataSnapshot s in e.snapshot.children) print('${s.key}: ${s.value}');
/// });
/// ```
///
/// Validation. The client checks a query when you build it, in release builds too, with the JS SDK's rules:
/// one `orderBy*`; at most one start bound and one end bound; [equalTo] excludes both; a `key:` argument only
/// where the order allows it; a limit above 0. A violation throws an [ArgumentError] or a [StateError] at the
/// call.
///
/// Streams. Every event getter returns a stream made with `Stream.multi`: not broadcast, and each `listen`,
/// also a second `listen` on the same stream object, is its own registration that gets its own initial
/// events. Equal queries share one listen on the server. Cancelling a subscription removes it at once,
/// without waiting for the server; the last one on a query removes the server listen. A stream ends only
/// when the database closes (error `database-closed`, then done) or when the server cancels the listen
/// (error, for example `permission-denied`, then done). A lost connection is never a stream error.
///
/// Delivery. No listener runs inside the call that caused it: events go through one queue per database,
/// drained in a microtask. Inside one change, events come child removed, added, moved, changed, then value;
/// deeper locations before shallower ones. Changes are delivered in the order they were applied. Pausing a
/// subscription buffers its events without bound; nothing is dropped. Order across subscriptions holds only
/// for `listen` callbacks that are not paused: `await for` pauses after each event, so it loses order
/// relative to other streams (use [onChildEvents] to keep the order of child events). An exception thrown
/// by a listener goes to that listener's zone; its subscription stays open.
///
/// Cache. A new listener on a location whose data is held complete (by another listener, or by a pending
/// local write) gets its initial events from that data with no round trip. Two queries are equal when they
/// have the same database, path and query parameters.
base class Query {
  /// Creates the query [spec] of [database]. Use `FirebaseDatabase.ref` and the modifiers instead.
  @internal
  const Query.internal(this.database, this.spec);

  /// The database this query reads.
  final FirebaseDatabase database;

  /// The path and parameters of this query.
  @internal
  final QuerySpec spec;

  /// The reference to this query's location, without order, range or limit.
  DatabaseReference get ref => throw UnimplementedError();

  /// The path of the location: `'/a/b'`, or `'/'` at the root.
  String get path => throw UnimplementedError();

  /// The database URL followed by the percent-encoded [path].
  Uri get url => throw UnimplementedError();

  /// Orders by the value of the child at [path] (which may have several segments) of each child. Children
  /// without it come first. Ordering by a child the server has no `.indexOn` rule for downloads all data in
  /// development and fails with `index-not-defined` where the rules require an index.
  Query orderByChild(String path) => throw UnimplementedError();

  /// Orders by child key: keys that parse as 32-bit integers (leading zeros allowed) come first, by value,
  /// ties going to the shorter string; then all other keys by UTF-16 code units.
  Query orderByKey() => throw UnimplementedError();

  /// Orders by the children's values: null, then false, true, numbers, strings, then objects by key.
  Query orderByValue() => throw UnimplementedError();

  /// Orders by the children's priorities.
  Query orderByPriority() => throw UnimplementedError();

  /// Starts the range at [value], included, and at children whose key is at least [key] among those equal
  /// to [value]. A `null` [value] is a real bound (null priority or value). Throws when a start bound is
  /// already set or [key] is not allowed by the order.
  Query startAt(Object? value, {String? key}) => throw UnimplementedError();

  /// Starts the range just after [value] (and after [key] among children equal to [value]). A `null`
  /// [value] is a real bound.
  Query startAfter(Object? value, {String? key}) => throw UnimplementedError();

  /// Ends the range at [value], included (and at [key] among children equal to [value]). A `null` [value]
  /// is a real bound. Throws when an end bound is already set.
  Query endAt(Object? value, {String? key}) => throw UnimplementedError();

  /// Ends the range just before [value] (and before [key] among children equal to [value]). A `null`
  /// [value] is a real bound.
  Query endBefore(Object? value, {String? key}) => throw UnimplementedError();

  /// Keeps only the children equal to [value] (and with key [key] when given): a start and an end bound at
  /// once, so it throws when either is already set.
  Query equalTo(Object? value, {String? key}) => throw UnimplementedError();

  /// Keeps the first [limit] children in the order; [limit] must be above 0 and no limit may be set yet.
  Query limitToFirst(int limit) => throw UnimplementedError();

  /// Keeps the last [limit] children in the order; [limit] must be above 0 and no limit may be set yet.
  Query limitToLast(int limit) => throw UnimplementedError();

  /// Reads the query's data once, preferring the server.
  ///
  /// 1. When the client already holds the query's data complete (server data kept for an active listener,
  ///    or pending local writes that cover the query, with pending writes laid over it), it answers from
  ///    that with no round trip.
  /// 2. Otherwise it asks the server and waits, with no client timeout while connected. The answer also
  ///    raises events on the listeners it completes, before this Future completes.
  /// 3. When not connected, it waits up to 3 seconds for a connection, then answers from the persisted
  ///    cache, or fails with `unavailable`. After `FirebaseDatabase.goOffline` it does not wait.
  /// 4. When the connection drops while the request is out, case 3 applies from then.
  /// 5. When the server refuses the read it fails with `permission-denied`, never with a cached answer.
  ///
  /// Outside case 1 the answer does not include this client's pending writes.
  Future<DataSnapshot> get() => throw UnimplementedError();

  /// The first event of [type], after which the registration is removed inside that event's delivery.
  ///
  /// It may answer from the cache and includes pending local writes; `onValue.first` behaves the same.
  ///
  /// ```dart
  /// final DatabaseEvent e = await db.ref('config').once();
  /// print(e.snapshot.value);
  /// ```
  Future<DatabaseEvent> once([
    DatabaseEventType type = DatabaseEventType.value,
  ]) => throw UnimplementedError();

  /// The value of the query: its current data first, then again after every change.
  Stream<DatabaseEvent> get onValue => throw UnimplementedError();

  /// A [DatabaseEventType.childAdded] event per child, first for each existing child, then for each new
  /// one.
  Stream<DatabaseEvent> get onChildAdded => throw UnimplementedError();

  /// A [DatabaseEventType.childChanged] event each time a child's data changes.
  Stream<DatabaseEvent> get onChildChanged => throw UnimplementedError();

  /// A [DatabaseEventType.childMoved] event each time a child changes place in the order.
  Stream<DatabaseEvent> get onChildMoved => throw UnimplementedError();

  /// A [DatabaseEventType.childRemoved] event each time a child leaves the results.
  Stream<DatabaseEvent> get onChildRemoved => throw UnimplementedError();

  /// The four child event kinds in one stream, in their true order, with no value events and no batching
  /// per change; switch on [DatabaseEvent.type]. Unlike four separate streams, it keeps the order of child
  /// events under pause and `await for`.
  Stream<DatabaseEvent> get onChildEvents => throw UnimplementedError();

  /// Keeps this query's data synchronised even with no listener when [value] is true, and stops when it is
  /// false.
  ///
  /// It is a flag, not a counter: calling it with true twice and false once turns it off. Without
  /// persistence it keeps the in-memory data and the server listen.
  Future<void> keepSynced(bool value) => throw UnimplementedError();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Query && other.database == database && other.spec == spec;

  @override
  int get hashCode => Object.hash(database, spec);
}
