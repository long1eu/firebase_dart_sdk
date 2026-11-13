// First half of the page load test of the offline cache in a browser: this
// page writes and is then thrown away without closing anything, the way a tab
// is reloaded or closed. web_persistence_reload_2_read_test.dart, which the
// test runner loads as a new page of the same origin, finds the cache.
//
// Run both in one `dart test -j 1 -p chrome` and name this file before the
// other one: the runner loads the files in the order of its arguments (and in
// no particular order when it is given the directory).

@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

import '../../example/sqlite_database_web.dart';
import 'browser_test_util.dart';

typedef Json = Map<String, Object?>;

/// Where the first page leaves the name of its collection for the second.
const String reloadStorageKey = 'cloud_firestore_dart.reload_test.collection';
const String reloadAppName = 'reload-test-app';

FirebaseApp reloadApp() => FirebaseApp.withOptions(
      const FirebaseOptions(
        apiKey: 'demo-key',
        applicationId: '1:1234567890:dart:browser',
        projectId: projectId,
      ),
      name: reloadAppName,
    );

Firestore reloadClient() => Firestore.instanceFor(
      app: reloadApp(),
      openDatabase:
          sqliteWebOpener(sqlite3Wasm: Uri.base.resolve('sqlite3.wasm')),
      settings: FirestoreSettings().withEmulator(emulatorHost, emulatorPort),
    );

Future<bool> hasSqlite3Wasm() async {
  try {
    return (await web.window
            .fetch(Uri.base.resolve('sqlite3.wasm').toString().toJS)
            .toDart)
        .ok;
  } catch (_) {
    return false;
  }
}

void main() {
  setUpAll(loadEmulatorPort);
  test('page 1 writes, and leaves without closing the client', () async {
    if (!await hasSqlite3Wasm()) {
      markTestSkipped('test/browser/sqlite3.wasm is missing: see '
          'web_persistence_test.dart');
      return;
    }
    web.window.localStorage.removeItem(reloadStorageKey);

    // Not terminated and not torn down: the page just goes away.
    final Firestore firestore = reloadClient();
    final String collection = newCollectionName();
    await firestore.collection(collection).doc('acknowledged').set(
      <String, Object?>{'v': 1},
    );

    await firestore.disableNetwork();
    unawaited(firestore.collection(collection).doc('pending').set(
      <String, Object?>{'v': 2},
    ));
    unawaited(firestore.collection(collection).doc('acknowledged').update(
      <String, Object?>{'v': FieldValue.increment(10)},
    ));
    // A cache read comes after the writes on the client's queue: once it
    // answers, the writes are in the mutation queue (and their transaction is
    // stored).
    final DocumentSnapshot<Json> pending =
        await firestore.collection(collection).doc('pending').get(Source.cache);
    expect(pending.metadata.hasPendingWrites, isTrue);

    web.window.localStorage.setItem(reloadStorageKey, collection);
  });
}
