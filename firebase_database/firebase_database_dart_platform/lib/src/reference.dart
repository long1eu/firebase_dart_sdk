/// [DartReference], the [DatabaseReferencePlatform] of this package.
library;

import 'package:firebase_database_dart/firebase_database_dart.dart' as fs;
import 'package:firebase_database_dart_platform/src/errors.dart';
import 'package:firebase_database_dart_platform/src/firebase_database.dart';
import 'package:firebase_database_dart_platform/src/on_disconnect.dart';
import 'package:firebase_database_dart_platform/src/query.dart';
import 'package:firebase_database_dart_platform/src/transaction.dart';
import 'package:firebase_database_dart_platform/src/values.dart';
import 'package:firebase_database_platform_interface/firebase_database_platform_interface.dart';

/// The implementation of [DatabaseReferencePlatform], whose constructor is
/// private: it extends [DartQuery] and implements the interface, as the web
/// plugin does.
///
/// [key], [parent], [root], [child] and [path] work on the keys of the
/// location and create no client; the writes go to [DartQuery.clientRef].
class DartReference extends DartQuery implements DatabaseReferencePlatform {
  /// The reference of [path] in [database], in any form FlutterFire passes
  /// (see [pathSegments]).
  DartReference(DartFirebaseDatabase database, String? path)
    : super(database, pathSegments(path));

  /// The reference of [clientRef], a reference of `database.client` (the
  /// `ref` of a client snapshot), kept as [DartQuery.clientRef].
  DartReference.ofClient(
    DartFirebaseDatabase database,
    fs.DatabaseReference clientRef,
  ) : super(database, pathSegments(clientRef.path), clientRef: clientRef);

  DartReference._ofSegments(super.database, super.segments);

  /// `DatabaseReferencePlatform.child`: [path] may have several keys
  /// (`'a/b'`). Invalid keys are reported by the client at the first I/O.
  @override
  DartReference child(String path) => DartReference._ofSegments(
    database,
    <String>[...segments, ...pathSegments(path)],
  );

  /// `DatabaseReferencePlatform.parent`: null at the root.
  @override
  DartReference? get parent => segments.isEmpty
      ? null
      : DartReference._ofSegments(
          database,
          segments.sublist(0, segments.length - 1),
        );

  /// `DatabaseReferencePlatform.root`.
  @override
  DartReference root() => DartReference._ofSegments(database, const <String>[]);

  /// `DatabaseReferencePlatform.key`: the last key, null at the root.
  @override
  String? get key => segments.isEmpty ? null : segments.last;

  /// `DatabaseReferencePlatform.push`: client `push()`, which makes the key
  /// locally from the server time offset. No write, but it creates the client
  /// and so fixes its settings: call `useDatabaseEmulator` before it.
  @override
  DartReference push() => DartReference.ofClient(database, clientRef.push());

  /// `DatabaseReferencePlatform.set`: client `set` of the [transformValue] of
  /// [value], through [guard].
  @override
  Future<void> set(Object? value) =>
      guard<void>(() async => clientRef.set(transformValue(value)));

  /// `DatabaseReferencePlatform.setWithPriority`: client
  /// `set(transformValue(value), priority: priority)` through [guard].
  @override
  Future<void> setWithPriority(Object? value, Object? priority) => guard<void>(
    () async => clientRef.set(transformValue(value), priority: priority),
  );

  /// `DatabaseReferencePlatform.update`: client
  /// `update(transformValue(value) as Map<String, Object?>)` through [guard].
  @override
  Future<void> update(Map<String, Object?> value) => guard<void>(
    () async =>
        clientRef.update(transformValue(value)! as Map<String, Object?>),
  );

  /// `DatabaseReferencePlatform.setPriority`: client `setPriority` through
  /// [guard].
  @override
  Future<void> setPriority(Object? priority) =>
      guard<void>(() async => clientRef.setPriority(priority));

  /// `DatabaseReferencePlatform.remove`: client `remove()` through [guard].
  /// The official `DatabaseReference.remove()` calls `set(null)` instead.
  @override
  Future<void> remove() => guard<void>(() async => clientRef.remove());

  /// `DatabaseReferencePlatform.runTransaction`: [runDartTransaction].
  @override
  Future<TransactionResultPlatform> runTransaction(
    TransactionHandler transactionHandler, {
    bool applyLocally = true,
  }) =>
      runDartTransaction(this, transactionHandler, applyLocally: applyLocally);

  /// `DatabaseReferencePlatform.onDisconnect`: a [DartOnDisconnect] of this
  /// reference (no client yet).
  @override
  DartOnDisconnect onDisconnect() => DartOnDisconnect(database, this);
}
