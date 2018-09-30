// File created by
// Lung Razvan <long1eu>
// on 30/09/2018

import 'dart:async';

import 'package:firebase_firestore/src/firebase/firestore/local/local_serializer.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/memory_persistence.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/sqlite_persistence.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/database_id.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/database_impl.dart';

import 'mock/database_mock.dart';

class PersistenceTestHelpers {
  /// A counter for generating unique database names.
  static int _databaseNameCounter = 0;

  static Future<SQLitePersistence> openSQLitePersistence(String name) async {
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

  static String nextSQLiteDatabaseName() => 'test-${_databaseNameCounter++}';

  /// Creates and starts a new [SQLitePersistence] instance for testing.
  /// Returns a new [SQLitePersistence] with an empty database and an up-to-date
  /// schema.
  static Future<SQLitePersistence> createSQLitePersistence() {
    return openSQLitePersistence(nextSQLiteDatabaseName());
  }

  /// Creates and starts a new [MemoryPersistence] instance for testing.
  static MemoryPersistence createEagerGCMemoryPersistence() {
    final MemoryPersistence persistence =
        MemoryPersistence.createEagerGcMemoryPersistence();
    persistence.start();
    return persistence;
  }

  static MemoryPersistence createLRUMemoryPersistence() {
    final MemoryPersistence persistence =
        MemoryPersistence.createLruGcMemoryPersistence();
    persistence.start();
    return persistence;
  }
}
