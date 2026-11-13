## 0.1.0

First release under the new name. This package was published as `cloud_firestore_vm` (last
version 0.0.7, April 2020); it is the same code base, revived and brought forward to roughly
the behaviour of the current Android and JS SDKs. One entry covers the whole revival.

The published package contains `lib/` and `example/`. Tests, tooling and design notes (the
`test/`, `tool/` and `docs/` paths mentioned below) are in the
[repository](https://github.com/long1eu/firebase_dart_sdk).

How this was verified:

- Unit tests, the spec tests shared with the JS and Android SDKs, and integration tests against
  the local Firestore emulator. **Nothing was run against production Firestore.**
- Features of the Enterprise edition (BSON value types, Pipelines) were run against the
  emulator in Enterprise edition only.
- Web support is experimental: it was run in Chrome only, against the emulator only, with a
  memory cache or the opt-in SQLite cache in IndexedDB (browser tests, and the standard
  integration suite on the VM over the web transport).

### Renamed packages

- `cloud_firestore_vm` is now `cloud_firestore_dart`: import
  `package:cloud_firestore_dart/cloud_firestore_dart.dart`.
- `firebase_core_vm` is now `firebase_app_dart` (`FirebaseApp`, `FirebaseOptions`, ... keep
  their names).
- `_firebase_database_collection_vm` is folded into this package and `_firebase_internal_vm`
  into `firebase_app_dart`; neither is a separate dependency any more.
- The Flutter example app is replaced by command-line examples, one per topic, in `example/`
  (including a complete `package:sqlite3` opener for offline persistence); they run against the
  Firestore emulator.
- Migration guide with before/after code:
  [docs/migrating_from_vm_packages.md](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/migrating_from_vm_packages.md).

### Breaking changes

Requirements:

- Dart 3.8 (`sdk: ^3.8.0`, required by `grpc` 5) with sound null safety; dependencies updated
  to the current majors (`grpc` ^5.1.0, `protobuf` ^6.1.0, `rxdart`, ...). Values that can be
  missing are nullable: `DocumentSnapshot.data` is null for a missing document and field values
  are `Object?`.

API changes that need code changes:

- `DocumentReference`, `CollectionReference`, `Query`, `DocumentSnapshot`,
  `QueryDocumentSnapshot`, `QuerySnapshot` and `DocumentChange` are generic in the type of the
  document data (see typed data converters under Added). Code that uses the references returned
  by `Firestore` keeps compiling (they are `...<Map<String, Object?>>`); a bare type annotation
  such as `DocumentSnapshot` now means `dynamic` data.
- `Database.file` (a `dart:io` `File`) is replaced by `Database.path` (a `String`), so the
  persistence interface no longer needs `dart:io`. Implementations of `Database` must rename
  the getter.
- `FirebaseApp.setDataCollectionDefaultEnabled` (`firebase_app_dart`) now takes a required
  named `enabled` parameter.
- Narrowed public API (internals that leaked through the barrel or as public members):
  - No longer exported: `ConflictAlgorithm`, `maxVectorQueryLimit`, `maxVectorQueryDimensions`.
    From `util/database.dart` only the SQLite opener contract stays public: `Database`,
    `OpenDatabase`, `OnConfigure`, `OnCreate`, `OnOpen`, `OnVersionChange` (now documented).
    `UnaryFilter` / `CompositeFilter` were already not exported; the API golden listed them by
    mistake.
  - Marked `@internal` (the analyzer reports any use outside this package; they will be made
    private or removed later): `Firestore(...)` constructor, `Firestore.newInstance`, `client`,
    `scheduler`, `dataConverter`, `databaseId` (use the new `Firestore.projectId` and
    `Firestore.databaseName` getters), `validateReference`; `Query.query`;
    `QuerySnapshot.snapshot`; `DocumentSnapshot.document`; `DocumentReference.key`;
    `SetOptions.fieldMask`; `FieldPath(...)` unnamed constructor, `internalPath`, `reserved`,
    `documentIdInstance` (use `FieldPath.documentIdField`); `FieldValue.elements`, `methodName`
    and the `isDelete` / `isServerTimestamp` / `isArrayUnion` / `isArrayRemove` /
    `isIncrement` / `isMinimum` / `isMaximum` getters; `AggregateField.alias`; the
    `AggregateQuery` and `AggregateQuerySnapshot` constructors; the `LoadBundleTask`
    constructor, `setResult`, `setException`, `updateProgress`;
    `LoadBundleTaskProgress.forInitial` / `forSuccess`; `FirestoreErrorCode.fromValue`;
    `Timestamp.validateRange`.

Behaviour changes without a compile error:

- Read-write transactions no longer fail with "Every document read in a transaction must also
  be written": documents that were read but not written are sent as `VerifyMutation`s at commit
  (upstream ef38ef7), so the transaction retries if they changed.
- Operations on a terminated instance fail with a `FirestoreError` with the code
  `failedPrecondition` and the message "The client has already been terminated." (as the JS SDK;
  it was an `ArgumentError` "The client has already been shutdown"). The error always arrives
  through the returned `Future`, as the first event of a `Stream` (which then closes;
  `snapshotsInSync` used to stay silent) or through the `LoadBundleTask`, never as a
  synchronous throw. Builders that do no I/O (`collection`, `doc`, `batch`, `where`, ...) and
  committing an empty `WriteBatch` keep working, as upstream.
- Default transaction attempts changed from 6 to 5 (now `TransactionOptions.defaultMaxAttempts`).
- Idle stream timeout changed from 10 seconds to 1 minute (as Android).
- A clean close of a stream by the server is now reported as `UNAVAILABLE` and retried instead
  of being ignored (fixes a start hang).
- `TransformMutation` is removed: field transforms are folded into set/patch mutations
  (`update_transforms`). Stored legacy transform writes are squashed on load by the local
  serializer.
- Locally mutated documents carry `SnapshotVersion.none`, as upstream.
- The SQLite schema goes from version 8 to 13 (bundle tables, read times on remote documents,
  document overlays, and the tables of the client-side index engine, which nothing reads yet;
  see index-free queries and document overlays under Added). The migration
  runs through the opener's `onUpgrade` callback on the first open; pending writes are
  converted to overlays the first time the client starts. A cache written by
  `cloud_firestore_vm` 0.0.7 (schema 8) is migrated with its documents, targets (reused: the
  canonical ids did not change), pending writes (legacy transform writes are folded into the
  preceding write) and collection parents. Covered by a test on a schema 8 database
  reconstructed from the 0.0.7 sources, and by a migration test from every intermediate schema
  version.
- With overlays, array transforms (`arrayUnion` / `arrayRemove`) keep their local result until
  the write is acknowledged instead of being re-applied on top of newer server data (as
  upstream).
- `Timestamp.fromDate` / `toDate` are microsecond-accurate (they truncated to milliseconds);
  results for millisecond inputs are unchanged, and `DateTime` values written to documents keep
  their microseconds. `Timestamp.now()` still has millisecond precision.
- `Blob.bytes` returns a copy. Out-of-range `Timestamp`s are rejected with an `ArgumentError`
  when written, also in builds without asserts.
- `FirebaseApp.persistenceKey` (`firebase_app_dart`) now uses URL-safe base64 without padding;
  keys computed by older versions differ.

Deprecated, still working:

- `Firestore.getInstance` (use `instanceFor`), `Firestore.shutdown` (use `terminate`),
  `document` (use `doc`), `DocumentSnapshot.reference` (use `ref`), `QuerySnapshot.documents` /
  `documentChanges` (use `docs` / `docChanges`), `FieldPath.documentId()` (use
  `documentIdField`), `Source.defaultSource` (use `serverAndCache`). `FirebaseFirestore` and
  `Settings` are typedefs of `Firestore` and `FirestoreSettings`.
- Security hardening (from a review of both packages):
  - `FirestoreSettings` throws an `ArgumentError` for `sslEnabled: false` with the production
    host in every build mode (it was an `assert`, which release builds drop, so the auth token
    could be sent without TLS), whatever the case of the host or a trailing dot.
  - `FirestoreSettings.host` must be a host name or IP address: an empty value or one with
    `/`, `@`, `?`, `#`, `\` or whitespace is an `ArgumentError` (a value such as
    `firestore.googleapis.com@other.example` made the web transport talk to the other host).
  - Bundles are treated as untrusted input: a length prefix has to be at most 10 plain decimal
    digits, an element is at most 64 MiB (`BundleReader.maxElementBytes`), values and filters
    may be nested at most 100 levels, and fields of the wrong JSON type are reported as an
    invalid bundle. A stream without a valid element is rejected at once instead of being
    buffered, and elements that arrive in small chunks are no longer re-copied per chunk.
  - WebChannel responses with a negative, non-decimal or larger than 64 MiB chunk length end
    the stream with `unavailable`.

### Added

Queries and aggregations:

- Queries: `!=` / `not-in`, composite `Filter.or` / `Filter.and` (OR queries), multiple
  inequality filters, `limitToLast`, arrays in `whereIn` values.
- `Query.where` also takes a field with FlutterFire-style named arguments:
  `where('age', isGreaterThanOrEqualTo: 18, isLessThan: 65)`, `where(FieldPath.documentIdField,
  whereIn: [...])`, `isNull: true/false`. `where(Filter)` keeps working (the parameter is now
  `Object`: a `Filter`, a `String` field or a `FieldPath`). Unlike FlutterFire, a call with a
  field and no non-null named argument throws an `ArgumentError` instead of returning the query
  unchanged.
- Aggregations: `count()`, `sum`, `average` through `RunAggregationQuery`.
  `Query.aggregateWithAliases({'total': AggregateField.sum('price')})` runs aggregations with
  user-chosen aliases, as JS `getAggregateFromServer`; `AggregateQuerySnapshot.data()` returns
  the results keyed by alias (also exposed as `AggregateQuery.aliases`).
- Vector values and `Query.findNearest` (server only).

Data types:

- Typed data converters: `FirestoreDataConverter<T>` (with `FirestoreDataConverter.from`),
  `SnapshotOptions`, and `withConverter<T>` / `withoutConverter()` on `DocumentReference`,
  `CollectionReference` and `Query`. `set` / `add` / `WriteBatch.set` / `Transaction.set` take
  `T`, `data` returns `T`; a converter of a nullable type may return null, and snapshot equality
  takes the converter into account. `runTransaction<T>` is generic in its result.
- BSON value types for Enterprise edition databases: `MinKey`, `MaxKey`, `Int32Value`,
  `Decimal128Value`, `BsonObjectId`, `BsonTimestamp`, `RegexValue`, and BSON binary data as a
  `Blob` with a subtype (`Blob.bsonBinary`, `Blob.subtype`). They can be written, read (with
  typed `DocumentSnapshot` getters such as `getInt32Value`), filtered and ordered, and the local
  cache sorts them like the backend. `Blob.fromJson` accepts a `subtype`. Until now a
  document with such a field was read as a map like `{'__int__': 5}`.
  `AggregateQuerySnapshot.getDouble` / `getInt` convert a `Decimal128Value` sum or average, and
  a plain map with a reserved key used as a query value or as an `arrayUnion` / `arrayRemove`
  element (for example `{'__int__': 5}`) is read as the BSON value, so that the local cache
  evaluates the query like the backend. Verified on the Enterprise edition emulator only.
- Value helpers from the JS SDK: `Timestamp.fromMillis` / `toMillis`, `Blob.fromBase64String` /
  `toBase64`, and `toJson` / `fromJson` on `Timestamp`, `GeoPoint`, `Blob` and `VectorValue` in
  the JS `toJSON()` shape (so `jsonEncode` works on them).
- `ServerTimestampBehavior` is exported.

Transactions and writes:

- Read-only transactions: `TransactionOptions(readOnly: true)`, verified at commit with a
  `VerifyMutation` (new `verify` field in the vendored `write.proto`).
- Transaction retry with exponential backoff and `TransactionOptions(maxAttempts)`.
- `FieldValue.maximum` / `FieldValue.minimum`.

Listeners, cache and lifecycle:

- `Firestore.waitForPendingWrites`, `terminate`, `snapshotsInSync`.
- Cache settings (`PersistentCacheSettings`, `MemoryCacheSettings`), `ListenSource.cache` and
  `SnapshotListenOptions`.
- Persistent cache indexes (the client-side index engine of the Android and JS SDKs):
  `Firestore.persistentCacheIndexManager` with `enableIndexAutoCreation()`,
  `disableIndexAutoCreation()` and `deleteAllIndexes()`, and the deprecated
  `Firestore.setIndexConfiguration(json)`. Queries against the SQLite cache are served from an
  index when one matches (all operators, `in` / `not-in`, array membership, OR queries, cursors,
  limits), merged with the documents that are not indexed yet; indexes are filled in the
  background. Schema versions 12 and 13 add the tables. Not available with a memory cache.
  The stored index entries differ from the Android SDK's in two places where its encoding
  returns wrong results (references of different depths, BSON timestamps past 2^31 seconds).
- `Firestore.clearPersistence()`: deletes the local SQLite database (and its `-journal`, `-wal`,
  `-shm` files) of a terminated instance. It fails with `failedPrecondition` while the instance,
  or a newer instance of the same app and database, is running, and is a no-op for memory
  persistence.
- Index-free queries (upstream 21.3.0): queries that were synced before are executed from their
  cached result plus the documents read since then, instead of a full collection scan (SQLite
  schema version 10: read time columns on `remote_documents`). Older versions of the port can
  still open the database, and a later upgrade discards the data they could not maintain.
- Document overlays (upstream 24.0.0): the local view of documents with pending writes is stored
  as one overlay per document instead of replaying the whole mutation queue on every read and
  query (SQLite schema version 11).
- Data bundles and named queries (`loadBundle`, `loadBundleStream`, `getNamedQuery`), including
  bundles with `OR` composite filters.
- Snapshot serialization (JS SDK `toJSON()` / `documentSnapshotFromJSON()` /
  `querySnapshotFromJSON()` / `onSnapshotResume()`): `DocumentSnapshot.toJson()`,
  `QuerySnapshot.toJson()`, `DocumentSnapshot.fromJson()`, `QuerySnapshot.fromJson()`,
  `Firestore.documentSnapshotsFromJson()` and `Firestore.querySnapshotsFromJson()`. The JSON
  holds the snapshot as a bundle string; resuming a query listen sends the snapshot's read time
  to the backend. Also `DocumentReference.toJson()` / `DocumentReference.fromJson()`. The JSON
  and bundle formats are checked against the JS SDK (13.3.0) and firebase-admin by
  `test/integration/.../js_interop_test.dart` (needs `tool/interop`). A serialized snapshot
  keeps empty blobs and `-0.0`.

Emulator and logging:

- `FirestoreSettings.withEmulator(host, port, mockUserToken: ...)` (and the `mockUserToken`
  setting): a token string or a map of claims, encoded as an unsigned JWT like
  `connectFirestoreEmulator` of the JS SDK, sent as the bearer token to the emulator. It can only be
  set through `withEmulator`; settings that have a token and are pointed at another host throw an
  `ArgumentError`, so the unsigned token is never sent to production. A token with an empty `sub`
  uses `user_id` for the user.
- `Firestore.setLogLevel(LogLevel)` with `debug`, `error` and `silent` (as the JS SDK);
  `setLoggingEnabled` still works.

Pipelines (preview):

- Firestore Pipelines as a **preview** in a separate library,
  `package:cloud_firestore_dart/pipelines.dart`: `firestore.pipeline()` with the sources
  `collection`, `collectionGroup`, `database`, `documents`, `literals` and `createFrom(query)`, the
  stages `where`, `select`, `addFields`, `removeFields`, `sort`, `limit`, `offset`, `aggregate`,
  `distinct`, `findNearest`, `sample`, `union`, `unnest`, `replaceWith` and `rawStage`, and
  expressions for comparisons, logic, math, strings, arrays, maps, timestamps and vectors.
  Pipelines need an Enterprise edition database and are always executed by the server (no
  cache, no offline support, no listeners). The API is experimental and may change. Tested
  with the unit suite and an Enterprise edition emulator only.
- The preview also has the write stages `update`, `delete`, `insert` and `upsert` with
  `execute(atomic: true)`, variables and subqueries (`define`, `variable`, `subcollection`,
  `toArrayExpression`, `toScalarExpression`), lambda functions (`arrayFilter`,
  `arrayTransform`), `switchOn`, `nor`, and `PipelineSnapshot.explainStats`.
  `createFrom(query)`, `createFromAggregateQuery` and `createFromVectorQuery` convert the
  classic queries; `example/pipelines.dart` shows the API. A converted query returns what the
  classic query returns in two cases where the pipeline functions behave differently (the JS and
  Android SDKs do not add these checks): `!=` and `not-in` do not match a null value, and
  `array-contains` / `array-contains-any` skip a field that is not an array instead of failing
  the pipeline. Known difference: a cursor on a field that holds values of several types only
  returns the documents whose value has the type of the cursor value.
  Pipeline results return BSON values as their value classes.

Networking:

- App Check token plumbing (`x-firebase-appcheck` header); the enforcement side was not tested.
- Bloom-filter existence-filter handling, gRPC keepalive and connect timeout, backoff reset on
  connectivity change, instance cache per app and database, serial queue for remote store work.
- **Experimental web support.** The RPCs are behind a transport interface and the
  platform-specific code is behind conditional imports. Where `dart:io` is missing (browsers) the
  client uses a second network transport: REST/JSON for `Commit`, `BatchGetDocuments`,
  `RunQuery`, `RunAggregationQuery` and `ExecutePipeline`, and a WebChannel client for the
  `Listen` and `Write` streams, over `fetch` (`package:web`, a new dependency). This is what the
  JS SDK does; neither the backend nor the emulator accept gRPC-Web. The VM keeps using gRPC.
  Limits:
  - The cache is in memory on the web unless the application opts in to the SQLite cache in
    IndexedDB (below).
  - Verified against the emulator only: on the VM, where the whole standard integration suite
    runs over the web transport (`tool/test_integration.sh standard --transport=webchannel`, or
    `FIRESTORE_TEST_TRANSPORT=webchannel`), and in Chrome with 19 browser tests
    (`dart test -p chrome -c dart2wasm test/browser`; with `-c dart2js` 18 pass and 1 is
    skipped). No other browser and no production backend was tried.
  - Compile with dart2wasm to keep 64 bit integers exact. Compiled with dart2js, integers
    above 2^53 lose precision.
- **Opt-in persistence on the web** (experimental): `example/sqlite_database_web.dart` is a
  complete `OpenDatabase` for browsers, to copy into an application like
  `example/sqlite_database.dart`. It runs SQLite as WebAssembly (`package:sqlite3`, which stays
  out of this package's dependencies) with the database in IndexedDB, guards it with a Web Lock
  so that a second tab is refused with `failedPrecondition`, and waits for IndexedDB at the end
  of every transaction. New public interface `ClearableDatabase`: a `Database` that implements
  it deletes its own storage for `clearPersistence()`, which is how the IndexedDB database is
  removed (by default `clearPersistence` deletes the file at `Database.path`). Verified in
  Chrome against the emulator: data and pending writes survive a new page load of a tab that
  was not closed properly, a cache held by another browsing context is refused, the 14 schema
  migrations run one by one and at once, automatic cache indexes work, `clearPersistence`
  removes the database. Not verified: other browsers, large caches (the database is held in
  memory), a tab killed in the middle of a transaction.
- Web transport robustness (web only, the gRPC transport is unchanged):
  - `FirestoreSettings.experimentalForceLongPolling` and
    `experimentalAutoDetectLongPolling` (on by default), for networks where a proxy buffers
    streamed responses. Forced long polling was run against the emulator (the whole standard
    integration suite on the VM with `--transport=webchannel-longpolling`, and a test in
    Chrome). The automatic switch has the purpose of the JS option of the same name but its own
    detection (no data on the first stream response within 10 seconds), and was only tested
    with a simulated silent response, not behind a real buffering proxy.
  - Unary calls time out after 15 seconds with `DEADLINE_EXCEEDED`, as in the JS SDK.
  - The client listens to the `online` / `offline` events of the browser and restarts its
    streams when the network comes back.
  - A WebChannel session is now always terminated on the server: also when it is closed while
    its handshake is in flight, and the HTTP layer of a client that is terminated waits for
    those requests (up to 3 seconds) instead of cutting them off. Before, every terminated
    client left its sessions behind, and the emulator keeps a socket for each (see
    `tool/README.md`).
  - A stream request that is lost on the way is sent again with the same request id (the
    server applies an id once; checked on the emulator), and a listen or write response that
    is cut is asked for again from the last message that arrived, both after 100 ms and after
    1 s, before the stream fails with `UNAVAILABLE`. A WebChannel session therefore survives a
    cut connection without losing or repeating a message. The chaos tests (cuts, stalls,
    delays) run over the web transport as well.
  - Values are sent faithfully: an empty `Blob` was sent without its type (and rejected or
    misread), and the sign of `-0.0` was dropped before sending, also in a `GeoPoint`. They are
    now encoded like the JS SDK does (`"bytesValue": ""`, `"doubleValue": "-0"`). The JSON
    endpoints of the emulator (v1.22.0) still store `-0.0` as `0.0`, whatever its spelling, so
    the sign only round-trips there over gRPC.
  - Over WebChannel a failed write is reported as a message and the session goes on (seen on
    the emulator), so writes sent ahead of the failure are applied although the client closes
    the stream and sends them again: an `increment` behind a rejected write was counted twice.
    Over gRPC the backend ends the call instead. Writes are therefore only sent ahead of the
    answers to earlier writes when applying them twice is harmless: a write with an
    `increment` waits for all earlier answers, and so does a write that shares a document
    with a write in flight when one of the two has a precondition (`update`). Sets, merges,
    deletes and updates of distinct documents are sent ahead, up to the ten writes the client
    keeps in flight.
  - A WebChannel request that carries messages to the server and is not answered within 20
    seconds is aborted and sent again (with the same request id), instead of blocking every
    later message of the stream for ever on a connection that silently drops data.
  - Request headers with a line break are refused instead of being sent in the handshake, and
    `fetch` no longer follows redirects (a redirect would re-send the credentials elsewhere).
  - A clear `UnsupportedError` at start when the application was compiled with
    `-Dprotobuf.omit_field_names=true` or `-Dprotobuf.omit_enum_names=true`, which would
    make every request wrong.

Documentation and tests:

- Every exported class and member has a doc comment (members marked `@internal` say so), the
  library has an overview, and `dart doc` runs without warnings.
- Runnable examples in `example/`, README and migration guide snippets that are compiled by a
  test, and public API golden files for both libraries.
- Test suite: unit tests, the spec tests re-synced with JS SDK `main`, an emulator integration
  suite (also run against the Enterprise edition emulator), Enterprise-only tests in
  `test/integration_enterprise`, and an opt-in mode against a real project that has not been
  run. Protos resynced with current googleapis (`tool/gen_protos.sh`).

### Fixed

- Cache after a lost write acknowledgement: a write that is sent again and changes nothing on the backend is
  acknowledged with the unchanged update time of the document, and was then dropped from the cached document
  (as in the other SDKs), so `get(Source.cache)` returned the old value without a pending write until the document
  was read from the backend. It is now applied when the cached document is only the result of earlier
  acknowledgements. Emulator-verified only.
- The local evaluation of filters follows the backend in three places where the JS and Android
  SDKs do not: `whereIn`, `whereNotIn`, `arrayContains` and `arrayContainsAny` match numbers by
  value (`1` is `1.0`, `0.0` is `-0.0`); `<`, `<=`, `>` and `>=` do not order `null` and `NaN`
  (`a < 1` does not match a `NaN`, `a >= NaN` matches no number); `arrayUnion` and
  `arrayRemove` compare numbers by value. Before, a cached document that only the client
  matched stayed in limbo (the listener never left `isFromCache`, `get(Source.server)` did not
  complete), and after an array transform the cached document differed from the stored one.
  Found by the seeded property tests (`test/util/property.dart`).
- A cached document that the client matches for a query but the backend does not return no
  longer stays in limbo when the backend confirms that it exists (the JS and Android SDKs keep
  it there: the listener never leaves `isFromCache` and `get(Source.server)` does not
  complete). The view of that query drops the document once no pending write can explain the
  difference; it comes back when the backend returns it or when it is written locally. This
  covers the remaining known difference (`null` / `NaN` operands of `whereIn`, the array
  filters, `<=` and `>=` on a Standard edition database) and any other disagreement.
- A double and an integer beyond 2^53 are compared by their exact values (the order used to
  depend on the side of the operands).
- Fixes from the upstream sync (UTF-8 string ordering, limbo handling, limbo-resolution
  document removal, transaction precondition, listener lifecycle and others); see
  `docs/upstream_sync/UPSTREAM_PLAN.md`.
- Every listen is sent to the backend with a fresh remote target id (as the JS SDK), so a late
  removal or error for an earlier listen of a query no longer rejects a newer listen of it.
- A pending `set(..., merge)` on a document that the cache knows as deleted no longer hides the other
  fields of the document when the backend creates it before the write is acknowledged.
- Web transport: a listen or write stream that the client closes ends its WebChannel session right away
  instead of keeping it open for 10 seconds.
- The client no longer resets a call that the backend may be finishing (aggregate queries,
  stopped or idle listen and write streams, transaction lookups): it closes its side and lets
  the call end, and cancels it only if it is still open after 10 seconds. A reset that raced
  the end of a call made `package:http2` terminate the whole connection and fail every call in
  flight. For a transaction that meant a commit that the backend had applied looked failed and
  was retried (a counter incremented twice).
- Transactions are no longer retried once the instance is terminated.
- The SQLite persistence lock is per database instead of process-wide, so a long transaction in
  one `Firestore` instance no longer blocks the others.
- `Firestore.instanceFor` no longer returns an instance whose `terminate()` is still in
  progress. With a new `FirebaseApp` that has the name of a deleted one it no longer returns the
  instance of the deleted app (which was about to be terminated, since `FirebaseApp.delete()`
  terminates the instances of the app in the background): it waits for that instance to close
  and returns a new one on the same cache.
- `FirestoreSettings.copyWith(cacheSettings: ...)` on settings that set `persistenceEnabled` or
  `cacheSizeBytes` throws instead of dropping them.

### Not done

- Persistent cache indexes for queries with inequalities on several fields (they are scanned,
  as upstream), and indexes with a memory cache.
- Sharing the persistent cache between browser tabs (one tab at a time), OPFS storage, and
  any browser other than Chrome.
- Pipelines beyond the preview: full-text search, window functions, pipelines in a
  `Transaction`, evaluation against the local cache and real-time pipelines.
- Multi-tab / multi-process sharing of one cache, as in the JS SDK.
- Any run against production Firestore.

## Versions published as `cloud_firestore_vm`

## [0.0.7] - April 22, 2020 
* make Firestore.newInstance register the new instance with the multi db component
* add warning in case of not initializing FirebaseAuth prior to calling Firestore.instance 

## [0.0.6] - April 21, 2020 
* fix auth provider picker logic
* fix exporting Source

## [0.0.5] - April 18, 2020 
* fix null bool

## [0.0.4] - April 18, 2020 
* disable verbose logging
* make sql connection not exclusive so we don't break hot reload

## [0.0.3] - April 18, 2020 
* fix return when garbage collection kicks in

## [0.0.2] - April 18, 2020 
* update export statements

## [0.0.1] - April 18, 2020 
* initial release
