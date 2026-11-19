// A CacheStore on IndexedDB (package:web, dart:js_interop): one object store of keys and values, for the web.
//
// IndexedDB orders binary keys (array buffers and their views) by their unsigned bytes, a prefix first: the order of
// the store contract. So a scan is a key range of the object store. A read is a read-only IndexedDB transaction of its
// own; a write is one read-write transaction with strict durability, which IndexedDB commits whole or not at all.
//
// IndexedDB commits a transaction by itself as soon as no request is pending when the event loop turns, so a
// transaction cannot stay open across the awaits of the SDK. The store contract does not ask for that: the SDK keeps
// the writes of its own transactions and hands them over in one write.

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/cache_store.dart';
import 'package:web/web.dart' as web;

class IndexedDbCacheStore implements CacheStore {
  /// A store in the IndexedDB database [name] of this origin.
  IndexedDbCacheStore(this.name);

  /// The name of the database.
  final String name;

  static const String _entries = 'entries';

  web.IDBDatabase? _database;

  web.IDBDatabase get _db =>
      _database ?? (throw StateError('The store is not open'));

  /// Deletes the database [name] (closed by every page first).
  static Future<void> deleteDatabase(String name) async {
    await _request(web.window.indexedDB.deleteDatabase(name));
  }

  @override
  Future<void> open() async {
    final web.IDBOpenDBRequest request = web.window.indexedDB.open(name, 1);
    request.onupgradeneeded = ((web.IDBVersionChangeEvent _) {
      (request.result! as web.IDBDatabase).createObjectStore(_entries);
    }).toJS;
    request.onblocked = ((web.Event _) {
      // An older version is open in another page: the request waits until it closes.
    }).toJS;
    final web.IDBDatabase database =
        (await _request(request))! as web.IDBDatabase;
    // Another page that deletes or upgrades the database: let it go ahead.
    database.onversionchange = ((web.Event _) {
      database.close();
      if (identical(_database, database)) {
        _database = null;
      }
    }).toJS;
    _database = database;
  }

  @override
  Future<void> close() async {
    _database?.close();
    _database = null;
  }

  @override
  Future<Uint8List?> get(Uint8List key) async {
    final JSAny? value = await _request(_read().get(_key(key)));
    return value.isUndefinedOrNull ? null : _bytes(value!);
  }

  @override
  Future<List<CacheStoreEntry>> scan(
    Uint8List start,
    Uint8List end, {
    bool reverse = false,
    int? limit,
  }) async {
    if ((limit != null && limit <= 0) ||
        compareCacheStoreKeys(start, end) >= 0) {
      return <CacheStoreEntry>[];
    }
    final web.IDBObjectStore store = _read();
    final web.IDBKeyRange range = web.IDBKeyRange.bound(
      _key(start),
      _key(end),
      false,
      true,
    );
    if (!reverse) {
      // Two requests of one transaction see the same data: the keys and the values of the range.
      final Future<JSAny?> keys = limit == null
          ? _request(store.getAllKeys(range))
          : _request(store.getAllKeys(range, limit));
      final Future<JSAny?> values = limit == null
          ? _request(store.getAll(range))
          : _request(store.getAll(range, limit));
      final List<JSAny?> keyList = ((await keys)! as JSArray<JSAny?>).toDart;
      final List<JSAny?> valueList =
          ((await values)! as JSArray<JSAny?>).toDart;
      return <CacheStoreEntry>[
        for (int i = 0; i < keyList.length; i++)
          CacheStoreEntry(_bytes(keyList[i]!), _bytes(valueList[i]!)),
      ];
    }
    // getAll has no direction: a cursor that walks back from the end.
    final List<CacheStoreEntry> result = <CacheStoreEntry>[];
    final web.IDBRequest request = store.openCursor(range, 'prev');
    final Completer<void> done = Completer<void>();
    request.onsuccess = ((web.Event _) {
      final web.IDBCursorWithValue? cursor =
          request.result as web.IDBCursorWithValue?;
      if (cursor == null) {
        done.complete();
        return;
      }
      result.add(CacheStoreEntry(_bytes(cursor.key!), _bytes(cursor.value!)));
      if (limit != null && result.length >= limit) {
        done.complete();
      } else {
        cursor.continue_();
      }
    }).toJS;
    request.onerror = ((web.Event _) {
      if (!done.isCompleted) {
        done.completeError(_error(request.error));
      }
    }).toJS;
    await done.future;
    return result;
  }

  @override
  Future<void> write(List<CacheStoreEntry> puts, List<Uint8List> deletes) {
    if (puts.isEmpty && deletes.isEmpty) {
      return Future<void>.value();
    }
    final web.IDBTransaction transaction = _db.transaction(
      _entries.toJS,
      'readwrite',
      // Committed to disk before the future completes, as the contract asks.
      web.IDBTransactionOptions(durability: 'strict'),
    );
    final Completer<void> done = Completer<void>();
    transaction.oncomplete = ((web.Event _) => done.complete()).toJS;
    transaction.onabort = ((web.Event _) {
      if (!done.isCompleted) {
        done.completeError(_error(transaction.error));
      }
    }).toJS;
    final web.IDBObjectStore store = transaction.objectStore(_entries);
    for (final CacheStoreEntry entry in puts) {
      store.put(_value(entry.value), _key(entry.key));
    }
    for (final Uint8List key in deletes) {
      store.delete(_key(key));
    }
    return done.future;
  }

  web.IDBObjectStore _read() =>
      _db.transaction(_entries.toJS, 'readonly').objectStore(_entries);

  /// A key: IndexedDB copies the bytes of the view (and only those) into a binary key.
  static JSUint8Array _key(Uint8List bytes) => bytes.toJS;

  /// A value: IndexedDB clones the whole buffer behind a view, so a view of part of a buffer is copied first.
  static JSUint8Array _value(Uint8List bytes) =>
      bytes.offsetInBytes == 0 &&
          bytes.lengthInBytes == bytes.buffer.lengthInBytes
      ? bytes.toJS
      : Uint8List.fromList(bytes).toJS;

  /// The bytes of a key (an array buffer) or of a value (a Uint8Array).
  static Uint8List _bytes(JSAny value) => value.isA<JSArrayBuffer>()
      ? (value as JSArrayBuffer).toDart.asUint8List()
      : (value as JSUint8Array).toDart;

  static Future<JSAny?> _request(web.IDBRequest request) {
    final Completer<JSAny?> completer = Completer<JSAny?>();
    request.onsuccess = ((web.Event _) => completer.complete(
      request.result,
    )).toJS;
    request.onerror = ((web.Event _) => completer.completeError(
      _error(request.error),
    )).toJS;
    return completer.future;
  }

  static Object _error(web.DOMException? error) => StateError(
    'IndexedDB: ${error?.name ?? 'UnknownError'}: ${error?.message ?? 'aborted'}',
  );
}
