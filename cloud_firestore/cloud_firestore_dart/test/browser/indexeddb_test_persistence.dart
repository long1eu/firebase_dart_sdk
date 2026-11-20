// The IndexedDB engine (WebIndexedDbPersistence) for the shared persistence suites of test/unit/firebase/firestore/local
// and the spec tests, run in a browser: the browser counterpart of persistence_test_helpers.dart, which imports
// `dart:io` and can not be compiled for the web. No emulator is needed by the suites that use it.

import 'dart:js_interop';

import 'package:cloud_firestore_dart/src/firebase/firestore/local/indexeddb/indexeddb_schema.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/indexeddb/web/idb.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/indexeddb/web/indexeddb_persistence_web.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/stats_collector.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:web/web.dart' as web;

int _databases = 0;

/// A persistence key (app name) used by no other test of this page.
String newIndexedDbPersistenceKey([String prefix = 'idb-test']) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_databases++}';

/// Creates and starts a [WebIndexedDbPersistence] on the database of the app [persistenceKey] (a new one by default)
/// and project [projectId]. A later call with the same key, after the first one was shut down, opens the same database
/// again (a restart).
Future<WebIndexedDbPersistence> newIndexedDbTestPersistence({
  String? persistenceKey,
  String projectId = 'projectId',
  LruGarbageCollectorParams params = const LruGarbageCollectorParams(),
  StatsCollector statsCollector = StatsCollector.noOp,
  String? clientId,
  bool multiTab = false,
}) async {
  final DatabaseId databaseId = DatabaseId.forProject(projectId);
  final WebIndexedDbPersistence persistence = WebIndexedDbPersistence(
    persistenceKey: persistenceKey ?? newIndexedDbPersistenceKey(),
    databaseId: databaseId,
    serializer: LocalSerializer(RemoteSerializer(databaseId)),
    lruParams: params,
    statsCollector: statsCollector,
    clientId: clientId,
    multiTab: multiTab,
  );
  await persistence.start();
  return persistence;
}

/// Deletes the database [name] (closed connections only; an open one is asked to close by the browser).
Future<void> deleteIndexedDbDatabase(String name) async {
  await idbRequest(web.window.indexedDB.deleteDatabase(name));
}

/// The number of rows of [store] in the database [name], read through a connection of its own.
Future<int> countIndexedDbRows(String name, String store) async {
  final web.IDBDatabase db =
      (await idbRequest(web.window.indexedDB.open(name)))! as web.IDBDatabase;
  try {
    return ((await idbRequest(
              db.transaction(store.toJS).objectStore(store).count(),
            ))!
            as JSNumber)
        .toDartInt;
  } finally {
    db.close();
  }
}

/// Opens the database [name] without a version (the one it has), runs [body] on a read-write transaction over
/// [stores], and closes it: what another client (a JS tab) does to the database.
Future<void> writeAsOtherClient(
  String name,
  List<String> stores,
  void Function(web.IDBTransaction transaction) body,
) async {
  final web.IDBDatabase db =
      (await idbRequest(web.window.indexedDB.open(name)))! as web.IDBDatabase;
  try {
    final web.IDBTransaction transaction = db.transaction(
      <JSString>[for (final String store in stores) store.toJS].toJS,
      'readwrite',
    );
    final Future<void> committed = idbCommitted(transaction);
    body(transaction);
    await committed;
  } finally {
    db.close();
  }
}

/// Puts the primary lease of the client [ownerId], refreshed [ageMs] ago, into the database [name].
Future<void> putLease(String name, String ownerId, {int ageMs = 0}) =>
    writeAsOtherClient(name, <String>[DbStores.owner], (
      web.IDBTransaction transaction,
    ) {
      transaction
          .objectStore(DbStores.owner)
          .put(
            idbToJs(<String, Object?>{
              'ownerId': ownerId,
              'allowTabSynchronization': false,
              'leaseTimestampMs': DateTime.now().millisecondsSinceEpoch - ageMs,
            }),
            DbStores.ownerKey.toJS,
          );
    });
