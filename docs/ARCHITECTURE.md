# Architecture of `cloud_firestore_dart`

For contributors. This is a map of the code, of the upstream code it was ported from, of the
tests, and of the places where the port deliberately differs from upstream. Paths without a
package are relative to `cloud_firestore/cloud_firestore_dart/`; `lib/...` below means
`lib/src/firebase/firestore/...`.

The port follows the Firebase Android SDK (`firebase-firestore/src/main/java/com/google/firebase/firestore/`,
"Android" below) class by class, and takes some later pieces from the JS SDK
(`packages/firestore/src/`, "JS" below). Behaviour is ported in Dart, not copied. Everything was
verified with unit tests and the Firestore emulator only; nothing was run against production
Firestore.

## Layers

A call goes down through these layers, and a server event comes back up through them.

| Layer | What it does | Dart | Upstream |
|---|---|---|---|
| Public API | `Firestore`, references, queries, snapshots, converters, value types. Parses user data into the model and converts results back. | `lib/firestore.dart`, `query.dart`, `document_reference.dart`, `document_snapshot.dart`, `user_data_converter.dart`, `snapshot_json.dart`; exported by `lib/cloud_firestore_dart.dart` | Android `FirebaseFirestore.java`, `Query.java`, `UserDataReader.java`, `UserDataWriter.java`; JS `api/snapshot.ts` for snapshot JSON |
| Client | Owns the components of one instance and the serial queue; every public operation enters here. | `lib/core/firestore_client.dart`, `core/serial_queue.dart` | Android `core/FirestoreClient.java`, `util/AsyncQueue.java` |
| Event manager and views | Fans query snapshots out to listeners; a `View` turns document changes into a `ViewSnapshot`. | `lib/core/event_manager.dart`, `core/view.dart`, `core/query_stream.dart` | Android `core/EventManager.java`, `core/View.java` |
| Sync engine | Glue between local store and remote store: listens, writes, limbo resolution, transactions, bundles. | `lib/core/sync_engine.dart`, `core/transaction_runner.dart` | Android `core/SyncEngine.java`, `core/TransactionRunner.java` |
| Local store | The cache: remote documents, mutation queue, targets, bundles, overlays. | `lib/local/local_store.dart`, `local/local_documents_view.dart` | Android `local/LocalStore.java`, `local/LocalDocumentsView.java` |
| Query engine | Runs a query against the cache, trying in this order: a persistent cache index that matches the query (merged with the documents the index does not cover yet), the previous results of the target plus the documents changed since (index-free), a collection scan. Decides when to create an index automatically. | `lib/local/default_query_engine.dart` (`QueryEngine` in `local/query_engine.dart`), `local/query_context.dart` | Android `local/QueryEngine.java` |
| Persistence | Memory and SQLite implementations of the caches; schema migrations; LRU garbage collection. | `lib/local/memory/`, `lib/local/sqlite/` (`sqlite_schema.dart`, `sqlite_persistence.dart`), `local/lru_garbage_collector.dart`; interfaces in `lib/local/persistance/` | Android `local/SQLitePersistence.java`, `local/SQLiteSchema.java`, `local/LruGarbageCollector.java` |
| Remote store | Keeps the listen and write streams in step with the local store; online state; watch change aggregation. | `lib/remote/remote_store.dart`, `remote/watch_change_aggregator.dart`, `remote/online_state_tracker.dart`, `remote/connectivity_monitor.dart` (platform connectivity hints) | Android `remote/RemoteStore.java`, `remote/WatchChangeAggregator.java`; JS `remote/remote_store.ts` for the remote target ids |
| Datastore and streams | The RPCs: the two streams with backoff and idle timeout, and the unary calls. | `lib/remote/datastore/datastore.dart`, `base_stream.dart`, `watch_stream.dart`, `write_stream.dart`, `call_release.dart` | Android `remote/Datastore.java`, `remote/AbstractStream.java`, `remote/WatchStream.java`, `remote/WriteStream.java` |
| Transport | How bytes reach the backend, behind `FirestoreTransport` (`firestore_transport.dart`). `transport_factory.dart` picks one with a conditional import. | `grpc_transport.dart` with `keep_alive_transport.dart` (VM, `dart:io`: gRPC, keepalive, and the guard against reconnect loops); `web/web_channel_transport.dart` with `web/rest_client.dart`, `web/web_channel.dart` and `web/write_send_ahead.dart` (browsers, experimental: REST for unary calls, WebChannel for the streams); `web/rest_transport.dart` (Firestore Lite on the web: REST only) | Android `remote/FirestoreChannel.java`, `remote/GrpcCallProvider.java`; JS `remote/rest_connection.ts`, `platform/browser/webchannel_connection.ts` |
| Serializers | Model to proto and back, for the wire and for the cache; bundles as JSON. | `lib/remote/remote_serializer.dart`, `local/local_serializer.dart`, `bundle/bundle_serializer.dart`, `bundle/bundle_builder.dart` | Android `remote/RemoteSerializer.java`, `bundle/BundleSerializer.java`; JS `util/bundle_builder_impl.ts` |
| Model | Documents, keys, paths, mutations, field values and their ordering. | `lib/model/`, `lib/model/value/`, `lib/model/mutation/` | Android `model/` (`Values.kt` for ordering; see the deviation on the value model below) |

Also in the tree:

- **Overlays**: the local view of a document with pending writes is one stored overlay per
  document (`local/persistance/document_overlay_cache.dart`, `local/sqlite/sqlite_overlay_migration_manager.dart`),
  as Android `local/DocumentOverlayCache.java` and `local/SQLiteOverlayMigrationManager.java`.
- **Pipelines** (preview, separate library `lib/pipelines.dart`): `lib/pipeline/`. Executed by the
  server. JS `lite-api/pipeline.ts`, `api/pipeline_impl.ts`, `core/pipeline-util.ts`. A local
  evaluator for expressions and aggregates and an executor for whole pipelines are in
  `lib/pipeline/evaluation/` (Android `pipeline/evaluation/`, JS `core/pipeline_run.ts`); they are
  internal and not yet used by the client (`test/unit/firebase/firestore/pipeline/evaluation/`,
  the port of Android's realtime pipeline tests in `test/unit/firebase/firestore/pipeline/realtime/`,
  and `test/integration_enterprise/pipeline_*_property_test.dart`).
- **Firestore Lite** (experimental, separate library `lib/lite.dart`): `lib/lite/`. No cache, no
  listeners: the API classes call `Datastore` directly (`remote/datastore/unary_client.dart`,
  `TransactionClient`), over gRPC or, on the web, over `remote/datastore/web/rest_transport.dart`
  (REST without WebChannel). Both `Query` classes build and validate their internal query with
  `lib/query_builder.dart`, which depends on neither client. JS `lite-api/`.
- **Persistent cache indexes** (the client-side index engine): the index value encoding in
  `lib/index/` (Android `index/FirestoreIndexValueWriter.java`), `lib/model/field_index.dart`
  and `lib/model/target_index_matcher.dart` (Android `model/FieldIndex.java`,
  `model/TargetIndexMatcher.java`), the index manager
  `lib/local/sqlite/sqlite_index_manager.dart` (Android `local/SQLiteIndexManager.java`), the
  backfiller `lib/local/index_backfiller.dart` (Android `local/IndexBackfiller.java`), and the
  public `lib/persistent_cache_index_manager.dart`. SQLite persistence only.
- **Connectivity**: `lib/remote/connectivity_monitor.dart` selects the platform part: the
  `online` / `offline` events of the browser, or on the VM
  `remote/connectivity_change_detector.dart`, which only gives hints while a stream is failing.
- **Releasing calls**: `remote/datastore/call_release.dart` (`CallReleaser`) half-closes a call
  that the client is done with and cancels it only after a grace period (see the deviations).
- **The app layer** is the other package, `firebase_core/firebase_app_dart` (`FirebaseApp`,
  `FirebaseOptions`, `PlatformDependencies`). Ready-made token providers (Firebase Auth users over
  REST, service accounts, Application Default Credentials) are in the optional package
  `firebase_auth/firebase_auth_providers_dart`; they plug into `FirebaseApp.authProvider`.

### The serial queue

Android runs every user operation, stream event and timer on one worker queue
(`AsyncQueue`), where a task finishes before the next one starts. Dart handlers are
asynchronous, so two of them could be in flight at once. `core/serial_queue.dart` restores the
guarantee: `FirestoreClient` enqueues every operation on a `SerialQueue` that it shares with
the `RemoteStore`, and a task that is already on the queue runs nested calls inline. Covered by
`test/unit/firebase/firestore/core/serial_queue_test.dart`.

## Tests

| Kind | Where | What it needs | Command (from the package directory unless noted) |
|---|---|---|---|
| Unit | `test/unit` | nothing | `dart test test/unit` (or `./tool/test_all.sh` from the repository root: pub get, analyze, unit tests of both packages) |
| Spec tests | `test/res/json/*.json`, run by `test/unit/firebase/firestore/spec/` on memory and SQLite persistence | nothing; part of the unit run | `dart test test/unit/firebase/firestore/spec` |
| API goldens | `test/unit/api/` (`public_api.golden.txt`, `pipelines_api.golden.txt`, `lite_api.golden.txt`, README snippets) | nothing | `dart test test/unit/api`; regenerate with `UPDATE_GOLDEN=1` |
| Integration, standard | `test/integration` | emulator on 127.0.0.1:8080 (`tool/start_emulator.sh`) | `tool/test_integration.sh standard` (repository root), or `FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart test test/integration` |
| Integration over the web transport | `test/integration`, on the VM | a private emulator on 127.0.0.1:8090 (`tool/start_private_emulator.sh`; the script starts it) | `tool/test_integration.sh standard --transport=webchannel` (also `--transport=webchannel-longpolling`), from the repository root |
| Enterprise | `test/integration_enterprise` (BSON types, Pipelines, edition differences) | Enterprise edition emulator on 127.0.0.1:8181 (`tool/start_enterprise_emulator.sh`) | `tool/test_integration.sh enterprise`, or `FIRESTORE_ENTERPRISE_EMULATOR_HOST=127.0.0.1:8181 dart test test/integration_enterprise` |
| Browser | `test/browser` (transport, features, Firestore Lite, web persistence and its crash harness) | the private emulator on 127.0.0.1:8090, Chrome | `tool/test_browser.sh [dart2wasm\|dart2js\|both]`, from the repository root |
| Property tests | `test/unit/property/` (value order, serializers, canonical ids), `test/integration/firebase/firestore/property_*_test.dart` and `test/integration_enterprise/property_*_test.dart` (queries and mutations against the backend) | nothing, or the emulators | run with the unit and integration suites; seeded, the seed is printed on failure |
| Chaos | `test/integration/firebase/firestore/chaos/` behind `test/util/chaos_proxy.dart`, a TCP proxy that cuts, stalls and delays connections | standard emulator | run with the standard integration suite |
| Production verification kit | `tool/verify_production` (`test/production/`) | an emulator, or a real project with your credentials and `--yes` (not run yet) | `tool/verify_production/run.sh --backend=emulator`, from the repository root |
| Size check | `tool/size`, `tool/check_size.sh` | nothing | `tool/check_size.sh`, from the repository root |
| Interop with the JS SDK | `test/integration/firebase/firestore/js_interop_test.dart` | standard emulator and the Node harness in `tool/interop` (`npm install` there) | runs with the standard integration suite; skipped without the harness |
| Examples | `example/*.dart`, run by `test/integration/firebase/firestore/examples_smoke_test.dart` and `test/integration_enterprise/examples_enterprise_smoke_test.dart` | the emulators | run with the integration suites |

The spec tests are the shared, data-driven tests of the official SDKs: the JSON is generated
from the JS SDK sources (`test/unit/specs/*.test.ts`) and describes sequences of user actions,
watch events and expected snapshots. `spec/spec_skip_list.dart` names every spec that does not
run and why (for example multi-client specs). One skip there is a limit of the test harness,
not of the library: the runner lets the event loop settle after every step, so a timer with no
delay that the JS runner would still see pending has run (the recovery spec "Multiple user
changes during transaction failure"). The mock watch stream
(`test/unit/firebase/firestore/remote/mock_datastore.dart`) goes through a backoff timer
(`TaskId.listenStreamConnectionBackoff`) after an error, as the JS mock connection does; the
runner fires it on `watchStreamClose` with `runBackoffTimer: true` and before a listen, and
otherwise leaves it pending. The `failDatabase` step makes the transactions of the persistence
fail by name through `local/persistence_fault_injector.dart` (the JS `injectFailures`).

Rules that the suite relies on: do not weaken or remove assertions; a skip needs a reason
string; tests that need a backend are skipped with a reason when its environment variable is
not set. `tool/README.md` lists the environment variables and the CI jobs.

## Deliberate deviations from upstream

Each row is a decision, not an omission. "Pinned by" is the test that fails if the behaviour
changes. `PORTING NOTE` comments in `lib/` mark these places in the code.

### Persistence

| Deviation | Why | Pinned by |
|---|---|---|
| The SQLite connection is never switched to `PRAGMA locking_mode = EXCLUSIVE` (Android does). | After a Flutter hot restart the old isolate still holds the file and the new one must open it. | `test/unit/firebase/firestore/local/sqlite_shared_file_test.dart` |
| Every transaction is `BEGIN IMMEDIATE` and starts by comparing `PRAGMA data_version`; when another connection committed, the target globals, the listen sequence, the batch id and stream token of the mutation queues and the memoized field indexes are read again, and a changed `user_version` fails the client. Schema migrations run in an exclusive transaction that reads the stored version itself. (Android caches all of this for the life of the process and migrates without a lock.) | Android owns the file exclusively; the port does not, so two clients on one file are possible and must not hand out the same ids or overwrite each other's metadata. | `test/unit/firebase/firestore/local/sqlite_shared_clients_test.dart`, `sqlite_shared_file_test.dart` |
| The package does not open SQLite itself: the application passes an `OpenDatabase` function, and `clearPersistence` deletes the file that the opener opened (Android derives the path itself). | No native dependency in the package; any SQLite binding can be used. | `test/unit/firebase/firestore/clear_persistence_test.dart`; a complete opener is `example/sqlite_database.dart` |
| The schema has its own numbering (version 16); Android's migrations are mapped onto it (`sqlite_schema.dart` says which). | The port branched off at schema 8 and took the later Android migrations in a different order. | `test/unit/firebase/firestore/local/sqlite_schema_test.dart`, `sqlite_schema_read_time_test.dart`, `legacy_cache_upgrade_test.dart` |
| The overlay migration rebuilds all overlays from the mutation queues (Android keeps existing rows). | Rows can be stale when an older version of the port, without overlays, changed the queue in between. | `test/unit/firebase/firestore/local/sqlite_overlay_migration_manager_test.dart` (`testRebuildsStaleOverlaysAfterDowngrade`) |
| Recalculating overlays removes the overlay of a document whose mutations no longer apply (Android keeps it). | The kept overlay would still be applied on the next read. | no dedicated test was found; the code is in `local/local_documents_view.dart` |
| A patch that creates a document, and a patch of no fields, are treated as mutating the whole document when the overlay mask is computed. | Android's mask loses the document for a merge of no fields on a deleted document. | no test that names this case was found; the overlay mask cases are in `test/unit/firebase/firestore/model/mutation/overlay_mutation_test.dart` |
| A persistence transaction that fails with a `TransientDatabaseException` is recovered from as in JS (its `IndexedDbTransactionError`), not as in Android, which has no recovery: a listen or a write that can not be stored fails with `unavailable`, a failed release or view update is ignored, and an acknowledgement, a rejection, a watch snapshot or a credential change that can not be stored takes the network offline and is retried with a backoff (`RemoteStore.enqueueRetryable` and `_disableNetworkUntilRecovery`, `util/retryable_operation_queue.dart`). The `Database` of the application decides what is transient; the example openers report SQLite's busy, locked, I/O and full-disk errors, and on the web a failed copy to IndexedDB (reported at the next transaction, since SQLite has committed in memory). Differences to JS: the in-memory resume tokens of the `RemoteStore` and the target data of the `LocalStore` change only once a remote event is stored (JS updates the tokens first); a retried operation that fails with another error is dropped (JS fails the client); a failed refresh of the primary lease keeps the current state (as JS; `SQLitePersistence.refreshClientMetadata`) and a change of the primary state is applied as a retryable operation. | Another connection holding the database (two isolates, a hot restart), a full disk or a closed IndexedDB must not fail the client for good; the backend resends what was not stored. | 17 of the 18 single-client recovery specs (`recovery_spec_test.json`; 15 on memory, which skips the durable ones), `test/unit/firebase/firestore/util/retryable_operation_queue_test.dart`, `local/example_sqlite_opener_errors_test.dart` |
| The canonical id of a target writes cursor positions without a separator (upstream uses a comma). | Canonical ids are persisted with the targets; changing the format would orphan cached targets. | `test/unit/firebase/firestore/core/bound_order_by_test.dart`, `legacy_cache_upgrade_test.dart` |

### Persistent cache indexes

| Deviation | Why | Pinned by |
|---|---|---|
| A reference ends with a truncation marker in the index encoding (Android writes no terminator). | Without it `a/b` sorts after `a/b/c/d` and the lowest reference after every reference: index scans for `<`, `<=`, `>`, `>=`, cursors and limits on a reference field return other documents than a collection scan. The entries are local only and never exchanged. | `test/unit/firebase/firestore/index/firestore_index_value_writer_test.dart`, `local/sqlite_field_index_manager_extra_test.dart` ("references") |
| A BSON timestamp is encoded as two numbers, seconds and increment (Android packs them into one signed 64-bit long). | The packed long is negative for seconds >= 2^31 (the year 2038), so those timestamps sort first and range scans on them are wrong. | the same two files ("BSON timestamps"), and `test/integration_enterprise/index_engine_bson_test.dart` |
| With an index offset, the remote documents read after the offset are read unfiltered and their overlays are looked up by key (Android reads only the overlays of later batches and filters the documents by the query). | A document that was read after the last backfill and has a pending patch from an earlier batch is otherwise returned without the patch, or wrongly in or out of the result, until the next backfill. | `test/unit/firebase/firestore/local/sqlite_query_engine_test.dart` ("documents read after the index offset") |
| `Persistence.indexManager` is a shared collection parent index next to the user scoped `Persistence.getIndexManager(user)` (Android only has the latter). | The remote document cache and the mutation queues of the port maintain the collection parents without knowing the user; the field index methods of the shared one assert. | `test/unit/firebase/firestore/local/sqlite_field_index_manager_extra_test.dart` ("the shared index manager of the persistence") |
| Read times are returned next to the documents (`ReadDocument`, `LocalDocumentsResult.readTimes`) instead of being a property of the document. | The immutable documents of the port have no read time. | `test/unit/firebase/firestore/local/sqlite_next_documents_test.dart` |
| The lowest timestamp used as an index bound is year 1 (Android: `Long.MIN_VALUE` seconds). | The earliest value a `Timestamp` of the port can hold; no stored timestamp is lower. | `test/unit/firebase/firestore/model/value_bounds_test.dart` |
| An index definition is parsed the way Android does: a field that is neither `CONTAINS` nor `ASCENDING` is descending (the JS SDK drops such a field). | One rule had to be picked; Android's keeps the field. | `test/unit/firebase/firestore/index/index_configuration_test.dart` |
| `PersistentCacheIndexManager` methods return a `Future` that completes when the change is applied (void in Android and JS). | So that a caller, and a test, can wait for it and see a failure on a terminated instance. | `test/unit/firebase/firestore/persistent_cache_index_manager_test.dart` |

### Networking

| Deviation | Why | Pinned by |
|---|---|---|
| A clean close of a stream by the server is reported as `UNAVAILABLE`, not `OK`. | The stream owner would mistake `OK` for a requested stop; the stream must back off and restart. | `test/unit/firebase/firestore/remote/stream_connection_failure_test.dart` |
| The client does not reset a call that the backend may be finishing: it half-closes, and cancels only after a grace period (`CallReleaser`). | A reset that races the server's trailers makes `package:http2` terminate the whole connection; a commit that had been applied then looked failed and was retried. | `test/unit/firebase/firestore/remote/call_release_test.dart`, `http2_reset_race_test.dart` |
| The transport connector fails the connection attempt that follows a connection that was lost before any call was started on it (`remote/datastore/keep_alive_transport.dart`). | `package:grpc` reconnects at once, forever, when a peer accepts connections and drops them or sends GOAWAY; failing the attempt fails the waiting calls, so the backoff of the streams applies. | `test/unit/firebase/firestore/remote/reconnect_backoff_test.dart`, `test/integration/firebase/firestore/chaos/connectivity_chaos_test.dart` |
| Every listen is sent with a fresh remote target id (the JS behaviour, not Android's). | A late removal or error for an earlier listen of a query must not hit a newer listen of it. | `test/unit/firebase/firestore/remote/remote_store_test.dart`, and the spec tests |
| The existence-filter `expected_count` is only sent with a resume token (upstream also sends it with a read time). | The count is relative to the documents the client had when the token was handed out. | `test/unit/firebase/firestore/remote/remote_serializer_test.dart` |
| Connectivity changes are not events from the system (Android registers a network callback): on the VM `remote/connectivity_change_detector.dart` polls the network interfaces, only while a stream is failing, and its hints only make the client retry sooner. They never set the offline state. An app that feeds `FirebaseApp.onNetworkConnected` replaces it. | `dart:io` has no connectivity events, and an interface being up does not mean that Firestore is reachable. | `test/unit/firebase/firestore/remote/connectivity_change_detector_test.dart`, `remote_store_connectivity_test.dart`, `test/integration/firebase/firestore/chaos/connectivity_chaos_test.dart` |
| On the web the transport is REST for unary calls and a WebChannel client over `fetch` for the streams. The cache is in memory unless the application passes the SQLite-on-IndexedDB opener of `example/sqlite_database_web.dart`. | Browsers have no sockets, and neither the backend nor the emulator accept gRPC-Web. Experimental, Chrome only. | `test/browser/`, and `test/integration` with `--transport=webchannel` |
| Over WebChannel a write is only sent ahead of the answers to earlier writes when applying it twice is harmless: a write with an `increment`, or one that shares a document with a write in flight when either has a precondition, waits (`web/write_send_ahead.dart`). gRPC needs no such gate. | Over WebChannel the backend reports a failed write as a message and keeps the session, so writes sent ahead of the failure are applied although the client sends them again. | `test/unit/firebase/firestore/remote/web/write_send_ahead_test.dart` |

### Values, queries and API

| Deviation | Why | Pinned by |
|---|---|---|
| The model keeps the typed `FieldValue` classes of the 2019 port (`lib/model/value/`) instead of proto `Value`s; the BSON types are classes too, detected by shape only when decoding. | Rewriting the model on protos was out of scope. | `test/unit/firebase/firestore/model/field_value_test.dart`, `model/bson_values_test.dart`, `bson_serialization_test.dart` |
| `==` on numbers of different types is false while `compareTo` compares by value (as JS; Android's `Values.equals` compares by value). Filters do not use `==`: see the next row. | `==` drives document equality and change detection. | `test/unit/firebase/firestore/model/bson_values_test.dart` |
| The local evaluation of filters and transforms follows the backend where the JS and Android SDKs do not: `in`, `not-in`, the array filters, `arrayUnion` and `arrayRemove` compare numbers by value whatever their type, and range filters do not match `null` and `NaN`. | Otherwise a cached document that only the client matches stays in limbo, and the cache differs from the stored document after an array transform. Found by the property tests. | `test/unit/property/`, `test/integration/firebase/firestore/property_query_test.dart`, `property_mutation_test.dart`, `test/unit/firebase/firestore/model/bson_values_test.dart` ("membership filters match numbers by value") |
| A cached document that the client matches for a query but the backend does not return is dropped from that query's view once limbo resolution shows that it exists, the target is current without it and no pending write explains the difference (`core/view.dart`, `core/sync_engine.dart`). JS and Android keep it in limbo. | The listener would never leave `isFromCache` and `get(Source.server)` would not complete whenever local filter semantics disagree with the backend. The backend is trusted. | `test/unit/firebase/firestore/spec/limbo_mismatch_spec_test.dart`, `core/view_limbo_cache_test.dart`, `core/view_limbo_from_cache_test.dart` |
| A write that is acknowledged with the version the cached document already has (a re-sent write that changed nothing on the backend) is applied when the cached document is only the result of earlier acknowledgements. Upstream drops it. | After a lost acknowledgement `get(Source.cache)` returned the old value without a pending write. | `test/unit/firebase/firestore/local/local_store_ack_same_version_test.dart` |
| `Decimal128Value` is compared exactly with `BigInt` (`util/exact_number.dart`); upstream converts to a 128-bit-mantissa `Quadruple`. | Smaller, exact, and no ordering difference appeared in the ported upstream tests. | `test/unit/firebase/firestore/bson_types_test.dart`, `model/bson_values_test.dart` |
| A plain map with a reserved key (`{'__int__': 5}`) is rejected in document data, and read as the BSON value in a query value or an array transform element. | The backend does not tell the map from the BSON value; the cache must evaluate the query the same way. | `test/unit/firebase/firestore/bson_shaped_maps_test.dart` |
| Bundles may contain `OR` composite filters (Android only reads `AND`). | The bundle inside `QuerySnapshot.toJson()` of an OR query must be readable. | `test/unit/firebase/firestore/bundle/bundle_serializer_test.dart`, `snapshot_json_test.dart` |
| `fromJson` of a missing document accepts the empty bundle that `toJson` writes (the JS SDK fails to parse it). | A round trip of a missing document should work. | `test/unit/firebase/firestore/snapshot_json_test.dart` |
| A query converted to a pipeline adds checks that JS and Android do not: `!=` / `not-in` exclude null, array filters skip non-array fields. | So that `createFrom(query)` returns what the query returns. | `test/unit/firebase/firestore/pipeline/query_to_pipeline_test.dart`, `test/integration_enterprise/pipeline_create_from_test.dart` |
| `TransactionOptions(readOnly: true)` runs a read-only transaction of the backend (`BeginTransaction`, reads with its id, `Rollback`), with `Transaction.getQuery` / `getAggregate` and an optional `readTime`. Android and JS have no read-only transactions. | A consistent snapshot across documents and queries, as the server SDKs offer. | `test/integration/firebase/firestore/read_only_transaction_test.dart`, `test/unit/firebase/firestore/core/read_only_transaction_test.dart` |
| Calls on a terminated instance fail with `FirestoreError` `failedPrecondition` through the returned `Future` or `Stream`, never synchronously (the JS behaviour). | One way to handle the error, whatever the call. | `test/integration/firebase/firestore/terminated_instance_test.dart` |
| `Query.where('field')` with no non-null named argument throws an `ArgumentError` (FlutterFire returns the query unchanged). | A filter that silently does nothing hides mistakes. | `test/unit/firebase/firestore/query_where_test.dart` |
| The public API is classes and methods with Java-style names plus Dart aliases, not the modular functions of the JS SDK. Internal members are library-private and reached through extensions that the public libraries do not export. | Dart tree-shakes methods. | `test/unit/api/public_api.golden.txt` is the exact surface |
| There is no multi-tab coordination (the JS SDK's primary lease and `SharedClientState`): two clients on one SQLite file keep it consistent (see Persistence) but do not share listeners or pending writes, and on the web a second tab is refused by a Web Lock. Android and iOS have none either; the staged plan for it is in progress. | A VM client usually has one process per cache. | `test/unit/firebase/firestore/local/sqlite_shared_clients_test.dart`; the `multi-client` entry of `spec/spec_skip_list.dart` |

### Not deviations, but worth knowing

- 64-bit arithmetic in the bloom filter and the index encoding goes through `Int64`, so that the
  code also works compiled to JavaScript (`remote/bloom_filter.dart`, `index/ordered_code_writer.dart`).
- LRU garbage collection removes orphaned documents with one query, where Android batches; on a
  very large cache this loads all orphan paths at once (see `docs/upstream_sync/UPSTREAM_PLAN.md`).
- The emulator differs between the Standard and the Enterprise edition in a few places; they are
  listed in the package README and pinned by `test/integration_enterprise/edition_differences_test.dart`.

## Where to read more

- `docs/upstream_sync/UPSTREAM_PLAN.md`: what was ported from which upstream commits, and the
  current status.
- `docs/update_transforms_design.md`: field transforms inside set and patch mutations.
- `cloud_firestore/cloud_firestore_dart/docs/api_modernization_plan.md`: the state of the
  Dart-idiom API work.
- `cloud_firestore/cloud_firestore_dart/docs/app_check_design.md`: App Check token plumbing.
- `docs/migrating_from_vm_packages.md`: what changed for users of the old packages.
- `tool/README.md`: scripts, emulators, environment variables, CI.
