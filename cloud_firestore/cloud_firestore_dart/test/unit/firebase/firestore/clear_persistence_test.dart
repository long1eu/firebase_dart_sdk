import 'dart:io';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_database_files.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'local/mock/database_mock.dart';

import '../../../util/test_hygiene.dart';

/// An [OpenDatabase] that always opens the file of [dbName], keeping it when
/// the database is closed (like a real app restart).
OpenDatabase openFixed(String dbName) {
  return (String path,
      {int? version,
      OnConfigure? onConfigure,
      OnCreate? onCreate,
      OnVersionChange? onUpgrade,
      OnVersionChange? onDowngrade,
      OnOpen? onOpen}) async {
    final DatabaseMock db = await DatabaseMock.create(dbName,
        version: version,
        onConfigure: onConfigure,
        onCreate: onCreate,
        onUpgrade: onUpgrade,
        onDowngrade: onDowngrade,
        onOpen: onOpen);
    db.renamePath = false;
    return db;
  };
}

/// Like [openFixed], for a database that clears its own storage.
OpenDatabase openSelfClearing(String dbName, List<String> calls,
    {bool fail = false}) {
  return (String path,
      {int? version,
      OnConfigure? onConfigure,
      OnCreate? onCreate,
      OnVersionChange? onUpgrade,
      OnVersionChange? onDowngrade,
      OnOpen? onOpen}) async {
    late final _SelfClearingDatabase db;
    // The callbacks get the database Firestore will use.
    final DatabaseMock mock = await DatabaseMock.create(dbName,
        version: version,
        onConfigure: onConfigure,
        onCreate: onCreate,
        onUpgrade: onUpgrade,
        onDowngrade: onDowngrade,
        onOpen: onOpen);
    mock.renamePath = false;
    db = _SelfClearingDatabase(mock, calls, fail: fail);
    return db;
  };
}

FirebaseApp newApp(String name) => FirebaseApp.withOptions(
      const FirebaseOptions(
          apiKey: 'key', applicationId: 'appId', projectId: 'projectId'),
      dependencies: null,
      name: name,
    );

/// Points at a port nothing listens on: writes stay pending, nothing reaches a
/// backend.
final FirestoreSettings offlineSettings =
    FirestoreSettings().withEmulator('127.0.0.1', 1);

TypeMatcher<FirestoreError> firestoreErrorWithCode(FirestoreErrorCode code) =>
    isA<FirestoreError>().having((FirestoreError e) => e.code, 'code', code);

void main() {
  checkTestsLeaveNothingBehind();

  group('deleteSqliteDatabaseFiles', () {
    test('deletes the database and its journal, WAL and shm files', () {
      final String dbName = 'clear-${const Uuid().v4()}.db';
      final File file = DatabaseMock.pathForName(dbName);
      addTearDown(() => DatabaseMock.deleteDatabaseFiles(dbName));
      final List<File> all = <File>[
        file,
        for (final String suffix in sqliteSideFileSuffixes)
          File('${file.path}$suffix'),
      ];
      for (final File f in all) {
        f.createSync(recursive: true);
      }
      // A file whose name only starts with the database name is not touched.
      final File other = File('${file.path}-other')..createSync();
      addTearDown(() => other.existsSync() ? other.deleteSync() : null);

      deleteSqliteDatabaseFiles(file.path);

      for (final File f in all) {
        expect(f.existsSync(), isFalse, reason: f.path);
      }
      expect(other.existsSync(), isTrue);
    });

    test('skips files that do not exist', () {
      final File file =
          DatabaseMock.pathForName('clear-missing-${const Uuid().v4()}.db');
      deleteSqliteDatabaseFiles(file.path);
      expect(file.existsSync(), isFalse);
    });
  });

  group('SQLitePersistence.clearPersistence', () {
    final DatabaseId databaseId = DatabaseId.forProject('projectId');

    Future<SQLitePersistence> create(String dbName) {
      return SQLitePersistence.create(
        'key',
        databaseId,
        LocalSerializer(RemoteSerializer(databaseId)),
        openFixed(dbName),
        const LruGarbageCollectorParams(),
      );
    }

    test('deletes the files of the database after shutdown', () async {
      final String dbName = 'clear-${const Uuid().v4()}.db';
      addTearDown(() => DatabaseMock.deleteDatabaseFiles(dbName));
      final File file = DatabaseMock.pathForName(dbName);

      final SQLitePersistence persistence = await create(dbName);
      await persistence.start();
      await persistence.execute(
          'INSERT INTO bundles (bundle_id, create_time_seconds, '
          'create_time_nanos, schema_version, total_documents, total_bytes) '
          'VALUES (?, 0, 0, 1, 0, 0)',
          <Object?>['b']);
      await persistence.shutdown();
      expect(file.existsSync(), isTrue);
      final File wal = File('${file.path}-wal')..createSync();

      await persistence.clearPersistence();
      expect(file.existsSync(), isFalse);
      expect(wal.existsSync(), isFalse);

      // Opening the same file again starts from an empty database.
      final SQLitePersistence again = await create(dbName);
      await again.start();
      addTearDown(again.shutdown);
      expect(await again.query('SELECT bundle_id FROM bundles'), isEmpty);
    });

    test('a ClearableDatabase clears its own storage; no file is deleted',
        () async {
      final String dbName = 'clear-${const Uuid().v4()}.db';
      addTearDown(() => DatabaseMock.deleteDatabaseFiles(dbName));
      final File file = DatabaseMock.pathForName(dbName);
      final List<String> calls = <String>[];

      final SQLitePersistence persistence = await SQLitePersistence.create(
        'key',
        databaseId,
        LocalSerializer(RemoteSerializer(databaseId)),
        openSelfClearing(dbName, calls),
        const LruGarbageCollectorParams(),
      );
      await persistence.start();
      await persistence.shutdown();
      expect(calls, <String>['close']);

      await persistence.clearPersistence();
      // After the close, once, and instead of deleting the file at `path`.
      expect(calls, <String>['close', 'clearStorage']);
      expect(file.existsSync(), isTrue);
    });

    test('an error of clearStorage is reported as unknown', () async {
      final String dbName = 'clear-${const Uuid().v4()}.db';
      addTearDown(() => DatabaseMock.deleteDatabaseFiles(dbName));
      final SQLitePersistence persistence = await SQLitePersistence.create(
        'key',
        databaseId,
        LocalSerializer(RemoteSerializer(databaseId)),
        openSelfClearing(dbName, <String>[], fail: true),
        const LruGarbageCollectorParams(),
      );
      await persistence.start();
      await persistence.shutdown();

      await expectLater(persistence.clearPersistence(),
          throwsA(firestoreErrorWithCode(FirestoreErrorCode.unknown)));
    });

    test('is rejected while the persistence is running', () async {
      final String dbName = 'clear-${const Uuid().v4()}.db';
      addTearDown(() => DatabaseMock.deleteDatabaseFiles(dbName));

      final SQLitePersistence persistence = await create(dbName);
      await persistence.start();
      addTearDown(persistence.shutdown);

      await expectLater(
          persistence.clearPersistence(), throwsA(isA<AssertionError>()));
      expect(DatabaseMock.pathForName(dbName).existsSync(), isTrue);
    });

    test('does nothing when the database was never opened', () async {
      final String dbName = 'clear-${const Uuid().v4()}.db';
      final SQLitePersistence persistence = await create(dbName);
      await persistence.clearPersistence();
      expect(DatabaseMock.pathForName(dbName).existsSync(), isFalse);
    });
  });

  group('Firestore.clearPersistence', () {
    test('fails with failedPrecondition while the instance is running',
        () async {
      final FirebaseApp app = newApp('clearPersistenceRunning');
      addTearDown(app.delete);
      final Firestore firestore =
          Firestore.instanceFor(app: app, settings: offlineSettings);
      addTearDown(firestore.terminate);

      await expectLater(
          firestore.clearPersistence(),
          throwsA(firestoreErrorWithCode(FirestoreErrorCode.failedPrecondition)
              .having(
                  (FirestoreError e) => e.message,
                  'message',
                  'Persistence cannot be cleared while the firestore instance '
                      'is running.')));
    });

    test('is a no-op for memory persistence after terminate', () async {
      final FirebaseApp app = newApp('clearPersistenceMemory');
      addTearDown(app.delete);
      final Firestore firestore = Firestore.instanceFor(
          app: app,
          settings: offlineSettings.copyWith(
              cacheSettings: const MemoryCacheSettings()));
      await firestore.terminate();
      await firestore.clearPersistence();
    });

    test('drops the SQLite cache of a terminated instance', () async {
      final String dbName = 'clear-firestore-${const Uuid().v4()}.db';
      addTearDown(() => DatabaseMock.deleteDatabaseFiles(dbName));
      final FirebaseApp app = newApp('clearPersistenceSqlite');
      addTearDown(app.delete);

      final Firestore firestore = Firestore.instanceFor(
          app: app, settings: offlineSettings, openDatabase: openFixed(dbName));
      final DocumentReference<Map<String, Object?>> doc =
          firestore.doc('col/doc');
      // Never acknowledged (no backend), but applied to the local cache.
      doc.set(<String, Object?>{'a': 1}).ignore();
      expect((await doc.get(Source.cache)).data, <String, Object?>{'a': 1});

      await firestore.terminate();
      await firestore.clearPersistence();
      expect(DatabaseMock.pathForName(dbName).existsSync(), isFalse);
      // Calling it again is fine.
      await firestore.clearPersistence();

      final Firestore restarted = Firestore.instanceFor(
          app: app, settings: offlineSettings, openDatabase: openFixed(dbName));
      addTearDown(restarted.terminate);
      await expectLater(restarted.doc('col/doc').get(Source.cache),
          throwsA(firestoreErrorWithCode(FirestoreErrorCode.unavailable)));
    });

    test('keeps the SQLite cache when the instance is only terminated',
        () async {
      // Control for the test above.
      final String dbName = 'clear-firestore-${const Uuid().v4()}.db';
      addTearDown(() => DatabaseMock.deleteDatabaseFiles(dbName));
      final FirebaseApp app = newApp('clearPersistenceControl');
      addTearDown(app.delete);

      final Firestore firestore = Firestore.instanceFor(
          app: app, settings: offlineSettings, openDatabase: openFixed(dbName));
      firestore.doc('col/doc').set(<String, Object?>{'a': 1}).ignore();
      await firestore.doc('col/doc').get(Source.cache);
      await firestore.terminate();

      final Firestore restarted = Firestore.instanceFor(
          app: app, settings: offlineSettings, openDatabase: openFixed(dbName));
      addTearDown(restarted.terminate);
      expect((await restarted.doc('col/doc').get(Source.cache)).data,
          <String, Object?>{'a': 1});
    });
  });
}

/// A database that keeps its data somewhere `clearPersistence` cannot delete
/// by path, as a database in IndexedDB does.
class _SelfClearingDatabase implements ClearableDatabase {
  _SelfClearingDatabase(this._delegate, this._calls, {this.fail = false});

  final Database _delegate;
  final List<String> _calls;
  final bool fail;

  @override
  String get path => _delegate.path;

  @override
  Future<void> execute(String statement, [List<Object?>? arguments]) =>
      _delegate.execute(statement, arguments);

  @override
  Future<List<Map<String, dynamic>>> query(String statement,
          [List<Object?>? arguments]) =>
      _delegate.query(statement, arguments);

  @override
  Future<int> delete(String statement, [List<Object?>? arguments]) =>
      _delegate.delete(statement, arguments);

  @override
  void close() {
    _calls.add('close');
    _delegate.close();
  }

  @override
  Future<void> clearStorage() async {
    _calls.add('clearStorage');
    if (fail) {
      throw StateError('storage is busy');
    }
  }
}
