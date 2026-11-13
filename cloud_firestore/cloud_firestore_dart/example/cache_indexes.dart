// Persistent cache indexes: make queries against the local SQLite cache faster
// (offline, `Source.cache`, and the first results of a listener).
//
// A cache index only exists inside the SDK, on this device. It is not a Cloud
// Firestore index and it never changes what a query returns, only how many
// cached documents the SDK has to read to answer it.
//
// The opener is in sqlite_database.dart (package:sqlite3).
//
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run example/cache_indexes.dart

import 'dart:io';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

import 'common.dart';
import 'sqlite_database.dart';

Future<void> main() async {
  final Directory directory = Directory.systemTemp.createTempSync(
    'firestore_example_',
  );

  final Firestore firestore = Firestore.instanceFor(
    app: exampleApp(),
    // Cache indexes need the persistent cache: with a memory cache
    // `persistentCacheIndexManager` is null.
    openDatabase: sqliteOpener(directory),
    settings: emulatorSettings(cacheSettings: PersistentCacheSettings()),
  );

  // Let the SDK create indexes on its own. When a cache query had to scan at
  // least 100 cached documents and less than half of them were results, the
  // SDK creates an index for that query. The setting is not stored: turn it
  // on every time the instance is created.
  final PersistentCacheIndexManager indexes =
      firestore.persistentCacheIndexManager!;
  await indexes.enableIndexAutoCreation();

  // 150 cities, 5 of them in the country we will ask for.
  final CollectionReference<Map<String, Object?>> cities = firestore.collection(
    scratch('cities'),
  );
  final WriteBatch batch = firestore.batch();
  for (int i = 0; i < 150; i++) {
    batch.set(cities.doc('city$i'), <String, Object?>{
      'country': i < 5 ? 'RO' : 'other',
      'population': 1000 * i,
    });
  }
  await batch.commit();
  // Read the collection once so that the documents are in the cache as the
  // backend has them.
  await cities.get(Source.server);

  final Query<Map<String, Object?>> romanian = cities
      .whereEqualTo('country', 'RO')
      .orderBy('population');

  // The first cache query scans the 150 cached documents; the SDK notices
  // that an index would help and creates one.
  QuerySnapshot<Map<String, Object?>> snapshot = await romanian.get(
    Source.cache,
  );
  print('first run: ${snapshot.docs.length} cities (collection scan)');

  // The index is filled in the background, 50 documents per run: a first run
  // 15 seconds after the instance started, then one per minute. Queries use
  // the index as far as it is filled and read the rest of the collection, so
  // the result is the same at every moment.
  snapshot = await romanian.get(Source.cache);
  print(
    'second run: ${snapshot.docs.length} cities '
    '(index, plus the documents that are not indexed yet)',
  );

  // Stop creating new indexes; the ones that exist keep being used.
  await indexes.disableIndexAutoCreation();

  // Remove all cache indexes. Queries go back to scanning.
  await indexes.deleteAllIndexes();
  snapshot = await romanian.get(Source.cache);
  print('after deleteAllIndexes: ${snapshot.docs.length} cities');

  await firestore.terminate();
  directory.deleteSync(recursive: true);
}
