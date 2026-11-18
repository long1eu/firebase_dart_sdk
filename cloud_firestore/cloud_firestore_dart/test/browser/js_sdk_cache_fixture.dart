// Loads js_sdk_cache_fixture.json, a dump of the IndexedDB database that the official JS SDK (firebase 12.19.0,
// schema 18) left after tool/bench/web_idb/js_import/writer.js, back into IndexedDB, for the browser tests of
// importJsSdkCache without npm. The dump is from tool/bench/web_idb/js_import/dump.sh; its format is in the header of
// static/dump.js there: the version, and every object store with its key path, autoIncrement, indexes and records,
// binary values as {"__u8": base64}.
//
// What the fixture holds (project demo-idb, database firestore/[DEFAULT]/demo-idb/main): six pending batches, five of
// the signed-out user ("": a set of items/w1 with every value type and a server timestamp, a set of items/w2, an
// update of items/w2 with increment, arrayUnion and a dotted path, a delete of items/w3, and a WriteBatch that sets
// items/b1, updates items/cached1 and deletes items/b2) and one of user2 (a copy of the first); the cached documents
// items/cached1 and items/gone (deleted), from a bundle; no owner lease and no clientMetadata row (the client
// terminated).
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Where the browser tests serve the fixture: next to this file.
final Uri jsSdkCacheFixture = Uri.base.resolve('js_sdk_cache_fixture.json');

/// The name of the database in the fixture.
const String jsSdkCacheFixtureDatabase = 'firestore/[DEFAULT]/demo-idb/main';

/// Fetches [fixture] and loads it with [loadJsSdkCacheDump] under [databaseName] (by default the name in the dump,
/// [jsSdkCacheFixtureDatabase]).
Future<void> loadJsSdkCacheFixture({String? databaseName, Uri? fixture}) async {
  final Uri uri = fixture ?? jsSdkCacheFixture;
  final web.Response response = await web.window
      .fetch(uri.toString().toJS)
      .toDart;
  if (!response.ok) {
    throw StateError('Fetching $uri failed: HTTP ${response.status}');
  }
  final String text = (await response.text().toDart).toDart;
  await loadJsSdkCacheDump(
    (jsonDecode(text) as Map<Object?, Object?>).cast<String, Object?>(),
    databaseName: databaseName,
  );
}

/// Deletes the database [databaseName] (by default the name in [dump]) if it exists, and creates it again at the
/// version of [dump] with its object stores, indexes and records.
Future<void> loadJsSdkCacheDump(
  Map<String, Object?> dump, {
  String? databaseName,
}) async {
  final String name = databaseName ?? dump['name']! as String;
  final int version = (dump['version']! as num).toInt();
  final List<Map<String, Object?>> stores = <Map<String, Object?>>[
    for (final Object? store in dump['stores']! as List<Object?>)
      (store! as Map<Object?, Object?>).cast<String, Object?>(),
  ];

  await _request(web.window.indexedDB.deleteDatabase(name));

  final web.IDBOpenDBRequest open = web.window.indexedDB.open(name, version);
  open.onupgradeneeded = ((web.Event _) {
    final web.IDBDatabase db = open.result! as web.IDBDatabase;
    for (final Map<String, Object?> store in stores) {
      final Object? keyPath = store['keyPath'];
      final web.IDBObjectStore created = db.createObjectStore(
        store['name']! as String,
        keyPath == null
            ? web.IDBObjectStoreParameters(
                autoIncrement: store['autoIncrement'] == true,
              )
            : web.IDBObjectStoreParameters(
                keyPath: _toJs(keyPath),
                autoIncrement: store['autoIncrement'] == true,
              ),
      );
      for (final Object? index in store['indexes']! as List<Object?>) {
        final Map<Object?, Object?> i = index! as Map<Object?, Object?>;
        created.createIndex(
          i['name']! as String,
          _toJs(i['keyPath'])!,
          web.IDBIndexParameters(
            unique: i['unique'] == true,
            multiEntry: i['multiEntry'] == true,
          ),
        );
      }
    }
  }).toJS;
  final web.IDBDatabase db = await _request(open) as web.IDBDatabase;
  try {
    final web.IDBTransaction transaction = db.transaction(
      <JSString>[
        for (final Map<String, Object?> store in stores)
          (store['name']! as String).toJS,
      ].toJS,
      'readwrite',
    );
    final Completer<void> committed = Completer<void>();
    transaction.oncomplete = ((web.Event _) => committed.complete()).toJS;
    transaction.onabort = ((web.Event _) => committed.completeError(
      StateError('Loading the fixture failed: ${transaction.error?.message}'),
    )).toJS;
    for (final Map<String, Object?> store in stores) {
      final web.IDBObjectStore objectStore = transaction.objectStore(
        store['name']! as String,
      );
      final bool inlineKeys = store['keyPath'] != null;
      for (final Object? record in store['records']! as List<Object?>) {
        final Map<Object?, Object?> r = record! as Map<Object?, Object?>;
        // Requests are queued synchronously: the transaction stays active.
        if (inlineKeys) {
          objectStore.put(_toJs(r['value']));
        } else {
          objectStore.put(_toJs(r['value']), _toJs(r['key']));
        }
      }
    }
    await committed.future;
  } finally {
    db.close();
  }
}

Future<JSAny?> _request(web.IDBRequest request) {
  final Completer<JSAny?> completer = Completer<JSAny?>();
  request.onsuccess = ((web.Event _) => completer.complete(
    request.result,
  )).toJS;
  request.onerror = ((web.Event _) => completer.completeError(
    StateError('IndexedDB request failed: ${request.error?.message}'),
  )).toJS;
  return completer.future;
}

/// A JSON value of the dump as a JS value: maps become plain objects, {"__u8": base64} a Uint8Array.
JSAny? _toJs(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value.toJS;
  }
  if (value is num) {
    return value.toJS;
  }
  if (value is bool) {
    return value.toJS;
  }
  if (value is List<Object?>) {
    return <JSAny?>[for (final Object? e in value) _toJs(e)].toJS;
  }
  final Map<Object?, Object?> map = value as Map<Object?, Object?>;
  if (map.length == 1 && map['__u8'] is String) {
    return base64Decode(map['__u8']! as String).toJS;
  }
  final JSObject object = JSObject();
  for (final MapEntry<Object?, Object?> entry in map.entries) {
    object.setProperty((entry.key! as String).toJS, _toJs(entry.value));
  }
  return object;
}
