## 0.1.0

First release under the new name. This package was published as `cloud_firestore_vm` (last
version 0.0.7, April 2020); it is the same code base, revived. One entry covers the whole
revival. Everything below was verified with the unit suite and the local Firestore emulator
only. **Nothing was run against production Firestore.**

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

- Dart 3 (`sdk: ^3.0.0`) with sound null safety; dependencies updated (`grpc`, `protobuf`,
  `rxdart`, `sqlite3`, ...).
- Read-write transactions no longer fail with "Every document read in a transaction must also be written":
  documents that were read but not written are sent as `VerifyMutation`s at commit (upstream ef38ef7), so
  the transaction retries if they changed.
- Default transaction attempts changed from 6 to 5 (now `TransactionOptions.defaultMaxAttempts`).
- Idle stream timeout changed from 10 seconds to 1 minute (as Android).
- `FirebaseApp.setDataCollectionDefaultEnabled` (`firebase_app_dart`) now takes a required
  named `enabled` parameter.
- `FirebaseApp.persistenceKey` now uses URL-safe base64 without padding; keys computed by older
  versions differ.
- `TransformMutation` is removed: field transforms are folded into set/patch mutations
  (`update_transforms`). Stored legacy transform writes are squashed on load by the local
  serializer.
- A clean close of a stream by the server is now reported as `UNAVAILABLE` instead of being
  ignored (fixes a start hang).
- Locally mutated documents carry `SnapshotVersion.none`, as upstream.
- Deprecated, still working: `Firestore.getInstance` (use `instanceFor`), `document` (use
  `doc`), `DocumentSnapshot.reference` (use `ref`), `QuerySnapshot.documents` /
  `documentChanges` (use `docs` / `docChanges`), `FieldPath.documentId()` (use
  `documentIdField`), `Source.defaultSource` (use `serverAndCache`). `FirebaseFirestore` and
  `Settings` are typedefs of `Firestore` and `FirestoreSettings`.
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
  - Deprecated, still working: `Firestore.shutdown` (use `terminate`).
- `Database.file` (a `dart:io` `File`) is replaced by `Database.path` (a `String`), so the
  persistence interface no longer needs `dart:io`. Implementations of `Database` must rename
  the getter.

### Added

- Firestore Pipelines as a **preview** in a separate library,
  `package:cloud_firestore_dart/pipelines.dart`: `firestore.pipeline()` with the sources
  `collection`, `collectionGroup`, `database`, `documents`, `literals` and `createFrom(query)`, the
  stages `where`, `select`, `addFields`, `removeFields`, `sort`, `limit`, `offset`, `aggregate`,
  `distinct`, `findNearest`, `sample`, `union`, `unnest`, `replaceWith` and `rawStage`, and
  expressions for comparisons, logic, math, strings, arrays, maps, timestamps and vectors.
  Pipelines need an Enterprise edition database and are always executed by the server (no
  cache, no offline support, no listeners). The API is experimental and may change. Tested
  with the unit suite and an Enterprise edition emulator only.

- BSON value types for Enterprise edition databases: `MinKey`, `MaxKey`, `Int32Value`,
  `Decimal128Value`, `BsonObjectId`, `BsonTimestamp`, `RegexValue`, and BSON binary data as a
  `Blob` with a subtype (`Blob.bsonBinary`, `Blob.subtype`). They can be written, read (with
  typed `DocumentSnapshot` getters such as `getInt32Value`), filtered and ordered, and the local
  cache sorts them like the backend. `Blob.fromJson` now accepts a `subtype`. Until now a
  document with such a field was read as a map like `{'__int__': 5}`.
- Value helpers from the JS SDK: `Timestamp.fromMillis` / `toMillis`, `Blob.fromBase64String` /
  `toBase64`, `AggregateQuerySnapshot.data()` (results keyed by alias), and `toJson` /
  `fromJson` on `Timestamp`, `GeoPoint` and `Blob` in the JS `toJSON()` shape (so `jsonEncode`
  works on them).
- `Query.where` also takes a field with FlutterFire-style named arguments:
  `where('age', isGreaterThanOrEqualTo: 18, isLessThan: 65)`, `where(FieldPath.documentIdField,
  whereIn: [...])`, `isNull: true/false`. `where(Filter)` keeps working (the parameter is now
  `Object`: a `Filter`, a `String` field or a `FieldPath`). Unlike FlutterFire, a call with a
  field and no non-null named argument throws an `ArgumentError` instead of returning the query
  unchanged.
- `Query.aggregateWithAliases({'total': AggregateField.sum('price')})`: aggregations with
  user-chosen aliases, as JS `getAggregateFromServer`; `AggregateQuerySnapshot.data()` is then
  keyed by those aliases (also exposed as `AggregateQuery.aliases`).
- `Timestamp.fromDate` / `toDate` are microsecond-accurate (they truncated to milliseconds);
  results for millisecond inputs are unchanged, and `DateTime` values written to documents keep
  their microseconds. `Timestamp.now()` still has millisecond precision.
- Typed data converters: `FirestoreDataConverter<T>` (with `FirestoreDataConverter.from`),
  `SnapshotOptions`, and `withConverter<T>` / `withoutConverter()` on `DocumentReference`,
  `CollectionReference` and `Query`. `DocumentReference`, `CollectionReference`, `Query`,
  `DocumentSnapshot`, `QueryDocumentSnapshot`, `QuerySnapshot` and `DocumentChange` are now
  generic; `set` / `add` / `WriteBatch.set` / `Transaction.set` take `T`, `data` returns `T`.
  Existing code that uses the references returned by `Firestore` keeps compiling (they are
  `...<Map<String, Object?>>`); a bare type annotation such as `DocumentSnapshot` now means
  `dynamic` data.
- Snapshot serialization (JS SDK `toJSON()` / `documentSnapshotFromJSON()` / `querySnapshotFromJSON()` /
  `onSnapshotResume()`): `DocumentSnapshot.toJson()`, `QuerySnapshot.toJson()`, `DocumentSnapshot.fromJson()`,
  `QuerySnapshot.fromJson()`, `Firestore.documentSnapshotsFromJson()` and `Firestore.querySnapshotsFromJson()`. The
  JSON holds the snapshot as a bundle string; resuming a query listen sends the snapshot's read time to the backend.
  Also `DocumentReference.toJson()` / `DocumentReference.fromJson()` and `VectorValue.toJson()` /
  `VectorValue.fromJson()`. The JSON and bundle formats are checked against the JS SDK (13.3.0) and firebase-admin
  by `test/integration/.../js_interop_test.dart` (needs `tool/interop`). Bundles with `OR` composite filters can now be
  loaded. Emulator-verified only.
- Read-only transactions: `TransactionOptions(readOnly: true)`, verified at commit with a `VerifyMutation`
  (new `verify` field in the vendored `write.proto`). Emulator-verified only.
- `Firestore.clearPersistence()`: deletes the local SQLite database (and its `-journal`, `-wal`,
  `-shm` files) of a terminated instance; fails with `failedPrecondition` while the instance runs, a
  no-op for memory persistence.
  It fails with `failedPrecondition` while a newer instance of the same app and database is running.
- `Firestore.instanceFor` no longer returns an instance whose `terminate()` is still in progress; a
  `QueryDocumentSnapshot` returns a null produced by a converter of a nullable type; `DocumentSnapshot`
  equality takes the converter into account.
- Transactions: a document lookup no longer resets its call as soon as the last document arrived. The
  reset could make the HTTP/2 connection fail every call in flight, so a commit that the backend had
  applied looked failed and was retried (a counter incremented twice). Transactions are also no longer
  retried once the instance is terminated.
- `Blob.bytes` returns a copy; out-of-range `Timestamp`s are rejected with an `ArgumentError` when written,
  also in builds without asserts; `FirestoreSettings.copyWith(cacheSettings: ...)` on settings that set
  `persistenceEnabled` or `cacheSizeBytes` throws instead of dropping them; a `mockUserToken` with an
  empty `sub` uses `user_id` for the user.
- `Firestore.setLogLevel(LogLevel)` with `debug`, `error` and `silent` (as the JS SDK);
  `setLoggingEnabled` still works.
- `FirestoreSettings.withEmulator(host, port, mockUserToken: ...)` (and the `mockUserToken`
  setting): a token string or a map of claims, encoded as an unsigned JWT like
  `connectFirestoreEmulator` of the JS SDK, sent as the bearer token to the emulator. It can only be
  set through `withEmulator`; settings that have a token and are pointed at another host throw an
  `ArgumentError`, so the unsigned token is never sent to production.

- Queries: `!=` / `not-in`, composite `Filter.or` / `Filter.and` (OR queries), multiple
  inequality filters, `limitToLast`, arrays in `whereIn` values.
- Aggregations: `count()`, `sum`, `average` through `RunAggregationQuery`.
- Vector values and `Query.findNearest` (server only).
- Data bundles and named queries (`loadBundle`, `loadBundleStream`, `getNamedQuery`).
- `FieldValue.maximum` / `FieldValue.minimum`.
- `FirestoreSettings.withEmulator`, cache settings (`PersistentCacheSettings`,
  `MemoryCacheSettings`), `ListenSource.cache` and `SnapshotListenOptions`.
- `Firestore.waitForPendingWrites`, `terminate`, `snapshotsInSync`; transaction retry with
  exponential backoff and `TransactionOptions(maxAttempts)`.
- App Check token plumbing (`x-firebase-appcheck` header); the enforcement side was not tested.
- Bloom-filter existence-filter handling, gRPC keepalive and connect timeout, backoff reset on
  connectivity change, instance cache per app and database, serial queue for remote store work.
- Every listen is sent to the backend with a fresh remote target id (as the JS SDK), so a late
  removal or error for an earlier listen of a query no longer rejects a newer listen of it.
- `ServerTimestampBehavior` is exported; `@internal` on constructors that leaked internals.
- Fixes from the upstream sync (UTF-8 string ordering, limbo handling, limbo-resolution
  document removal, transaction precondition, listener lifecycle and others); see
  `docs/upstream_sync/UPSTREAM_PLAN.md`.
- Test suite: unit tests, current-format upstream spec tests, a public API golden file, and an
  emulator integration suite. Protos resynced with current googleapis
  (`tool/gen_protos.sh`).

### Documentation

- Every exported class and member has a doc comment (members marked `@internal` say so), the
  library has an overview, and `dart doc` runs without warnings.

### Not done

Index-free queries / overlays / index engine, persistence clearing (API to be
decided), Pipelines.

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
