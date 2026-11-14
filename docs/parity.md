# Parity with the Firebase JS SDK

This page compares `cloud_firestore_dart` (with `firebase_app_dart`) with the Firestore part of the
Firebase JS SDK, area by area, and then lists every gap and behaviour difference we know of.

**Compared against:** `@firebase/firestore` **4.20.0** (Firebase JS SDK 13.3.0), source at
firebase-js-sdk commit `c03d2aa` of 2026-11-12, recorded in
[`docs/upstream_sync/js_reference.md`](upstream_sync/js_reference.md) with how to compare next time.
The rest of `docs/upstream_sync/` tracks the sync with the **Android** SDK, which this port follows
more closely. Where the Android and JS SDKs differ, the port usually follows Android and says so.

**How the status was decided:** from the code and the tests of this repository, not from the
documentation alone. A row marked *supported* cites a test file where the support is not obvious
from the API. Test paths are relative to `cloud_firestore/cloud_firestore_dart/`. The exact public
signatures are in `test/unit/api/public_api.golden.txt`.

| Status | Meaning |
|---|---|
| supported | The feature exists and is tested (against the emulator unless stated). |
| partial | Part of it exists, or it exists with a documented difference. |
| not supported | The JS SDK has it and this port does not. |
| not applicable | The feature is tied to the browser, IndexedDB, TypeScript or the JS build, or Dart has it by other means. |

## How it is tested

These are the numbers behind the statements below. Each one says where it comes from.

| Suite | Result | Source |
|---|---|---|
| Unit tests of `cloud_firestore_dart` (`dart test test/unit`, no backend) | 5,882 passed, 498 skipped, 0 failed | run for this page on 2026-11-14 |
| Integration, `test/integration` over gRPC (`tool/test_integration.sh standard --transport=grpc test/integration`, emulator v1.22.0) | 887 passed, 21 skipped, 0 failed | run for this page on 2026-11-14 |
| The same tests over the web transport (`--transport=webchannel`: REST and WebChannel, on the VM) | 882 passed, 26 skipped, 0 failed | run for this page on 2026-11-14 |
| The same tests with WebChannel in long-polling mode (`--transport=webchannel-longpolling`) | 882 passed, 26 skipped, 0 failed | run for this page on 2026-11-14 |
| Browser tests in Chrome (`tool/test_browser.sh both`) | 54 tests per compiler, 53 pass and 1 is skipped, on dart2js and dart2wasm | [Platforms](guides/platforms.md); run on 2026-11-14 at main 50470689 |
| Production verification kit (`tool/verify_production`) against a real Standard edition database | 13 of 15 checks passed, 2 skipped | [Features and limits](guides/features.md), [The emulator and testing](guides/emulator_and_testing.md) |

Each integration run used a fresh emulator. The same 908 tests run on every transport. The web transport skips five
more than gRPC: two because the emulator's JSON endpoints store -0.0 as 0.0, two backoff measurements that only apply
to gRPC, and one that needs two increments in flight at once. Among the skips on every transport: 8 large-document
tests (production only), 7 tests against the real JS SDK (they need Node.js, which the machine that ran them does not
have) and the opt-in scale soak. The Enterprise edition suites (`test/integration_enterprise`, and
the standard suite against the Enterprise emulator) were not run for this page.

Most of the testing is against the Firestore emulator. The integration suite has an opt-in mode
for a real project that has not been run yet; see [Known limitations](#known-limitations).

## Documents and writes

| JS feature | Status | Dart API or gap |
|---|---|---|
| `doc`, `collection`, `collectionGroup`, references and paths | supported | `firestore.doc`, `collection`, `collectionGroup`; `DocumentReference.id/path/parent` |
| `getDoc`, `getDocFromCache`, `getDocFromServer` | supported | `ref.get()`, `ref.get(Source.cache)`, `ref.get(Source.server)`; `test/integration/firebase/firestore/source_test.dart` |
| `setDoc`, `setDoc(..., {merge})`, `{mergeFields}` | supported | `set(data, SetOptions.mergeAllFields)`, `SetOptions.mergeFields([...])` / `mergeFieldPaths` |
| `updateDoc` (map and varargs forms) | supported | `update(map)`, `updateFromList([field, value, ...])` |
| `deleteDoc`, `addDoc` | supported | `delete()`, `CollectionReference.add` |
| `serverTimestamp`, `increment`, `arrayUnion`, `arrayRemove`, `deleteField` | supported | `FieldValue.serverTimestamp()`, `.increment`, `.arrayUnion`, `.arrayRemove`, `.delete()`; `numeric_transformas_test.dart`, `array_transforms_test.dart`, `server_timestamp_test.dart` (all under `test/integration/firebase/firestore/`) |
| `minimum` / `maximum` field transforms | supported | `FieldValue.minimum` / `.maximum`; `test/integration/firebase/firestore/min_max_transforms_test.dart` |
| Value types: `Timestamp`, `GeoPoint`, `Bytes`, `DocumentReference`, maps, arrays | supported | `Timestamp`, `GeoPoint`, `Blob`, `DocumentReference`; `test/integration/firebase/firestore/type_test.dart`, `value_fidelity_test.dart` |
| `vector()` / `VectorValue` | supported | `FieldValue.vector`, `VectorValue`; `test/integration/firebase/firestore/vector_test.dart` |
| BSON types (`MinKey`, `MaxKey`, `Int32Value`, `Decimal128Value`, `BsonObjectId`, `BsonTimestamp`, `RegexValue`, BSON binary) | supported (Enterprise edition) | Same class names, `Blob.bsonBinary`; `test/integration_enterprise/bson_types_test.dart`. Differences in [Known limitations](#known-limitations) |
| `withConverter`, `FirestoreDataConverter`, `withConverter(null)` | supported | `withConverter<T>(...)`, `withoutConverter()`; `test/integration/firebase/firestore/converter_test.dart` |
| `SnapshotOptions.serverTimestamps` (`'estimate'`, `'previous'`) | supported | `snapshot.getData(ServerTimestampBehavior.estimate)` or per field; `server_timestamp_test.dart` |
| `refEqual`, `queryEqual`, `snapshotEqual` | supported | `==` on references, queries and snapshots |
| `toJSON` / `fromJSON` on `Timestamp`, `GeoPoint`, `Bytes`, `VectorValue`, `DocumentReference` | supported | `toJson()` / `.fromJson(...)` in the JSON format of the JS SDK; `test/unit/firebase/firestore/snapshot_json_test.dart`. A cross-SDK test against the real JS SDK exists (`test/integration/firebase/firestore/js_interop_test.dart`) but is skipped unless Node.js and its harness are installed |
| Named databases (`getFirestore(app, 'db')`) | supported | `Firestore.instanceFor(app: app, database: 'db')`; `test/integration/firebase/firestore/firestore_test.dart` |
| Documents up to 16 MB | partial | Not verified: the gRPC transport sets no message size limit, but `test/integration/firebase/firestore/large_document_test.dart` needs a production database (the emulator rejects documents over 1 MiB) and has not been run |
| `UpdateData<T>` / `WithFieldValue<T>` typing | not applicable | TypeScript typing; `update` takes `Map<String, Object?>` |
| `ignoreUndefinedProperties` | not applicable | Dart has no `undefined` |
| `Temporal.Instant` conversion | not applicable | JS type |

## Queries and filters

| JS feature | Status | Dart API or gap |
|---|---|---|
| `where` with `==`, `<`, `<=`, `>`, `>=`, `array-contains`, `in`, `array-contains-any` | supported | `where('f', isEqualTo: ...)` named arguments, `whereEqualTo(...)` style methods or `Filter.equalTo(...)` objects |
| `!=` and `not-in` | supported | `isNotEqualTo`, `whereNotIn`; `test/integration/firebase/firestore/query_test.dart` (`testSDKUsesNotEqualFiltersSameAsServer`, `testSDKUsesNotInFiltersSameAsServer`) |
| `or()` / `and()` composite filters | supported | `Filter.or([...])`, `Filter.and([...])`; `test/integration/firebase/firestore/or_query_test.dart` |
| Range and inequality filters on several fields | supported | `test/integration/firebase/firestore/composite_index_query_test.dart` |
| `orderBy`, `limit`, `limitToLast` | supported | `orderBy`, `limit`, `limitToLast`; `test/integration/firebase/firestore/limit_to_last_test.dart` |
| Cursors `startAt`, `startAfter`, `endAt`, `endBefore` (values or snapshot) | supported | `startAt([...])`, `startAtDocument(snapshot)`, ...; `test/integration/firebase/firestore/cursor_test.dart` |
| `documentId()` | supported | `FieldPath.documentIdField`; `test/integration/firebase/firestore/query_where_test.dart` |
| `getDocs`, `getDocsFromCache`, `getDocsFromServer` | supported | `query.get()`, `get(Source.cache)`, `get(Source.server)` |
| Vector search `findNearest` on a classic query | supported (extra) | `Query.findNearest(...)`, server only. Not in the JS client SDK (there it is a pipeline stage); follows the Android SDK. `test/integration/firebase/firestore/vector_test.dart` |

## Aggregations

| JS feature | Status | Dart API or gap |
|---|---|---|
| `getCountFromServer` | supported | `query.count().get()` |
| `getAggregateFromServer` with `count()`, `sum()`, `average()` | supported | `query.aggregate([AggregateField.count(), .sum('f'), .average('f')])`, or `aggregateWithAliases({...})` for named results; `test/integration/firebase/firestore/aggregation_test.dart` |
| Aggregations in Lite (`getCount`, `getAggregate`) | supported | Same API in `lite.dart`; `test/integration/firebase/firestore/lite_test.dart` |

## Listeners and snapshot options

| JS feature | Status | Dart API or gap |
|---|---|---|
| `onSnapshot` on documents and queries | supported | `ref.snapshots`, `query.snapshots` (a `Stream`); cancel the subscription to stop |
| `includeMetadataChanges` | supported | `getSnapshots(MetadataChanges.include)` |
| `source: 'cache'` (listen to the cache only) | supported | `getSnapshotsWithOptions(SnapshotListenOptions(source: ListenSource.cache))`; `test/integration/firebase/firestore/listen_source_test.dart`, `snapshot_listener_source_test.dart` |
| `docChanges()` and change types | supported | `snapshot.docChanges`, `DocumentChangeType` |
| `SnapshotMetadata` (`hasPendingWrites`, `fromCache`) | supported | `snapshot.metadata.hasPendingWrites`, `.isFromCache` |
| `onSnapshotsInSync` | supported | `firestore.snapshotsInSync` stream; `test/integration/firebase/firestore/firestore_test.dart` |
| `QuerySnapshot.toJSON`, `DocumentSnapshot.toJSON`, `querySnapshotFromJSON`, `documentSnapshotFromJSON` | supported | `toJson()`, `QuerySnapshot.fromJson`, `DocumentSnapshot.fromJson`; `test/integration/firebase/firestore/snapshot_json_test.dart` |
| `onSnapshotResume` (listen from a serialized snapshot) | supported | `firestore.querySnapshotsFromJson(json)`, `documentSnapshotsFromJson(json)`; `snapshot_json_test.dart` |
| Error callback of `onSnapshot` | supported | The stream's `onError` |

## Transactions and batches

| JS feature | Status | Dart API or gap |
|---|---|---|
| `runTransaction` with retries and backoff, `maxAttempts` | supported | `firestore.runTransaction(fn, options: TransactionOptions(maxAttempts: 5))`; `test/integration/firebase/firestore/transaction_test.dart` |
| `writeBatch` | supported | `firestore.batch()`, `runBatch(fn)`; `test/integration/firebase/firestore/write_batch_test.dart` |
| Read-only transactions | supported (extra) | `TransactionOptions(readOnly: true, readTime: ...)` with `getQuery` and `getAggregate`. Not in the JS client SDK (the server SDKs have it); `test/integration/firebase/firestore/read_only_transaction_test.dart` |
| `waitForPendingWrites` | supported | `firestore.waitForPendingWrites()` |
| `terminate` | supported | `firestore.terminate()`; `test/integration/firebase/firestore/terminate_in_flight_test.dart`, `terminated_instance_test.dart` |

## Offline persistence and cache settings

| JS feature | Status | Dart API or gap |
|---|---|---|
| Memory cache, eager and LRU garbage collection | supported | `MemoryCacheSettings()`, `MemoryCacheSettings(gcSettings: MemoryLruGcSettings(sizeBytes: ...))` |
| Persistent cache (`persistentLocalCache`) with `cacheSizeBytes`, `CACHE_SIZE_UNLIMITED` | supported | `PersistentCacheSettings(sizeBytes: ...)`, `FirestoreSettings.cacheSizeUnlimited`; you pass an `OpenDatabase` (SQLite on the VM, SQLite in WebAssembly on the web). See [Offline persistence](guides/offline_persistence.md) |
| IndexedDB as the storage | not applicable | SQLite file on the VM; on the web SQLite (WebAssembly) stored in IndexedDB or OPFS. `test/browser/web_persistence_test.dart`, `web_persistence_opfs_test.dart` |
| `enableIndexedDbPersistence`, `enableMultiTabIndexedDbPersistence` (deprecated in JS) | not applicable | Use `cacheSettings` |
| `clearIndexedDbPersistence` | supported | `firestore.clearPersistence()` after `terminate()`; `test/integration/firebase/firestore/clear_persistence_test.dart` |
| `enableNetwork` / `disableNetwork` | supported | Same names |
| Offline writes, pending writes survive a restart | supported | `test/unit/firebase/firestore/local/` (SQLite persistence tests), browser reload tests `test/browser/web_persistence_reload_*` |
| Recovery from a busy or failing database | supported (extra) | `TransientDatabaseException`; see [Offline persistence](guides/offline_persistence.md#a-cache-that-is-busy-for-a-moment) |

## Indexes

| JS feature | Status | Dart API or gap |
|---|---|---|
| `getPersistentCacheIndexManager` | supported | `firestore.persistentCacheIndexManager` (null with a memory cache, as in JS) |
| `enablePersistentCacheIndexAutoCreation`, `disable...`, `deleteAllPersistentCacheIndexes` | supported | `enableIndexAutoCreation()`, `disableIndexAutoCreation()`, `deleteAllIndexes()`; `test/integration/firebase/firestore/index_engine_test.dart`, `test/unit/firebase/firestore/persistent_cache_index_manager_test.dart` |
| `setIndexConfiguration` (deprecated in JS) | supported | `firestore.setIndexConfiguration(json)` (deprecated here too); `test/integration/firebase/firestore/indexing_test.dart` |
| Indexes for queries with inequalities on several fields | not supported | Scanned instead, as in the JS SDK |

## Bundles

| JS feature | Status | Dart API or gap |
|---|---|---|
| `loadBundle` (bytes, string, stream) with progress | supported | `loadBundle(bytes)`, `loadBundleStream(stream)` (encode a string with `utf8.encode`), `LoadBundleTask.stream` / `addOnProgressListener`; `test/integration/firebase/firestore/bundle_test.dart` |
| `namedQuery` | supported | `firestore.getNamedQuery(name)`; `bundle_test.dart` |

## Lite

| JS feature | Status | Dart API or gap |
|---|---|---|
| `firebase/firestore/lite` entry point | supported (experimental) | `package:cloud_firestore_dart/lite.dart`; `test/integration/firebase/firestore/lite_test.dart`, browser `test/browser/web_lite_test.dart`. See [Firestore Lite](guides/lite.md) |
| Reads, writes, batches, transactions, queries, aggregations, converters | supported | Same as the main library, every call one request |
| `where` with named arguments / `Filter` | supported | The `whereEqualTo(...)`-style methods of the main library are not in Lite |
| Small web build | supported | `tool/check_size.sh` checks that the Lite program contains no sync engine, cache or WebChannel |

## Pipelines

Preview, Enterprise edition only, as in the JS SDK. See [Pipelines](guides/pipelines.md).

| JS feature | Status | Dart API or gap |
|---|---|---|
| `pipeline().collection/collectionGroup/database/documents` and `execute` | supported (preview) | `firestore.pipeline()` (extension `FirestorePipelines` in `package:cloud_firestore_dart/pipelines.dart`), `execute()`; `test/integration_enterprise/pipeline_test.dart` |
| Stages `where`, `sort`, `limit`, `offset`, `select`, `addFields`, `removeFields`, `aggregate`, `distinct`, `unnest`, `union`, `sample`, `findNearest`, `replaceWith` | supported (preview) | `test/integration_enterprise/pipeline_test.dart`, `android_pipeline_test.dart`, `pipeline_surface_test.dart` |
| Expressions (string, array, map, math, timestamp, logical, `isType`, `ifNull`, `coalesce`, regex, `parent`, ...) | supported (preview) | `pipeline_surface_test.dart` and the tests above |
| Subqueries, variables | supported (preview) | See [Pipelines](guides/pipelines.md#variables-subqueries-and-lambdas) |
| DML stages (`delete`, `update`, `insert`, `upsert`), `literals`, atomic execute | supported (preview) | `test/integration_enterprise/android_pipeline_dml_integration_test.dart`. The emulator denies `literals` to clients under security rules |
| `createFrom(query)` | partial | `createFrom`, `createFromAggregateQuery`, `createFromVectorQuery`; `test/integration_enterprise/pipeline_create_from_test.dart`. Keeps classic-query results for `!=` / `not-in`, which JS 4.20.0 no longer does; see [Known limitations](#known-limitations) |
| Full-text search, geo search, window functions | partial | Encoded as the JS SDK encodes them; the emulator rejects them, so they were never run against a backend (`android_pipeline_search_test.dart`, `android_pipeline_window_test.dart`) |
| Explain options | partial | `PipelineExplainOptions`; the emulator ignores them |
| Pipelines in a transaction | supported (extra) | `transaction.execute(pipeline)` in read-only transactions (a read-write transaction rejects it). Not in the JS client SDK; `test/integration_enterprise/pipeline_surface_test.dart` |
| Real-time pipelines | not supported | Also not public in JS 4.20.0 (`RealtimePipeline` is marked `@internal` there); `test/integration_enterprise/android_realtime_pipeline_test.dart` lists the Android tests as skipped |

## Multi-tab or multi-client

| JS feature | Status | Dart API or gap |
|---|---|---|
| `persistentSingleTabManager` | supported | The default: one client per cache. On the web a Web Lock keeps a second tab out (`failedPrecondition`) |
| `persistentMultipleTabManager`: several clients on one cache, one primary, lease of 5 s | partial | Clients on one SQLite file (isolates, processes, a Flutter hot restart) elect a primary with the JS lease; the cache stays consistent. `test/unit/firebase/firestore/local/sqlite_shared_clients_test.dart`, `sqlite_shared_processes_test.dart`, `sqlite_primary_lease_test.dart`, `test/unit/firebase/firestore/primary_client_test.dart`, `test/integration/firebase/firestore/shared_cache_isolates_test.dart`. See [Several clients on one cache](guides/multiple_clients.md) |
| Secondary tabs share the primary's listeners and writes | not supported | A secondary client works from the cache, reports itself offline and keeps its writes pending until it becomes primary. Deferred until after 0.1.0 |
| Several tabs on one cache in a browser | not supported | One tab at a time |

## App Check

| JS feature | Status | Dart API or gap |
|---|---|---|
| App Check token on every request | supported | An `InternalAppCheckTokenProvider` on the `FirebaseApp` adds `x-firebase-appcheck` over gRPC, WebChannel, REST and Lite; `test/integration_auth/credentials_on_the_wire_test.dart`, `test/unit/firebase/firestore/auth/app_check_token_provider_test.dart`. Enforcement was never tested: the emulator does not enforce App Check |
| Device attestation (`initializeAppCheck` with reCAPTCHA and similar providers) | not supported | You supply the provider, for example one that gets tokens from your backend |

## Emulator

| JS feature | Status | Dart API or gap |
|---|---|---|
| `connectFirestoreEmulator(db, host, port)` | supported | `FirestoreSettings().withEmulator(host, port)` |
| `mockUserToken` | supported | `withEmulator(host, port, mockUserToken: ...)`; `test/integration/firebase/firestore/emulator_mock_user_token_test.dart` |
| Emulator UI banner | not applicable | Browser UI of the JS SDK |

## Web transports

| JS feature | Status | Dart API or gap |
|---|---|---|
| WebChannel streams for listen and write | supported (experimental) | Used automatically on the web; the integration suite runs over it on the VM (see the numbers above) and `test/browser/web_transport_smoke_test.dart` in Chrome |
| REST for one-shot calls (fetch) | supported | `test/unit/firebase/firestore/remote/web/rest_transport_test.dart` |
| `experimentalForceLongPolling`, `experimentalAutoDetectLongPolling` | supported | Same names on `FirestoreSettings`; long polling has its own integration run (above) and `test/browser/web_robustness_test.dart` |
| `experimentalLongPollingOptions.timeoutSeconds` | supported | `FirestoreSettings(experimentalLongPollingOptions: ExperimentalLongPollingOptions(timeoutSeconds: 25))`, validated as in JS (5 to 30 seconds), sent as the `TO` parameter of long-polling requests; `test/unit/firebase/firestore/firestore_settings_test.dart`, `long_polling_options_test.dart`, `test/unit/firebase/firestore/remote/web/web_channel_test.dart` |
| `useFetchStreams` | not applicable | The web transport always uses `fetch` |
| HTTP/2 flow control window (`grpcFlowControlWindow`, Node) | supported | `FirestoreSettings.grpcFlowControlWindow` on the gRPC transport; `test/integration/firebase/firestore/transport_limits_test.dart` |
| WebChannel drops duplicate server messages, closes on terminate | supported | `test/unit/firebase/firestore/remote/web/web_channel_test.dart`, `web_channel_transport_test.dart` |
| Online state as soon as the stream connects (JS 4.6.1) | supported | The client is online once the WebChannel handshake succeeds (gRPC: at the first message, as JS on Node), not only at the first watch change; `test/unit/firebase/firestore/remote/stream_unit_test.dart`, `remote_store_test.dart`, `web/web_channel_transport_test.dart`, `test/integration/firebase/firestore/remote/stream_test.dart` |

## Platforms

| JS feature | Status | Dart API or gap |
|---|---|---|
| Browsers | partial (experimental) | Chrome only (dart2js and dart2wasm); other browsers untested. See [Platforms](guides/platforms.md) |
| Node.js | not applicable | The Dart VM takes its place: servers, command line tools, Flutter apps (Android, iOS, desktop) over gRPC |
| Linux, macOS on the VM | supported | Developed on macOS; unit and integration suites run in a Linux container and on Ubuntu in CI (`tool/linux/run_in_container.sh`) |
| Windows | partial | Expected to work, not tested |
| React Native, service workers | not applicable | |
| Authentication | partial | No Firebase Auth SDK; `firebase_auth_providers_dart` gets tokens over REST (user sign-in, service accounts, Application Default Credentials). Tested against the Auth emulator only. See [Authentication](guides/authentication.md) |

## Known limitations

Every gap and behaviour difference we know of, the ones you are most likely to meet first.

1. **Not published, little production use.** The packages are not on pub.dev yet (0.1.0 is in
   preparation). Most testing is against the emulator. Against a real Firestore database only the
   production verification kit has run (13 of 15 checks passed, 2 skipped); the integration
   suite's real-project mode, the Enterprise edition features and long-running load have not.
2. **The web is experimental.** Chrome only; a persistent cache can be open in one tab at a time;
   compiled to JavaScript (dart2js), integers above 2^53 lose precision, so prefer dart2wasm;
   against the emulator a query that returns more than about 10,000 documents fails on the web
   transport (production not checked). See [Platforms](guides/platforms.md).
3. **No device attestation for App Check and no Firebase Auth SDK.** You supply an App Check
   provider and get user tokens through `firebase_auth_providers_dart`, which was tested against
   the Auth emulator only. App Check enforcement was never tested.
4. **Clients that share a cache do not share listeners or writes.** A second isolate, process or
   Flutter hot restart on the same SQLite file works, but only the primary client is online; a
   secondary answers from the cache and keeps its writes pending. The JS SDK shares them between
   tabs. Give a background isolate its own app name or database. See
   [Several clients on one cache](guides/multiple_clients.md).
5. **A transaction or an increment can be applied twice** when the answer to a commit is lost and
   the client retries. The JS and Android SDKs have the same exposure; make such writes
   idempotent. See [Transactions](guides/transactions_and_lifecycle.md#transactions).
6. **Equality in `in`, `not-in`, `array-contains`, `array-contains-any`, `arrayUnion` and
   `arrayRemove` follows the backend, not the JS SDK.** The integer 1 and the double 1.0 are the
   same value here (and 0.0 is -0.0), as the backend treats them. The JS SDK compares them
   strictly, and a cached document that only it matches can stay in limbo.
7. **Comparisons with `null` and `NaN` match what the backend returns.** `a < 1` does not match a
   `NaN`, `a > null` matches nothing, `<=` / `>=` hold for null with null and NaN with NaN. The JS
   SDK evaluates these with the order of values and can show documents the backend does not
   return.
8. **Cached `null` / `NaN` documents on a Standard edition database.** In `in`,
   `array-contains(-any)` filters the client first treats `null` and `NaN` like an Enterprise
   database does (as the JS SDK), and removes such a document once the backend has not returned
   it: a listener sees it with `isFromCache: true`, then its removal. The JS SDK keeps it in limbo
   and `getDocsFromServer` does not complete. See
   [Enterprise edition differences](guides/emulator_and_testing.md#enterprise-edition-differences).
9. **Pipelines are a preview and were run against the Enterprise emulator only.** Server only
    (no cache, no pending writes, `unavailable` offline); no real-time pipelines (not public in JS
    either); full-text search, geo search and window functions were only checked for their
    encoding; explain options are ignored by the emulator.
10. **`createFrom(query)` keeps classic-query results.** For `!=` and `not-in` the Dart conversion
    excludes documents where the field is `null` or missing, like the query does. JS 4.20.0
    (#9444) drops that check, so its pipeline returns documents without the field. A cursor on a
    field with values of several types only returns documents whose value has the type of the
    cursor value. Cursors on descending orderings compare in the direction of the ordering (JS
    and Android always use `greater_than` for start bounds).
11. **`!=` and `not-in` with `limit` on an Enterprise database** can return a page with fewer
    documents than the limit: the backend counts documents where the field is missing or `null`,
    and the client drops them.
12. **BSON value details.** `Decimal128Value` accepts only strings that decimal128 holds exactly
    (the backend rejects the others; JS accepts any and rounds); the sum and average of an
    aggregation that includes a `Decimal128Value` are a `Decimal128Value`; increments on BSON
    numbers could not be compared with a backend (the emulator replaces the value); a plain `Map`
    with a reserved key such as `{'__int__': 5}` is rejected as document data and read as the
    BSON value in a query.
13. **Lite differences.** No `whereEqualTo(...)`-style query methods (use `where`);
    `FirestoreDataConverter.fromFirestore` takes only the snapshot; `DocumentReference.parent`
    keeps the converter; `firestore.doc('')` throws.
14. **Persistent cache indexes** are not used for queries with inequalities on several fields
    (scanned, as in JS) and do not exist for a memory cache (as in JS). The stored index entries
    are not byte-compatible with the Android SDK's (they are never exchanged).
15. **Snapshot JSON edge cases.** `toJson()` of a missing document writes an empty bundle, which
    the JS SDK cannot read; this port reads it back as the missing document. A serialized query
    snapshot whose documents lack a field the query orders by is rejected as invalid (the JS SDK
    fails an internal assertion).
16. **Platform details.** Windows is untested; there `clearPersistence()` fails with `unknown`
    while another isolate or process has the file open. On Linux, `package:sqlite3` needs
    `libsqlite3.so` (the example opener falls back to `libsqlite3.so.0`).
17. **Not ported:** the console-only `_customHeaders` setting of the JS SDK.
18. **Behaviour that is not a gap but differs from JS by design:** listeners are Dart `Stream`s,
    `snapshot.data` is a getter, `Source` replaces `getDocFromCache` / `getDocFromServer`, and the
    API spelling follows the Android SDK and FlutterFire (see
    [Coming from FlutterFire or the JS SDK](guides/queries_and_data.md#coming-from-flutterfire-or-the-js-sdk)).
    Extras over the JS client SDK: `Query.findNearest`, read-only transactions (also with
    pipelines).
