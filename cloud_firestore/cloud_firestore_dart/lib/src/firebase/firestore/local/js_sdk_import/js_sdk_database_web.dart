import 'dart:async';
import 'dart:js_interop';

import 'package:cloud_firestore_dart/src/firebase/firestore/local/indexeddb/indexeddb_schema.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/indexeddb/web/idb.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/js_sdk_import/js_sdk_database.dart';
import 'package:web/web.dart' as web;

/// Whether this platform can hold a database of the JS SDK: only the web.
const bool jsSdkDatabaseSupported = true;

/// Opens the database [name] at its current version, or returns null when there is none. A database that does not
/// exist is not created: its creation (the upgrade from version 0) is aborted.
Future<JsSdkDatabase?> openJsSdkDatabase(String name) async {
  final web.IDBOpenDBRequest request = web.window.indexedDB.open(name);
  final Completer<web.IDBDatabase?> completer = Completer<web.IDBDatabase?>();
  bool created = false;
  request.onupgradeneeded = ((web.Event _) {
    // Without a version, an upgrade is only needed when the database does not exist.
    created = true;
    request.transaction?.abort();
  }).toJS;
  request.onsuccess = ((web.Event _) {
    completer.complete(request.result as web.IDBDatabase);
  }).toJS;
  request.onerror = ((web.Event event) {
    if (created) {
      event.preventDefault();
      completer.complete(null);
    } else {
      completer.completeError(
        StateError('Opening $name failed: ${idbDescribe(request.error)}'),
      );
    }
  }).toJS;
  final web.IDBDatabase? db = await completer.future;
  if (db == null) {
    return null;
  }
  // A JS SDK that upgrades or deletes the database waits for this connection: let it go.
  db.onversionchange = ((web.Event _) => db.close()).toJS;
  return _WebJsSdkDatabase(db);
}

/// Deletes the database [name]. A JS tab that has it open closes its connection when asked (the JS SDK handles the
/// `versionchange` event), and the deletion waits for that.
Future<void> deleteJsSdkDatabase(String name) async {
  await idbRequest(web.window.indexedDB.deleteDatabase(name));
}

/// Whether the JS SDK marked the client [clientId] as gone in LocalStorage (`firestore_zombie_<prefix>_<clientId>`,
/// written when its page is hidden for good). False when LocalStorage can not be read, as in the JS SDK.
bool isJsSdkClientZombied(String storagePrefix, String clientId) {
  try {
    return web.window.localStorage.getItem(
          indexedDbZombieKey(storagePrefix, clientId),
        ) !=
        null;
  } catch (_) {
    return false;
  }
}

class _WebJsSdkDatabase implements JsSdkDatabase {
  _WebJsSdkDatabase(this._db);

  final web.IDBDatabase _db;

  @override
  int get version => _db.version;

  @override
  bool hasStore(String name) => _db.objectStoreNames.contains(name);

  @override
  Future<List<Map<String, Object?>>> readAll(String name) async {
    final web.IDBTransaction transaction = _db.transaction(
      name.toJS,
      'readonly',
    );
    final JSAny? all = await idbRequest(transaction.objectStore(name).getAll());
    final List<Object?> rows = idbToDart(all)! as List<Object?>;
    return <Map<String, Object?>>[
      for (final Object? row in rows) (row! as Map<Object?, Object?>).cast(),
    ];
  }

  @override
  Future<int> removeMutationBatches(
    Iterable<int> batchIds,
    bool Function(Map<String, Object?> row) matches,
  ) async {
    final bool hasOverlays = hasStore('documentOverlays');
    final web.IDBTransaction transaction = _db.transaction(
      <JSString>[
        'mutations'.toJS,
        'documentMutations'.toJS,
        if (hasOverlays) 'documentOverlays'.toJS,
      ].toJS,
      'readwrite',
    );
    final Future<void> committed = idbCommitted(transaction);
    // Failing a request aborts the transaction: the error is reported by the request, not by the commit.
    unawaited(committed.then<void>((_) {}, onError: (Object _) {}));
    final web.IDBObjectStore mutations = transaction.objectStore('mutations');

    // The removed batch ids of each user.
    final Map<String, Set<int>> removed = <String, Set<int>>{};
    try {
      for (final int batchId in batchIds) {
        final Object? row = idbToDart(
          await idbRequest(mutations.get(batchId.toJS)),
        );
        if (row is! Map || !matches(row.cast<String, Object?>())) {
          continue;
        }
        await idbRequest(mutations.delete(batchId.toJS));
        (removed[row['userId'] as String] ??= <int>{}).add(batchId);
      }

      if (removed.isNotEmpty) {
        // Keys [userId, encodedPath, batchId].
        await idbForEach(
          transaction.objectStore('documentMutations').openCursor(),
          (web.IDBCursor cursor) {
            final List<Object?> key = idbToDart(cursor.key)! as List<Object?>;
            final Set<int>? ids = removed[key[0]];
            if (ids != null && ids.contains((key[2]! as num).toInt())) {
              cursor.delete();
            }
            return true;
          },
        );
        if (hasOverlays) {
          await idbForEach(
            transaction.objectStore('documentOverlays').openCursor(),
            (web.IDBCursor cursor) {
              final Map<Object?, Object?> overlay =
                  idbToDart((cursor as web.IDBCursorWithValue).value)!
                      as Map<Object?, Object?>;
              final Set<int>? ids = removed[overlay['userId']];
              final Object? largestBatchId = overlay['largestBatchId'];
              if (ids != null &&
                  largestBatchId is num &&
                  ids.contains(largestBatchId.toInt())) {
                cursor.delete();
              }
              return true;
            },
          );
        }
      }
    } catch (_) {
      // Without this the requests made so far would commit when the transaction ends: batches removed without their
      // documentMutations rows, which the JS SDK asserts on when it reads them.
      try {
        transaction.abort();
      } catch (_) {
        // Already finished.
      }
      rethrow;
    }
    await committed;
    return removed.values.fold<int>(0, (int n, Set<int> ids) => n + ids.length);
  }

  @override
  void close() => _db.close();
}
