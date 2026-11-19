# A cache store on SQLite

`sqlite_cache_store.dart` implements `CacheStore` of `package:cloud_firestore_dart/cache_store.dart`
(experimental) on one SQLite table, through [`package:sqlite3`](https://pub.dev/packages/sqlite3):

```sql
CREATE TABLE entries (key BLOB PRIMARY KEY, value BLOB NOT NULL) WITHOUT ROWID
```

SQLite compares BLOBs byte by byte, a shorter key first when it is a prefix of the other: the
order the store contract asks for. So `scan` is a range of the primary key, and `write` is one
SQLite transaction (`BEGIN IMMEDIATE`, the puts and deletes, `COMMIT`, or `ROLLBACK` when a
statement fails).

The reads share one read transaction that ends when the event loop turns, or before a write: a
SQLite statement outside of a transaction takes and releases its locks by itself, which costs
about as much as a read by key, and the SDK reads several times per document within one turn.
Nobody else writes to the store while the SDK uses it, so this changes nothing in what the reads
see.

This shows the shape of a store over an embedded database. It is not how this SDK's default
persistent cache works: `PersistentCacheSettings` keeps its own SQL schema, with a table per cache
and SQL indexes, where the key-value cache lays everything out in this one table.

`main.dart` writes offline, terminates the instance, starts a new one over the same database file
and reads the pending writes back. It needs no emulator and no project.

```sh
dart run example/cache_store/sqlite/main.dart
```

`package:sqlite3` loads the SQLite library of the system (on Linux, install `libsqlite3`). The
checks of `package:cloud_firestore_dart/cache_store_testing.dart` run on this store in
`test/unit/firebase/firestore/local/cache_store_conformance_test.dart`.
