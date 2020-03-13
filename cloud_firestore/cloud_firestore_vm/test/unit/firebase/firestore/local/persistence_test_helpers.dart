// File created by
// Lung Razvan <long1eu>
// on 30/09/2018

import 'dart:async';

import 'package:cloud_firestore_vm/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/memory_persistence.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/sqlite_persistence.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/database.dart';
import 'package:uuid/uuid.dart';

import 'mock/database_mock.dart';

Future<SQLitePersistence> openSQLitePersistence(String name,
    [LruGarbageCollectorParams params =
        const LruGarbageCollectorParams()]) async {
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
  );
  await persistence.start();
  return persistence;
}

/// Creates and starts a new [SQLitePersistence] instance for testing.
///
/// Returns a new [SQLitePersistence] with an empty database and an up-to-date schema.
Future<SQLitePersistence> createSQLitePersistence(
    [LruGarbageCollectorParams params = const LruGarbageCollectorParams()]) {
  return openSQLitePersistence('test-${Uuid().v4()}', params);
}

/// Creates and starts a new [MemoryPersistence] instance for testing.
Future<MemoryPersistence> createEagerGCMemoryPersistence() async {
  final MemoryPersistence persistence =
      MemoryPersistence.createEagerGcMemoryPersistence();
  await persistence.start();
  return persistence;
}

Future<MemoryPersistence> createLRUMemoryPersistence(
    [LruGarbageCollectorParams params =
        const LruGarbageCollectorParams()]) async {
  final DatabaseId databaseId = DatabaseId.forProject('projectId');
  final LocalSerializer serializer =
      LocalSerializer(RemoteSerializer(databaseId));
  final MemoryPersistence persistence =
      MemoryPersistence.createLruGcMemoryPersistence(params, serializer);
  await persistence.start();
  return persistence;
}
