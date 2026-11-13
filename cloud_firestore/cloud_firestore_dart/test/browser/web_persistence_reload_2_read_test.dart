// Second half of the page load test, see
// web_persistence_reload_1_write_test.dart: a new page of the same origin
// opens the cache that the first page left behind without closing it.

@TestOn('browser')
library;

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

import 'browser_test_util.dart';
import 'web_persistence_reload_1_write_test.dart'
    show hasSqlite3Wasm, reloadClient, reloadStorageKey;

typedef Json = Map<String, Object?>;

void main() {
  test('page 2 finds the data and the pending writes of page 1', () async {
    if (!await hasSqlite3Wasm()) {
      markTestSkipped('test/browser/sqlite3.wasm is missing: see '
          'web_persistence_test.dart');
      return;
    }
    final String? collection =
        web.window.localStorage.getItem(reloadStorageKey);
    if (collection == null) {
      markTestSkipped(
          'Page 1 did not run before this page in the same test run: pass '
          'web_persistence_reload_1_write_test.dart and then this file to '
          '`dart test -j 1 -p chrome`');
      return;
    }
    web.window.localStorage.removeItem(reloadStorageKey);

    // The first page is gone, and with it its Web Lock.
    final Firestore firestore = await reloadClient();
    addTearDown(() async {
      await firestore.terminate();
      await firestore.clearPersistence();
    });

    await firestore.disableNetwork();
    final DocumentSnapshot<Json> acknowledged = await firestore
        .collection(collection)
        .doc('acknowledged')
        .get(Source.cache);
    expect(acknowledged.data, <String, Object?>{'v': 11});
    expect(acknowledged.metadata.hasPendingWrites, isTrue);
    final DocumentSnapshot<Json> pending =
        await firestore.collection(collection).doc('pending').get(Source.cache);
    expect(pending.data, <String, Object?>{'v': 2});
    expect(pending.metadata.hasPendingWrites, isTrue);

    // The backend only has what page 1 was told is written.
    final Firestore other = await newClient();
    expect(
        (await other.collection(collection).doc('acknowledged').get(Source.server))
            .data,
        <String, Object?>{'v': 1});
    expect(
        (await other.collection(collection).doc('pending').get(Source.server))
            .exists,
        isFalse);

    // Page 2 sends the writes of page 1, once.
    await firestore.enableNetwork();
    await firestore.waitForPendingWrites().timeout(const Duration(seconds: 20));
    final QuerySnapshot<Json> server =
        await other.collection(collection).get(Source.server);
    expect(<String, Object?>{
      for (final QueryDocumentSnapshot<Json> d in server.docs) d.id: d.data,
    }, <String, Object?>{
      'acknowledged': <String, Object?>{'v': 11},
      'pending': <String, Object?>{'v': 2},
    });
  });
}
