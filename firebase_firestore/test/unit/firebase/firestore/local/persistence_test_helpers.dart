// File created by
// Lung Razvan <long1eu>
// on 30/09/2018

import 'dart:async';

import 'package:firebase_firestore/src/firebase/firestore/local/local_serializer.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/memory_persistence.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/sqlite_persistence.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/database_id.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/database.dart';

import 'mock/database_mock.dart';

/// A counter for generating unique database names.
int _databaseNameCounter = 0;

Future<SQLitePersistence> openSQLitePersistence(String name) async {
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
  );
  await persistence.start();
  return persistence;
}

String nextSQLiteDatabaseName() => 'test-${_databaseNameCounter++}';

/// Creates and starts a new [SQLitePersistence] instance for testing.
/// Returns a new [SQLitePersistence] with an empty database and an up-to-date
/// schema.
Future<SQLitePersistence> createSQLitePersistence() {
  return openSQLitePersistence(nextSQLiteDatabaseName());
}

/// Creates and starts a new [MemoryPersistence] instance for testing.
Future<MemoryPersistence> createEagerGCMemoryPersistence() async {
  final MemoryPersistence persistence =
      MemoryPersistence.createEagerGcMemoryPersistence();
  await persistence.start();
  return persistence;
}

Future<MemoryPersistence> createLRUMemoryPersistence() async {
  final MemoryPersistence persistence =
      MemoryPersistence.createLruGcMemoryPersistence();
  await persistence.start();
  return persistence;
}
