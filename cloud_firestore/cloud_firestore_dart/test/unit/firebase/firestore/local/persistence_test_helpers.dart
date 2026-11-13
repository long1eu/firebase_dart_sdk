// File created by
// Lung Razvan <long1eu>
// on 30/09/2018

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/memory/memory_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/stats_collector.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/database.dart';
import 'package:uuid/uuid.dart';

import 'mock/database_mock.dart';

Future<SQLitePersistence> createSQLitePersistence([
  String? name,
  LruGarbageCollectorParams params = const LruGarbageCollectorParams(),
  StatsCollector statsCollector = StatsCollector.noOp,
]) =>
    createSQLitePersistenceForProject('projectId', name, params, statsCollector);

Future<SQLitePersistence> createSQLitePersistenceForProject(
  String projectId, [
  String? name,
  LruGarbageCollectorParams params = const LruGarbageCollectorParams(),
  StatsCollector statsCollector = StatsCollector.noOp,
]) async {
  name ??= 'test-${const Uuid().v4()}';
  final DatabaseId databaseId = DatabaseId.forProject(projectId);
  final LocalSerializer serializer =
      LocalSerializer(RemoteSerializer(databaseId));

  final SQLitePersistence persistence = await SQLitePersistence.create(
    name,
    databaseId,
    serializer,
    (String path,
            {int? version,
            OnConfigure? onConfigure,
            OnCreate? onCreate,
            OnVersionChange? onUpgrade,
            OnVersionChange? onDowngrade,
            OnOpen? onOpen}) =>
        DatabaseMock.create(name!,
            version: version,
            onConfigure: onConfigure,
            onCreate: onCreate,
            onUpgrade: onUpgrade,
            onDowngrade: onDowngrade,
            onOpen: onOpen),
    params,
    statsCollector,
  );
  await persistence.start();
  return persistence;
}

/// Creates and starts a new [MemoryPersistence] instance for testing.
Future<MemoryPersistence> createEagerGCMemoryPersistence([
  StatsCollector statsCollector = StatsCollector.noOp,
]) async {
  final MemoryPersistence persistence =
      MemoryPersistence.createEagerGcMemoryPersistence(statsCollector);
  await persistence.start();
  return persistence;
}

Future<MemoryPersistence> createLRUMemoryPersistence([
  LruGarbageCollectorParams params = const LruGarbageCollectorParams(),
  StatsCollector statsCollector = StatsCollector.noOp,
]) async {
  final DatabaseId databaseId = DatabaseId.forProject('projectId');
  final LocalSerializer serializer =
      LocalSerializer(RemoteSerializer(databaseId));
  final MemoryPersistence persistence =
      MemoryPersistence.createLruGcMemoryPersistence(
          params, serializer, statsCollector);
  await persistence.start();
  return persistence;
}

/// Creates and starts a [SQLitePersistence] on the database [name] of [projectId] as the client [clientId] of a cache
/// shared by several clients: the primary lease uses [clock] and respects the lease of another client
/// ([PrimaryLeaseMode.multipleClients], the election of the JS SDK with tab synchronization).
Future<SQLitePersistence> createSharedSQLitePersistenceForProject(
  String projectId,
  String name,
  String clientId,
  int Function() clock,
) async {
  final DatabaseId databaseId = DatabaseId.forProject(projectId);
  final SQLitePersistence persistence =
      await SQLitePersistence.createWithLease(
    name,
    databaseId,
    LocalSerializer(RemoteSerializer(databaseId)),
    (String path,
            {int? version,
            OnConfigure? onConfigure,
            OnCreate? onCreate,
            OnVersionChange? onUpgrade,
            OnVersionChange? onDowngrade,
            OnOpen? onOpen}) =>
        DatabaseMock.create(name,
            version: version,
            onConfigure: onConfigure,
            onCreate: onCreate,
            onUpgrade: onUpgrade,
            onDowngrade: onDowngrade,
            onOpen: onOpen),
    const LruGarbageCollectorParams(),
    clientId: clientId,
    clock: clock,
    leaseMode: PrimaryLeaseMode.multipleClients,
  );
  await persistence.start();
  return persistence;
}
