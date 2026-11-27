// The ```dart samples of the doc comments, compiled and run. Each sample's body is copied as it is
// written in the doc comment; the free names it uses (`app`, `supportDirectory`, `MyEngine`) are
// given here. Each database is closed before its store finishes opening, so no Repo starts and
// nothing connects.
@TestOn('vm')
library;

import 'dart:io';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:firebase_database_dart/storage_engine.dart';
import 'package:firebase_database_dart_sqlite/firebase_database_dart_sqlite.dart';
import 'package:test/test.dart';

/// The engine of the `storage_engine.dart` sample.
abstract final class MyEngine {
  static int opens = 0;

  static PersistenceStorageEngine open(
    PersistenceKey key,
    DatabaseLogger? logger,
  ) {
    opens++;
    return InMemoryPersistenceStorageEngine();
  }
}

// lib/firebase_database_dart_sqlite.dart, library doc.
FirebaseDatabase librarySample(FirebaseApp app, String supportDirectory) {
  final FirebaseDatabase database = FirebaseDatabase(
    app,
    persistence: sqlitePersistence('$supportDirectory/firebase_database'),
  );
  return database;
}

// ../firebase_database_dart/lib/storage_engine.dart, library doc.
FirebaseDatabase storageEngineSample(FirebaseApp app) {
  final FirebaseDatabase db = FirebaseDatabase(
    app,
    persistence: databasePersistence(
      opener: (PersistenceKey key, {DatabaseLogger? logger}) async =>
          MyEngine.open(key, logger),
      cacheSizeBytes: 20 * 1024 * 1024,
    ),
  );
  return db;
}

int _apps = 0;

void main() {
  late Directory temp;
  late FirebaseApp app;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('rtdb_doc_samples_');
    app = FirebaseApp.withOptions(
      const FirebaseOptions(
        apiKey: 'test-key',
        appId: '1:1234567890:dart:test',
        projectId: 'demo-test',
      ),
      name: 'doc-samples-${_apps++}',
    );
  });
  tearDown(() => temp.deleteSync(recursive: true));

  test('the library sample opens a store in the directory', () async {
    final FirebaseDatabase database = librarySample(app, temp.path);
    await database.close();

    final List<FileSystemEntity> files = Directory(
      '${temp.path}/firebase_database',
    ).listSync();
    expect(
      files.map((FileSystemEntity f) => f.uri.pathSegments.last),
      contains(matches(RegExp(r'^rtdb-[0-9a-f]{32}\.sqlite$'))),
    );
  });

  test('the storage_engine sample opens its engine once', () async {
    final FirebaseDatabase db = storageEngineSample(app);
    await db.close();

    expect(MyEngine.opens, 1);
  });
}
