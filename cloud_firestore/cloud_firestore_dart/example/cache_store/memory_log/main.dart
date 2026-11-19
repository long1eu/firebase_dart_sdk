// Writes offline with the cache in a MemoryLogStore, "restarts" with a new instance (and a new store object over the
// same log file), and reads the writes back: they are still pending, and are sent once the app is online again.
//
//     dart run example/cache_store/memory_log/main.dart

import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore_dart/cache_store.dart';
import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';

import 'memory_log_store.dart';

Future<void> main() async {
  final Directory directory = Directory.systemTemp.createTempSync(
    'memory_log_store_',
  );
  final String path = '${directory.path}/firestore.log';
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'demo-key',
      appId: '1:1234567890:dart:example',
      projectId: 'demo-example',
    ),
  );

  FirebaseFirestore open() => FirebaseFirestore.instanceFor(
    app: app,
    settings: Settings(
      cacheSettings: keyValueCacheSettings(store: MemoryLogStore(path)),
      // Nothing listens on port 1: the writes stay pending, as on a device
      // without a connection. An app uses the settings of its project.
    ).withEmulator('127.0.0.1', 1),
  );

  // First run: write offline. The futures of the writes complete when the
  // backend accepts them, so they are not awaited.
  FirebaseFirestore firestore = open();
  unawaited(firestore.doc('notes/1').set(<String, Object?>{'text': 'milk'}));
  unawaited(firestore.doc('notes/2').set(<String, Object?>{'text': 'eggs'}));
  unawaited(firestore.doc('notes/1').update(<String, Object?>{'done': true}));
  print('pending writes: ${await firestore.getPendingWriteCount()}');
  await firestore.terminate();
  print('log file: ${File(path).lengthSync()} bytes');

  // "Restart": a new instance, a new store over the same file.
  firestore = open();
  final QuerySnapshot<Map<String, Object?>> notes = await firestore
      .collection('notes')
      .get(GetOptions(source: Source.cache));
  for (final QueryDocumentSnapshot<Map<String, Object?>> note in notes.docs) {
    print(
      '${note.id}: ${note.data()} '
      '(pending: ${note.metadata.hasPendingWrites})',
    );
  }
  print(
    'pending writes after the restart: '
    '${await firestore.getPendingWriteCount()}',
  );

  await firestore.terminate();
  await app.delete();
  directory.deleteSync(recursive: true);
}
