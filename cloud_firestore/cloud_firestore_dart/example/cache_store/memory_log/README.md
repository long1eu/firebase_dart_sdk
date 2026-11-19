# A cache store in plain Dart: a sorted map and a log file

`memory_log_store.dart` implements `CacheStore` of `package:cloud_firestore_dart/cache_store.dart`
(experimental) without any dependency: the data is a `SplayTreeMap` ordered by
`compareCacheStoreKeys`, and every write appends one record to a log file. It is the store to read
first when you write your own; it fits in one sitting.

- **Reads** (`get`, `scan`) read the map. The SDK keeps the writes of its own transactions and
  reads through them, so the store needs no transactions.
- **Writes**: `write` changes the map and appends the puts and deletes to the log as one record,
  which starts with its length, and flushes it. If the log cannot be written, it puts back what it
  replaced. Opening the store replays the log; a record that a crash cut short is ignored, so a
  write is kept whole or not at all.
- **Compaction**: when the log is several times the size of the data, opening the store rewrites
  it as one record (through a temporary file and a rename).
- Without a path, the store keeps its data in memory only, for tests.

It is meant to teach, not to hold a large cache: all the data is in memory, and every write
waits for a flush.

`main.dart` uses it as the cache of a Firestore instance: it writes offline, terminates the
instance, starts a new one over the same file and reads the pending writes back. It needs no
emulator and no project.

```sh
dart run example/cache_store/memory_log/main.dart
```

The checks of `package:cloud_firestore_dart/cache_store_testing.dart` run on this store in
`test/unit/firebase/firestore/local/cache_store_conformance_test.dart`, and the persistence tests
of the SDK use it (in memory) for the key-value cache.
