## Unreleased

- Persistent cache indexes: a limit query served by a field index could show a document that had left its window.
  The query engine looked beyond the window only when the document at its edge had a version (update time) after the
  index offset; a document delivered late by a target that lagged behind has an older version. It now also refills
  the window when the document at its edge changed in the cache after the offset. The JS and Android SDKs only test
  the version.
- Persistent cache indexes: the query engine could return documents that do not match the query, among the
  documents that changed after the offset of a field index, when none of them had a pending write.
- Persistent cache indexes: a query served by a field index could miss a document for good after one of the
  client's own writes. The acknowledged document is stored with the commit version as read time, and the index
  backfill moved past it; a document that watch delivered afterwards in a snapshot at or before that version was
  never indexed. While such an acknowledged document has not been sent by watch, the backfill now stops at the last
  snapshot version of watch. The JS and Android SDKs have the same gap.
- **Behaviour change:** `Firestore.instanceFor()` (and `getInstance`) throws a `StateError` when it is given settings
  that differ from those of the instance that already exists for the app and database, as the JS and Android SDKs
  do. Before, the new settings were silently ignored. Call it without settings to get the existing instance, or
  `terminate()` that instance first.
- A listener no longer gets an extra `modified` event, with pending writes and unchanged fields, when watch sends a
  document before the acknowledgement of a set with a server timestamp. A set overlay that comes from a real set is
  now applied as stored when the document arrives, as in the other SDKs; only one that stands for a merge or update
  of a document without a remote version is computed again.
- `FirestoreSettings.experimentalLongPollingOptions` (`timeoutSeconds`, 5 to 30) sets the long-polling timeout of
  the web transport, as in the JS SDK. The client reports online as soon as the watch stream connects rather than
  at its first message.
- Persistent cache indexes: after a write was rejected by the backend, a query served by a field index could miss
  the document, or return it as the rejected write had left it (for example a document that the user deleted, and
  whose delete was rejected, stayed out of the result). The index entries of the documents of a rejected write are
  now written when it is rejected. The Android SDK has the same gap.
- Web transport: writes that were in flight when the write stream was closed by the client (`disableNetwork()`, a
  credential change, an idle stream) could reach the backend later, after the same writes and newer ones had been
  sent on the next stream, and replace the newer values: the WebChannel session of the closed stream went on
  delivering what it had queued, sending a failed request again for up to its timeout. The session now ends when
  the stream is closed, as in the JS SDK: what was not sent is dropped (the client keeps unacknowledged writes and
  sends them again anyway), and a request in flight is not sent again.
- A listener could lose a document for good after an existence filter mismatch. The client then resets the target
  and listens to it again, and its documents go through limbo resolution. When a resolution confirmed a document
  before the backend had sent the target again, the view concluded that the backend does not return the document
  for the query and dropped it; it did not come back, and the snapshot was reported as in sync. That conclusion is
  now only drawn once watch marked the target CURRENT on the current stream.
- Web: a page sends the pending writes that the page before it left in a persistent cache as soon as it starts,
  and `waitForPendingWrites()` waits for them. Since the change below (writes belong to the client that made them)
  they were held back for 60 s after a reload, and `waitForPendingWrites()` returned without them. A `Database`
  whose opener holds an exclusive lock while it is open now says so with the new `ExclusiveDatabase` interface
  (the web openers of the example do, with their Web Lock): every other client of the cache is then known to be
  gone. If you copied `example/sqlite_database_web.dart` into your app, copy it again. On the VM the 60 s remain.
- `toString()` of the public classes is one line now, in the format of the Android SDK where it has one:
  `DocumentSnapshot{key=..., metadata=..., doc=...}`, `SnapshotMetadata{hasPendingWrites=..., isFromCache=...}`,
  `Blob { bytes=0102, subtype=0 }`, `FirestoreSettings{host=..., ...}`. A `QuerySnapshot` prints its query and the
  number of its documents, a `Query` its filters and orderings. `FirestoreErrorCode.cancelled` and
  `resourceExhausted` print their own names (they printed `canceled` and `resourcesExhausted`), and messages name
  the query operators as the JS SDK does (`array-contains`, `array-contains-any`, `not-in`).
- `Timestamp.toString()` is now `Timestamp(seconds=1, nanoseconds=2)`, as in the JS and Android SDKs. It used to
  print the two fields over four lines.
- The canonical ids of queries, which the SQLite cache stores to find the cached results of a query again, are now
  the ids of the JS SDK (`rooms|f:at<=time(60,3000)|ob:atasc,__name__asc`). They were built from the `toString()`
  of the values of a query, so they contained multi-line debug output and changed whenever such a `toString()`
  changed. An existing cache keeps its cached queries: the ids of its stored targets are computed again when it is
  opened (SQLite schema version 19).
- Error messages no longer contain multi-line debug output. `FirestoreError.toString()` is now
  `FirestoreError: [code=<code>]: <message>` (the JS format; it used to end in the cause and the stack trace, or
  `null null`), and messages that name a document print its path, for example
  `Failed to get document 'rooms/eros' from cache` (it printed `'DocumentKey {\n  path=rooms/eros,\n}'`).
- Two clients on one SQLite cache: the primary client now sends the pending writes of a client that is gone (it
  crashed or was killed, see below) at its next metadata refresh, every 4 s. It only looked for them when it wrote
  something itself, so with an idle primary they were never sent.
- Web transport: the double -0.0 read from production Firestore came back as 0.0. Production writes it as the
  JSON number `-0`, which `jsonDecode` reads as the int 0; the responses of REST and WebChannel are now decoded
  keeping the sign, as `JSON.parse` does in the JS SDK. (The emulator writes `-0.0`, so its tests did not show
  it.) Empty bytes were not affected.
- Two clients on one SQLite cache: the primary client no longer sends the pending writes of the other client. It
  sent them, but the other client was never told the result, so its `set()` and `waitForPendingWrites()` futures
  never completed. Each write now records the client that made it (SQLite schema version 18), and the primary sends
  only its own writes, the writes of a client that is gone (it terminated, or did not refresh its metadata, which a
  live client does every 4 s, for 60 s: it crashed or its app was killed) and the writes stored before this version.
  The other client sends its writes, and its futures complete, once it is primary itself. A client that stalls for
  more than 60 s (a paused isolate, an app in the background) can still have a write sent by the primary without
  being told the result.
- The switch of a SQLite cache to write-ahead logging is tried again a few times (within 1.5 s) when
  another connection opening the same file at that moment makes it fail with `database is locked`;
  if it still fails, that is logged at debug level instead of as a warning, and the next open
  switches the file.
- Web transport (and Firestore Lite on the web): the calls in flight when the instance is terminated fail with
  `unavailable`, as over gRPC. Their responses used to just end, so a transaction read failed with "Mismatch in
  docs returned from document lookup" and a commit with `unimplemented` ("No responses received").
- Web transport: a WebChannel stream (Listen, Write) sends the headers of the JS SDK's
  WebChannelConnection: the client, `Content-Type: text/plain`, the app id, the credentials and
  the API key. It no longer sends `google-cloud-resource-prefix` or `x-goog-request-params`, which
  JS sends only with unary calls; the stream is routed by its `database` URL parameter.
- The app id of the app (`FirebaseOptions.applicationId`) is sent with every request in the
  `x-firebase-gmpid` header, as the Android SDK (`x-firebase-gmpid`) and the JS SDK
  (`X-Firebase-GMPID`) do.
- Web transport: a REST call sends `x-goog-request-params` as the JS SDK's RestConnection does,
  `project_id=<project>` (with `&database_id=<database>` for a named database), instead of the
  database name the gRPC transport sends.
- Firestore Lite on the web sends the browser's cookies with its REST calls to a Cloud Workstations
  host (`*.cloudworkstations.dev`), as the JS SDK's FetchConnection does; other hosts get none.
- `FieldPath.fromServerFormat` (used for field paths from the backend, bundles and index configurations) rejects
  a path with an unterminated backtick, as the JS SDK does.
- A bundle whose document or document metadata names something other than a document (a collection, the
  `documents` root) or that holds a reference value that is not a document is now rejected as an invalid bundle
  (an `ArgumentError`), as in the iOS SDK. Before, the root name loaded a document with an empty key and the other
  names failed an internal assertion.
- The local view of a document is now right when its pending writes delete a nested field and later its
  parent (for example `a.b.c` set, then `a.b.c` and `a.b` deleted): the overlay kept for it handles the fields
  in order, as the JS and iOS SDKs do, and no longer drops the parent `a` left as an empty map.
- Argument validation errors are worded like the JS SDK's (the error types do not change).
  Invalid document data names the method, the field and the document, for example "Function
  WriteBatch.set() called with invalid data. Unsupported field value: a custom Foo object (found in
  field a in document c/d)", with "(via `toFirestore()`)" when a converter produced the data; this
  applies to where() and cursor values and to field path arguments too. An empty path passed to
  collection() or doc() fails with "Function Firestore.collection() cannot be called with an empty
  path." instead of a segment count. The messages of the pipelines are unchanged.
- A listen or write stream that the backend closes with UNAUTHENTICATED invalidates the token
  only if it has been open for less than 10 seconds, as in the Android and JS SDKs; a stream that
  was healthy keeps it. Before, every UNAUTHENTICATED of a stream invalidated the token (unary
  calls still do, as upstream).
- The API key of the app (`FirebaseOptions.apiKey`) is sent with every request, as the JS SDK
  does: the `x-goog-api-key` header over gRPC and WebChannel, and the `key` query parameter of a
  REST call (Firestore Lite on the web sends only the parameter). Requests used to carry no API key,
  so API key restrictions of the project did not apply to them. The Android SDK sends none.
- gRPC transport: a server that ignores HTTP/2 flow control can no longer make the client buffer without
  limit. More data than the flow-control window allows, more than 1 MiB of held frames without data, or a
  frame larger than 16 KiB ends the connection (package:http2 does the same, but only once a frame is
  complete); the call fails as for any lost connection. A padded frame with more padding than payload is no
  longer counted as negative.
- A query, vector query or commit whose response can not be used (a document that does not decode, a second
  commit response) no longer resets its HTTP/2 stream: the call is left to end and cancelled only if the
  backend keeps it open. A reset that races the end of the call made package:http2 terminate the connection
  and fail every other call on it. The same for a Listen or Write call that was started for a stream stopped
  in the meantime.
- Errors of auth and App Check providers are logged and passed on with anything that looks like a token
  (JWTs, bearer and `token=` values, long opaque strings) replaced by `<redacted>`; the stack trace of a
  failed auth token request is logged at debug level only.
- Web transport: a REST response or the answer to a WebChannel request is read up to 256 Mi characters
  (`WebHttpResponse.maxBodyLength`, the bound of one WebChannel chunk); a larger one fails the call with
  RESOURCE_EXHAUSTED and the request is aborted. An error body of the back channel is read up to 1 MiB.
- Web transport: an HTTP 400 without a status in its body maps to FAILED_PRECONDITION as in the JS SDK
  (was INVALID_ARGUMENT).
- A write whose mutation can not be stored because the cache is busy for a moment (a
  `TransientDatabaseException`) fails only its future with `unavailable`, as in the JS SDK. Before,
  the error was also raised as an uncaught error of the zone, which ends a command-line program.

## 0.1.0

First release under the new name. This package was published as `cloud_firestore_vm` (last
version 0.0.7, April 2020); it is the same code base, revived and brought forward to roughly
the behaviour of the current Android and JS SDKs. One entry covers the whole revival.

The published package contains `lib/` and `example/`. Tests, tooling and design notes (the
`test/`, `tool/` and `docs/` paths mentioned below) are in the
[repository](https://github.com/long1eu/firebase_dart_sdk).

How this was verified:

- Unit tests, the spec tests shared with the JS and Android SDKs, and integration tests against
  the local Firestore emulator. Against production Firestore only the verification kit
  (`tool/verify_production`) was run, on a Standard edition database: 13 of its 15 checks
  passed in one run and 2 were skipped (one needs an Enterprise edition database, the other a Web
  API key with anonymous sign-in). An earlier run found the -0.0 bug of the web transport that is
  fixed in this version.
- Features of the Enterprise edition (BSON value types, Pipelines) were run against the
  emulator in Enterprise edition only.
- Web support is experimental: it was run in Chrome only, against the emulator only, with a
  memory cache or the opt-in SQLite cache in IndexedDB (browser tests, and the standard
  integration suite on the VM over the web transport).
- On the VM: macOS, Ubuntu x64 (CI) and Debian arm64 (a container: unit tests, the standard
  integration suite, SQLite shared by two isolates and by two processes, the connectivity
  detector against a real interface change). Windows was not run. The SQLite opener of the
  example falls back to `libsqlite3.so.0` on Linux systems without `libsqlite3-dev`.

### Renamed packages

- **License:** Apache-2.0 (see `LICENSE` and `NOTICE`). `cloud_firestore_vm` and the two
  internal `_vm` packages were licensed under BSD-3-Clause.
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
- `Firestore.instanceFor` (new) and the deprecated `getInstance` return the `Firestore` instead of
  a `Future<Firestore>`, like Firestore Lite, the JS, Android and FlutterFire SDKs. The instance
  initializes in the background as the first task of its queue: it waits for the first user of
  the auth provider, opens and migrates the cache, and starts the local and remote stores, and
  every operation runs after that. A failed initialization (the opener throws, a migration fails)
  is reported by the operations of the instance instead of by `instanceFor`. A new `FirebaseApp`
  with the name of a deleted one gets its instance at once; it opens the cache once the instance
  of the deleted app has closed it. `await Firestore.instanceFor(...)` keeps compiling.
- `Firestore.databaseId` is the database name as a `String` (as FlutterFire's), no longer the
  `DatabaseId` model; the new `Firestore.projectId` gives the project. The same in Firestore
  Lite.
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
  - No longer reachable from `package:cloud_firestore_dart/cloud_firestore_dart.dart` (they are
    library private; the SDK itself uses them through extensions that the public libraries do
    not export). None of the classes below has a public constructor any more, so they cannot be
    subclassed outside the SDK (`implements` for a test double still works): `Firestore(...)`
    constructor, `Firestore.newInstance`, `client`,
    `scheduler`, `dataConverter`, the `DatabaseId` model of `databaseId` (`Firestore.databaseId`
    is now the database name as a `String`, as in FlutterFire; with the new `Firestore.projectId`
    it replaces the model), `validateReference`; `Query.query`;
    `QuerySnapshot.snapshot`; `DocumentSnapshot.document`; `DocumentReference.key`;
    `SetOptions.fieldMask`; `FieldPath(...)` unnamed constructor, `internalPath`, `reserved`,
    `documentIdInstance` (use `FieldPath.documentIdField`); `FieldValue.elements`, `methodName`
    and the `isDelete` / `isServerTimestamp` / `isArrayUnion` / `isArrayRemove` /
    `isIncrement` / `isMinimum` / `isMaximum` getters; `AggregateField.alias`; the
    `AggregateQuery` and `AggregateQuerySnapshot` constructors; the `LoadBundleTask`
    constructor, `setResult`, `setException`, `updateProgress`;
    `LoadBundleTaskProgress.forInitial` / `forSuccess`; `FirestoreErrorCode.fromValue`;
    `Timestamp.validateRange`; and the constructors of `DocumentReference`,
    `CollectionReference`, `Query`, `DocumentSnapshot`, `QueryDocumentSnapshot`, `QuerySnapshot`,
    `DocumentChange` (with `changesFromSnapshot`), `Transaction`, `WriteBatch`, `VectorQuery`,
    `VectorQuerySnapshot` and `PersistentCacheIndexManager`. `package:cloud_firestore_dart/lite.dart`
    hides the same members of the classes it shares with the main library (`FieldPath`,
    `FieldValue`, `SetOptions`, `AggregateField`, `Timestamp`).

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
- Read-only transactions (`TransactionOptions(readOnly: true)`, new in this release) run on the
  backend: they read one snapshot, commit nothing and are not run again when documents change.
  Revisions of this package before the release verified the documents at commit and retried;
  code written against those sees the snapshot instead. See Added.
- Arguments are validated in every build mode, not only with asserts: a collection path with an
  even number of segments, a `cacheSizeBytes` below 1 MB with persistence, a `GeoPoint` or
  `Timestamp` outside its range when it is written or used in a query. `firestore.doc('')`,
  a document path that is only a slash and `collectionGroup('')` throw an `ArgumentError`
  (they were accepted). Details under Fixed.
- Settings and input are validated more strictly (from a security review):
  - `FirestoreSettings` throws an `ArgumentError` for `sslEnabled: false` with the production
    host in every build mode (it was an `assert`, which release builds drop, so the auth token
    could be sent without TLS), whatever the case of the host or a trailing dot.
  - `FirestoreSettings.host` must be a host name or IP address: an empty value or one with
    `/`, `@`, `?`, `#`, `\` or whitespace is an `ArgumentError` (a value such as
    `firestore.googleapis.com@other.example` made the web transport talk to the other host).
  - Bundles are treated as untrusted input: a length prefix has to be at most 10 plain decimal
    digits, an element is at most 64 MiB, values and filters
    may be nested at most 100 levels, and fields of the wrong JSON type are reported as an
    invalid bundle. A stream without a valid element is rejected at once instead of being
    buffered, and elements that arrive in small chunks are no longer re-copied per chunk.
  - Over REST (Firestore Lite on the web, and the single calls of the web transport) a document
    or collection path with a `.` or `..` segment fails with `invalid-argument` before anything
    is sent: the URL resolved such segments, so the request went to another path (or project)
    with the credentials of this one. The gRPC transport sends the path as data, and the
    backend rejects these ids.
  - The bundle inside a snapshot JSON (`DocumentSnapshot.fromJson`, `QuerySnapshot.fromJson`)
    needs the same plain decimal length prefix as `loadBundle` (a sign, white space or a hex
    prefix was accepted), and its errors quote at most 200 characters of the input.
  - Decimal128 values are parsed, compared and hashed in linear time: a value with a million
    digits (in a bundle or a snapshot JSON) took seconds to minutes and blocked the isolate.
    The accepted strings and the order are unchanged.
  - `clearPersistence()` that empties a cache other clients still use quotes the table names it
    reads from the file: a table named by another process could run SQL (for example attach and
    create another file with the permissions of this process).
- The local evaluation of queries and transforms follows the backend where 0.0.7 (and the JS
  and Android SDKs) did not; details under Fixed:
  - `whereIn`, `whereNotIn`, `arrayContains`, `arrayContainsAny`, `arrayUnion` and
    `arrayRemove` compare numbers by value (`1` is `1.0`), whatever their type.
  - `<`, `<=`, `>` and `>=` do not match `null` and `NaN`.
  - A cached document that the client matches for a query but the backend does not return is
    dropped from that query's view once the backend confirms that it exists, instead of
    keeping the listener in `isFromCache`.
  - A write that is acknowledged without changing the document on the backend (a re-sent
    write) is applied to the cached document.
- Idle stream timeout changed from 10 seconds to 1 minute (as Android).
- A clean close of a stream by the server is now reported as `UNAVAILABLE` and retried instead
  of being ignored (fixes a start hang).
- `TransformMutation` is removed: field transforms are folded into set/patch mutations
  (`update_transforms`). Stored legacy transform writes are squashed on load by the local
  serializer.
- Locally mutated documents carry `SnapshotVersion.none`, as upstream.
- The SQLite schema goes from version 8 to 17 (bundle tables, read times on remote documents,
  document overlays, the tables of the persistent cache indexes, two lookup indexes, and the
  client lease tables of version 15, the globals table of version 16, ported from the JS and
  Android SDKs, which keep a session token there; nothing uses it yet, as upstream; and the
  `document_type` column of version 17 (Android 26.0.1), with which queries skip deleted
  documents; rows from older versions get it the first time they are read; see index-free queries, document overlays and persistent
  cache indexes under Added, and the primary client under Fixed). The migration
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
- `Timestamp.fromDate` / `toDate` are microsecond-accurate (they truncated to milliseconds), also
  on the web up to the end of the `Timestamp` range; results for millisecond inputs are unchanged, and `DateTime` values written to documents keep
  their microseconds. `Timestamp.now()` still has millisecond precision.
- `Blob.bytes` returns a copy.
- `FirebaseApp.persistenceKey` (`firebase_app_dart`) now uses URL-safe base64 without padding;
  keys computed by older versions differ.

Deprecated, still working:

- `Firestore.getInstance` (use `instanceFor`), `Firestore.shutdown` (use `terminate`),
  `document` (use `doc`), `DocumentSnapshot.reference` (use `ref`), `QuerySnapshot.documents` /
  `documentChanges` (use `docs` / `docChanges`), `FieldPath.documentId()` (use
  `documentIdField`), `Source.defaultSource` (use `serverAndCache`). `FirebaseFirestore` and
  `Settings` are typedefs of `Firestore` and `FirestoreSettings`.

### Added

- `example/sqlite_database.dart`: `sqliteOpener(directory, pageCacheMb: ...)` sets SQLite's page cache size
  (`PRAGMA cache_size`). The client keeps SQLite's default, as the Android SDK does; the offline persistence guide
  has measurements and a recommendation.
- Recovery from a cache that is not available for a while, as in the JS SDK: a `Database` can throw the new
  `TransientDatabaseException` (the example openers do for SQLite's busy, locked, I/O and full-disk errors, and on the
  web when IndexedDB fails to store a transaction). A listen or write that can not be stored then fails with
  `unavailable`; an acknowledgement, watch update or user change that can not be stored takes the client offline and
  is retried with a backoff until the cache works again. Before, such an error failed the operation that ran into it
  and could leave the client stuck. Verified with the shared recovery spec tests (simulated failures); not run against
  a real failing disk.
  An operation that is retried and itself runs into the failing cache again (an acknowledgement that is stored, after
  which reading the next write fails) no longer runs twice or drops the operation it queued, and the retries back off
  instead of looping without delay.
  A cache that reads but does not write (a full disk) no longer makes the client reconnect, download the same changes
  and fail to store them in a loop: after a failure, the next one waits for the backoff until a remote event or an
  acknowledgement was stored again. A write that can not be read from the cache is probed with that read, so the
  network stays offline until it works.
  `TransientDatabaseException.toString()` names the type of its `cause` instead of repeating it: the string of a
  `SqliteException` holds the statement and its arguments (document contents, paths, user ids), and Firestore puts
  this exception into the `unavailable` error the app gets and into a warning in its log.
- Authentication with ready-made token providers from the new `firebase_auth_providers_dart`
  package of this repository (Firebase Auth user sign-in over REST, service accounts, Application
  Default Credentials); see the README section "Authentication". `test/integration_auth` shows a
  signed-in user's token reaching Firestore over gRPC, the web transport and Firestore Lite, the
  streams restarting on a user switch and access ending at sign-out. Emulators only.

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
  `Decimal128Value` throws a `FormatException` for a string that decimal128 can not hold
  exactly, as the backend rejects such a value: more than 34 significant digits (leading zeros
  and trailing zeros that carry no digit do not count), anything above `9.99...9e6144`, or a
  last digit below `1e-6176` (`1e6145`, `1e-6177` and `15e-6177` are rejected; `1e6144`,
  `1e-6176` and `1.` with 40 zeros are fine). A stored value is read as it is. The other SDKs
  accept any decimal string and round it to a 128-bit binary float.
- Value helpers from the JS SDK: `Timestamp.fromMillis` / `toMillis`, `Blob.fromBase64String` /
  `toBase64`, and `toJson` / `fromJson` on `Timestamp`, `GeoPoint`, `Blob` and `VectorValue` in
  the JS `toJSON()` shape (so `jsonEncode` works on them).
- `ServerTimestampBehavior` is exported.

Transactions and writes:

- Read-only transactions of the backend: `TransactionOptions(readOnly: true)` starts a read-only
  transaction on the server with its first read. Every read sees one snapshot of the database:
  documents with `Transaction.get`, and (new) queries and aggregations with
  `Transaction.getQuery` and `Transaction.getAggregate`. `TransactionOptions.readTime` reads
  the database as it was at a past time. Nothing is committed and the callback is not run again
  for conflicts. (Before, the documents read were verified at commit with `VerifyMutation`s and
  the transaction retried; the `verify` write is still used for documents that a read-write
  transaction reads without writing.) Over the web transport they use the REST verbs
  `beginTransaction` and `rollback`. Emulator-verified only.
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
- `Firestore.setLogLevel(LogLevel)` with the six levels of the JS SDK: `verbose`, `debug`,
  `info`, `warn` (the default), `error` and `silent`; also in Firestore Lite.
  `setLoggingEnabled` still works.
- `Firestore.app`, an alias of `Firestore.firebaseApp` under the name the JS SDK and FlutterFire use.

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
- `documents()` rejects a path given twice, as the JS SDK does.
- `rawStage` takes aggregate functions and orderings as arguments, also as values of a map
  argument, as Android's `RawStage` does.
- `literals` rejects, as the JS and Android SDKs do, an empty field name at any depth of a
  document, and names the field of a `FieldValue` sentinel in its error.
- Also in the preview: `Pipeline.search` with `documentMatches` and `score`; window functions
  with `Pipeline.addWindowFields`, `WindowSpec`, `WindowFrame`, `WindowFunction`, `rank()` and
  `AggregateFunction.over` (beta upstream; the emulator rejects search and window functions, so
  both are checked for their encoding only); `Transaction.execute(pipeline)` in read-only
  transactions; typed `PipelineExplainOptions` for `Pipeline.execute`; `Expression.arraySum`,
  `Expression.log10`, more key/value pairs for `Expression.mapSet`, and `pipelineResultEqual`.
  The surface has every symbol of the JS `firestore-pipelines` API, in Dart shape.

Firestore Lite (experimental):

- A second entry point, `package:cloud_firestore_dart/lite.dart`: the counterpart of
  `firebase/firestore/lite` of the JS SDK. A client without local cache, listeners and sync
  engine, where every call is one request and one response: `ref.get()`, `set` / `update` /
  `delete`, `collection.add`, write batches, `runTransaction` (also read-only, with queries),
  queries (`where`, `orderBy`, `limit`, `limitToLast`, cursors, collection groups), `count` /
  `sum` / `average` aggregations with aliases, converters and `terminate()`. Its classes have the names and the shape of the
  main library's (`Firestore`, `DocumentReference`, `Query`, ...), without streams, snapshot
  metadata, `Source` and cache settings; the value types are shared. It uses gRPC on native
  platforms and REST without WebChannel on the web, with the Auth and App Check tokens of the
  app and the emulator settings (`withEmulator`, `mockUserToken`). A program that only imports
  it does not contain the sync engine, the local store or the SQLite layer. The API is
  experimental and may change. See the README section and `example/lite.dart`.

Networking:

- A built-in connectivity detector on the VM. While a stream is failing, the client watches the
  addresses of the network interfaces (and the clock, for a wake-up from sleep) and restarts
  its streams at once when the connectivity may be back, instead of waiting for the backoff. It
  only speeds up recovery: it never declares the client offline, and it has no timer while the
  streams work. An app that feeds `PlatformDependencies.onNetworkConnected` itself replaces it.
  Tested on macOS only.
- App Check: the token of the app's App Check provider is sent in the `x-firebase-appcheck`
  header. When the provider throws, requests are sent without the header and a warning is
  logged, as the JS and Android SDKs behave (their App Check SDKs report failures with a
  placeholder token instead of failing). Tested on the wire over gRPC, WebChannel and REST (full
  SDK and Lite): the App Check and ID tokens on every request, their refresh after
  `UNAUTHENTICATED`, a new App Check token used from the next request on, and a failing
  provider. Enforcement by the backend is not testable on the emulator and remains untested.
- `FirestoreSettings.grpcFlowControlWindow` (also in the settings of Firestore Lite): the
  HTTP/2 flow-control window of the gRPC transport, 256 KiB by default
  (`FirestoreSettings.defaultGrpcFlowControlWindow`) as in the Android and JS SDKs, for the
  connection as a whole and for each request (0.0.7 used the HTTP/2 default of 64 KiB, which
  limited a large read to 64 KiB per round trip). package:http2 can only set the window of the
  streams, so the client grows the window of the connection itself and holds back data that
  package:http2 would refuse while a response is not read. With another window than 65535
  bytes a new connection waits for the backend to acknowledge it before its first request, and
  a server that answers with GOAWAY instead fails the connection attempt. Ignored by the web
  transport.
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
    `FIRESTORE_TEST_TRANSPORT=webchannel`), and in Chrome with 54 browser tests
    (`tool/test_browser.sh both`; 53 pass and 1 is skipped with each compiler: the IndexedDB
    crash harness under dart2wasm, the 64 bit integer test under dart2js). No other browser and no production backend was tried.
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
  was not closed properly, a cache held by another browsing context is refused, the schema
  migrations (up to version 14 when this was run) run one by one and at once, automatic cache indexes work, `clearPersistence`
  removes the database. The opener creates or upgrades a cache in one transaction and keeps
  SQLite from writing pages before their commit, and a worker that is killed at random moments
  (2700 times) always left a database that passed `PRAGMA integrity_check` with every
  acknowledged transaction in it. 10,000 cached documents of 1 KB are 17 MB and open in
  0.1 s, 100,000 are 160 MB and open in 1.2 s compiled with dart2wasm (0.6 s with dart2js).
  The opener wraps the file system of `sqlite3` 2.9.4 so that a read copies what it reads:
  compiled with dart2wasm every read used to convert the whole database file (26 ms per
  statement on a 1.2 MB database; opening a cache of 1,000 documents went from 0.7 s to 19 ms,
  scanning it from 2.4 s to 39 ms, a write from 0.7 s to 17 ms). Not verified: other browsers,
  a crash of the browser itself.
- **OPFS storage for the web cache** (experimental): `sqliteWebOpener(opfsWorker: ...)` in
  `example/sqlite_database_web.dart` keeps the database in the origin private file system,
  with SQLite in a dedicated worker (`example/sqlite_opfs_worker.dart`, compiled with
  `dart compile js`) on the synchronous access handles of `SimpleOpfsFileSystem`
  (`package:sqlite3`), instead of a copy of the whole database in memory. No cross-origin
  isolation is needed. IndexedDB stays the default, and the fallback in a browser without
  synchronous OPFS access in workers; the first OPFS open of a cache that is in IndexedDB
  moves it, pending writes included. Measured in Chrome with 100,000 documents of about 1 KB:
  3 to 7 MB once open instead of 133 to 138 MB, opens in 45 to 170 ms instead of 0.55 to
  1.2 s; reads by id and scans cost about the same (a scan of 100,000 documents needs about
  0.45 GB for its snapshot with either storage). A worker killed at random moments 1500 times
  always left an intact database with every acknowledged transaction. I/O errors in the worker
  (BUSY, LOCKED, IOERR, FULL) are reported as `TransientDatabaseException` (offline, then a
  retry) only when nothing can have been stored: inside a transaction, at a COMMIT that left
  the transaction open or after which the database file is unchanged (its change counter), and
  for reads; an error at a COMMIT that may have stored the transaction stays fatal, so that it is
  not applied twice (tested with a worker that fails reads, writes, syncs and the journal delete
  on command). Not verified: browsers other than Chrome.
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
  - WebChannel responses with a negative or non-decimal chunk length, or one above 256 Mi
    characters (enough for a 16 MiB document as JSON), end the stream with `unavailable`.
  - A WebChannel response of many megabytes (for example a query or a listener with many large
    documents) is parsed in one pass instead of being copied once per network chunk; reading 12
    documents of 1 MiB from the emulator takes about 0.2 s instead of 4 s.
  - Request headers with a line break are refused instead of being sent in the handshake, and
    `fetch` no longer follows redirects (a redirect would re-send the credentials elsewhere).
  - A clear `UnsupportedError` at start when the application was compiled with
    `-Dprotobuf.omit_field_names=true` or `-Dprotobuf.omit_enum_names=true`, which would
    make every request wrong.

Documentation and tests:

- Every exported class and member has a doc comment (members marked `@internal` say so), the
  library has an overview, and `dart doc` runs without warnings.
- Runnable examples in `example/`, README and migration guide snippets that are compiled by a
  test, and public API golden files for the three libraries (main, pipelines, lite).
- Test suite (in the repository, not in the published package): unit tests, the spec tests
  re-synced with JS SDK `main`, seeded property tests, an emulator integration suite (also run
  over the web transport and against the Enterprise edition emulator), chaos tests behind a
  TCP proxy that cuts and stalls connections, Enterprise-only tests in
  `test/integration_enterprise`, browser tests in Chrome, interop tests with the JS SDK, and size
  budgets for a small web app with Firestore Lite and with the main library (`tool/check_size.sh`). Protos regenerated from current googleapis
  (`tool/gen_protos.sh`).
- A production verification kit (`tool/verify_production`): 15 named checks that run against
  the emulator and, only with your own credentials and an explicit `--yes`, against a real
  project. It was run against a real Standard edition database; its README lists the results.

### Fixed

- On the VM a SQLite cache in the default rollback-journal mode is switched to write-ahead logging when it is
  opened (a journal mode the opener sets is kept). With several clients on one cache (isolates, processes), a
  client could wait out the 10-second busy timeout without ever getting the file and fail with `database is
  locked`, for example when several isolates opened a new cache at once.
- `Firestore.instance` before the default instance exists throws a `StateError` that says to call
  `Firestore.instanceFor(app: FirebaseApp.instance)` (0.0.7 named `Firestore.getInstance`).
- Two clients with the same SQLite cache open (the isolate before a Flutter hot restart, a background isolate, a
  second process) could give two listens the same target id or two writes the same batch id, and overwrite the
  cache metadata with what each had read at its start; a transaction could also fail with "database is locked"
  the moment the other client wrote. Transactions now take the write lock when they start and wait for it,
  the state kept in memory is read again after a commit of another connection, and two clients that open an old
  cache at the same time migrate it once. A client whose cache is moved to another schema version by a different
  version of the SDK while it runs fails with `failedPrecondition` instead of working on a schema it does not
  know. The clients are still not coordinated (there is no multi-tab support).
- Clients of one SQLite cache now elect a primary client with the lease of the JS SDK (valid for 5 s, refreshed
  every 4 s; a terminated client releases it at once, a dead one loses it when it expires). Only the primary uses
  the network, applies remote events and acknowledgements, collects garbage and backfills indexes. A client that
  opens a cache another live client holds takes the lease and logs a warning (as after a hot restart); the other
  client then reports offline, serves its listeners and gets from the cache and keeps its writes pending, until it
  becomes primary again (when the new client terminates or disables its network). (In this version the primary
  sent the pending writes of the other client, whose futures then never completed; fixed in the next version, see
  Unreleased.) A lone client is always primary.
- `clearPersistence()` with another live client on the cache empties the cache in place instead of deleting the
  file under that client; the other client fails with `failedPrecondition` at its next use and terminates.
- `clearPersistence()` deletes the `-journal`, `-wal` and `-shm` files before the database file, tries all of them,
  and keeps the database file when one of them can't be deleted (a journal left next to a new database of the same
  name would be applied to it); the error names every file that failed. A persistent cache whose start fails after
  the database was opened closes it again instead of leaving the handle open.
- A malformed primary lease or client row in a SQLite cache (a value of the wrong type) counts as no lease or no
  client instead of making every new client fail to start; a missing or malformed epoch row is repaired by a new
  client and makes running clients stop as after a clear. The warning about a lease or client row dated in the
  future is logged once a minute instead of at every refresh. Clearing a cache in place (another client is alive)
  overwrites the deleted rows with zeros (`PRAGMA secure_delete`) and checkpoints the write-ahead log, and a client
  row from the future no longer counts as a live client there.
- When the cache can't be opened, the operations that were queued while it was opening fail with the error of the
  open, like the later ones, instead of `LateInitializationError: Field 'localStore'`. `openWithMemoryFallback` in
  `example/sqlite_database_web.dart` waits for a first operation to see that error, since `Firestore.instanceFor`
  returns before the cache is open.
- Argument checks that were only `assert`s, and so did nothing in release builds, now throw an `ArgumentError`
  in every build: a collection path with an even number of segments (`firestore.collection('coll/doc')`,
  `doc.collection('')`), a `cacheSizeBytes` below the minimum of 1 MB with persistence enabled, and a `GeoPoint`
  outside its range when it is written or used in a query (the `GeoPoint` and `Timestamp` constructors are
  `const` and keep their asserts; both values are checked when they enter the SDK).
- `firestore.doc('')` returned a reference to nothing instead of failing, and `collectionGroup('')` was
  accepted. Both throw an `ArgumentError` (as the JS SDK; also for a document path that is only a slash).
- Two `AggregateQuerySnapshot`s made with `aggregateWithAliases` (or `aggregate`) were only equal when the
  aggregations were asked for in the same order. They are now equal when they aggregate the same query and hold
  the same results under the same names, as `aggregateQuerySnapshotEqual` of the JS SDK.
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
- A listener no longer keeps showing the local version of a document, with `hasPendingWrites`,
  after its writes were acknowledged or rejected, when the backend deleted the document (or
  stopped returning it) before watch sent it again. The view waits for watch after such a
  change (as the JS and Android SDKs do, which have the same gap), and watch never sends a
  document that left the query: the document now goes through limbo resolution once watch
  took it out of the target, or once a snapshot of watch at or after the commit of the write
  does not have it (also when the acknowledgement left the data unchanged, and for a document
  that watch never had). Found by the chaos soak test (a write rejected with `not-found` on top
  of the result of an earlier, acknowledged write; a document created by one client and
  deleted by another before watch sent it); emulator-verified only.
- A double and an integer beyond 2^53 are compared by their exact values (the order used to
  depend on the side of the operands).
- Fixes from the upstream sync (UTF-8 string ordering, limbo handling, limbo-resolution
  document removal, transaction precondition, listener lifecycle and others); see
  `docs/upstream_sync/UPSTREAM_PLAN.md`.
- Every listen is sent to the backend with a fresh remote target id (as the JS SDK), so a late
  removal or error for an earlier listen of a query no longer rejects a newer listen of it.
- A document in limbo whose limbo resolution finds it deleted is now removed even when another
  query's target sent and removed the same document in the same snapshot window (the JS fix for
  firebase-js-sdk#8474; Android does not have it). Before, the stale document stayed in the
  view of the other query.
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
- The client no longer reconnects in a tight loop to a peer that accepts connections and then
  drops them before a call could start (it closes them at once, also after the TLS handshake or
  after the HTTP/2 preface, or it sends GOAWAY: a load balancer without a backend, a captive
  portal, a TLS-terminating middlebox). `package:grpc` kept the waiting calls and connected
  again immediately, about 43 times per second, without failing a call, so the backoff of the
  streams never applied. The attempt that follows such a connection now fails, the calls fail
  with `unavailable`, and the streams retry with their exponential backoff as they do when a
  connection is refused (about 15 connections in 30 seconds instead of 1300). The web transport
  was checked and did not have the problem.
- The SQLite persistence lock is per database instead of process-wide, so a long transaction in
  one `Firestore` instance no longer blocks the others.
- `Firestore.instanceFor` no longer returns an instance whose `terminate()` is still in
  progress. With a new `FirebaseApp` that has the name of a deleted one it no longer returns the
  instance of the deleted app (which was about to be terminated, since `FirebaseApp.delete()`
  terminates the instances of the app in the background): it returns a new instance at once,
  which opens the same cache after the old instance has closed it.
- The `x-goog-api-client` header carries only the Dart version (`gl-dart/3.12.2`); it carried
  the whole `Platform.version` string, with spaces, a date and a quoted platform name.
- `FirestoreSettings.copyWith(cacheSettings: ...)` on settings that set `persistenceEnabled` or
  `cacheSizeBytes` throws instead of dropping them.
- Firestore Lite: a transaction no longer holds off `terminate()` (awaiting `terminate()` inside
  a transaction used to hang). As in the JS SDK, once the instance is terminated the next read
  or the commit of a running transaction fails with `failedPrecondition`, and the transaction is
  not retried.
- Transactions (main library and Firestore Lite): a read after a write fails with the message of
  the JS and Android SDKs ("Firestore transactions require all reads to be executed before all
  writes.") and, as in the JS SDK, the transaction then fails to commit even if the update
  function caught the error.
- `FieldValue.arrayUnion` and `FieldValue.arrayRemove` are equal (`==`) when their elements are
  equal in the same order, as `isEqual` of the JS SDK.
- LRU garbage collection of the SQLite cache read every orphaned document in one query, so its memory grew with
  the cache (several hundred MB for a million cached documents). It now works in batches as the Android SDK does.
  Collection queries no longer read the documents of subcollections out of the cache.
- `terminate()` no longer hangs when the backend dropped the connection while a request was on its way out:
  `package:http2` waited for the socket to close, which never happened, and the open socket (and then the idle
  timer of `package:grpc`) kept the isolate or process alive. As in the Android SDK, the connection gets one second
  to close and the socket is then destroyed.
- A listen or unlisten made while the watch stream was opening was sent twice; the backend rejects a target that is
  already active and fails the whole stream, which then had to reconnect.
- A write stream that failed right after its handshake no longer crashes the client with "Writing mutations
  requires an opened stream": as in the Android SDK, the late report of a stream that already failed is dropped.

### Not done

- Persistent cache indexes for queries with inequalities on several fields (they are scanned,
  as upstream), and indexes with a memory cache.
- Coordinating running clients that share one persistent cache (the multi-tab support of the JS
  SDK). Two clients on one SQLite file keep it consistent and elect a primary client that alone
  uses the network (see Fixed), but they do not share listens or writes; in the browser the cache
  is refused to a second tab. Sharing them (stage 3 of the multi-client plan) is deferred until
  after 0.1.0.
- On the web: any browser other than Chrome.
- Pipelines beyond the preview: pipelines in a read-write `Transaction`, evaluation against the
  local cache (an internal evaluator exists but is not wired into the client) and real-time
  pipelines. Search and window functions are only checked for their encoding.
- A port of the Firebase Auth SDK. The app supplies tokens through `PlatformDependencies`, for
  example with the providers of `firebase_auth_providers_dart` (email/password, anonymous and
  custom-token sign-in, service accounts); there are no federated or phone sign-in providers.
- Any run against production Firestore beyond the verification kit: no Enterprise edition
  database, no Firebase Auth user sign-in, no long-running load. The packages are not published
  yet.

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
