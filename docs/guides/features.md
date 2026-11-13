# Features and limits

What `cloud_firestore_dart` does, what it does not do yet, and the known gaps. The
[guides](README.md) explain each area.

## Features

- Documents, collections, collection groups, set/update/delete, `SetOptions` merge.
- Typed data converters: `withConverter<T>` on references and queries, generic snapshots.
- Queries: `where` filters including `!=` and `not-in`, `arrayContains(Any)`, `in`, as
  `whereEqualTo(...)`-style methods, `where('age', isGreaterThan: 18)` named arguments or
  `Filter` objects; composite `Filter.or` / `Filter.and` (OR queries, multiple inequality
  filters); `orderBy`, cursors, `limit` and `limitToLast`.
- Real-time listeners with `MetadataChanges`, and `ListenSource.cache` to listen to the local
  cache only.
- Aggregations: `Query.count()`, `Query.aggregate([...])` with `AggregateField.count/sum/average`,
  `Query.aggregateWithAliases({...})`.
- Vector values (`FieldValue.vector`) and `Query.findNearest` (server only; no local evaluation).
- BSON value types of Enterprise edition databases: `MinKey`, `MaxKey`, `Int32Value`,
  `Decimal128Value`, `BsonObjectId`, `BsonTimestamp`, `RegexValue` and `Blob.bsonBinary`.
- Pipelines (**preview**, Enterprise edition databases, server only): see
  [Pipelines](pipelines.md).
- Firestore Lite (**experimental**): a second entry point without cache, listeners and sync
  engine, where every call is one request. See [Firestore Lite](lite.md).
- Transactions with `TransactionOptions(maxAttempts)` and retry with exponential backoff,
  read-only transactions (`TransactionOptions(readOnly: true)`); write batches.
- Field transforms: server timestamp, increment, `FieldValue.maximum` / `minimum`, array union
  and remove. Transforms are folded into set/patch writes (the old `TransformMutation` is gone).
- Data bundles: `loadBundle`, `loadBundleStream`, `getNamedQuery`.
- Snapshots and references as JSON (`toJson` / `fromJson`, in the format of the JS SDK), and
  listeners resumed from a serialized snapshot.
- Offline cache in SQLite with LRU garbage collection; `FirestoreSettings.cacheSettings`
  (`PersistentCacheSettings`, `MemoryCacheSettings` with eager or LRU GC). Queries against the
  cache use the results of earlier listens instead of scanning the collection (index-free
  queries), and pending writes are kept as per-document overlays.
- Persistent cache indexes: `Firestore.persistentCacheIndexManager` lets the SDK create
  indexes for cache queries on its own (`enableIndexAutoCreation`), and the deprecated
  `Firestore.setIndexConfiguration` takes a `firestore.indexes.json` definition. See
  [Persistent cache indexes](offline_persistence.md#persistent-cache-indexes).
- `Firestore.waitForPendingWrites()`, `terminate()`, `clearPersistence()`, `snapshotsInSync`
  stream, `enableNetwork` / `disableNetwork`.
- Emulator support with a mock user token; `Firestore.setLogLevel`.
- Bloom-filter existence-filter handling on reconnect (server `expected_count`).
- gRPC keepalive, connect timeout, backoff reset on connectivity change, streams closed after
  one minute idle.
- App Check token plumbing: an `InternalAppCheckTokenProvider` set on the `FirebaseApp` makes
  every RPC carry the `x-firebase-appcheck` header (see `docs/app_check_design.md` in the repository). This
  package does not attest a device; you supply the provider.

## Not supported or not done

Not done:

- **Production.** Nothing has been run against production Firestore, and the Enterprise edition
  features only against the Enterprise edition emulator. The production verification kit and
  the opt-in real-project test mode exist but have not been run. The packages are not
  published.
- **Web beyond the experiment**: any browser other than Chrome (the OPFS storage was not run
  in Safari or Firefox either), and a cache shared between tabs or owned by a shared worker.
- **Pipelines** beyond the [preview](pipelines.md): local evaluation (an
  evaluator exists inside the package but the client does not use it yet) and real-time
  pipelines. Full-text search, window functions and explain options are encoded but were not
  run against a backend that supports them.
- `Query.findNearest` evaluation against the local cache.
- **Coordination between running clients that share one cache** (the multi-tab support of the
  JS SDK). Two clients on one SQLite file keep it consistent but do not see each other's
  listeners or pending writes; in a browser, one tab at a time. Sharing them (stage 3 of the
  multi-client plan) is deferred until after 0.1.0. See
  [Several clients on one cache](multiple_clients.md).
- **Persistent cache indexes** for queries with inequalities on several fields, and with a
  memory cache (neither exists upstream: such queries are scanned).
- Android-specific pieces of the Android SDK.
- A Firebase Auth SDK. Tokens for Firestore (user sign-in over REST, service accounts,
  Application Default Credentials) are in `firebase_auth_providers_dart`, see
  [Authentication](authentication.md). For federated sign-in, Storage and Realtime Database see
  [appsup-dart/firebase_dart](https://github.com/appsup-dart/firebase_dart).

Known gaps in what is done:

- **Plain maps with a reserved key.** A plain `Map` with one of the reserved keys (for example
  `{'__int__': 5}`) is rejected in document data, like every field name that begins and ends
  with `__`; as a query value or an `arrayUnion` / `arrayRemove` element it is read as the BSON
  value, like the backend does.
- **`Decimal128Value` aggregates.** The sum and the average of an aggregation that includes a
  `Decimal128Value` are a `Decimal128Value` (`getDouble` and `getInt` convert it).
- **Increments on BSON numbers.** The emulator (v1.22.0) replaces an `Int32Value` or
  `Decimal128Value` field with the operand of `FieldValue.increment` instead of adding to it, so
  the local result (which adds) could not be compared with a backend.
- **Transactions** can be applied twice when the answer to a commit is lost; see
  [Transactions](transactions_and_lifecycle.md#transactions).
- **App Check** tokens are sent on every gRPC, WebChannel, REST and Lite request (checked by
  a test proxy), but enforcement cannot be tested on the emulator.
- The Enterprise edition differences listed under [Testing](emulator_and_testing.md#enterprise-edition-differences) and the
  emulator gaps listed under [Pipelines](pipelines.md).

## Design notes

In the [GitHub repository](https://github.com/long1eu/firebase_dart_sdk):
`cloud_firestore/cloud_firestore_dart/docs/api_modernization_plan.md` (status of the Dart-idiom
API work), `cloud_firestore/cloud_firestore_dart/docs/app_check_design.md`, and
`docs/update_transforms_design.md`.

Issues and pull requests: https://github.com/long1eu/firebase_dart_sdk
