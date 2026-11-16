// Measures one query from the server and from the cache with a Stopwatch, for
// the three kinds of cache: memory with eager garbage collection (the default
// without an openDatabase), memory with LRU garbage collection, and SQLite.
// Also shows that a second listener on the same query shares the first one's
// target and gets its first snapshot without a new request.
//
// The numbers depend on your machine and on the emulator, which answers much
// faster than a real backend over the internet; compare them with each other,
// not with production.
//
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run example/performance/cache_vs_server.dart

import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

import '../common.dart';
import '../sqlite_database.dart';

const int documentCount = 1000;

Future<void> main() async {
  final Directory directory = Directory.systemTemp.createTempSync(
    'firestore_example_',
  );
  final String collectionPath = scratch('products');

  // Fill the collection once, with its own instance.
  final FirebaseFirestore writer = connect('writer');
  final CollectionReference<Map<String, Object?>> products = writer.collection(
    collectionPath,
  );
  for (int start = 0; start < documentCount; start += 250) {
    final WriteBatch batch = writer.batch();
    for (int i = start; i < start + 250; i++) {
      batch.set(products.doc('p$i'), <String, Object?>{
        'category': i % 10,
        'price': i,
      });
    }
    await batch.commit();
  }
  await writer.terminate();

  final Map<String, FirebaseFirestore> clients = <String, FirebaseFirestore>{
    'memory, eager GC': FirebaseFirestore.instanceFor(
      app: exampleApp('eager'),
      settings: emulatorSettings(),
    ),
    'memory, LRU GC': FirebaseFirestore.instanceFor(
      app: exampleApp('lru'),
      settings: emulatorSettings(
        cacheSettings: MemoryCacheSettings(gcSettings: MemoryLruGcSettings()),
      ),
    ),
    'SQLite': FirebaseFirestore.instanceFor(
      app: exampleApp('sqlite'),
      openDatabase: sqliteOpener(directory),
      settings: emulatorSettings(cacheSettings: PersistentCacheSettings()),
    ),
  };

  for (final MapEntry<String, FirebaseFirestore> entry in clients.entries) {
    final FirebaseFirestore firestore = entry.value;
    final Query<Map<String, Object?>> cheap = firestore
        .collection(collectionPath)
        .where('category', isEqualTo: 3);

    // The first call also opens the connection (and the SQLite file): run it
    // once before measuring.
    await cheap.limit(1).get(Source.server);

    final Stopwatch server = Stopwatch()..start();
    final QuerySnapshot<Map<String, Object?>> fromServer = await cheap.get(
      Source.server,
    );
    server.stop();

    final Stopwatch cache = Stopwatch()..start();
    final QuerySnapshot<Map<String, Object?>> fromCache = await cheap.get(
      Source.cache,
    );
    cache.stop();

    // With eager garbage collection (the default memory cache) the documents
    // leave the cache as soon as the get() has its result: a cache read finds
    // only what an active listener or a pending write holds.
    print(
      '${entry.key}: server ${fromServer.length} documents in '
      '${server.elapsedMilliseconds} ms, cache ${fromCache.length} documents in '
      '${cache.elapsedMilliseconds} ms',
    );
  }

  // Listener reuse: the second listener on an equal query joins the first
  // one's target. Its first snapshot comes from the view that already exists.
  final FirebaseFirestore firestore = clients['SQLite']!;
  final Query<Map<String, Object?>> query = firestore
      .collection(collectionPath)
      .where('category', isEqualTo: 5);

  final Stopwatch first = Stopwatch()..start();
  final Completer<void> firstSynced = Completer<void>();
  final StreamSubscription<QuerySnapshot<Map<String, Object?>>> one = query
      .snapshots
      .listen((QuerySnapshot<Map<String, Object?>> snapshot) {
        if (!snapshot.metadata.isFromCache && !firstSynced.isCompleted) {
          first.stop();
          firstSynced.complete();
        }
      });
  await firstSynced.future;

  final Stopwatch second = Stopwatch()..start();
  final Completer<QuerySnapshot<Map<String, Object?>>> secondFirst =
      Completer<QuerySnapshot<Map<String, Object?>>>();
  final StreamSubscription<QuerySnapshot<Map<String, Object?>>> two = query
      .snapshots
      .listen((QuerySnapshot<Map<String, Object?>> snapshot) {
        if (!secondFirst.isCompleted) {
          second.stop();
          secondFirst.complete(snapshot);
        }
      });
  final QuerySnapshot<Map<String, Object?>> shared = await secondFirst.future;
  print(
    'first listener in sync after ${first.elapsedMilliseconds} ms; '
    'second listener on the same query: first snapshot after '
    '${second.elapsedMilliseconds} ms, from cache: '
    '${shared.metadata.isFromCache}',
  );
  await one.cancel();
  await two.cancel();

  for (final FirebaseFirestore client in clients.values) {
    await client.terminate();
  }
  directory.deleteSync(recursive: true);
}
