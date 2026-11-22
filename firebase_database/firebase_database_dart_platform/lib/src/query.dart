/// [DartQuery], the [QueryPlatform] of this package.
library;

import 'package:firebase_database_dart/firebase_database_dart.dart' as fs;
import 'package:firebase_database_dart_platform/src/data_snapshot.dart';
import 'package:firebase_database_dart_platform/src/errors.dart';
import 'package:firebase_database_dart_platform/src/firebase_database.dart';
import 'package:firebase_database_dart_platform/src/reference.dart';
import 'package:firebase_database_platform_interface/firebase_database_platform_interface.dart';

/// The keys of [path] from the root: null, `''` and `'/'` are the root;
/// leading, trailing and repeated slashes are dropped (`'/a//b/'` is
/// `['a', 'b']`), as the client's `ref` does. Keys are not validated here:
/// the client does that when the reference is first used.
List<String> pathSegments(String? path) => <String>[
  for (final String segment in (path ?? '').split('/'))
    if (segment.isNotEmpty) segment,
];

/// The implementation of [QueryPlatform]: a location of a
/// [DartFirebaseDatabase].
///
/// The official `Query` holds a reference as its delegate and passes its
/// [QueryModifiers] to every call, so this class is a location, and each call
/// builds the client query from the modifiers ([clientQuery]).
class DartQuery extends QueryPlatform {
  /// The location of [segments] (see [pathSegments]) in [database].
  ///
  /// [clientRef], when given, is the client reference of the same location,
  /// kept as [DartQuery.clientRef] (the `ref` of a client snapshot).
  DartQuery(DartFirebaseDatabase database, this.segments, {this._clientRef})
    : super(database: database);

  /// The keys of this location from the root; empty at the root.
  final List<String> segments;

  fs.DatabaseReference? _clientRef;

  /// `QueryPlatform.database`, typed.
  @override
  DartFirebaseDatabase get database => super.database as DartFirebaseDatabase;

  /// The client reference of this location, `database.client.ref(...)`.
  /// Creates the client on first use; throws the client's [ArgumentError] for
  /// an invalid key.
  fs.DatabaseReference get clientRef =>
      _clientRef ??= database.client.ref(segments.join('/'));

  /// The client query of [modifiers] at this location. The modifiers are
  /// applied in one order whatever the call order: orderBy, then start
  /// (`startAt`/`startAfter`), then end (`endAt`/`endBefore`), then limit, so
  /// that `startAt(1).orderByChild('x')`, which FlutterFire accepts, works.
  /// `equalTo` arrives as `startAt` plus `endAt`. A null cursor value is
  /// passed as null (a real bound), not dropped. Throws the client's
  /// [ArgumentError] or [StateError] for an invalid combination.
  fs.Query clientQuery(QueryModifiers modifiers) {
    final List<QueryModifier> all = modifiers.toIterable().toList();
    fs.Query query = clientRef;
    for (final OrderModifier order in all.whereType<OrderModifier>()) {
      query = _applyOrder(query, order);
    }
    for (final StartCursorModifier start
        in all.whereType<StartCursorModifier>()) {
      query = _applyStart(query, start);
    }
    for (final EndCursorModifier end in all.whereType<EndCursorModifier>()) {
      query = _applyEnd(query, end);
    }
    for (final LimitModifier limit in all.whereType<LimitModifier>()) {
      query = _applyLimit(query, limit);
    }
    return query;
  }

  /// `QueryPlatform.path`: the client's `path`, `'/a/b'`, `'/'` at the root
  /// (the web plugin's form; native has no leading slash). No client.
  @override
  String get path => '/${segments.join('/')}';

  /// `QueryPlatform.ref`: the [DartReference] of this location.
  @override
  DartReference get ref => DartReference(database, path);

  /// `QueryPlatform.observe`: the client stream of [eventType]
  /// (`onValue`, `onChildAdded`, ...) of [clientQuery], mapped to
  /// [DartDatabaseEvent]s and through [guardStream]. Not a broadcast stream:
  /// as the client's `Stream.multi`, each listen is its own registration with
  /// its own initial events, and its cancel removes it. An invalid query is a
  /// stream with that error, then done (not a throw from this call).
  @override
  Stream<DatabaseEventPlatform> observe(
    QueryModifiers modifiers,
    DatabaseEventType eventType,
  ) {
    Stream<fs.DatabaseEvent> events;
    try {
      final fs.Query query = clientQuery(modifiers);
      events = switch (eventType) {
        DatabaseEventType.value => query.onValue,
        DatabaseEventType.childAdded => query.onChildAdded,
        DatabaseEventType.childChanged => query.onChildChanged,
        DatabaseEventType.childMoved => query.onChildMoved,
        DatabaseEventType.childRemoved => query.onChildRemoved,
      };
    } on Object catch (error, stackTrace) {
      events = Stream<fs.DatabaseEvent>.error(error, stackTrace);
    }
    return guardStream(
      events.map<DatabaseEventPlatform>(
        (fs.DatabaseEvent event) => DartDatabaseEvent(database, event),
      ),
    );
  }

  /// `QueryPlatform.get`: client `Query.get()` of [clientQuery] through
  /// [guard], as a [DartDataSnapshot].
  @override
  Future<DataSnapshotPlatform> get(QueryModifiers modifiers) =>
      guard<DataSnapshotPlatform>(
        () async =>
            DartDataSnapshot(database, await clientQuery(modifiers).get()),
      );

  /// `QueryPlatform.keepSynced`: client `Query.keepSynced(value)` of
  /// [clientQuery] through [guard]; a flag per query, not a counter.
  @override
  Future<void> keepSynced(QueryModifiers modifiers, bool value) =>
      guard<void>(() async => clientQuery(modifiers).keepSynced(value));
}

fs.Query _applyOrder(fs.Query query, OrderModifier order) =>
    switch (order.name) {
      'orderByChild' => query.orderByChild(order.path!),
      'orderByKey' => query.orderByKey(),
      'orderByValue' => query.orderByValue(),
      'orderByPriority' => query.orderByPriority(),
      _ => throw ArgumentError.value(order.name, 'order', 'Unknown order'),
    };

fs.Query _applyStart(fs.Query query, StartCursorModifier start) =>
    switch (start.name) {
      'startAt' => query.startAt(start.value, key: start.key),
      'startAfter' => query.startAfter(start.value, key: start.key),
      _ => throw ArgumentError.value(start.name, 'start', 'Unknown cursor'),
    };

fs.Query _applyEnd(fs.Query query, EndCursorModifier end) => switch (end.name) {
  'endAt' => query.endAt(end.value, key: end.key),
  'endBefore' => query.endBefore(end.value, key: end.key),
  _ => throw ArgumentError.value(end.name, 'end', 'Unknown cursor'),
};

fs.Query _applyLimit(fs.Query query, LimitModifier limit) =>
    switch (limit.name) {
      'limitToFirst' => query.limitToFirst(limit.value),
      'limitToLast' => query.limitToLast(limit.value),
      _ => throw ArgumentError.value(limit.name, 'limit', 'Unknown limit'),
    };
