// The IndexedDB cache engine (IndexedDbCacheSettings, first slice) in a browser against the emulator: writes, reads,
// listeners and a restart, and opening the database the official JS SDK left (js_sdk_cache_fixture.json): its pending
// writes are sent by this SDK without an import.
//
//   dart test -j 1 -p chrome -c dart2wasm test/browser/web_indexeddb_engine_test.dart

@TestOn('browser')
library;

import 'dart:async';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/internal_access.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';

import 'browser_test_util.dart'
    show emulatorHost, emulatorPort, loadEmulatorPort, newCollectionName;
import 'js_sdk_cache_fixture.dart';

int _names = 0;
String newAppName() =>
    'idb-engine-${DateTime.now().microsecondsSinceEpoch}-${_names++}';

final Map<FirebaseFirestore, FirebaseApp> _apps =
    <FirebaseFirestore, FirebaseApp>{};

Future<void> shutDown(FirebaseFirestore firestore) async {
  await firestore.terminate();
  await _apps.remove(firestore)?.delete();
}

/// A client of project demo-idb (the one of the fixture) on the IndexedDB engine, or on a memory cache.
Future<FirebaseFirestore> newClient(
  String appName, {
  bool memory = false,
}) async {
  await loadEmulatorPort();
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'demo-key',
      appId: '1:1234567890:dart:browser',
      projectId: 'demo-idb',
    ),
    name: appName,
  );
  final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
    app: app,
    settings: Settings(
      cacheSettings: memory
          ? const MemoryCacheSettings()
          : IndexedDbCacheSettings(),
    ).withEmulator(emulatorHost, emulatorPort),
  );
  _apps[firestore] = app;
  addTearDown(() => shutDown(firestore));
  await firestore.initialized;
  return firestore;
}

const GetOptions cache = GetOptions(source: Source.cache);
const GetOptions server = GetOptions(source: Source.server);

void main() {
  test('writes, reads and a listener, and the cache after a restart', () async {
    final String appName = newAppName();
    final String name = newCollectionName();
    FirebaseFirestore firestore = await newClient(appName);
    CollectionReference<Map<String, Object?>> collection = firestore.collection(
      name,
    );

    final List<QuerySnapshot<Map<String, Object?>>> events =
        <QuerySnapshot<Map<String, Object?>>>[];
    final StreamSubscription<QuerySnapshot<Map<String, Object?>>> sub =
        collection.orderBy('n').snapshots().listen(events.add);

    for (int i = 0; i < 20; i++) {
      await collection.doc('doc$i').set(<String, Object?>{
        'n': i,
        'text': 'value $i',
        'when': FieldValue.serverTimestamp(),
        'tags': <String>['a', 'b'],
      });
    }
    await collection.doc('doc3').update(<String, Object?>{
      'n': FieldValue.increment(100),
      'tags': FieldValue.arrayUnion(<String>['c']),
    });
    await collection.doc('doc4').delete();
    await firestore.waitForPendingWrites();
    expect(await firestore.getPendingWriteCount(), 0);

    final QuerySnapshot<Map<String, Object?>> fromServer = await collection
        .orderBy('n')
        .get(server);
    expect(fromServer.docs, hasLength(19));
    expect(fromServer.docs.last.id, 'doc3');
    expect(fromServer.docs.last['n'], 103);
    expect(fromServer.docs.last['tags'], <String>['a', 'b', 'c']);
    expect(fromServer.docs.first['when'], isA<Timestamp>());

    // The listener ends in sync with the backend.
    await Future.doWhile(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return events.isEmpty ||
          events.last.metadata.isFromCache ||
          events.last.metadata.hasPendingWrites ||
          events.last.docs.length != 19;
    }).timeout(const Duration(seconds: 20));
    expect(events.last.docs.last['n'], 103);
    await sub.cancel();

    // Offline: the cache answers, and writes wait.
    await firestore.disableNetwork();
    final QuerySnapshot<Map<String, Object?>> offline = await collection
        .where('n', isLessThan: 10)
        .orderBy('n')
        .get(cache);
    expect(
      offline.docs.map((QueryDocumentSnapshot<Map<String, Object?>> d) => d.id),
      <String>['doc0', 'doc1', 'doc2', 'doc5', 'doc6', 'doc7', 'doc8', 'doc9'],
    );
    collection.doc('doc0').update(<String, Object?>{
      'text': 'offline',
    }).ignore();
    collection.doc('new').set(<String, Object?>{'n': 5.5}).ignore();
    expect((await collection.doc('doc0').get(cache))['text'], 'offline');
    expect(await firestore.getPendingWriteCount(), 2);

    // A restart: the documents and the two writes are still there, and the writes are sent.
    await shutDown(firestore);
    firestore = await newClient(appName);
    collection = firestore.collection(name);
    await firestore.disableNetwork();
    expect(await firestore.getPendingWriteCount(), 2);
    final QuerySnapshot<Map<String, Object?>> afterRestart = await collection
        .orderBy('n')
        .get(cache);
    expect(afterRestart.docs, hasLength(20));
    expect(afterRestart.docs.first['text'], 'offline');
    expect(afterRestart.docs.first.metadata.hasPendingWrites, isTrue);

    await firestore.enableNetwork();
    await firestore.waitForPendingWrites();
    expect(await firestore.getPendingWriteCount(), 0);
    expect((await collection.doc('doc0').get(server))['text'], 'offline');
    expect((await collection.doc('new').get(server))['n'], 5.5);
  });

  test('opens the database the JS SDK left and sends its pending writes', () async {
    // What the backend holds before: the writes of the fixture update items/cached1 and need it to exist.
    final FirebaseFirestore other = await newClient(newAppName(), memory: true);
    final CollectionReference<Map<String, Object?>> items = other.collection(
      'items',
    );
    for (final String id in <String>['w1', 'w2', 'b1', 'gone']) {
      await items.doc(id).delete();
    }
    await items.doc('cached1').set(<String, Object?>{'title': 'from bundle'});
    await items.doc('w3').set(<String, Object?>{'old': true});
    await items.doc('b2').set(<String, Object?>{'old': true});

    // The JS app had this app's name, so this is the database the engine opens.
    final String appName = newAppName();
    await loadJsSdkCacheFixture(
      databaseName: 'firestore/$appName/demo-idb/main',
    );
    final FirebaseFirestore firestore = await newClient(appName);
    await firestore.disableNetwork();
    expect(await firestore.getPendingWriteCount(), 5);
    expect(
      (await firestore.doc('items/w2').get(cache)).data(),
      <String, Object?>{
        'count': 6,
        'nested': <String, Object?>{'field': 'v'},
        'tags': <String>['a', 'b'],
      },
    );
    final DocumentSnapshot<Map<String, Object?>> cached1 = await firestore
        .doc('items/cached1')
        .get(cache);
    expect(cached1['title'], 'updated offline');
    expect(cached1['n'], 42);
    expect(cached1.metadata.hasPendingWrites, isTrue);
    expect((await firestore.doc('items/w3').get(cache)).exists, isFalse);

    await firestore.enableNetwork();
    await firestore.waitForPendingWrites();
    expect(await firestore.getPendingWriteCount(), 0);

    final Map<String, Object?> w1 = (await items.doc('w1').get(server)).data()!;
    expect(w1['title'], 'written offline');
    expect(w1['a'], <Object?>[1, 'two']);
    expect(w1['st'], isA<Timestamp>());
    expect((await items.doc('w2').get(server)).data(), <String, Object?>{
      'count': 6,
      'nested': <String, Object?>{'field': 'v'},
      'tags': <String>['a', 'b'],
    });
    expect((await items.doc('w3').get(server)).exists, isFalse);
    expect((await items.doc('b1').get(server)).data(), <String, Object?>{
      'inBatch': true,
    });
    expect((await items.doc('b2').get(server)).exists, isFalse);
    expect(
      (await items.doc('cached1').get(server))['title'],
      'updated offline',
    );
  });
}
