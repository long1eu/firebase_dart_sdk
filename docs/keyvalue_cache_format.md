# The stored format of the key-value cache

This note describes what the key-value cache (`package:cloud_firestore_dart/cache_store.dart`, a cache
in a `CacheStore` that the app supplies) writes into the store, and the rules for changing it. The code is in
`cloud_firestore/cloud_firestore_dart/lib/src/firebase/firestore/local/keyvalue/`. The cache data is
private to the SDK. An app never needs to read it, but a store must keep it byte for byte, and a
cache written by one release must open in the next.

## The store

The store keeps byte keys and byte values, ordered by the unsigned bytes of the key. A key that is a
prefix of another sorts first (`memcmp` order). The SDK uses only `get`, a range `scan` (forward or
reverse, with an optional limit) and an atomic `write` of puts and deletes. Every transaction of the
SDK becomes at most one `write`; see `CacheStore` for the full contract.

## Key encoding

A key is a sequence of parts written by `KvKeyWriter` (`kv_codec.dart`). The encoding preserves order:
comparing two encoded keys byte by byte gives the same result as comparing their parts one after the
other.

| part | bytes |
|---|---|
| string | its UTF-8 bytes, each `00` written as `00 FF`, then the terminator `00 01` |
| bytes (`bytesPart`) | the same escaping as a string |
| integer | 8 bytes, big endian, of the value plus 2^53; values between -2^53 and 2^53, so the web writes the same bytes |
| resource path | its segments as strings, then `00 00` |
| document key | the path of its collection, then its id as a string |
| snapshot version | two integers: seconds, nanoseconds |

The first part of every key is the table name, as a string. A table is therefore a key prefix, and
`prefixEnd` of that prefix ends a scan of the table.

## Value encoding

A value is either a protocol buffer (the same messages the SQLite cache stores: `MaybeDocument`,
`WriteBatch`, `Write`, `Target`, `BundledQuery`, `google.firestore.admin.v1.Index`), or a header of
`KvKeyWriter` parts followed by such a message, or only `KvKeyWriter` parts. Index tables and other
tables that hold only keys store an empty value.

## Tables

| table | key after the table name | value |
|---|---|---|
| `meta` | `version` | integer: the schema version |
| `meta` | `database` | UTF-8 `project/database` of the cache |
| `doc` | document key | read time, document type (integer: 1 deleted, 2 found, 3 unknown), `MaybeDocument` |
| `docRead` | collection path, read time, document id | empty |
| `collParent` | collection id, parent path | empty |
| `mutQueue` | uid | the last stream token (raw bytes) |
| `mut` | uid, batch id | `WriteBatch` |
| `docMut` | uid, document key, batch id | empty |
| `overlay` | uid, document key | integer largest batch id, `Write` |
| `overlayBatch` | uid, batch id, document key | empty |
| `overlayColl` | uid, collection path, batch id, document id | empty |
| `overlayGroup` | uid, collection group, batch id, document key | empty |
| `target` | target id | `Target` |
| `targetCanon` | canonical id, target id | empty |
| `targetDoc` | target id, document key | empty |
| `docTarget` | document key, target id | empty; for target id 0 (the LRU sentinel) the integer sequence number |
| `targetGlobal` | (nothing) | integers: highest target id, highest listen sequence number, last remote snapshot version (2), target count |
| `bundle` | bundle id | integers: schema version, create time (2), total documents, total bytes |
| `namedQuery` | name | read time, `BundledQuery` |
| `global` | `docBytes` | integer: total byte size of the values of `doc` (compared with the LRU threshold) |
| `global` | `value/<name>` | the value of `GlobalsCache.setValue`: `value/sessionToken` holds raw bytes, `value/queuedWritesMergeMark/<uid>` holds integers batch id, seconds, nanoseconds |
| `indexConfig` | index id | collection group, `Index` |
| `indexState` | uid, index id | integers: sequence number, read time (2), then the document key path, integer largest batch id |
| `indexEntry` | index id, uid, array value (bytes), directional value (bytes), document key | empty |
| `docIndexEntry` | index id, uid, document key, array value (bytes), directional value (bytes) | empty |

The uid is the user's uid, or the empty string when no user is signed in. Batch ids are unique
across the users of the cache.

## Schema version and migrations

`kvSchemaVersion` in `cache_store_persistence.dart` is the version this SDK writes. It is 1. Opening a
store does the following:

- An empty store gets `meta/version` and `meta/database`.
- A store with data and no version is refused, because it is not a cache.
- A store of a newer version is refused with `failed-precondition`. The message says that a newer SDK
  wrote it, and that clearing the store (`clearPersistence`) starts an empty cache. Nothing is
  written.
- A store of an older version is migrated. The migrations in `kvMigrations` (keyed by the version
  they upgrade to) run in order, all in the transaction that opens the store, and that transaction
  then writes the new version. The store holds either the old version or the new one, never part of
  a migration. A migration that fails leaves the store as it was. The writes of that transaction stay
  in memory until it commits, so a migration that rewrites a large table needs memory for all of it.
- A store of another database is refused.

There is no downgrade. A store migrated by a newer SDK is refused by the older SDK, which must clear
it. This differs from the SQLite cache, whose migrations are written so that older versions keep
working.

The list of migrations is empty today, but the check runs on every open, and
`keyvalue_schema_test.dart` tests the mechanism with migrations it adds itself.

## Changing the format

Any change to what is stored needs these four things together:

1. Increment `kvSchemaVersion`. A change here means a new table, a new key layout or a new value
   layout, or a different meaning for an existing value.
2. Add the migration of stores of the previous version to `kvMigrations`.
3. Add the fixture of the new version: `UPDATE_GOLDEN=1 dart test
   test/unit/firebase/firestore/local/keyvalue_schema_test.dart` writes
   `test/res/keyvalue/schema_<version>.json` and leaves the older fixtures alone.
4. Keep the fixtures of the older versions. They are what those releases wrote.

`keyvalue_schema_test.dart` enforces this:

- The cache written today by `writeFixtureCache` (one transaction that touches every table) must
  equal the fixture of the current version, byte for byte. A format change without a new version
  fails here.
- The fixture of every version from 1 to the current one must open, migrate and read back
  everything through the caches (`expectFixtureCache`).
- Every version after 1 must have a migration.

`test/res/keyvalue/schema_1.json` is the format of `cloud_firestore_dart` 0.3.0, the first release
with the key-value cache.
