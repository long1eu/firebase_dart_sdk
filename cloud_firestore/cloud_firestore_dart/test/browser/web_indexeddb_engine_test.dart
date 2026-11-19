// The IndexedDB cache engine (IndexedDbCacheSettings) in a browser against the emulator: writes, reads, listeners and a
// restart, opening the database the official JS SDK left (js_sdk_cache_fixture.json): its pending writes are sent by
// this SDK without an import; the primary lease against another client; garbage collection; cache indexes; bundles.
//
//   dart test -j 1 -p chrome -c dart2wasm test/browser/web_indexeddb_engine_test.dart

@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/indexeddb/indexeddb_schema.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/indexeddb/web/idb.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/lru_delegate.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/index_manager.dart';
import 'package:cloud_firestore_dart/src/internal_access.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

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
  IndexedDbCacheSettings? cacheSettings,
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
          : cacheSettings ?? IndexedDbCacheSettings(),
    ).withEmulator(emulatorHost, emulatorPort),
  );
  _apps[firestore] = app;
  addTearDown(() => shutDown(firestore));
  await firestore.initialized;
  return firestore;
}

/// Puts [row] under [key] in [store] of the engine's database of [appName] (it must exist), as another client would.
Future<void> putRow(
  String appName,
  String store,
  Map<String, Object?> row, [
  String? key,
]) async {
  final web.IDBDatabase db =
      (await idbRequest(
            web.window.indexedDB.open('firestore/$appName/demo-idb/main'),
          ))!
          as web.IDBDatabase;
  try {
    final web.IDBTransaction transaction = db.transaction(
      store.toJS,
      'readwrite',
    );
    final Future<void> committed = idbCommitted(transaction);
    final web.IDBObjectStore objects = transaction.objectStore(store);
    if (key == null) {
      objects.put(idbToJs(row));
    } else {
      objects.put(idbToJs(row), key.toJS);
    }
    await committed;
  } finally {
    db.close();
  }
}

/// The number of rows of [store] in the engine's database of [appName].
Future<int> countRows(String appName, String store) async {
  final web.IDBDatabase db =
      (await idbRequest(
            web.window.indexedDB.open('firestore/$appName/demo-idb/main'),
          ))!
          as web.IDBDatabase;
  try {
    final web.IDBTransaction transaction = db.transaction(store.toJS);
    return ((await idbRequest(transaction.objectStore(store).count()))!
            as JSNumber)
        .toDartInt;
  } finally {
    db.close();
  }
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

  test('refuses to open while another client holds the primary lease', () async {
    final String appName = newAppName();
    // Creates the database.
    await shutDown(await newClient(appName));

    // A JS tab that refreshed its lease just now.
    await putRow(appName, DbStores.owner, <String, Object?>{
      'ownerId': 'js-client',
      'allowTabSynchronization': false,
      'leaseTimestampMs': DateTime.now().millisecondsSinceEpoch,
    }, DbStores.ownerKey);
    await expectLater(
      newClient(appName),
      throwsA(
        isA<FirestoreException>().having(
          (FirestoreException e) => e.code,
          'code',
          FirestoreErrorCode.failedPrecondition,
        ),
      ),
    );

    // The same lease 6 s later: it lapsed, the engine takes it.
    await putRow(appName, DbStores.owner, <String, Object?>{
      'ownerId': 'js-client',
      'allowTabSynchronization': false,
      'leaseTimestampMs': DateTime.now().millisecondsSinceEpoch - 6000,
    }, DbStores.ownerKey);
    final FirebaseFirestore firestore = await newClient(appName);
    await firestore.disableNetwork();
    await firestore.doc('a/b').set(<String, Object?>{'x': 1});

    // Another client takes the lease over (as after a lapse in the background): the next operation fails, and nothing
    // more is written.
    await putRow(appName, DbStores.owner, <String, Object?>{
      'ownerId': 'js-client',
      'allowTabSynchronization': false,
      'leaseTimestampMs': DateTime.now().millisecondsSinceEpoch,
    }, DbStores.ownerKey);
    await expectLater(
      firestore.doc('a/c').set(<String, Object?>{'x': 2}),
      throwsA(isA<FirestoreException>()),
    );
  });

  test('collects garbage on the JS SDK sequence numbers', () async {
    final String name = newCollectionName();
    final FirebaseFirestore writer = await newClient(
      newAppName(),
      memory: true,
    );
    for (int i = 0; i < 10; i++) {
      await writer.collection(name).doc('d$i').set(<String, Object?>{'n': i});
    }

    final String appName = newAppName();
    final FirebaseFirestore firestore = await newClient(appName);
    expect((await firestore.collection(name).get(server)).docs, hasLength(10));
    await firestore.collection(name).doc('pending').set(<String, Object?>{
      'n': -1,
    });
    await firestore.disableNetwork();
    firestore.collection(name).doc('d0').update(<String, Object?>{
      'n': 100,
    }).ignore();
    expect(await countRows(appName, DbStores.remoteDocuments), 11);

    final LocalStore localStore = firestore.client.localStore;
    final LruGarbageCollectorResults results = await localStore.collectGarbage(
      LruGarbageCollector(
        firestore.client.persistence.referenceDelegate as LruDelegate,
        const LruGarbageCollectorParams(
          minBytesThreshold: 0,
          percentileToCollect: 100,
          maximumSequenceNumbersToCollect: 1000,
        ),
      ),
    );
    expect(results.hasRun, isTrue);
    expect(results.targetsRemoved, greaterThanOrEqualTo(1));
    // d0 has a pending write and stays; the others go.
    expect(await countRows(appName, DbStores.remoteDocuments), 1);
    expect((await firestore.doc('$name/d0').get(cache))['n'], 100);
    await expectLater(
      firestore.doc('$name/d1').get(cache),
      throwsA(isA<FirestoreException>()),
    );
  });

  test('cache indexes: created, filled and used', () async {
    final String name = newCollectionName();
    final FirebaseFirestore writer = await newClient(
      newAppName(),
      memory: true,
    );
    final WriteBatch batch = writer.batch();
    for (int i = 0; i < 150; i++) {
      batch.set(writer.collection(name).doc('city$i'), <String, Object?>{
        'country': i < 5 ? 'RO' : 'other',
        'population': 1000 * i,
      });
    }
    await batch.commit();

    final String appName = newAppName();
    final FirebaseFirestore firestore = await newClient(
      appName,
      cacheSettings: IndexedDbCacheSettings(indexAutoCreation: true),
    );
    final CollectionReference<Map<String, Object?>> cities = firestore
        .collection(name);
    await cities.get(server);
    final Query<Map<String, Object?>> romanian = cities
        .where('country', isEqualTo: 'RO')
        .orderBy('population');
    final LocalStore localStore = firestore.client.localStore;
    IndexType indexType() => localStore.indexManagerForCurrentUser.getIndexType(
      romanian.query.toTarget(),
    );
    List<String> ids(QuerySnapshot<Map<String, Object?>> snapshot) => <String>[
      for (final QueryDocumentSnapshot<Map<String, Object?>> doc
          in snapshot.docs)
        doc.id,
    ];
    final List<String> expected = <String>[
      for (int i = 0; i < 5; i++) 'city$i',
    ];

    expect(ids(await romanian.get(cache)), expected);
    expect(localStore.getFieldIndexes(), hasLength(1));
    expect(indexType(), IndexType.full);
    expect(await countRows(appName, DbStores.indexConfiguration), 1);

    int filled = 0;
    for (
      int n = await firestore.client.backfillIndexes();
      n > 0;
      n = await firestore.client.backfillIndexes()
    ) {
      filled += n;
    }
    expect(filled, 150);
    expect(await countRows(appName, DbStores.indexEntries), 150);
    expect(ids(await romanian.get(cache)), expected);

    // After a restart the index is read from the database.
    await shutDown(firestore);
    final FirebaseFirestore again = await newClient(appName);
    await again.disableNetwork();
    expect(again.client.localStore.getFieldIndexes(), hasLength(1));
    expect(
      ids(
        await again
            .collection(name)
            .where('country', isEqualTo: 'RO')
            .orderBy('population')
            .get(cache),
      ),
      expected,
    );
  });

  test('loads a bundle and keeps its named query', () async {
    final String name = newCollectionName();
    const String db = 'projects/demo-idb/databases/(default)';
    int utf8Length(String s) => utf8.encode(s).length;
    final List<String> elements = <String>[
      '{"namedQuery":{"name":"limit","readTime":{"seconds":1000,"nanos":9999},'
          '"bundledQuery":{"parent":"$db/documents",'
          '"structuredQuery":{"from":[{"collectionId":"$name"}],"orderBy":'
          '[{"field":{"fieldPath":"bar"},"direction":"DESCENDING"},{"field":'
          '{"fieldPath":"__name__"},"direction":"DESCENDING"}],"limit":'
          '{"value":1}},"limitType":"FIRST"}}}',
      '{"documentMetadata":{"name":"$db/documents/$name/a","readTime":'
          '{"seconds":1000,"nanos":9999},"exists":true}}',
      '{"document":{"name":"$db/documents/$name/a",'
          '"createTime":{"seconds":1,"nanos":9},"updateTime":{"seconds":1,'
          '"nanos":9},"fields":{"bar":{"integerValue":1}}}}',
      '{"documentMetadata":{"name":"$db/documents/$name/b","readTime":'
          '{"seconds":1000,"nanos":9999},"exists":true}}',
      '{"document":{"name":"$db/documents/$name/b",'
          '"createTime":{"seconds":1,"nanos":9},"updateTime":{"seconds":1,'
          '"nanos":9},"fields":{"bar":{"integerValue":2}}}}',
    ];
    final String body = elements
        .map((String element) => '${utf8Length(element)}$element')
        .join();
    final String metadata =
        '{"metadata":{"id":"idb-bundle","createTime":{"seconds":1001,"nanos":9999},'
        '"version":1,"totalDocuments":2,"totalBytes":${utf8Length(body)}}}';
    final List<int> bundle = utf8.encode(
      '${utf8Length(metadata)}$metadata$body',
    );

    final String appName = newAppName();
    FirebaseFirestore firestore = await newClient(appName);
    await firestore.disableNetwork();
    await firestore.loadBundle(bundle).future;
    expect(await countRows(appName, DbStores.bundles), 1);
    expect(await countRows(appName, DbStores.namedQueries), 1);

    await shutDown(firestore);
    firestore = await newClient(appName);
    await firestore.disableNetwork();
    final Query<Map<String, Object?>>? named = await firestore.namedQuery(
      'limit',
    );
    expect(named, isNotNull);
    final QuerySnapshot<Map<String, Object?>> snapshot = await named!.get(
      cache,
    );
    expect(
      snapshot.docs.map(
        (QueryDocumentSnapshot<Map<String, Object?>> d) => d.id,
      ),
      <String>['b'],
    );
  });
}
