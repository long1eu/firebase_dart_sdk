// Lifecycle: log level, waiting for pending writes, terminating an instance
// and clearing its persistent cache.
//
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run example/lifecycle.dart

import 'dart:io';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';

import 'common.dart';
import 'sqlite_database.dart';

Future<void> main() async {
  // Log level: `error` (the default) prints warnings and errors, `debug`
  // prints everything the SDK does, `silent` nothing. It applies to all
  // instances.
  Firestore.setLogLevel(LogLevel.silent);

  final Directory directory = Directory.systemTemp.createTempSync(
    'firestore_example_',
  );
  final FirebaseApp app = exampleApp();
  Future<Firestore> open() {
    return Firestore.instanceFor(
      app: app,
      openDatabase: sqliteOpener(directory),
      settings: emulatorSettings(cacheSettings: PersistentCacheSettings()),
    );
  }

  bool hasDatabaseFile() => directory.listSync().isNotEmpty;

  Firestore firestore = await open();
  final String path = '${scratch('settings')}/theme';

  // waitForPendingWrites completes when the backend has acknowledged every
  // write that was pending when it was called.
  await firestore.disableNetwork();
  final Future<void> write = firestore.doc(path).set(<String, Object?>{
    'dark': true,
  });
  await firestore.enableNetwork();
  await firestore.waitForPendingWrites();
  await write;
  print('pending writes are on the backend');

  // snapshotsInSync fires when all listeners are in sync with each other.
  final Future<void> inSync = firestore.snapshotsInSync.first;
  final subscription = firestore.doc(path).snapshots.listen((_) {});
  await inSync;
  await subscription.cancel();
  print('listeners are in sync');

  // terminate releases the connection, the timers and the database file. The
  // instance cannot be used afterwards: every operation fails with a
  // FirestoreError with the code failedPrecondition.
  await firestore.terminate();
  try {
    await firestore.doc(path).get();
  } on FirestoreError catch (e) {
    print('after terminate: ${e.code} (${e.message})');
  }

  // clearPersistence deletes the cache file of a terminated instance.
  print('database file before clearPersistence: ${hasDatabaseFile()}');
  await firestore.clearPersistence();
  print('database file after clearPersistence: ${hasDatabaseFile()}');

  // The same app and database can be opened again; the cache starts empty
  // and the data is still on the backend.
  firestore = await open();
  try {
    await firestore.doc(path).get(Source.cache);
  } on FirestoreError catch (e) {
    print('cache after clear: ${e.code}');
  }
  print('server: ${(await firestore.doc(path).get(Source.server)).data}');

  await firestore.terminate();
  directory.deleteSync(recursive: true);
}
