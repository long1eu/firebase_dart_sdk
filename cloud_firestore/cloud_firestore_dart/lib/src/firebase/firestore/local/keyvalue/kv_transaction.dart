import 'dart:collection';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/local/keyvalue/cache_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/keyvalue/kv_codec.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/database.dart';

final Future<void> _done = Future<void>.value();

/// What the SDK makes of an error of the store: the transaction that needed it did not take effect (the contract of
/// [CacheStore.write]), so it is a [TransientDatabaseException], which the SDK recovers from as the JS SDK does from a
/// failed IndexedDB transaction (the operation fails with `unavailable` or is retried with a backoff while the client
/// stays offline).
Never _storeFailed(String what, Object error, StackTrace stackTrace) {
  if (error is TransientDatabaseException) {
    Error.throwWithStackTrace(error, stackTrace);
  }
  Error.throwWithStackTrace(
    TransientDatabaseException(
      'The CacheStore failed in $what: ${error.runtimeType}',
      error,
    ),
    stackTrace,
  );
}

Future<T> _guard<T>(String what, Future<T> future) => future.catchError(
  (Object error, StackTrace stackTrace) =>
      _storeFailed(what, error, stackTrace),
);

/// The reads and writes of one transaction of the persistence.
///
/// The store has no transactions: the writes stay here, in key order (a put with its value, a delete with null), until
/// [commit] hands them to the store in one [CacheStore.write]. The reads see them: [get] and [scan] read the store and
/// lay these writes over what it returns. A transaction that rolls back is simply dropped.
class KvTransaction {
  KvTransaction(this._store, {this.autoCommit = false});

  final CacheStore _store;

  /// Whether each write goes to the store at once (outside of a transaction, in tests).
  final bool autoCommit;

  final SplayTreeMap<Uint8List, Uint8List?> _writes =
      SplayTreeMap<Uint8List, Uint8List?>(compareCacheStoreKeys);

  Future<Uint8List?> get(Uint8List key) {
    if (_writes.containsKey(key)) {
      return Future<Uint8List?>.value(_writes[key]);
    }
    return _get(key);
  }

  Future<void> put(Uint8List key, Uint8List value) {
    if (autoCommit) {
      return _write(<CacheStoreEntry>[
        CacheStoreEntry(key, value),
      ], const <Uint8List>[]);
    }
    _writes[key] = value;
    return _done;
  }

  Future<void> delete(Uint8List key) {
    if (autoCommit) {
      return _write(const <CacheStoreEntry>[], <Uint8List>[key]);
    }
    _writes[key] = null;
    return _done;
  }

  /// Hands the writes to the store, in one write.
  Future<void> commit() {
    if (_writes.isEmpty) {
      return _done;
    }
    final List<CacheStoreEntry> puts = <CacheStoreEntry>[];
    final List<Uint8List> deletes = <Uint8List>[];
    _writes.forEach((Uint8List key, Uint8List? value) {
      if (value == null) {
        deletes.add(key);
      } else {
        puts.add(CacheStoreEntry(key, value));
      }
    });
    _writes.clear();
    return _write(puts, deletes);
  }

  // The calls of the store, whose errors are made [TransientDatabaseException]s (see [_storeFailed]).

  Future<Uint8List?> _get(Uint8List key) {
    try {
      return _guard('get', _store.get(key));
    } catch (error, stackTrace) {
      _storeFailed('get', error, stackTrace);
    }
  }

  Future<List<CacheStoreEntry>> _scan(
    Uint8List start,
    Uint8List end, {
    required bool reverse,
    int? limit,
  }) {
    try {
      return _guard(
        'scan',
        _store.scan(start, end, reverse: reverse, limit: limit),
      );
    } catch (error, stackTrace) {
      _storeFailed('scan', error, stackTrace);
    }
  }

  Future<void> _write(List<CacheStoreEntry> puts, List<Uint8List> deletes) {
    try {
      return _guard('write', _store.write(puts, deletes));
    } catch (error, stackTrace) {
      _storeFailed('write', error, stackTrace);
    }
  }

  /// The first written key that is at least [key].
  Uint8List? _firstFrom(Uint8List key) =>
      _writes.containsKey(key) ? key : _writes.firstKeyAfter(key);

  /// The entries of [start] to [end] (see [CacheStore.scan]): the store's, with the writes of this transaction laid
  /// over them.
  ///
  /// A page of the store of `limit` entries gives the keys of the store up to its last key. Writes up to that key are
  /// merged in; when deletes took entries out and the page is short of the limit, the next page continues after it.
  Future<List<CacheStoreEntry>> scan(
    Uint8List start,
    Uint8List end, {
    bool reverse = false,
    int? limit,
  }) async {
    final Uint8List? firstWrite = _writes.isEmpty ? null : _firstFrom(start);
    if (firstWrite == null || compareCacheStoreKeys(firstWrite, end) >= 0) {
      return _scan(start, end, reverse: reverse, limit: limit);
    }
    final List<CacheStoreEntry> result = <CacheStoreEntry>[];
    if (limit != null && limit <= 0) {
      return result;
    }
    // In the order of the scan: negative when a comes before b.
    int order(Uint8List a, Uint8List b) =>
        reverse ? compareCacheStoreKeys(b, a) : compareCacheStoreKeys(a, b);
    // The range still to read: [from, to).
    Uint8List from = start;
    Uint8List to = end;
    while (true) {
      final int? wanted = limit == null ? null : limit - result.length;
      final List<CacheStoreEntry> page = await _scan(
        from,
        to,
        reverse: reverse,
        limit: wanted,
      );
      final bool last = wanted == null || page.length < wanted;
      // The store's keys are all known up to here (in the order of the scan), or up to the end of the range.
      final Uint8List? known = last ? null : page.last.key;
      bool inKnown(Uint8List key) => known != null
          ? order(key, known) <= 0
          : (reverse
                ? compareCacheStoreKeys(key, from) >= 0
                : compareCacheStoreKeys(key, to) < 0);

      Uint8List? write = reverse ? _writes.lastKeyBefore(to) : _firstFrom(from);
      int index = 0;
      while (limit == null || result.length < limit) {
        final CacheStoreEntry? stored = index < page.length
            ? page[index]
            : null;
        final bool hasWrite = write != null && inKnown(write);
        if (stored == null && !hasWrite) {
          break;
        }
        final int compared = stored == null
            ? 1
            : (!hasWrite ? -1 : order(stored.key, write));
        if (compared < 0) {
          result.add(stored!);
          index++;
        } else {
          final Uint8List? value = _writes[write!];
          if (value != null) {
            result.add(CacheStoreEntry(write, value));
          }
          if (compared == 0) {
            index++;
          }
          write = reverse
              ? _writes.lastKeyBefore(write)
              : _writes.firstKeyAfter(write);
        }
      }
      if (last || (limit != null && result.length >= limit)) {
        return result;
      }
      if (reverse) {
        to = page.last.key;
      } else {
        from = keySuccessor(page.last.key);
      }
    }
  }
}
