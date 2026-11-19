// Writes offline with the cache in an IndexedDbCacheStore, "restarts" with a new instance (and a new store object over
// the same IndexedDB database), and reads the writes back: they are still pending, and are sent once the app is online
// again. Reload the page and the count of pending writes keeps growing: the database outlives the page.
//
//     dart compile js -o example/cache_store/indexeddb/main.dart.js example/cache_store/indexeddb/main.dart
//     python3 -m http.server -d example/cache_store/indexeddb 8000    # then open http://localhost:8000

import 'dart:async';

import 'package:cloud_firestore_dart/cache_store.dart';
import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:web/web.dart' as web;

import 'indexeddb_cache_store.dart';

void show(String line) {
  print(line);
  web.document.body?.append(
    web.document.createElement('pre')..textContent = line,
  );
}

Future<void> main() async {
  const String database = 'cache_store_example';
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'demo-key',
      appId: '1:1234567890:web:example',
      projectId: 'demo-example',
    ),
  );

  FirebaseFirestore open() => FirebaseFirestore.instanceFor(
    app: app,
    settings: Settings(
      cacheSettings: keyValueCacheSettings(
        store: IndexedDbCacheStore(database),
      ),
      // Nothing listens on port 1: the writes stay pending, as on a device
      // without a connection. An app uses the settings of its project.
    ).withEmulator('127.0.0.1', 1),
  );

  // First run: write offline. The futures of the writes complete when the
  // backend accepts them, so they are not awaited.
  FirebaseFirestore firestore = open();
  final String id = DateTime.now().millisecondsSinceEpoch.toString();
  unawaited(firestore.doc('notes/$id').set(<String, Object?>{'text': 'milk'}));
  unawaited(firestore.doc('notes/$id').update(<String, Object?>{'done': true}));
  show('pending writes: ${await firestore.getPendingWriteCount()}');
  await firestore.terminate();

  // "Restart": a new instance, a new store over the same database.
  firestore = open();
  final QuerySnapshot<Map<String, Object?>> notes = await firestore
      .collection('notes')
      .get(GetOptions(source: Source.cache));
  for (final QueryDocumentSnapshot<Map<String, Object?>> note in notes.docs) {
    show(
      '${note.id}: ${note.data()} '
      '(pending: ${note.metadata.hasPendingWrites})',
    );
  }
  show(
    'pending writes after the restart: '
    '${await firestore.getPendingWriteCount()}',
  );

  await firestore.terminate();
  await app.delete();
}
