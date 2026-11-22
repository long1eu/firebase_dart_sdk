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
List<String> pathSegments(String? path) => throw UnimplementedError();

/// The implementation of [QueryPlatform]: a location of a
/// [DartFirebaseDatabase].
///
/// The official `Query` holds a reference as its delegate and passes its
/// [QueryModifiers] to every call, so this class is a location, and each call
/// builds the client query from the modifiers ([clientQuery]).
class DartQuery extends QueryPlatform {
  /// The location of [segments] (see [pathSegments]) in [database].
  DartQuery(DartFirebaseDatabase database, this.segments)
    : super(database: database);

  /// The keys of this location from the root; empty at the root.
  final List<String> segments;

  /// `QueryPlatform.database`, typed.
  @override
  DartFirebaseDatabase get database => throw UnimplementedError();

  /// The client reference of this location, `database.client.ref(...)`.
  /// Creates the client on first use; throws the client's [ArgumentError] for
  /// an invalid key.
  fs.DatabaseReference get clientRef => throw UnimplementedError();

  /// The client query of [modifiers] at this location. The modifiers are
  /// applied in one order whatever the call order: orderBy, then start
  /// (`startAt`/`startAfter`), then end (`endAt`/`endBefore`), then limit, so
  /// that `startAt(1).orderByChild('x')`, which FlutterFire accepts, works.
  /// `equalTo` arrives as `startAt` plus `endAt`. A null cursor value is
  /// passed as null (a real bound), not dropped. Throws the client's
  /// [ArgumentError] or [StateError] for an invalid combination.
  fs.Query clientQuery(QueryModifiers modifiers) => throw UnimplementedError();

  /// `QueryPlatform.path`: the client's `path`, `'/a/b'`, `'/'` at the root
  /// (the web plugin's form; native has no leading slash). No client.
  @override
  String get path => throw UnimplementedError();

  /// `QueryPlatform.ref`: the [DartReference] of this location.
  @override
  DartReference get ref => throw UnimplementedError();

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
  ) => throw UnimplementedError();

  /// `QueryPlatform.get`: client `Query.get()` of [clientQuery] through
  /// [guard], as a [DartDataSnapshot].
  @override
  Future<DataSnapshotPlatform> get(QueryModifiers modifiers) =>
      throw UnimplementedError();

  /// `QueryPlatform.keepSynced`: client `Query.keepSynced(value)` of
  /// [clientQuery] through [guard]; a flag per query, not a counter.
  @override
  Future<void> keepSynced(QueryModifiers modifiers, bool value) =>
      throw UnimplementedError();
}
