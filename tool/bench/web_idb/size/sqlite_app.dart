// The size measurement of docs/spikes/indexeddb_cache.md: a small app with
// the SQLite cache of cloud_firestore_dart_sqlite (IndexedDB, or OPFS
// with the worker). tool/size/full_app.dart with only the opener changed.
// Compiled by size.sh, never run.

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart_sqlite/cloud_firestore_dart_sqlite.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';

Future<void> main() async {
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'key',
      appId: 'appId',
      projectId: 'demo-size',
    ),
    name: 'size',
  );
  final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
    app: app,
    openDatabase: sqliteOpener(
      sqlite3Wasm: Uri.parse('sqlite3.wasm'),
      opfsWorker: Uri.parse('sqlite_opfs_worker.js'),
    ),
    settings: Settings(
      cacheSettings: PersistentCacheSettings(),
    ).withEmulator('127.0.0.1', 8080),
  );
  final CollectionReference<Map<String, Object?>> cities = firestore.collection(
    'cities',
  );
  await cities.doc('SF').set(<String, Object?>{
    'name': 'San Francisco',
    'population': 800000,
  });
  await cities.doc('SF').update(<String, Object?>{
    'visits': FieldValue.increment(1),
  });
  print((await cities.doc('SF').get()).data());
  final QuerySnapshot<Map<String, Object?>> big = await cities
      .where('population', isGreaterThan: 100000)
      .orderBy('population')
      .limitToLast(2)
      .get();
  print(big.docs.length);
  print((await cities.count().get()).count);
  await (firestore.batch()..delete(cities.doc('LA'))).commit();
  await firestore.runTransaction<void>((Transaction transaction) async {
    final DocumentSnapshot<Map<String, Object?>> snapshot = await transaction
        .get(cities.doc('SF'));
    transaction.update(cities.doc('SF'), <String, Object?>{
      'seen': snapshot.exists,
    });
  });
  await firestore.terminate();
}
