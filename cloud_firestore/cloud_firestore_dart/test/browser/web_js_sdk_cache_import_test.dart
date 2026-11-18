// importJsSdkCache in a browser, against a copy of the IndexedDB database that the official JS SDK left
// (js_sdk_cache_fixture.json, see js_sdk_cache_fixture.dart): the pending writes reach the backend through this SDK,
// once.
//
//   dart test -j 1 -p chrome -c dart2wasm test/browser/web_js_sdk_cache_import_test.dart

@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/internal_access.dart';
import 'package:cloud_firestore_dart_sqlite/web.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

import 'browser_test_util.dart'
    show emulatorHost, emulatorPort, loadEmulatorPort;
import 'js_sdk_cache_fixture.dart';

final Uri sqlite3Wasm = Uri.base.resolve('sqlite3.wasm');

int _names = 0;

/// A client of the project of the fixture, and the name of the JS app whose database the fixture is loaded under.
Future<FirebaseFirestore> newClient({required bool persistent}) async {
  await loadEmulatorPort();
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'demo-key',
      appId: '1:1234567890:dart:browser',
      projectId: 'demo-idb',
    ),
    name: 'js-import-${DateTime.now().microsecondsSinceEpoch}-${_names++}',
  );
  final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
    app: app,
    openDatabase: persistent ? sqliteWebOpener(sqlite3Wasm: sqlite3Wasm) : null,
    settings: Settings(
      cacheSettings: persistent ? null : const MemoryCacheSettings(),
    ).withEmulator(emulatorHost, emulatorPort),
  );
  await firestore.initialized;
  addTearDown(() async {
    await firestore.terminate();
    await app.delete();
  });
  return firestore;
}

/// Loads the fixture as the database of a JS app with a new name, and returns that name.
Future<String> loadFixture() async {
  final String jsApp =
      'js-app-${DateTime.now().microsecondsSinceEpoch}-${_names++}';
  await loadJsSdkCacheFixture(databaseName: 'firestore/$jsApp/demo-idb/main');
  return jsApp;
}

Matcher refusal(JsSdkCacheImportRefusal reason) => throwsA(
  isA<JsSdkCacheImportException>().having(
    (JsSdkCacheImportException e) => e.reason,
    'reason',
    reason,
  ),
);

void main() {
  String? skip;

  setUpAll(() async {
    try {
      final web.Response response = await web.window
          .fetch(sqlite3Wasm.toString().toJS)
          .toDart;
      if (!response.ok) {
        skip = 'test/browser/sqlite3.wasm is missing (HTTP ${response.status})';
      }
    } catch (e) {
      skip = 'test/browser/sqlite3.wasm cannot be fetched: $e';
    }
  });

  test('the pending writes of the JS SDK reach the backend, once', () async {
    if (skip != null) {
      markTestSkipped(skip!);
      return;
    }
    // What the backend holds before: the writes of the fixture update items/cached1 and need it to exist.
    final FirebaseFirestore other = await newClient(persistent: false);
    final CollectionReference<Map<String, Object?>> items = other.collection(
      'items',
    );
    for (final String id in <String>['w1', 'w2', 'b1', 'gone']) {
      await items.doc(id).delete();
    }
    await items.doc('cached1').set(<String, Object?>{'title': 'from bundle'});
    await items.doc('w3').set(<String, Object?>{'old': true});
    await items.doc('b2').set(<String, Object?>{'old': true});

    final String jsApp = await loadFixture();
    final FirebaseFirestore firestore = await newClient(persistent: true);
    await firestore.disableNetwork();
    final JsSdkCacheImportResult result = await importJsSdkCache(
      firestore,
      jsAppName: jsApp,
    );
    expect(result.status, JsSdkCacheImportStatus.imported);
    expect(result.users, 2);
    expect(result.batches, 6);
    expect(result.documents, 2);
    // Five of the signed-out user; the one of user2 waits for that user.
    expect(await firestore.getPendingWriteCount(), 5);

    // The local view, before anything is sent.
    const GetOptions cache = GetOptions(source: Source.cache);
    final DocumentSnapshot<Map<String, Object?>> w2 = await firestore
        .doc('items/w2')
        .get(cache);
    expect(w2.metadata.hasPendingWrites, isTrue);
    expect(w2.data(), <String, Object?>{
      'count': 6,
      'nested': <String, Object?>{'field': 'v'},
      'tags': <String>['a', 'b'],
    });
    expect((await firestore.doc('items/w3').get(cache)).exists, isFalse);
    expect(
      (await firestore.doc('items/cached1').get(cache)).data()!['title'],
      'updated offline',
    );

    // A second call imports nothing, and nothing is left for it in the JS database.
    final JsSdkCacheImportResult again = await importJsSdkCache(
      firestore,
      jsAppName: jsApp,
    );
    expect(again.status, JsSdkCacheImportStatus.nothingToImport);
    expect(again.batches, 0);
    expect(await firestore.getPendingWriteCount(), 5);

    await firestore.enableNetwork();
    await firestore.waitForPendingWrites();
    expect(await firestore.getPendingWriteCount(), 0);

    const GetOptions server = GetOptions(source: Source.server);
    final Map<String, Object?> w1 = (await items.doc('w1').get(server)).data()!;
    expect(w1['title'], 'written offline');
    expect(w1['n'], 1);
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
      (await items.doc('cached1').get(server)).data()!['title'],
      'updated offline',
    );

    // Everything was imported, so the JS database can go.
    expect(await deleteJsSdkCache(firestore, jsAppName: jsApp), isTrue);
    expect(
      (await importJsSdkCache(firestore, jsAppName: jsApp)).status,
      JsSdkCacheImportStatus.noJsDatabase,
    );
  });

  test('refuses when this cache already has pending writes', () async {
    if (skip != null) {
      markTestSkipped(skip!);
      return;
    }
    final String jsApp = await loadFixture();
    final FirebaseFirestore firestore = await newClient(persistent: true);
    await firestore.disableNetwork();
    firestore.doc('other/doc').set(<String, Object?>{'a': 1}).ignore();
    await firestore
        .doc('other/doc')
        .get(const GetOptions(source: Source.cache));
    await expectLater(
      importJsSdkCache(firestore, jsAppName: jsApp),
      refusal(JsSdkCacheImportRefusal.pendingWritesInCache),
    );
    expect(await firestore.getPendingWriteCount(), 1);
    // The JS database still holds its writes: deleting it is refused too.
    await expectLater(
      deleteJsSdkCache(firestore, jsAppName: jsApp),
      throwsA(isA<JsSdkCacheImportException>()),
    );
  });

  test('a memory cache imports pending writes only when asked to', () async {
    final String jsApp = await loadFixture();
    final FirebaseFirestore firestore = await newClient(persistent: false);
    await firestore.disableNetwork();
    await expectLater(
      importJsSdkCache(firestore, jsAppName: jsApp),
      refusal(JsSdkCacheImportRefusal.memoryCache),
    );
    expect(await firestore.getPendingWriteCount(), 0);
    final JsSdkCacheImportResult result = await importJsSdkCache(
      firestore,
      jsAppName: jsApp,
      allowMemoryCache: true,
    );
    expect(result.status, JsSdkCacheImportStatus.imported);
    expect(await firestore.getPendingWriteCount(), 5);
  });

  test('no JS database: nothing happens', () async {
    final FirebaseFirestore firestore = await newClient(persistent: false);
    final JsSdkCacheImportResult result = await importJsSdkCache(
      firestore,
      jsAppName: 'no-such-app',
    );
    expect(result.status, JsSdkCacheImportStatus.noJsDatabase);
  });
}
