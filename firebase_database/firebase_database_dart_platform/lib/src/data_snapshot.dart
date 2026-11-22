/// [DartDataSnapshot] and [DartDatabaseEvent], the snapshot and event of this
/// package, and the two event type enums.
library;

import 'package:firebase_database_dart/firebase_database_dart.dart' as fs;
import 'package:firebase_database_dart_platform/src/firebase_database.dart';
import 'package:firebase_database_dart_platform/src/reference.dart';
import 'package:firebase_database_dart_platform/src/values.dart';
import 'package:firebase_database_platform_interface/firebase_database_platform_interface.dart';

/// The client event type of the FlutterFire [type].
fs.DatabaseEventType clientEventType(DatabaseEventType type) =>
    throw UnimplementedError();

/// The FlutterFire event type of the client's [type].
DatabaseEventType flutterFireEventType(fs.DatabaseEventType type) =>
    throw UnimplementedError();

/// The implementation of [DataSnapshotPlatform] over a client
/// [fs.DataSnapshot]. The platform class reads a private data map; every
/// getter that reads it is overridden here, and the map passed up is empty.
class DartDataSnapshot extends DataSnapshotPlatform {
  /// The snapshot of [clientSnapshot]. Its [ref] is the reference of
  /// `clientSnapshot.ref`, so the snapshot of a child event has the child's
  /// reference (FlutterFire gives the query's: fixed on purpose).
  DartDataSnapshot(DartFirebaseDatabase database, this.clientSnapshot)
    : super(
        DartReference.ofClient(database, clientSnapshot.ref),
        const <String, dynamic>{},
      );

  /// The client snapshot.
  final fs.DataSnapshot clientSnapshot;

  /// `DataSnapshotPlatform.ref`, typed.
  @override
  DartReference get ref => throw UnimplementedError();

  /// `DataSnapshotPlatform.key`: client `key`.
  @override
  String? get key => throw UnimplementedError();

  /// `DataSnapshotPlatform.exists`: client `exists`.
  @override
  bool get exists => throw UnimplementedError();

  /// `DataSnapshotPlatform.value`: the [mutableCopy] of the client `value`,
  /// made on the first read and the same object on every later read.
  @override
  Object? get value => throw UnimplementedError();

  /// `DataSnapshotPlatform.priority`: client `priority`, for child snapshots
  /// too (FlutterFire native gives null for children: fixed on purpose).
  @override
  Object? get priority => throw UnimplementedError();

  /// `DataSnapshotPlatform.hasChild`: client `hasChild`.
  @override
  bool hasChild(String path) => throw UnimplementedError();

  /// `DataSnapshotPlatform.child`: client `child`; [childPath] may have
  /// several keys and list indices.
  @override
  DartDataSnapshot child(String childPath) => throw UnimplementedError();

  /// `DataSnapshotPlatform.children`: client `children`, lazy, in the query's
  /// index order, each with its own reference and priority.
  @override
  Iterable<DartDataSnapshot> get children => throw UnimplementedError();
}

/// The implementation of [DatabaseEventPlatform] over a client
/// [fs.DatabaseEvent]. Every getter that reads the platform class's private
/// data map is overridden here, and the map passed up is empty.
///
/// One instance per event per listen: the client stream is a `Stream.multi`
/// and the shim maps it per listen, so the [snapshot] (and its mutable value)
/// is not shared between listeners.
class DartDatabaseEvent extends DatabaseEventPlatform {
  /// The event of [clientEvent], from a query of [database].
  DartDatabaseEvent(this.database, this.clientEvent)
    : super(<String, dynamic>{});

  /// The instance whose query raised the event.
  final DartFirebaseDatabase database;

  /// The client event.
  final fs.DatabaseEvent clientEvent;

  /// `DatabaseEventPlatform.snapshot`: a [DartDataSnapshot] of the client
  /// `snapshot`, made once.
  @override
  DartDataSnapshot get snapshot => throw UnimplementedError();

  /// `DatabaseEventPlatform.previousChildKey`: client `previousChildKey`.
  @override
  String? get previousChildKey => throw UnimplementedError();

  /// `DatabaseEventPlatform.type`: [flutterFireEventType] of the client
  /// `type`.
  @override
  DatabaseEventType get type => throw UnimplementedError();
}
