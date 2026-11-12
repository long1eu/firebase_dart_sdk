# Upstream analysis, chunk 1 (142 commits, 2020-07-02 to 2022-01-11)

Baseline: Dart port synced at 576da00e85 (2019-07-23). Dart port checked by grep in `lib/src/firebase/firestore/`. Items marked (unverified) were inferred from subjects/stats without reading the full diff. Release versions come from `runs/android_firestore_changelog.md` (Android Firestore 21.7.0 to 24.0.0).

## 1. Summary of themes

1. **Query operators != and NOT_IN** (Aug-Sep 2020, released 21.7.0): new Filter.Operator values, NotInFilter, KeyFieldNotInFilter, cross-type NOT_EQUAL matching, a `conflictingOps` validation table, unary encoding of NOT_EQUAL for null/NaN, proto additions. Dart has none of it (core/filter/filter_operator.dart has no notEqual/notIn).
2. **Validation removed for null/NaN in filters** (22.0.1): the backend accepts null/NaN for all operators; Dart still throws in core/filter/field_filter.dart:30,36 and an integration test encodes the old behaviour.
3. **timestampsInSnapshots removed** (22.0.0, breaking): Timestamps always returned as Timestamp.
4. **Transforms folded into set/patch writes** (`update_transforms`, 22.0.2): TransformMutation deleted; Mutation owns fieldTransforms; LocalSerializer squashes legacy stored transform writes. This is the biggest model/mutation/wire change in the chunk.
5. **Bundles / named queries** (Dec 2020 to Jul 2021, 22.1.0 plus fixes 22.1.1 and 23.0.3): bundle/* package, LoadBundleTask, LocalStore/SyncEngine hooks, bundle cache tables (needs a SQLite migration).
6. **MutableDocument refactor** (Feb 2021) and follow-ups (b5d06cd, 9b67604): documents mutated in place; local deletes now keep the document version; baseDoc argument dropped. Cross-cutting model refactor that later work (overlays, indexing) builds on.
7. **Core correctness fixes**: limbo resolutions dequeued when queries stop (22.1.1, get() never completing), existence-filter mismatch clears resume token and last-limbo-free snapshot (Jan 2022), DatabaseId/DocumentKey.fromName length assertions, Values equality without protobuf equals.
8. **Offline indexing, query planner and document overlays** (Jul 2021 to Jan 2022, ~75 commits, shipped later in 24.x): FieldIndex, index encoding, SQLite index tables, backfiller, overlay tables with repeated schema churn, merged QueryEngine. Large, mostly internal; not needed for API parity.
9. **Auth/AppCheck/streams/Android-specific**: AppCheck integration (24.0.0), stream Healthy state, dynamic-module credentials rework, connectivity monitoring (Android only), emulator settings.
10. **Public API additions**: public Filter class (Dec 2021, groundwork for Filter.or/and), setIndexConfiguration (preview), LoadBundleTask, whereNotEqualTo/whereNotIn.

## 2. Top items for the Dart port

- **1ee3caa + 6879f54 + 2d829f3 + 924aaa2**: Add != and NOT_IN (core filters, serializer, Query API, protos). Size: M-L (needs a Values-like cross-type compare for NOT_EQUAL; model/value FieldValue compare may suffice).
- **1dc2837**: Drop client-side null/NaN restrictions in filters (22.0.1); Dart tests encode old behaviour. Size: S.
- **d40e7f1 (+ df6a201, 8655b90, 7055d2a)**: Transforms as update_transforms on Set/Patch writes; remove TransformMutation; LocalSerializer legacy squash. Size: L.
- **c9fefbe**: Limbo resolutions dequeued when queries stop (get() never completing); Dart lacks the enqueued-limbo queue. Size: M.
- **618b08c**: Clear resume token and limbo-free snapshot on existence filter mismatch (data correctness). Size: M (depends on limbo-free snapshot from chunk 0).
- **b5d06cd**: DatabaseId/DocumentKey.fromName length fix and transform previous-value fix. Size: S.
- **9b67604**: Local deletes keep document version (behavioural change, spec tests). Size: M (verify against spec tests; ties to MutableDocument).
- **979000c + 7be699f**: MutableDocument refactor. Size: L (optional, prerequisite for overlays).
- **6ce7880 + a809f4d + 76597db + 2a3f7dc + ce1a078 + 76b029c**: Bundles / named queries (22.1.0 to 23.0.3), new SQLite tables. Size: L.
- **f9519f2**: Remove timestampsInSnapshots; simplify DocumentSnapshot. Size: S.
- **55e6921**: Values equality without protobuf equals (int/map equality). Size: S (check IntegerValue/ObjectValue ==).
- **ff414cb**: AppCheck token provider, x-firebase-appcheck header (24.0.0). Size: M (needs firebase_core_vm support).
- **cae3743**: Public Filter class; core Filter hierarchy rework (groundwork for Filter.or/and). Size: L.
- **424da4d**: Healthy state for streams (backoff reset). Size: S-M.
- **9466242**: Skip subcollection scanning in SQLiteRemoteDocumentCache via path-length columns (schema change). Size: M.
- **57ffa1f**: Unified emulator settings in FirebaseFirestore. Size: S.
- **13b12ca**: Removes SimpleQueryEngine; decide which engine the port keeps (Dart still has simple_query_engine.dart). Size: S.

## 3. Full table

sha7 | date | PR# | category | area | relevance | in Dart? | what changed and why it matters for the port
---|---|---|---|---|---|---|---
85ee822 | 2020-07-02 | 1751 | BUILD | other | N/A | N/A | Lint config fix (unverified: no src/main change).
57ffa1f | 2020-07-27 | 1802 | FEATURE-public-API | api | SHOULD | NO | Re-implements unified emulator settings in FirebaseFirestore (useEmulator/host handling). Dart has FirestoreSettings.host/sslEnabled only; would touch firestore.dart, firestore_settings.dart (Android 21.6/21.7 era, unverified mapping).
c277074 | 2020-08-04 | 1851 | DOCS | other | N/A | N/A | Release-version bookkeeping.
924aaa2 | 2020-08-05 | 1856 | PROTOCOL-wire | remote | MUST | UNKNOWN | Adds NOT_EQUAL/NOT_IN to protos (no src/main). Check Dart proto dir has StructuredQuery.FieldFilter.Operator.NOT_EQUAL/NOT_IN; the proto dir was regenerated by another agent.
1ee3caa | 2020-08-14 | 1872 | FEATURE-public-API | core | SHOULD | NO | Adds != and NOT_IN: Filter.Operator NOT_EQUAL/NOT_IN, NotInFilter, KeyFieldNotInFilter, FieldFilter.create/matches (NOT_EQUAL matches across types via Values.compare), RemoteSerializer unary NaN/null encoding for NOT_EQUAL, Query.whereNotEqualTo/whereNotIn with a conflictingOps() validation table. Dart: core/filter/filter_operator.dart, field_filter.dart, new not_in_filter/key_field_not_in_filter, remote_serializer.dart, query.dart (released 21.7.0). Needs Values-style compare for cross-type NOT_EQUAL.
9f69957 | 2020-08-20 | 1902 | DOCS | other | N/A | N/A | Release-version bookkeeping.
55e6921 | 2020-08-27 | 1920 | BUGFIX-correctness | model | SHOULD | N/A | Values.numberEquals/mapEquals stop using protobuf equals (integer compare, recursive Values.equals) so int/double/nested-map equality is correct. Dart has no Values class (FieldValue classes); check IntegerValue/ObjectValue == in model/value (ObjectValue == goes through ImmutableSortedMap ==). Depends on chunk 0 Values port (unverified).
c99b61c | 2020-08-27 | 1919 | DOCS | api | N/A | N/A | Javadoc review comments.
2d829f3 | 2020-09-09 | 1947 | BUGFIX-correctness | core | MUST | NO | NotInFilter.matches returns false when the array contains null. Part of NOT_IN; port together with 1ee3caa (core/filter/not_in_filter.dart). Later fixed again in 25.1.4 (null handling) outside this chunk.
26922e4 | 2020-09-11 | 1974 | DOCS | other | N/A | N/A | README emulator command.
0977571 | 2020-09-15 | 1972 | FEATURE-internal | remote | COULD | NO | Makes the language reported in x-goog-api-client header configurable (FirestoreChannel). Dart: remote/datastore/channel_options_provider.dart; cosmetic.
6879f54 | 2020-09-15 | 1975 | FEATURE-public-API | api | SHOULD | NO | Makes whereNotEqualTo/whereNotIn public, validation messages updated (FieldFilter, Query). Land with 1ee3caa; released 21.7.0.
8f27059 | 2020-09-18 | 1991 | TEST | other | N/A | N/A | Test determinism for != queries.
6e286da | 2020-09-22 | 2000 | TEST | other | COULD | N/A | Imports shared spec test JSON files. Useful for Dart spec tests (test/unit/.../spec) but not code (unverified).
22d1615 | 2020-09-29 | 2009 | ANDROID-ONLY | remote | N/A | N/A | Sends GMP app ID with user agent via Android heartbeat provider (platform logging).
12ae453 | 2020-09-29 | 2012 | ANDROID-ONLY | remote | N/A | N/A | Always send user agent regardless of heartbeat.
c8098ad | 2020-09-29 | 2018 | DOCS | other | N/A | N/A | Changelog entry.
26f1b13 | 2020-09-30 | 2024 | TEST | other | N/A | N/A | Heartbeat integration test.
e65f487 | 2020-10-07 | 2043 | DOCS | other | N/A | N/A | Release-version bookkeeping.
f9519f2 | 2020-10-09 | 2026 | FEATURE-public-API | api | SHOULD | NO | Removes the timestampsInSnapshots setting; timestamps always Timestamp (22.0.0 breaking). Dart still has _FieldValueOptions.timestampsInSnapshotsEnabled in document_snapshot.dart (_convertTimestamp branch) and ServerTimestampBehavior; simplify document_snapshot.dart.
0c69ef4 | 2020-10-16 | 2072 | DOCS | other | N/A | N/A | Release-version bookkeeping.
1dc2837 | 2020-10-29 | 2115 | BUGFIX-correctness | core | SHOULD | NO | Removes client-side validation that null/NaN only work with ==/!= and that IN/ARRAY_CONTAINS_ANY lists cannot contain null/NaN (backend accepts them; 22.0.1). Dart core/filter/field_filter.dart:30,36 still throws; integration test validation_test queriesWithNullOrNaNFiltersOtherThanEqualityFail encodes the old behaviour and must be updated; also query.dart list validation.
1fb6c62 | 2020-11-03 | 2135 | BUILD | other | N/A | N/A | errorprone upgrade.
fd76164 | 2020-11-10 | 2162 | DOCS | api | N/A | N/A | Javadoc link fixes.
25f8ed7 | 2020-11-20 | 1981 | BUGFIX-crash | api | COULD | N/A | Fixes ConcurrentModificationException in FirestoreMultiDbComponent.onDeleted (iterate over copy). Dart firestore_multi_db_component.dart holds a static instances map; check removal while iterating (unverified).
13b12ca | 2020-11-26 | 2203 | REFACTOR | local | COULD | PARTIAL | Removes SimpleQueryEngine; IndexFreeQueryEngine renamed DefaultQueryEngine. Dart still has local/simple_query_engine.dart and indexed_query_engine.dart (index-free engine from the 2019 sync is not clearly present); decide which engine the port uses (local/query_engine.dart).
15fdd36 | 2020-12-01 | 2214 | DOCS | other | N/A | N/A | Release-version bookkeeping.
df6a201 | 2020-12-02 | 2224 | PROTOCOL-wire | remote | MUST | UNKNOWN | Adds Write.update_transforms to protos. Prerequisite for d40e7f1; verify the regenerated Dart protos expose Write.updateTransforms.
a809f4d | 2020-12-15 | 2246 | FEATURE-public-API | bundle | SHOULD | NO | Adds LoadBundleTask/LoadBundleTaskProgress (Task wrapper); Dart equivalent would be a Stream<LoadBundleTaskProgress>/Future. Part of the bundles feature (22.1.0).
d40e7f1 | 2020-12-17 | 2262 | PROTOCOL-wire | model | MUST | NO | Replaces separate TransformMutation with Write.update_transforms on Set/Patch mutations: Mutation gets fieldTransforms, serverTransformResults/localTransformResults/transformObject/extractTransformBaseValue move into Mutation; TransformMutation deleted; LocalSerializer squashes legacy stored transform writes into the preceding set/patch (decode loop, hardAssert pairing); RemoteSerializer encodes/decodes updateTransforms; UserData builds set/patch with transforms. 22.0.2 (writes with transforms no longer split, so batches hold 500 writes). Dart: model/mutation/{mutation,set_mutation,patch_mutation,transform_mutation,mutation_result}.dart, core/user_data.dart, local/local_serializer.dart, remote/remote_serializer.dart:356-405, user_data_converter.dart, firestore.dart/write_batch.dart/transaction.dart. Mutation tests (mutation_test.dart) change shape. L.
a9e4ab8 | 2021-01-05 | 2290 | DOCS | other | N/A | N/A | Release-version bookkeeping.
48f9eeb | 2021-01-05 | 2273 | REFACTOR | remote | N/A | N/A | Renames "whitelist" wording in AbstractStream comments/vars.
2a3f7dc | 2021-01-05 | 2291 | PROTOCOL-wire | bundle | SHOULD | NO | Adds bundle protos (BundleMetadata, NamedQuery, BundledQuery). Needed by bundles; the Dart proto dir is separate, check or add.
76597db | 2021-01-08 | 2296 | FEATURE-public-API | bundle | SHOULD | NO | Implements LoadBundleTask + OnProgressListener (task state machine, progress). Bundles feature, 22.1.0; Dart api layer (new load_bundle_task.dart).
3402f9a | 2021-01-08 | 2305 | TEST | other | N/A | N/A | Adds missing spec test JSON.
48b41ff | 2021-01-08 | 2306 | TEST | model | N/A | N/A | Test util split mergeMutation/patchMutation (src/test only); useful when porting model tests (unverified for src).
4370f77 | 2021-01-20 | 2340 | REFACTOR | model | COULD | NO | Removes the unused baseDoc argument from Mutation.applyToLocalView/MutationBatch. Dart mutation.dart/mutation_batch.dart/local_documents_view.dart still pass baseDoc; do with the MutableDocument rewrite (979000c) or skip.
a030f2b | 2021-01-20 | 2329 | FEATURE-internal | util | SHOULD | NO | Adds ByteBufferInputStream used by BundleReader (util/). Dart: Dart streams/Uint8List reader instead; part of bundles.
36441ee | 2021-01-20 | 2345 | ANDROID-ONLY | api | N/A | N/A | ActivityLifecycleObserver in LoadBundleTask.
ef85b50 | 2021-01-27 | 2348 | TEST | other | N/A | N/A | Spec tests updated for bundles.
7055d2a | 2021-01-29 | 2375 | PERF | local | COULD | NO | LocalSerializer.decodeMutationBatch iterates forward instead of reverse+Collections.reverse after transform squashing; only meaningful after d40e7f1 (local/local_serializer.dart).
6ce7880 | 2021-02-03 | 2398 | FEATURE-public-API | bundle | SHOULD | NO | Firestore Bundles: bundle/* (BundleReader, BundleSerializer, BundleLoader, NamedQuery, BundleMetadata, BundledQuery), FirebaseFirestore.loadBundle/getNamedQuery, SyncEngine.loadBundle, LocalStore.applyBundledDocuments/saveNamedQuery/getNamedQuery, BundleCache (SQLite + memory), schema table bundles/named_queries, Target API change. 22.1.0. Needs a SQLite migration (new tables). Dart: new bundle/ dir, local/{bundle_cache,sqlite_bundle_cache,memory_bundle_cache}.dart, local_store.dart, sqlite_schema.dart, core/sync_engine.dart, firestore.dart. L.
6b44629 | 2021-02-03 | 2403 | BUILD | other | N/A | N/A | Gradle javadoc deps.
c9fefbe | 2021-02-05 | 2404 | BUGFIX-correctness | core | MUST | NO | SyncEngine dequeues limbo resolutions when the owning queries stop (enqueuedLimboResolutions becomes a LinkedHashSet, removeLimboTarget also removes enqueued key, dedupes in trackLimboChange). Fixes get() Tasks that never complete (22.1.1, #2404). Dart: core/sync_engine.dart has no enqueued-limbo queue/maxConcurrentLimboResolutions logic (only _limboTargetsByKey); port limbo queue + this fix. M.
8655b90 | 2021-02-09 | 2428 | REFACTOR | model | COULD | PARTIAL | MutationResult.transformResults becomes non-null (empty list); drops null handling in Set/Patch/Delete + RemoteSerializer. Dart MutationResult.transformResults is List<FieldValue>? (matches pre-d40e7f1 Java); change with d40e7f1.
fffbe08 | 2021-02-10 | 2412 | DOCS | api | N/A | N/A | Bundle API docs.
5947657 | 2021-02-11 | 2436 | BUGFIX-correctness | remote | COULD | N/A | Replaces gRPC Status.equals() (reference equality) with isOk()/code compare in AbstractStream/RemoteStore. gRPC Status is Java-specific; check Dart base_stream.dart/remote_store.dart compare error codes by value (unverified).
1ef3915 | 2021-02-12 | 2437 | DOCS | other | N/A | N/A | Release-version bookkeeping.
f54d96a | 2021-02-23 | 2432 | ANDROID-ONLY | api | N/A | N/A | Dynamic feature module support: credentials providers reworked (removes EmptyCredentialsProvider, FirebaseAuthCredentialsProvider uses Deferred<InternalAuthProvider>).
ce1a078 | 2021-02-24 | 2463 | BUGFIX-correctness | bundle | SHOULD | NO | BundleSerializer accepts proto3 JSON limits (int32 limit may be string/object, 22.1.1 limit-drop fix). Only relevant with bundles.
979000c | 2021-02-25 | 2383 | REFACTOR | model | SHOULD | NO | Mutable Documents: MaybeDocument/Document/NoDocument/UnknownDocument replaced by MutableDocument (type enum FOUND/NO/UNKNOWN/INVALID) with in-place mutation; Mutation.applyTo*(MutableDocument) mutates instead of returning; LocalDocumentsView/LocalStore/RemoteDocumentCache/View/SyncEngine updated. Semantic change: documents have read time and mutation results mutate in place. Huge cross-cutting refactor (M/L). Dart: model/{document,maybe_document,no_document,unknown_document}.dart + everything that uses them. Prerequisite for the overlay/index work in later commits; optional by itself.
7be699f | 2021-02-26 | 2468 | REFACTOR | model | SHOULD | NO | Post-merge cleanup of MutableDocument (MutableDocument.equals, MutationBatch simplification, RemoteSerializer decode). Port together with 979000c.
9eb699a | 2021-02-27 | 2470 | PROTOCOL-wire | local | SHOULD | NO | Changes bundle proto package (affects LocalSerializer/SQLiteBundleCache encoding of persisted bundle metadata). Only with bundles.
0abc215 | 2021-03-01 | 2473 | TEST | other | N/A | N/A | Tests no longer use Ant.
49f6587 | 2021-03-10 | 2494 | TEST | other | N/A | N/A | Test duplication cleanup.
68e53f9 | 2021-03-10 | 2498 | DOCS | other | N/A | N/A | Changelog typo.
c863d96 | 2021-03-18 | 2507 | TEST | other | N/A | N/A | Fixes failures from internal presubmit (tests).
40df7c8 | 2021-04-20 | 2517 | TEST | other | N/A | N/A | Tests stop using static RuntimeEnvironment contexts (Android).
3514ddf | 2021-04-23 | 2616 | DOCS | other | N/A | N/A | Release-version bookkeeping.
b5d06cd | 2021-05-25 | 2577 | BUGFIX-correctness | model | MUST | NO | Simplify Mutations & small bug fixes: DatabaseId.fromName and DocumentKey.fromName hardAssert length >= 3/4 becomes > 3/ > 4 (a name with no database/document segment was accepted); previousValue lookup in transform results no longer gated on isFoundDocument. Dart: remote_serializer.dart:165 (isValidResourceName `path.length >= 4`) and model/document_key.dart fromPath checks; low risk small fix.
a4d2ee4 | 2021-05-25 | 2694 | DOCS | other | N/A | N/A | Release-version bookkeeping.
3145da7 | 2021-05-26 | 2693 | ANDROID-ONLY | remote | N/A | N/A | Skip backoff when app enters foreground (AndroidConnectivityMonitor).
95b36fc | 2021-06-04 | 2716 | DOCS | other | N/A | N/A | Release-version bookkeeping.
7ba2d2a | 2021-06-18 | 2744 | BUILD | other | N/A | N/A | ProGuard handling.
c7d8a80 | 2021-06-18 | 2745 | BUILD | local | N/A | N/A | google-java-format upgrade touches SQLiteSchema formatting only.
563781c | 2021-06-25 | 2764 | REFACTOR | core | COULD | PARTIAL | Transaction retries renamed to attempts; attemptsRemaining decremented per attempt (DEFAULT_MAX_ATTEMPTS_COUNT=5) with the public maxAttempts option added later (outside chunk, unverified). Dart core/sync_engine.dart:212 uses retries>0; semantics same (5 attempts?) check off-by-one.
f65c333 | 2021-06-28 | 2763 | ANDROID-ONLY | remote | N/A | N/A | Manual foreground detection to trigger network reconnect.
76b029c | 2021-07-14 | 2820 | BUGFIX-correctness | bundle | SHOULD | NO | BundleReader fixes multi-byte UTF-8 chars when reading length-prefixed bundle elements (23.0.3). Only with bundles; read bytes not chars.
7c9c638 | 2021-07-15 | 2834 | REFACTOR | other | N/A | N/A | Removes unused com.google.cloud.datastore number encoder code.
cd24435 | 2021-07-28 | 2843 | PERSISTENCE-schema | local | COULD | NO | Adds field-index tables to SQLiteSchema (index_configuration, index_state, index_entries) behind an unreleased flag. Part of the offline query indexing project; not released in this chunk (24.x, later). Dart local/sqlite/sqlite_schema.dart; skip unless indexing is in scope.
1764a34 | 2021-07-29 | 2838 | FEATURE-internal | local | COULD | NO | Environment flag to control indexing (Persistence.java).
b0f2783 | 2021-08-04 | 2856 | FEATURE-public-API | index | COULD | NO | Adds FirebaseFirestore.setIndexConfiguration + FieldIndex model + IndexManager API (preview feature, released in 24.x; changelog lists it later). Dart: new model/field_index.dart, local/index_manager. Optional.
ba7e1dd | 2021-08-06 | 2890 | DOCS | other | N/A | N/A | Release-version bookkeeping.
958483c | 2021-08-09 | 2889 | BUILD | other | N/A | N/A | CI timeout.
ded7eda | 2021-08-16 | 2883 | FEATURE-internal | index | COULD | NO | Index encoding (OrderedCode writer/reader, FirestoreIndexValueWriter) copied from the backend. Needed only for local indexing.
defe4b7 | 2021-08-16 | 2887 | TEST | other | N/A | N/A | Conformance test protos.
27790de | 2021-08-20 | 2861 | TEST | other | COULD | N/A | Watch conformance tests; also changes UserDataWriter (timestamp conversion, unverified). Could be reused as Dart tests.
8d3f125 | 2021-08-23 | 2900 | FEATURE-internal | index | COULD | NO | Query planner: TargetIndexMatcher chooses a FieldIndex for a Target. Indexing only.
fda0aed | 2021-09-01 | 2935 | REFACTOR | index | COULD | NO | Review fixes for index encoding/FieldIndex. Indexing only.
b7915e3 | 2021-09-07 | 2960 | PERSISTENCE-schema | local | COULD | NO | Removes index_value from index_entries primary key; reverted by b0e18f9 next. Net zero.
b0e18f9 | 2021-09-07 | 2961 | PERSISTENCE-schema | local | COULD | NO | Reverts b7915e3.
e41b233 | 2021-09-08 | 2926 | FEATURE-internal | core | COULD | NO | Index bounds in Target (getLowerBound/getUpperBound, arrayValues, equalities). Indexing only; also changes Bound.
8122d55 | 2021-09-09 | 2950 | FEATURE-internal | index | COULD | NO | Index backfill base classes (IndexBackfiller, Scheduler rename from GarbageCollectionScheduler). Indexing only.
67f91ad | 2021-09-10 | 2965 | BUGFIX-correctness | api | COULD | UNKNOWN | FirebaseFirestoreSettings copy constructor forgot to copy cacheSizeBytes (23.0.4 changelog). Dart FirestoreSettings.copyWith exists (firestore_settings.dart:56): verify it copies cacheSizeBytes.
41715ed | 2021-09-11 | 2969 | TEST | remote | N/A | N/A | Speeds up SpecTest via Datastore test hook.
da62838 | 2021-09-16 | 2963 | FEATURE-internal | index | COULD | NO | Index evaluation (SQLiteIndexManager.getDocumentsMatchingTarget, IndexByteEncoder, Bound changes). Indexing only.
c30a15a | 2021-09-16 | 2979 | FEATURE-internal | model | COULD | NO | Tightens query bounds; adds Values.lowerBound/upperBound helpers (Values.java +90) used for NOT_EQUAL/NOT_IN index ranges. Model-level but indexing-only.
e445aca | 2021-09-17 | 2981 | REFACTOR | core | COULD | NO | Bound.before replaced by inclusive flag (Query startAt/After semantics, BundleSerializer, RemoteSerializer cursor encode/decode: before = !inclusive). Wire semantics unchanged; Dart core/bound.dart keeps `before`. Only needed if aligning with later Target code.
0e40391 | 2021-09-20 | 2984 | FEATURE-internal | index | COULD | NO | Update time (sequence number + read time) in FieldIndex. Indexing only.
45dd9ff | 2021-09-21 | 2982 | PERF | index | COULD | NO | Run one SQL query instead of n for index lookups. Indexing only.
9b67604 | 2021-09-21 | 2993 | BUGFIX-correctness | model | MUST | NO | Removes special handling in Mutations: local delete keeps the document version (convertToNoDocument(document.getVersion()).setHasLocalMutations) instead of SnapshotVersion.NONE; getPostMutationVersion removed. Changes observable NoDocument versions in the local view and spec tests; depends on MutableDocument model (979000c). Dart model/mutation/delete_mutation.dart (uses SnapshotVersion.none), mutation.dart getPostMutationVersion, local_documents_view.dart. Verify against spec tests before porting.
9815e45 | 2021-09-22 | 2962 | FEATURE-internal | model | COULD | NO | Overlay on top of mutation list: Mutation.applyToLocalView returns/consumes a FieldMask of mutated fields (PatchMutation merges mask+transform paths); ObjectValue.toString uses canonicalId. Prep for document overlays (24.x). Dart: model/mutation/*.dart; skip unless overlays are ported.
a90d3c5 | 2021-09-28 | 3003 | REFACTOR | index | N/A | N/A | Deletes unused OrderedCodeReader.
e8ac306 | 2021-09-29 | 2995 | FEATURE-internal | index | COULD | NO | Index ordering support (OrderBy/Target/IndexEntry). Indexing only.
6ac9d7f | 2021-09-29 | 3002 | BUGFIX-correctness | index | COULD | NO | Fix IN filters in the SQL index query (adds schema index). Indexing only.
a692f63 | 2021-09-29 | 3007 | PERSISTENCE-schema | local | COULD | NO | DocumentOverlay schema + scaffolding (document_overlays table, DocumentOverlay model, memory/SQLite). Overlays project; later commits (2cba82f, 7c9c133, 110b867, eec5f31, 1b8e6dd) change the schema repeatedly, so migrate only the final shape.
7a48c9d | 2021-10-04 | 3025 | DOCS | other | N/A | N/A | Release-version bookkeeping.
424da4d | 2021-10-10 | 3045 | FEATURE-internal | remote | SHOULD | NO | Adds a Healthy state to streams (AbstractStream.isHealthy / idle-restart) plus AsyncQueue timer tweaks, used by backoff reset logic (24.x). Dart remote/datastore/base_stream.dart; M-small, resilience improvement (unverified benefit).
ff414cb | 2021-10-13 | 3027 | FEATURE-public-API | remote | SHOULD | NO | AppCheck integration: FirebaseAppCheckTokenProvider, CredentialsProvider split into auth + app-check tokens, FirestoreCallCredentials adds x-firebase-appcheck header (24.0.0). Dart: remote/firestore_call_credentials.dart, auth/*, core/firestore_client.dart, datastore. Depends on firebase_core_vm support.
e1f356a | 2021-10-13 | 3053 | DOCS | other | N/A | N/A | Changelog for AppCheck.
7d40d4c | 2021-10-13 | 2788 | BUILD | other | N/A | N/A | gRPC version bump.
6a3e852 | 2021-10-14 | 3054 | DOCS | other | N/A | N/A | Release guide in changelog.
72deef8 | 2021-10-18 | 3001 | FEATURE-internal | index | COULD | NO | Writes index entries on backfill. Indexing only.
7b77281 | 2021-10-18 | 3017 | REFACTOR | index | COULD | NO | Uses the backend ordering/encoding implementation (IndexByteEncoder, TargetIndexMatcher). Indexing only.
430db4a | 2021-10-20 | 3032 | FEATURE-internal | index | COULD | NO | !=/NOT_IN filters in index-based queries (Target bounds, Values +23, Util). Requires 1ee3caa first; indexing only.
69fb475 | 2021-10-20 | 3037 | FEATURE-internal | local | COULD | NO | Integrates DocumentOverlay with the SDK: LocalDocumentsView computes docs via overlays, LocalStore writes overlays, DocumentOverlayCache (memory/SQLite). Overlays project (24.x); large behavioural rework of local view; optional.
1d493df | 2021-10-20 | 3062 | BUGFIX-crash | model | COULD | N/A | Fixes ConcurrentModificationException in ObjectValue overlays (clone/overlay map mutation during iteration). Applies to the Java ObjectValue overlay design (chunk 0); Dart ObjectValue is immutable ImmutableSortedMap, so not applicable unless the model is ported to Values/ObjectValue (unverified).
ddcee71 | 2021-10-20 | 2996 | REFACTOR | local | COULD | NO | Query Engine rework: IndexedQueryEngine reduced, SQLiteCollectionIndex removed. Indexing only.
1c21750 | 2021-10-21 | 3065 | FEATURE-internal | local | COULD | NO | Use document read time in backfiller; adds readTime to Document/MutableDocument and SQLiteRemoteDocumentCache columns (schema touch). Overlays/index only.
e7f5366 | 2021-10-28 | 3086 | DOCS | local | N/A | N/A | TODO comment only.
14eab32 | 2021-11-01 | 3095 | DOCS | other | N/A | N/A | Release bookkeeping (unverified).
a02a0c9 | 2021-11-03 | 3087 | FEATURE-internal | index | COULD | NO | User-scoped indices; component provider wiring. Indexing only.
79fc543 | 2021-11-03 | 3088 | FEATURE-internal | index | COULD | NO | Backfill oldest documents first. Indexing only.
4fefecc | 2021-11-03 | 3098 | PERF | index | COULD | NO | Memoize field indexes. Indexing only.
2cba82f | 2021-11-04 | 3094 | PERSISTENCE-schema | local | COULD | NO | Overlay data migration (SQLiteOverlayMigrationManager builds overlays from mutation queue at schema upgrade). Overlays only.
8068a9b | 2021-11-10 | 3116 | BUILD | other | N/A | N/A | Suppress Unicode warnings.
d481861 | 2021-11-12 | 3118 | FEATURE-internal | index | COULD | NO | Delete indexes (FieldIndex diff, Util.diffCollections). Indexing only.
710046b | 2021-11-19 | 3147 | REFACTOR | index | N/A | N/A | FieldIndex as AutoValue (Java only).
4e336c6 | 2021-11-19 | 3145 | FEATURE-internal | local | COULD | NO | Overlay API: filter overlays by batch id. Overlays only.
5bc0fef | 2021-11-19 | 3138 | PERSISTENCE-schema | index | COULD | NO | Removes shared index entries (SQL change). Indexing only.
d8fedfe | 2021-11-23 | 3153 | PERSISTENCE-schema | index | COULD | NO | Per-user index state schema/refactor. Indexing only.
486abaf | 2021-11-23 | 3132 | FEATURE-internal | index | COULD | NO | Update document index entries; schema edits. Indexing only.
a5f2f99 | 2021-11-24 | 3168 | REFACTOR | core | N/A | N/A | Removes unused core/IndexRange. Dart still has core/index_range.dart (dead; could be deleted).
ec2abdb | 2021-11-29 | 3169 | FEATURE-internal | index | COULD | NO | Random indexing changes (schema/backfill tweaks).
eec5f31 | 2021-11-29 | 3178 | PERSISTENCE-schema | local | COULD | NO | Overlay table keyed by collection_path + document_id. Overlays only.
d0048fd | 2021-11-30 | 3174 | FEATURE-internal | index | COULD | NO | Use DocumentKey as backfill tie breaker (FieldIndex.IndexOffset, RemoteDocumentCache API). Indexing only.
2b7812e | 2021-11-30 | 3195 | REFACTOR | local | N/A | N/A | Simplifies MemoryRemoteDocumentCache.
1c7dd64 | 2021-11-30 | 3194 | TEST | local | N/A | N/A | Test cleanup.
9466242 | 2021-12-03 | 3192 | PERF | local | COULD | NO | Use path length (collection_path/parent_path columns) to skip scanning subcollections in SQLiteRemoteDocumentCache; schema adds columns. Perf for getAll(collection). Dart local/sqlite/sqlite_remote_document_cache.dart + schema (needs migration).
7c9c133 | 2021-12-06 | 3112 | FEATURE-internal | local | COULD | NO | Release Overlay (turns overlays on by default, schema tweak, FieldMask change). Overlays; large behavioural change.
110b867 | 2021-12-08 | 3211 | REFACTOR | local | COULD | NO | Deletes overlay flag, old LocalDocumentsView path removed (-188 lines). Overlays.
1986969 | 2021-12-08 | 3193 | PERF | local | COULD | NO | Only fetch 50 documents per backfill. Indexing only.
dfa2231 | 2021-12-08 | 3201 | PERF | local | COULD | NO | Defer query evaluation in RemoteDocumentCache.getAll (filter callback replaces matcher; MutableDocument change). Overlay-era perf.
072ee4c | 2021-12-09 | 3208 | REFACTOR | local | COULD | NO | Merges DefaultQueryEngine and IndexedQueryEngine into one QueryEngine. Dart local/query_engine.dart/indexed_query_engine.dart/simple_query_engine.dart: restructure only if porting indexing.
7d86138 | 2021-12-09 | 3209 | FEATURE-internal | index | COULD | NO | Delete index entries for deleted docs (reference delegates). Indexing only.
70864ca | 2021-12-09 | 3225 | REFACTOR | local | N/A | N/A | Immutable Documents in MemoryRemoteDocumentCache (Java ownership model).
28e1a16 | 2021-12-09 | 3230 | REFACTOR | local | N/A | N/A | Deletes unused IndexCursor. Dart local/index_cursor.dart is likewise dead.
cae3743 | 2021-12-16 | 3237 | FEATURE-public-API | api | SHOULD | NO | Adds public Filter (Filter.equalTo/inArray/or/and...) and moves core Filter hierarchy to FieldFilter/CompositeFilter/Target; Query gets where(Filter) (24.x; Filter.or/and is 24.?, unverified). Dart: new api filter.dart, core/filter/*, query.dart, remote_serializer.dart, core/target. L (composite filters/disjunction handling come later, outside chunk).
a336497 | 2021-12-16 | 3247 | DOCS | index | N/A | N/A | Typo.
4884bcb | 2021-12-22 | 3257 | DOCS | api | N/A | N/A | SetOptions merge docs.
618b08c | 2022-01-04 | 3267 | BUGFIX-correctness | local | MUST | NO | Clears resume token and lastLimboFreeSnapshotVersion on existence filter mismatch (LocalStore.applyRemoteEvent uses remoteEvent.getTargetMismatches); removes the assert that a persisted target has a resume token. Dart already has targetMismatches in remote_event/watch_change_aggregator but local_store.dart does not use it and has no lastLimboFreeSnapshotVersion (needs the limbo-free resume-token feature from chunk 0, unverified). Data-correctness: stale cached targets after a filter mismatch. M.
1b8e6dd | 2022-01-11 | 3297 | PERSISTENCE-schema | local | COULD | NO | Adds collection_group column to overlay table. Overlays only.

## 4. Dependencies and ordering

- **NOT_EQUAL / NOT_IN**: 924aaa2 (protos) then 1ee3caa, 2d829f3 (null in NOT_IN array fix), 6879f54 (public). 8f27059 is the test fix. 430db4a adds them to index queries (indexing only, later). 25.1.4 (outside this chunk) fixes null handling in whereNotEqualTo/whereNotIn again: say so, do not guess its content; check chunk 3/4 for it.
- **Null/NaN validation removal**: 1dc2837 modifies code that 1ee3caa/6879f54 had edited (Query.validate*, FieldFilter.create). Port 1ee3caa, 6879f54 and 1dc2837 as one logical change; the final state has no null/NaN restrictions and only the NOT_IN/IN conflict rules.
- **Transforms**: df6a201 (proto) then d40e7f1 (main change) then 8655b90 (transformResults non-null), 4370f77 (drops baseDoc), 7055d2a (forward iteration in LocalSerializer), 48b41ff (test utils). b5d06cd and 9b67604 further simplify mutation code but are written against MutableDocument.
- **MutableDocument**: 979000c then 7be699f (cleanup), 9eb699a unrelated (bundle proto package). b5d06cd, 9b67604, 9815e45, 1c21750, dfa2231, 70864ca assume MutableDocument/Document split; they cannot be ported on the old MaybeDocument model without translation. 9b67604 (local delete keeps version) is the one behaviour change; compare spec tests first.
- **Bundles**: 2a3f7dc (protos) -> a809f4d (LoadBundleTask skeleton) -> 76597db (implementation) -> a030f2b (ByteBufferInputStream) -> 6ce7880 (main feature, depends on MutableDocument-era LocalStore APIs: applyBundledDocuments takes documents; with 979000c merged right after it, the order in this chunk is bundles first, MutableDocument second) -> 9eb699a (proto package rename; persisted proto, port the final package) -> ce1a078 (proto3 JSON limits) -> 76b029c (multi-byte fix). Port as one feature using the final state of each file.
- **Limbo / mismatch**: c9fefbe stands alone; 618b08c depends on limbo-free resume token support (lastLimboFreeSnapshotVersion), which belongs to an earlier chunk (unverified which one).
- **Overlays**: a692f63 (schema) -> 69fb475 (integrate) -> 2cba82f (migration) -> 4e336c6 -> eec5f31 -> 7c9c133 (release) -> 110b867 (remove flag) -> 1b8e6dd (collection_group column). The schema changed several times; port only the final table definition with one migration.
- **Indexing**: cd24435, b0f2783, ded7eda, 8d3f125, e41b233, 8122d55, da62838, c30a15a, e445aca, 0e40391, 45dd9ff, e8ac306, 6ac9d7f, 72deef8, 7b77281, 430db4a, ddcee71, 1c21750, a02a0c9, 79fc543, 4fefecc, d481861, 710046b, 5bc0fef, d8fedfe, 486abaf, ec2abdb, d0048fd, 1986969, 072ee4c, 7d86138 form one project. b7915e3 is reverted by b0e18f9; a5f2f99/a90d3c5/28e1a16 delete code that earlier commits added. Not needed unless local indexing is in scope.
- **Reverts/supersession inside the chunk**: b0e18f9 reverts b7915e3. 110b867 removes the flag introduced in 7c9c133/2cba82f. 072ee4c supersedes 13b12ca/ddcee71 engine split. cae3743 supersedes the old core/Filter. Across chunks: 1dc2837 supersedes validation added in earlier releases (chunk 0, unverified); 13b12ca renames IndexFreeQueryEngine which came from the 2019 sync (check Dart indexed_query_engine.dart against it).
