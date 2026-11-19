// The IndexedDB cache store of example/cache_store/indexeddb in a browser: the contract checks of
// package:cloud_firestore_dart/cache_store_testing.dart, and the key-value cache of a client over it, written offline,
// terminated and read back by a new client on the same database.
//
//   dart test -j 1 -p chrome -c dart2wasm test/browser/web_cache_store_indexeddb_test.dart

@TestOn('browser')
library;

import 'dart:async';

import 'package:cloud_firestore_dart/cache_store.dart';
import 'package:cloud_firestore_dart/cache_store_testing.dart';
import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/keyvalue/kv_codec.dart';
import 'package:cloud_firestore_dart/src/internal_access.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';

import '../../example/cache_store/indexeddb/indexeddb_cache_store.dart';
import 'browser_test_util.dart';

int _names = 0;
String newDatabaseName() =>
    'cache-store-${DateTime.now().microsecondsSinceEpoch}-${_names++}';

void main() {
  test('the key codec keeps integers exactly on the web', () {
    // value + 2^53 needs 54 bits: a double loses the last one.
    for (final int value in <int>[
      0,
      1,
      -1,
      7,
      -7,
      1 << 40,
      (1 << 40) + 1,
      -(1 << 40) - 1,
      9007199254740991,
      -9007199254740991,
    ]) {
      final KvKeyWriter writer = KvKeyWriter().integer(value);
      expect(KvKeyReader(writer.bytes).integer(), value);
    }
    expect(
      compareCacheStoreKeys(
        KvKeyWriter().integer(2).bytes,
        KvKeyWriter().integer(3).bytes,
      ),
      lessThan(0),
    );
  });

  group('IndexedDbCacheStore', () {
    for (final CacheStoreCheck check in cacheStoreConformanceChecks) {
      test(check.name, () async {
        final String name = newDatabaseName();
        addTearDown(() => IndexedDbCacheStore.deleteDatabase(name));
        await check.run(() => IndexedDbCacheStore(name));
      });
    }
  });

  test('writes made offline are read back by a new client', () async {
    await loadEmulatorPort();
    final String database = newDatabaseName();
    final String appName = 'kv-${DateTime.now().microsecondsSinceEpoch}';
    addTearDown(() => IndexedDbCacheStore.deleteDatabase(database));

    Future<(FirebaseApp, FirebaseFirestore)> open() async {
      final FirebaseApp app = FirebaseApp.withOptions(
        const FirebaseOptions(
          apiKey: 'demo-key',
          appId: '1:1234567890:dart:browser',
          projectId: projectId,
        ),
        name: appName,
      );
      final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
        app: app,
        settings: Settings(
          cacheSettings: keyValueCacheSettings(
            store: IndexedDbCacheStore(database),
          ),
        ).withEmulator(emulatorHost, emulatorPort),
      );
      await firestore.initialized;
      return (app, firestore);
    }

    final String collection = newCollectionName();
    var (FirebaseApp app, FirebaseFirestore firestore) = await open();
    await firestore.disableNetwork();
    unawaited(
      firestore.doc('$collection/a').set(<String, Object?>{'text': 'milk'}),
    );
    unawaited(
      firestore.doc('$collection/b').set(<String, Object?>{'text': 'eggs'}),
    );
    unawaited(
      firestore.doc('$collection/a').update(<String, Object?>{'done': true}),
    );
    expect(await firestore.getPendingWriteCount(), 3);
    await firestore.terminate();
    await app.delete();

    (app, firestore) = await open();
    addTearDown(() async {
      await firestore.terminate();
      await app.delete();
    });
    await firestore.disableNetwork();
    expect(await firestore.getPendingWriteCount(), 3);
    final QuerySnapshot<Map<String, Object?>> snapshot = await firestore
        .collection(collection)
        .get(GetOptions(source: Source.cache));
    expect(
      <String, Object?>{
        for (final QueryDocumentSnapshot<Map<String, Object?>> doc
            in snapshot.docs)
          doc.id: doc.data(),
      },
      <String, Object?>{
        'a': <String, Object?>{'text': 'milk', 'done': true},
        'b': <String, Object?>{'text': 'eggs'},
      },
    );
    expect(
      snapshot.docs.every(
        (QueryDocumentSnapshot<Map<String, Object?>> doc) =>
            doc.metadata.hasPendingWrites,
      ),
      isTrue,
    );
  });
}
