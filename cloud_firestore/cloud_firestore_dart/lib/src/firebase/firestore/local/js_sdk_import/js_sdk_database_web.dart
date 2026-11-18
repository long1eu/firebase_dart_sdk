import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:cloud_firestore_dart/src/firebase/firestore/local/js_sdk_import/js_sdk_database.dart';
import 'package:web/web.dart' as web;

/// Whether this platform can hold a database of the JS SDK: only the web.
const bool jsSdkDatabaseSupported = true;

@JS('JSON.stringify')
external JSString? _stringify(JSAny? value);

/// [value] as a JSON tree (see [JsSdkDatabase]).
Object? _toDart(JSAny? value) {
  if (value == null) {
    return null;
  }
  final JSString? json = _stringify(value);
  return json == null ? null : jsonDecode(json.toDart);
}

String _describe(web.DOMException? error) =>
    error == null ? 'unknown error' : '${error.name}: ${error.message}';

/// The result of [request], or its error.
Future<JSAny?> _request(web.IDBRequest request) {
  final Completer<JSAny?> completer = Completer<JSAny?>();
  request.onsuccess = ((web.Event _) => completer.complete(
    request.result,
  )).toJS;
  request.onerror = ((web.Event _) => completer.completeError(
    StateError('IndexedDB request failed: ${_describe(request.error)}'),
  )).toJS;
  return completer.future;
}

/// Completes when [transaction] committed, fails when it aborted.
Future<void> _committed(web.IDBTransaction transaction) {
  final Completer<void> completer = Completer<void>();
  transaction.oncomplete = ((web.Event _) => completer.complete()).toJS;
  transaction.onabort = ((web.Event _) {
    if (!completer.isCompleted) {
      completer.completeError(
        StateError(
          'IndexedDB transaction aborted: ${_describe(transaction.error)}',
        ),
      );
    }
  }).toJS;
  return completer.future;
}

/// Calls [visit] with every position of the cursor that [request] opened, synchronously in the success event of each
/// step, so that the transaction stays active.
Future<void> _forEach(
  web.IDBRequest request,
  void Function(web.IDBCursorWithValue cursor) visit,
) {
  final Completer<void> completer = Completer<void>();
  request.onsuccess = ((web.Event _) {
    final JSAny? result = request.result;
    if (result == null) {
      completer.complete();
      return;
    }
    final web.IDBCursorWithValue cursor = result as web.IDBCursorWithValue;
    try {
      visit(cursor);
      cursor.continue_();
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    }
  }).toJS;
  request.onerror = ((web.Event _) => completer.completeError(
    StateError('IndexedDB cursor failed: ${_describe(request.error)}'),
  )).toJS;
  return completer.future;
}

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
        StateError('Opening $name failed: ${_describe(request.error)}'),
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
  await _request(web.window.indexedDB.deleteDatabase(name));
}

/// Whether the JS SDK marked the client [clientId] as gone in LocalStorage (`firestore_zombie_<prefix>_<clientId>`,
/// written when its page is hidden for good). False when LocalStorage can not be read, as in the JS SDK.
bool isJsSdkClientZombied(String storagePrefix, String clientId) {
  try {
    return web.window.localStorage.getItem(
          'firestore_zombie_${storagePrefix}_$clientId',
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
    final JSAny? all = await _request(transaction.objectStore(name).getAll());
    final List<Object?> rows = _toDart(all)! as List<Object?>;
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
    final Future<void> committed = _committed(transaction);
    // Failing a request aborts the transaction: the error is reported by the request, not by the commit.
    unawaited(committed.then<void>((_) {}, onError: (Object _) {}));
    final web.IDBObjectStore mutations = transaction.objectStore('mutations');

    // The removed batch ids of each user.
    final Map<String, Set<int>> removed = <String, Set<int>>{};
    for (final int batchId in batchIds) {
      final Object? row = _toDart(await _request(mutations.get(batchId.toJS)));
      if (row is! Map || !matches(row.cast<String, Object?>())) {
        continue;
      }
      await _request(mutations.delete(batchId.toJS));
      (removed[row['userId'] as String] ??= <int>{}).add(batchId);
    }

    if (removed.isNotEmpty) {
      // Keys [userId, encodedPath, batchId].
      await _forEach(
        transaction.objectStore('documentMutations').openCursor(),
        (web.IDBCursorWithValue cursor) {
          final List<Object?> key = _toDart(cursor.key)! as List<Object?>;
          final Set<int>? ids = removed[key[0]];
          if (ids != null && ids.contains((key[2]! as num).toInt())) {
            cursor.delete();
          }
        },
      );
      if (hasOverlays) {
        await _forEach(
          transaction.objectStore('documentOverlays').openCursor(),
          (web.IDBCursorWithValue cursor) {
            final Map<Object?, Object?> overlay =
                _toDart(cursor.value)! as Map<Object?, Object?>;
            final Set<int>? ids = removed[overlay['userId']];
            final Object? largestBatchId = overlay['largestBatchId'];
            if (ids != null &&
                largestBatchId is num &&
                ids.contains(largestBatchId.toInt())) {
              cursor.delete();
            }
          },
        );
      }
    }
    await committed;
    return removed.values.fold<int>(0, (int n, Set<int> ids) => n + ids.length);
  }

  @override
  void close() => _db.close();
}
