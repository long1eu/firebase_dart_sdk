// File created by
// Lung Razvan <long1eu>
// on 30/09/2018

import 'dart:async';

import 'package:cloud_firestore_vm/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/memory/memory_persistence.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistence/stats_collector.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/database.dart';
import 'package:uuid/uuid.dart';

import 'mock/database_mock.dart';

Future<SQLitePersistence> createSQLitePersistence([
  String name,
  LruGarbageCollectorParams params = const LruGarbageCollectorParams(),
  StatsCollector statsCollector = StatsCollector.noOp,
]) async {
  name ??= 'test-${Uuid().v4()}';
  final DatabaseId databaseId = DatabaseId.forProject('projectId');
  final LocalSerializer serializer =
      LocalSerializer(RemoteSerializer(databaseId));

  final SQLitePersistence persistence = await SQLitePersistence.create(
    name,
    databaseId,
    serializer,
    (String path,
            {int version,
            OnConfigure onConfigure,
            OnCreate onCreate,
            OnVersionChange onUpgrade,
            OnVersionChange onDowngrade,
            OnOpen onOpen}) =>
        DatabaseMock.create(name,
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
