# cloud_firestore_dart examples

Small command-line programs, one per topic. They run against the local Firestore emulator
(`firebase emulators:start --only firestore --project demo-example`):

```sh
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run example/main.dart
```

| File | Shows |
|---|---|
| `main.dart` | Quick start: `set` and `add`, a read, a query, a listener, a batch, a transaction, `count`. |
| `server.dart` | Firestore in a backend process: a JSON API over HTTP that shares one instance across requests, keeps no cache on disk, reads with `Source.server` and writes with a batch and a transaction. |
| `crud_and_listeners.dart` | `set` / `add` / `update` / `delete`, field transforms, merge, collection and document listeners. |
| `queries.dart` | `where` with named arguments, `Filter.or` / `Filter.and`, `orderBy`, `limit`, `limitToLast`, cursors. |
| `aggregations.dart` | `count`, `sum`, `average`, and `aggregateWithAliases`. |
| `converters.dart` | `withConverter<T>` with a function pair or a `FirestoreDataConverter` subclass. |
| `transactions_and_batches.dart` | `WriteBatch`, `runBatch`, read-write and read-only transactions, `maxAttempts`. |
| `bundles.dart` | `loadBundle`, progress, reading bundled documents from the cache, `getNamedQuery`. |
| `snapshot_json.dart` | `toJson` / `fromJson` on snapshots and references, `querySnapshotsFromJson` to resume a listener. |
| `offline_persistence.dart` | A SQLite cache on disk: reading and writing offline, syncing when back online. |
| `cache_indexes.dart` | Persistent cache indexes: `persistentCacheIndexManager`, automatic index creation, `deleteAllIndexes`. |
| `sqlite_database_web.dart` | The `OpenDatabase` for browsers: SQLite as WebAssembly with the database in IndexedDB, one tab at a time. Copy it into your app. Not a command-line program. |
| `sqlite_opfs_worker.dart` | The worker of the OPFS storage of `sqlite_database_web.dart` (experimental). Copy it next to that file and compile it to JavaScript. Not a command-line program. |
| `sqlite_database.dart` | The complete `OpenDatabase` on top of `package:sqlite3` used by the examples around it. Copy it into your app. |
| `emulator_mock_user_token.dart` | `withEmulator` and `mockUserToken` to act as a signed-in user. |
| `lifecycle.dart` | `setLogLevel`, `waitForPendingWrites`, `snapshotsInSync`, `terminate`, `clearPersistence`. |
| `lite.dart` | Firestore Lite (experimental, `package:cloud_firestore_dart/lite.dart`): the client without cache and listeners. Reads, writes, a batch, queries with `limitToLast` and cursors, aggregations, a converter, a transaction, `terminate`. Does not use `common.dart`, so that it only imports the lite library. |
| `pipelines.dart` | Pipelines (preview): stages, expressions, grouped aggregation, lambdas, `createFrom(query)`, subqueries, an atomic `update`. Needs an Enterprise edition emulator (`FIRESTORE_ENTERPRISE_EMULATOR_HOST`); prints a note and exits without one. |

`common.dart` holds the setup the examples share (a `FirebaseApp` for the `demo-example`
project and emulator settings). Every example ends with `firestore.terminate()`; without it
the open gRPC channel keeps the process alive.

In the [repository](https://github.com/long1eu/firebase_dart_sdk/tree/main/cloud_firestore/cloud_firestore_dart),
`test/integration/firebase/firestore/examples_smoke_test.dart` runs all of them against the
emulator, and checks what `main.dart`, `server.dart`, `offline_persistence.dart` and `lite.dart`
print. `test/integration_enterprise/examples_enterprise_smoke_test.dart` runs
`pipelines.dart` against the Enterprise edition emulator.
