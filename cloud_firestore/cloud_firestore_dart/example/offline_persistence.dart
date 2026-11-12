// Offline persistence: keep the cache in a SQLite file so that data survives a
// restart and can be read without a connection.
//
// The opener is in sqlite_database.dart (package:sqlite3).
//
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run example/offline_persistence.dart

import 'dart:io';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';

import 'common.dart';
import 'sqlite_database.dart';

Future<void> main() async {
  // Where the database file lives is your choice; here a temporary directory
  // that is removed at the end.
  final Directory directory =
      Directory.systemTemp.createTempSync('firestore_example_');
  final FirebaseApp app = exampleApp();

  Future<Firestore> open() {
    return Firestore.instanceFor(
      app: app,
      // Without `openDatabase` the cache is in memory, whatever the settings.
      openDatabase: sqliteOpener(directory),
      settings: emulatorSettings(
        cacheSettings: PersistentCacheSettings(sizeBytes: 100 * 1024 * 1024),
      ),
    );
  }

  final String path = '${scratch('notes')}/first';

  // First run: write a document; it is stored in the cache and sent to the
  // backend.
  Firestore firestore = await open();
  await firestore.doc(path).set(<String, Object?>{'text': 'written online'});
  await firestore.terminate();
  print('database files: ${<String>[
    for (final FileSystemEntity file in directory.listSync())
      file.uri.pathSegments.last,
  ]}');

  // "Restart": a new instance on the same file. With the network disabled,
  // everything is answered from the cache.
  firestore = await open();
  await firestore.disableNetwork();
  final DocumentSnapshot<Map<String, Object?>> cached =
      await firestore.doc(path).get();
  print('offline read: ${cached.data} '
      '(from cache: ${cached.metadata.isFromCache})');

  // Writes made offline are kept in the file. Their future completes only
  // when the backend has accepted them, so it is not awaited here; listeners
  // and cache reads see the write immediately.
  final Future<void> pendingWrite =
      firestore.doc(path).update(<String, Object?>{'text': 'changed offline'});
  final DocumentSnapshot<Map<String, Object?>> local =
      await firestore.doc(path).get(Source.cache);
  print('offline write: ${local.data} '
      '(pending: ${local.metadata.hasPendingWrites})');

  // Back online the pending write is sent.
  await firestore.enableNetwork();
  await pendingWrite;
  final DocumentSnapshot<Map<String, Object?>> synced =
      await firestore.doc(path).get(Source.server);
  print('after sync: ${synced.data}');

  await firestore.terminate();
  directory.deleteSync(recursive: true);
}
