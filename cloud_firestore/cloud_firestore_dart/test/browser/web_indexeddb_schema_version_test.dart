// The IndexedDB engine opens the JS SDK's schema version 18 only: a database of another version (an older JS SDK that
// did not migrate it yet, or a newer one) is refused with an error that names the version, and is left as it was.
//
//   dart test -p chrome -c dart2wasm test/browser/web_indexeddb_schema_version_test.dart

@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/indexeddb/indexeddb_schema.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/indexeddb/web/idb.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

import 'indexeddb_test_persistence.dart';

/// Creates the database [name] at [version] with one store, `owner`, holding one row, as a JS SDK of that version
/// would have left it (the stores do not matter: the engine looks at the version first).
Future<void> createDatabase(String name, int version) async {
  await idbRequest(web.window.indexedDB.deleteDatabase(name));
  final web.IDBOpenDBRequest open = web.window.indexedDB.open(name, version);
  open.onupgradeneeded = ((web.Event _) {
    final web.IDBDatabase db = open.result! as web.IDBDatabase;
    db
        .createObjectStore(DbStores.owner)
        .put(
          idbToJs(<String, Object?>{'ownerId': 'js-client'}),
          DbStores.ownerKey.toJS,
        );
  }).toJS;
  ((await idbRequest(open))! as web.IDBDatabase).close();
}

/// The version of the database [name] and its `owner` row.
Future<(int, Object?)> readDatabase(String name) async {
  final web.IDBDatabase db =
      (await idbRequest(web.window.indexedDB.open(name)))! as web.IDBDatabase;
  try {
    final Object? row = idbToDart(
      await idbRequest(
        db
            .transaction(DbStores.owner.toJS)
            .objectStore(DbStores.owner)
            .get(DbStores.ownerKey.toJS),
      ),
    );
    return (db.version, row);
  } finally {
    db.close();
  }
}

void main() {
  for (final (int version, String description) in <(int, String)>[
    (17, 'written by an older JS SDK'),
    (12, 'written by an older JS SDK'),
    (19, 'newer than this SDK knows'),
  ]) {
    test(
      'refuses a database of schema version $version ($description) and leaves it as it was',
      () async {
        final String key = newIndexedDbPersistenceKey();
        final String name = 'firestore/$key/projectId/main';
        await createDatabase(name, version);

        await expectLater(
          newIndexedDbTestPersistence(persistenceKey: key),
          throwsA(
            isA<FirestoreException>()
                .having(
                  (FirestoreException e) => e.errorCode,
                  'errorCode',
                  FirestoreErrorCode.failedPrecondition,
                )
                .having(
                  (FirestoreException e) => e.message,
                  'message',
                  allOf(
                    contains(name),
                    contains(
                      version > 18
                          ? 'newer than 18'
                          : 'schema version $version',
                    ),
                  ),
                ),
          ),
        );

        final (int after, Object? row) = await readDatabase(name);
        expect(after, version);
        expect(row, <String, Object?>{'ownerId': 'js-client'});
      },
    );
  }

  test('creates a database of version 18 when there is none', () async {
    final String key = newIndexedDbPersistenceKey();
    final persistence = await newIndexedDbTestPersistence(persistenceKey: key);
    await persistence.shutdown();
    final web.IDBDatabase db =
        (await idbRequest(
              web.window.indexedDB.open('firestore/$key/projectId/main'),
            ))!
            as web.IDBDatabase;
    try {
      expect(db.version, indexedDbSchemaVersion);
      expect(indexedDbSchemaVersion, 18);
    } finally {
      db.close();
    }
  });
}
