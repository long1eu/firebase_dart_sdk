# A cache in your own storage

`package:cloud_firestore_dart/cache_store.dart` keeps the persistent cache in storage that your app
provides. You implement `CacheStore`, an ordered key-value store of bytes with five methods, and
pass it to `keyValueCacheSettings`. The SDK lays out the whole cache in that store: documents,
pending writes, overlays, targets, garbage collection, cache indexes and bundles. It keeps the same
behaviour as the SQLite cache for a single client.

```dart
import 'package:cloud_firestore_dart/cache_store.dart';

Future<void> withMyStore(CacheStore store) async {
  final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
    app: app,
    settings: Settings(cacheSettings: keyValueCacheSettings(store: store)),
  );
  await firestore.collection('notes').add(<String, Object?>{'text': 'kept in my store'});
}
```

The cache is in a library of its own, so only apps that import it carry its code.
`keyValueCacheSettings` takes the same options as `PersistentCacheSettings`: `sizeBytes` (the
garbage collection threshold), `indexAutoCreation`, `indexBackfill` and `mergeUnsentWrites`.

## When to use it

Use the SQLite cache (`PersistentCacheSettings` with an `openDatabase` of
`cloud_firestore_dart_sqlite`) unless one of these applies:

- The app already has a storage engine (an embedded database, a platform key-value store, an
  encrypted store, a file format of its own) and should not ship SQLite as well.
- The cache must be stored somewhere the SQLite opener cannot reach, or with encryption,
  compression or quotas that your storage applies.
- On the web, the app wants a cache without `sqlite3.wasm`. The IndexedDB example below is about
  70 lines.

Keep the SQLite cache when:

- **Several clients use one cache.** Hot restart, background isolates and second processes need
  the primary lease that only the SQLite cache has; see
  [Several clients on one cache](multiple_clients.md).
- **You want the most measured option.** The SQLite cache has more test coverage on more platforms,
  and its own SQL indexes.

## The contract

A store keeps byte keys and byte values. Keys are ordered by their unsigned bytes, and a key that
is a prefix of another comes first. This is the order of `memcmp`, LevelDB, a SQLite `BLOB` primary
key and IndexedDB array buffers.

| Method | What it does |
|---|---|
| `open()` | Opens the storage. Called when the instance starts, and again after `close()` when a new instance uses the same store. |
| `close()` | Closes it. Called by `terminate()`. |
| `get(key)` | The value under `key`, or null. |
| `scan(start, end, {reverse, limit})` | The entries with `start <= key < end`, in key order, or in reverse order, at most `limit` of them. |
| `write(puts, deletes)` | Stores all the puts and removes all the deletes, all or nothing, durable once the future completes. |

What the store must guarantee:

- **Order.** `scan` returns keys in the byte order above.
- **Atomic, durable writes.** `write` keeps all of its puts and deletes or none of them, even when
  the app crashes or the device turns off in the middle. Once its future completes, the data is on
  disk.
- **Reads see completed writes.** A `get` or `scan` that starts after a `write` completed sees it.
- **Bytes are kept as they are**, empty values included.

What the store may assume:

- **One writer at a time.** The SDK never calls `write` while another `write` or a read is
  running. Reads can run at the same time as each other.
- **No transactions needed.** The SDK keeps the writes of each of its transactions in memory and
  answers that transaction's reads from the store plus those writes. At commit it hands everything
  to the store in one `write`. A transaction that fails never reaches the store.
- **Arrays are not changed.** The SDK does not change the arrays it passes in, so the store may keep
  them, and it does not change the arrays the store returns.
- **One instance per store.** Only one Firestore instance uses a store at a time, and nothing else
  writes to it meanwhile.

When a call throws, the SDK takes it that the transaction that needed the call did not take
effect. A `write` that throws must have written nothing. The SDK also assumes the store may work
again later. The listen or write that needed the store fails with `unavailable`, an
acknowledgement or a remote change is kept and stored again later, and the client goes offline and
tries the store again with a backoff. This is what the JS SDK does when an IndexedDB transaction
fails.

A minimal store, in memory only, shows the shape. A real store must also make `write` durable:

```dart
import 'dart:collection';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/cache_store.dart';

class SortedMapStore implements CacheStore {
  final SplayTreeMap<Uint8List, Uint8List> _data =
      SplayTreeMap<Uint8List, Uint8List>(compareCacheStoreKeys);

  @override
  Future<void> open() async {}

  @override
  Future<void> close() async {}

  @override
  Future<Uint8List?> get(Uint8List key) async => _data[key];

  @override
  Future<List<CacheStoreEntry>> scan(Uint8List start, Uint8List end,
      {bool reverse = false, int? limit}) async {
    final Iterable<MapEntry<Uint8List, Uint8List>> range = _data.entries.where(
        (MapEntry<Uint8List, Uint8List> e) =>
            compareCacheStoreKeys(e.key, start) >= 0 &&
            compareCacheStoreKeys(e.key, end) < 0);
    final Iterable<MapEntry<Uint8List, Uint8List>> ordered =
        reverse ? range.toList().reversed : range;
    return <CacheStoreEntry>[
      for (final MapEntry<Uint8List, Uint8List> e
          in limit == null ? ordered : ordered.take(limit))
        CacheStoreEntry(e.key, e.value),
    ];
  }

  @override
  Future<void> write(List<CacheStoreEntry> puts, List<Uint8List> deletes) async {
    for (final CacheStoreEntry entry in puts) {
      _data[entry.key] = entry.value;
    }
    deletes.forEach(_data.remove);
  }
}
```

## The example stores

`cloud_firestore/cloud_firestore_dart/example/cache_store/` has three stores. Each one has a README
and a `main.dart` that writes offline, terminates the instance, starts a new one over the same
storage and reads the pending writes back. None of them needs an emulator or a project.

| Example | Storage | Read it for |
|---|---|---|
| [`memory_log`](../../cloud_firestore/cloud_firestore_dart/example/cache_store/memory_log/) | a `SplayTreeMap` in memory, made durable by an append-only log file that is replayed on open and compacted | the smallest complete store, in plain Dart with no dependency. It holds all data in memory, so it is not meant for a large cache |
| [`sqlite`](../../cloud_firestore/cloud_firestore_dart/example/cache_store/sqlite/) | one SQLite table `entries (key BLOB PRIMARY KEY, value BLOB) WITHOUT ROWID`, through `package:sqlite3` | a store over an embedded database: `scan` is a range of the primary key and `write` is one SQLite transaction |
| [`indexeddb`](../../cloud_firestore/cloud_firestore_dart/example/cache_store/indexeddb/) | one IndexedDB object store, through `package:web` | the web: a cache without `sqlite3.wasm`. `write` is one read-write transaction with `durability: 'strict'` |

The SDK's own tests run the key-value cache over the `memory_log` store, in memory.

## Checking a store

`package:cloud_firestore_dart/cache_store_testing.dart` has the contract as a list of checks.
They need no test framework, and each one throws a `StateError` that says what is wrong:

```dart
import 'package:cloud_firestore_dart/cache_store.dart';
import 'package:cloud_firestore_dart/cache_store_testing.dart';
import 'package:test/test.dart';

void checkMyStore(CacheStore Function() newEmptyStore) {
  for (final CacheStoreCheck check in cacheStoreConformanceChecks) {
    test(check.name, () => check.run(newEmptyStore));
  }
}
```

The checks cover get, write and delete; the byte order of keys (unsigned, prefix first); scan
bounds, reverse order and limits; puts and deletes in one write; concurrent reads; keys and values
kept byte for byte (empty values, zero bytes, a 256 KB value, a 1 KB key); a large write read back
in pages; and data that is still there after `close` and `open`.

What the checks cannot verify is the hard part: that a `write` is **atomic and durable** when the
process dies or the device turns off. Test that yourself, the way the storage you build on is
tested. For example, kill the process in the middle of writes many times, reopen the store and
check that every write is either whole or absent. The log of `memory_log` ignores a record that a
crash cut short. SQLite and IndexedDB give this guarantee through their own transactions.

## Limits

- **One instance per store, one client.** A second instance whose store is still the cache of a
  running instance fails to start with `failed-precondition`. The cache has no primary lease, so
  two processes, isolates or tabs must not share a store. The SDK cannot detect that case, because
  it only sees the store object. Give each one its own store, or guard the store with a lock of your
  own (`navigator.locks` on the web, a file lock on the VM).
- **No tab coordination** on the web. The IndexedDB example store does not share a cache between
  tabs. Each tab needs its own database name or a lock.
- **A transaction is held in memory until it commits.** The writes of one SDK transaction stay in
  memory until its single `write`. Most transactions are small, but a remote event with many
  documents, loading a large bundle, `clearPersistence` (one `write` that deletes every key) and a
  migration of the stored format hold all of their writes at once.
- **Format and versions.** The SDK stores its own format with a schema version
  ([the stored format](../keyvalue_cache_format.md)). A newer SDK migrates the store of an older
  one when it opens it. An older SDK refuses the store of a newer one with `failed-precondition`,
  and `clearPersistence()` then starts an empty cache. There is no downgrade.
- **`clearPersistence()`** (after `terminate()`) deletes every key of the store with one `write`.
  It does not delete the storage itself.
- **One database per store.** A store that holds the cache of another project or database is
  refused.

## Costs that grow with the cache

Measured with the SQLite example store on an Apple M5 laptop (`tool/bench/cache_store_costs_bench.dart`),
with 100,000 cached documents of about 250 bytes held by 100 targets (10,000 of them no longer held
by any target), and 10,000 pending writes:

| Operation | Time |
|---|---|
| `getPendingWriteCount()`, first call after the instance starts (reads every pending batch; in 0.3.0 every call did) | 7 to 11 ms |
| `getPendingWriteCount()`, later calls (the count is kept in memory) | under 0.1 ms |
| One more local write with 10,000 pending | 0.1 to 0.3 ms |
| One pass of garbage collection over the documents (each collection makes three: count, find the threshold, remove) | 90 to 200 ms |
| A garbage collection that removed 90 targets and 91,000 documents | 3 to 7 s |
| Restart (open the store and start the instance) | 2 ms |

Garbage collection reads the whole document-target table on each pass, the same way the SQLite
cache does (its query groups the `target_documents` table). It only runs when the cache is larger
than `sizeBytes` (100 MB by default), at most every few minutes, in the background.

## What is tested

- **Every shared persistence suite** also runs on this cache: the local store, the query engine,
  the mutation queue, the remote document cache, the query cache, overlays, LRU garbage collection,
  the index manager and backfiller, bundles, globals, and the upstream spec tests, including the
  ones that restart the client (`test/unit/firebase/firestore/local/keyvalue_*_test.dart`,
  `test/unit/firebase/firestore/spec/keyvalue_spec_test.dart`). The multi-client suites are left
  out, because the key-value cache supports one client.
- **Failures and crashes** (`keyvalue_fault_tolerance_test.dart`): a `write`, `get` or `scan` that
  throws leaves the cache usable, with its in-memory state read again from the store. A process
  that dies before or after a `write` (simulated by dropping the persistence without closing it and
  opening the same data again) reopens in the state of the last completed write. Pending writes are
  neither lost nor duplicated, and acknowledgements resume. A seeded random run of writes,
  acknowledgements, rejections and remote events, with failures and crashes at random points, is
  compared with a model after every step.
- **The stored format** (`keyvalue_schema_test.dart`): a fixture of what each schema version wrote
  must open and read back, and a format change without a new schema version fails the test.
- **The example stores**: the conformance checks run on `memory_log` and `sqlite` on the VM and on
  `indexeddb` in Chrome (dart2js and dart2wasm), along with each example's end-to-end case.

What is not verified: whether your store's `write` is atomic and durable through a real crash or
power loss (see [Checking a store](#checking-a-store)), stores on platforms other than the VM on
macOS and Chrome, and very large caches beyond the numbers above.
