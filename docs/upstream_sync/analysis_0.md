# Upstream analysis, chunk 0 (2019-07-23 .. 2020-06-30, 141 commits after the sync point)

## 1. Summary of themes
1. Local store correctness around remote events: manufactured NoDocument(NONE) handling and the order/shape of the "should I persist this document" checks in `applyRemoteEvent` changed three times (a96334f, a1d363b, 5e06078). The Dart port still has the pre-sync logic (MUST).
2. Index-free queries (47def6d .. d8ff6a5): read-time column on remote documents (schema v9), `lastLimboFreeSnapshotVersion` in target data, `IndexFreeQueryEngine`, new QueryEngine signature. Pure performance (21.3.0) but brings schema migrations 9 and 10 (a regression in 21.1.0 forced a data-clearing v10). Dart is at schema v8 and has none of it.
3. Schema: v9 (read_time columns / drop limbo-free version), v10 (clear regression data), v11 (rewrite canonical ids; 'd644fd6'). Only needed if index-free and/or the Target split are ported.
4. Public API features: waitForPendingWrites + terminate (21.1.0), addSnapshotsInSyncListener (21.2.0), IN/ARRAY_CONTAINS_ANY public (21.3.0, already in Dart), limitToLast via Query/Target split (21.3.1), read-only transaction docs via VerifyMutation (21.4.0), useEmulator (21.6.0).
5. Transactions: TransactionRunner with exponential backoff (137fb97), retries parameter dropped (451a76b), VerifyMutation lifts "every read must be written" (ef38ef7; needs proto `Write.verify`, absent from lib/src/proto).
6. Sync engine: limbo-resolution throttling at 100 concurrent listens (ef455a6), mirror-query support (assert removed, caf6c3b), queriesByTarget/synthesized CURRENT (2827026), unionWith for remote keys (939be87).
7. Large FieldValue rewrite to protobuf-backed `Value` (baa0a89 .. fdf249d, Jan-Feb 2020, 21.4.1): internal memory/perf refactor of model/; one behavioural piece (5db2238 server-timestamp type order) is a correctness backport.
8. Remote/auth bug fixes: watch aggregator iterates only active targets (4491f0a), token refetch when invalidated (58e83e6), UNAVAILABLE backoff cap (fa9a8c7), inhibitBackoff on connectivity change (751684d), credential-change-before-init crash (0213e1e).
9. Lots of noise: Kotlin/ktx, javadoc, api.txt, version bumps, spec-test imports, Android connectivity monitor/SSL (ANDROID-ONLY).
10. Net: most of the 23 MUST/SHOULD rows are small and independent (S); the big-ticket items are index-free (L), limitToLast/Target split (L) and the FieldValue rewrite (L, optional).

## 2. Top items (most important for the Dart port)
1. a96334f + 5e06078 + a1d363b (local/local_store.dart applyRemoteEvent): remove manufactured NoDocument(NONE) from the cache first, then write only newer/equal-with-pending docs. MUST, S (port together, one function).
2. 5db2238 (model/value/server_timestamp_value.dart, field_value.dart type order): server timestamp gets its own type order; fixes local filter/equality against pending server timestamps. SHOULD, S-M.
3. ef455a6 (core/sync_engine.dart): limbo resolution throttling (max 100 active, FIFO queue, pump on removal). SHOULD, M. Released 21.4.3.
4. 0213e1e (core/firestore_client.dart): credential change before init crashes (late syncEngine); queue it behind initialization. SHOULD, S.
5. 58e83e6 (auth/firebase_auth_credentials_provider.dart): retry getToken when invalidated instead of failing the RPC with ABORTED. SHOULD, S.
6. 436c81d (core/user_data.dart): reject empty field-path segments in writes. SHOULD, S.
7. 3057375 (core/firestore_client.dart stopListening): do not throw when cancelling a listener after shutdown. SHOULD, S.
8. 4491f0a (remote/watch_change_aggregator.dart): `_getTargetIds` must return only active targets. SHOULD, S.
9. 137fb97 + 451a76b (core/sync_engine.dart, new TransactionRunner, TaskId): transaction retry with exponential backoff, fixed 5 retries. SHOULD, M. 21.1.0.
10. ef38ef7 (core/transaction.dart, model/mutation/verify_mutation.dart, remote_serializer.dart, regenerate protos with Write.verify): reads without writes in transactions. SHOULD, M. 21.4.0.
11. f096bbe + b131334 + 2189a5a (firestore.dart, core/sync_engine.dart, mutation queues): waitForPendingWrites and terminate. SHOULD, M. 21.1.0.
12. d0d0b1c + d27214f + b1172c9 (core/event_manager.dart, query_stream.dart, firestore.dart): addSnapshotsInSyncListener. SHOULD, M. 21.2.0.
13. 6d360f0 (core/user_data.dart, user_data_converter.dart): arrays allowed as IN query values. SHOULD, S.
14. 2827026 + f629ebe + d644fd6 + 939be87 + caf6c3b: limitToLast and the Query/Target split with schema v11. SHOULD, L (21.3.1). Biggest structural change; also introduces migration 11 (needs serializer inside SQLiteSchema).
15. 47def6d chain (index-free; schema v9/v10): PERF only, COULD, L. If taken, migrations 9, 10 and 11 must be ported together in order; do not skip numbers.
16. 0dbc799 (memory_remote_document_cache getByteSize double count) and 3c512bb (batch orphan GC): COULD, S.
17. 0eaca5e (useEmulator) and 751684d (inhibitBackoff on connectivity change): SHOULD/COULD, S.

## 3. Full table

| sha7 | date | PR# | category | area | relevance | in Dart? | what changed and why it matters for the port |
|---|---|---|---|---|---|---|---|
| c6e7849 | 2019-07-24 | #649 | DOCS | api | N/A | N/A | Javadoc-only edits. |
| 436c81d | 2019-07-25 | #643 | BUGFIX-correctness | core | SHOULD | NO | UserData ParseContext.validatePathSegment now rejects empty path segments ("Document fields must not be empty") and does the reserved-name check with startsWith/endsWith("__"). Dart core/user_data.dart `_validatePathSegment` only does the regex check, so empty field names pass. (fixes android #632) |
| 4751124 | 2019-07-25 | #663 | TEST | other | N/A | N/A | Test change only (waitFor on set). |
| 69f29d4 | 2019-07-29 | #666 | ANDROID-ONLY | api | N/A | N/A | Merge of Kotlin nullability annotations (@Nullable/@NonNull); Dart already uses null safety. |
| 8f00bad | 2019-07-30 | #650 | TEST | other | N/A | N/A | Removes unused test helpers. |
| 484371e | 2019-07-30 | #670 | DOCS | api | N/A | N/A | Javadoc fixes. |
| 0b13b10 | 2019-07-31 | #674 | PERSISTENCE-schema | local | N/A | N/A | Reverts an earlier (pre-sync) commit that added schema v9 `update_time_*` columns to remote_documents; schema returns to v8. Superseded by the read_time columns of 47def6d; Dart is at v8 so no action by itself. |
| bfc895f | 2019-07-31 | #675 | TEST | other | N/A | N/A | Imports JS spec-test JSON. |
| 2e416b0 | 2019-08-01 | #677 | DOCS | other | N/A | N/A | Release notes for 21.0.0. |
| 5dc3bce | 2019-08-01 | #678 | ANDROID-ONLY | remote | N/A | N/A | Removes GrpcCallProvider.overrideChannelBuilder (reverted by 534e5b3). |
| 33d656e | 2019-08-02 | #682 | REFACTOR | core | COULD | NO | Message text of the FieldFilter assert for key IN filters changed ("...but the value was not an ArrayValue"). Dart core/filter/field_filter.dart still has the old text. |
| 5669699 | 2019-08-02 | #683 | TEST | other | N/A | N/A | Spec test for limit query init. |
| f096bbe | 2019-08-08 | #689 | FEATURE-public-API | core | SHOULD | NO | waitForPendingWrites(): SyncEngine.registerPendingWritesTask/resolvePendingWriteTasks/failOutstandingPendingWritesAwaitingTasks (fails with CANCELLED on user change), LocalStore/MutationQueue.getHighestUnacknowledgedBatchId (SQL `SELECT IFNULL(MAX(batch_id),-1) ...`, memory: queue empty ? UNKNOWN : nextBatchId-1), RemoteStore.canUseNetwork public. Dart: core/sync_engine.dart, local/local_store.dart, local/persistance/mutation_queue.dart + sqlite/memory queues, firestore.dart. Released in 21.1.0. |
| a96334f | 2019-08-09 | #695 | BUGFIX-correctness | local | MUST | NO | applyRemoteEvent: a NoDocument with SnapshotVersion.NONE (manufactured by failed limbo resolution) must REMOVE the doc from the remote cache instead of being written/persisted. Dart local/local_store.dart still uses the old `doc.version == SnapshotVersion.none` branch that adds it. Port together with 5e06078 and a1d363b. |
| 1651017 | 2019-08-09 | #696 | TEST | other | N/A | N/A | Spec test import. |
| 3057375 | 2019-08-12 | #701 | BUGFIX-crash | core | SHOULD | NO | Listener cancellation after shutdown must not throw: FirestoreClient.stopListening no longer calls verifyNotShutdown; EventManager.removeQueryListener returns void; SyncEngine.handleOnlineStateChange asserts callback. Dart core/firestore_client.dart stopListening still calls _verifyNotShutdown (cancel of a QueryStream after shutdown throws). |
| 137fb97 | 2019-08-13 | #698 | FEATURE-internal | core | SHOULD | NO | TransactionRunner: retries transactions with exponential backoff (RETRY_COUNT=5, TimerId.RETRY_TRANSACTION), replaces recursive retry in SyncEngine.transaction. 21.1.0 "Transactions now perform exponential backoff before retrying". Dart core/sync_engine.dart transaction() retries immediately with a caller-supplied count; needs a TransactionRunner + a new TaskId. |
| eab54ce | 2019-08-14 | #671 | BUILD | other | N/A | N/A | metalava gradle tasks. |
| 997736d | 2019-08-15 | #705 | BUGFIX-crash | core | COULD | YES | Early exit in FirestoreClient.shutdown if already shut down; Dart core/firestore_client.dart shutdown() already has the guard. |
| 65dcc2d | 2019-08-16 | #710 | TEST | util | N/A | N/A | AsyncQueue timerIdsToSkip handling (test infrastructure). |
| 5e35f4a | 2019-08-21 | #721 | TEST | other | N/A | N/A | Test cleanup. |
| bcc04b6 | 2019-08-21 | #724 | DOCS | api | N/A | N/A | api.txt update. |
| a1d363b | 2019-08-21 | #720 | BUGFIX-correctness | local | SHOULD | NO | applyRemoteEvent: drop the `authoritativeUpdates` set; only write a doc when remote version > existing version, or == and existing has pending writes (avoids re-persisting unchanged docs and fixes stale-overwrite semantics). Resume-token persistence assert is now a hardAssert. Dart local/local_store.dart still uses the authoritativeUpdates/`>=` logic. Final shape is visible in later LocalStore (existingDoc==null // v>existing // (v==existing && existing.hasPendingWrites)). Port with a96334f/5e06078. |
| 2189a5a | 2019-08-26 | #732 | FEATURE-public-API | api | SHOULD | PARTIAL | FirebaseFirestore.shutdown() renamed to public terminate() (verifyNotTerminated, isTerminated). Dart firestore.dart already exposes shutdown(); rename/alias for parity (21.1.0). |
| b131334 | 2019-08-26 | #738 | FEATURE-public-API | api | SHOULD | NO | Makes waitForPendingWrites() public in FirebaseFirestore (21.1.0). Depends on f096bbe. |
| 4744bbb | 2019-08-27 | #739 | DOCS | api | N/A | N/A | Javadoc link fixes. |
| 47def6d | 2019-08-27 | #727 | PERSISTENCE-schema | local | COULD | NO | Index-free queries (code, still disabled): IndexFreeQueryEngine, QueryEngine takes QueryData+remote keys, RemoteDocumentCache.add(doc, readTime)/getAllDocumentsMatchingQuery(query, sinceReadTime), SQLite `read_time_seconds/nanos` columns (schema v9), QueryData.lastLimboFreeSnapshotVersion (serialized in Target proto), LocalStore marks limbo-free version from synced LocalViewChanges, Query.matchesAllDocuments(). Pure PERF but changes the persisted schema. Dart has only SimpleQueryEngine/IndexedQueryEngine. Size L; chain: 47def6d, 934a88d, 2a2e789, 27c9f93, 0778d94, 6418e58, a744cb7, d8ff6a5 (+ migration 10 and 11 below). |
| c8544b1 | 2019-08-29 | #746 | BUILD | other | N/A | N/A | SDK version bump. |
| c0c4337 | 2019-08-29 | #751 | DOCS | api | N/A | N/A | api.txt. |
| a7cee8e | 2019-08-30 | #754 | TEST | util | N/A | N/A | Test runner annotation. |
| be0146a | 2019-08-30 | #755 | BUILD | other | N/A | N/A | Version bump. |
| 534e5b3 | 2019-08-30 | #756 | ANDROID-ONLY | remote | N/A | N/A | Reverts 5dc3bce (overrideChannelBuilder stays). |
| 0dbc799 | 2019-09-04 | #764 | BUGFIX-correctness | local | COULD | NO | MemoryRemoteDocumentCache.getByteSize no longer counts the key size separately (the serialized doc already contains the key) - double counting skewed memory LRU GC. Dart local/memory/memory_remote_document_cache.dart getByteSize still adds _getKeySize + encoded size. |
| 8003a69 | 2019-09-05 | #767 | PERF | local | N/A | N/A | releaseQuery no longer re-persists QueryData via a separate path; tied to index-free (limbo-free snapshot version). Only relevant if 47def6d is ported. |
| 934a88d | 2019-09-05 | #771 | REFACTOR | core | N/A | N/A | Removes the `synced` flag that 47def6d added to ViewSnapshot/LocalViewChanges (derived from isFromCache). Part of the index-free chain. |
| 7c94211 | 2019-09-07 | #776 | REFACTOR | local | N/A | N/A | Debug logging in IndexFreeQueryEngine. |
| 7f9d4ac | 2019-09-10 | #783 | DOCS | other | N/A | N/A | Changelog backport. |
| b61e695 | 2019-09-10 | #779 | TEST | other | N/A | N/A | Port clearPersistence spec tests. |
| 9f201a5 | 2019-09-10 | #785 | TEST | other | N/A | N/A | Test fix. |
| d0d0b1c | 2019-09-10 | #778 | FEATURE-public-API | core | SHOULD | NO | addSnapshotsInSyncListener: EventManager keeps a set of in-sync listeners and raises them whenever any QueryListener.onViewSnapshot/onOnlineStateChanged raised an event (these now return bool); FirestoreClient add/remove. Dart core/event_manager.dart, core/query_stream.dart, firestore.dart. Released 21.2.0 (made public by d27214f; remove-on-queue fix b1172c9). |
| 8a7b33c | 2019-09-12 | #791 | TEST | other | N/A | N/A | Integration test fix. |
| a011927 | 2019-09-12 | #790 | TEST | local | N/A | N/A | Index-free test simplification. |
| 6418e58 | 2019-09-13 | #800 | BUGFIX-crash | local | N/A | N/A | Removes the "read time of zero" hard asserts from the remote document caches (v21.1.1 regression: crash "Cannot add document to the RemoteDocumentCache with a read time of zero"). Only relevant with index-free; migration to v10 (a744cb7/d8ff6a5 chain) clears data affected by that regression. |
| 5e06078 | 2019-09-13 | #802 | BUGFIX-correctness | local | MUST | NO | applyRemoteEvent: check the manufactured NoDocument(NONE) case FIRST so rejected limbo resolutions can never add documents to the cache (previously `existingDoc == null` branch won). Dart local/local_store.dart has the wrong order. Port with a96334f. |
| 3c512bb | 2019-09-16 | #803 | PERF | local | COULD | NO | SQLiteLruReferenceDelegate.removeOrphanedDocuments runs in batches of 100 (`LIMIT ?` loop) instead of loading all rows (Android CursorWindow/memory). Dart local/sqlite/sqlite_lru_reference_delegate.dart loads all rows at once; fine functionally, add batching for large caches. |
| a4fcac3 | 2019-09-17 | #810 | TEST | other | N/A | N/A | Spec test function rename. |
| 0778d94 | 2019-09-18 | #816 | PERF | local | COULD | NO | IndexFreeQueryEngine updated from Web: full scan when query matches all docs or no limbo-free version; needsRefill logic for limit queries (compares last doc in limit with limbo-free version). Index-free chain. |
| 5da580d | 2019-09-18 | #820 | REFACTOR | local | N/A | N/A | Removes StatsCollector plumbing from production Memory/SQLite mutation queue, persistence and remote document cache (kept for tests). Dart still threads StatsCollector; no behaviour change. |
| 2a2e789 | 2019-09-19 | #822 | REFACTOR | local | N/A | N/A | QueryEngine.getDocumentsMatchingQuery(query, queryData, remoteKeys) + QueryResult class; LocalStore.executeQuery(query, queryData, remoteKeys). Index-free chain; Dart local/query_engine.dart has the old signature. |
| 27c9f93 | 2019-09-19 | #823 | PERF | local | COULD | NO | LocalStore keeps `targetIdByQuery` map (queryDataByTarget renamed) so allocate/getQueryData/releaseQuery use the in-memory view of target data (needed so resume tokens/limbo-free versions are not stale). Dart local/local_store.dart `_targetIds` only (no query->target map). |
| 18e37a5 | 2019-09-20 | #832 | TEST | other | N/A | N/A | Spec test rename. |
| 76ffd96 | 2019-09-20 | #786 | PROTOCOL-wire | remote | N/A | N/A | Adds heartbeat / user-agent gRPC metadata via firebase-common provider (21.7.1 "new internal HTTP headers"). Android component wiring; Dart has no equivalent (optional x-firebase-client headers). |
| 1f15bd6 | 2019-09-30 | #861 | TEST | local | N/A | N/A | Test for NoDocument assert. |
| d27214f | 2019-09-30 | #859 | FEATURE-public-API | api | SHOULD | NO | Makes addSnapshotsInSyncListener public (21.2.0). Depends on d0d0b1c. |
| a744cb7 | 2019-10-01 | #869 | PERSISTENCE-schema | local | COULD | NO | Schema v9 migration: if remote_documents already has read_time columns (downgrade/upgrade) run dropLastLimboFreeSnapshotVersion (rewrites every `targets.target_proto`). Index-free chain; needs SQLiteSchema to take a serializer-free proto rewrite. |
| 451a76b | 2019-10-02 | #874 | FEATURE-public-API | api | COULD | NO | Removes the unused `retries` parameter of runTransaction (runner fixes retries at 5). Dart firestore.dart/core/firestore_client.dart still pass retries. Pairs with 137fb97. |
| 1e5bddd | 2019-10-07 | #882 | BUILD | other | N/A | N/A | Release version bump. |
| e1fc161 | 2019-10-14 | #903 | BUGFIX-crash | model | N/A | N/A | Document.fieldValueCache read race between threads. Dart is single-isolate; no change needed. |
| 5171cfa | 2019-10-14 | #912 | DOCS | other | N/A | N/A | Changelog entry. |
| 1a3eb7c | 2019-10-15 | #917 | ANDROID-ONLY | remote | N/A | N/A | SSL handshake/cipher detection (isMissingSslCiphers); Android TLS specific. |
| 0213e1e | 2019-10-15 | #919 | BUGFIX-crash | core | SHOULD | NO | Credential change events arriving before init finished crashed with NPE: handler now runs on the async queue with hardAssert(syncEngine != null). Dart core/firestore_client.dart handler calls `client.syncEngine.handleCredentialChange` directly while syncEngine is `late` (LateInitializationError if a 2nd credential event beats _initialize). |
| 2e2d256 | 2019-10-17 | #923 | TEST | local | N/A | N/A | Typo in unit test. |
| 0a6cd09 | 2019-10-17 | #927 | DOCS | other | N/A | N/A | Release notes fix. |
| 7ecb3a9 | 2019-10-22 | #849 | ANDROID-ONLY | api | N/A | N/A | Kotlin ktx settings builder. |
| 8b83a78 | 2019-10-24 | #938 | ANDROID-ONLY | api | N/A | N/A | Nullability annotation on getHost. |
| 405d287 | 2019-10-29 | #939 | FEATURE-public-API | api | SHOULD | YES | whereIn/whereArrayContainsAny made public (21.3.0). Dart query.dart already exposes whereIn/whereArrayContainsAny. |
| 4e3a240 | 2019-10-29 | #943 | BUILD | other | N/A | N/A | Release info. |
| d8ff6a5 | 2019-10-30 | #730 | FEATURE-internal | local | COULD | NO | Enables IndexFreeQueryEngine in FirestoreClient and bumps schema VERSION to 10 (migration `fromVersion==9 && toVersion>=10`: dropLastLimboFreeSnapshotVersion to clear data hit by the 21.1.0 regression). Index-free chain (21.3.0 perf). |
| 10eb615 | 2019-10-31 | #955 | BUILD | other | N/A | N/A | Version bump. |
| 6d360f0 | 2019-11-11 | #970 | BUGFIX-correctness | core | SHOULD | NO | IN queries may contain arrays as values: new UserData.Source.ArrayArgument, UserDataConverter.parseQueryValue(input, allowArrays=op==IN). Dart core/user_data.dart / user_data_converter.dart rejects nested arrays in whereIn values. (unverified end-to-end) |
| 3868ace | 2019-11-14 | #975 | BUILD | other | N/A | N/A | Version bump. |
| 2827026 | 2019-11-22 | #994 | FEATURE-public-API | core | SHOULD | NO | limitToLast + Query/Target split (3 PRs squashed): new core/Target (query without limitToLast/direction), SyncEngine keeps queriesByTarget (many queries per target, mirror queries, synthesized CURRENT change), View handles limitToLast (firstDocInLimit), LocalStore/RemoteStore/QueryCache work with Target, QueryData gets target (LocalSerializer/RemoteSerializer encodeTarget), RemoteStore.listen ignores duplicate target ids, new canonical id format. Dart: core/query.dart, core/view.dart, core/sync_engine.dart, local/*, remote_serializer.dart, query.dart. 21.3.1. Requires schema v11 (d644fd6) and drops hardAssert in caf6c3b. Size L. |
| 8015fa6 | 2019-12-03 | #1024 | DOCS | api | N/A | N/A | Javadoc fixes. |
| 93e59eb | 2019-12-09 | #1041 | DOCS | api | N/A | N/A | api files. |
| 6c72014 | 2019-12-10 | #1049 | BUILD | other | N/A | N/A | metalava task. |
| f629ebe | 2020-01-02 | #1087 | REFACTOR | local | COULD | NO | Renames QueryData->TargetData, QueryCache->TargetCache across local/core/remote. No behaviour change; Dart names (QueryData, QueryCache) differ - only needed for name parity before porting later commits that mention TargetData. |
| fa9a8c7 | 2020-01-08 | #1045 | BUGFIX-correctness | remote | COULD | NO | AbstractStream: on UNAVAILABLE caused by UnknownHost/ConnectException cap backoff at 10s (setTemporaryMaxDelay) - 21.4.0 "recovers more quickly when connections suffering packet loss"; rest is Android gRPC channel connectivity monitor (ANDROID-ONLY). Dart remote/datastore/base_stream.dart / exponential_backoff.dart have no temporary max delay. |
| ef38ef7 | 2020-01-09 | #1107 | PROTOCOL-wire | core | SHOULD | NO | VerifyMutation: Transaction.commit adds a VerifyMutation(key, precondition) for documents read but not written (no more "Every document read in a transaction must also be written"); RemoteSerializer encodes Write.verify. Dart core/transaction.dart still errors; needs model/mutation/verify_mutation.dart, remote_serializer.dart encode/decode, and the proto Write.verify field (not present in lib/src/proto - regenerate). 21.4.0. |
| 1c606ec | 2020-01-16 | #1134 | DOCS | other | N/A | N/A | Version info. |
| 0711e04 | 2020-01-17 | #1142 | DOCS | other | N/A | N/A | Version info. |
| 3ef1c41 | 2020-01-22 | #1146 | DOCS | other | N/A | N/A | Changelog. |
| baa0a89 | 2020-01-23 | #1150 | REFACTOR | model | COULD | NO | ObjectValue builder; first step of the proto-backed FieldValue rewrite (21.4.1 memory/perf). Dart model/value/object_value.dart is the old tree type. |
| e7ac8b9 | 2020-01-24 | #1157 | REFACTOR | model | COULD | NO | Proto-based equality/comparison (ProtoValues). Step of FieldValue rewrite; also SQLiteMutationQueue small tweak. |
| 94844bb | 2020-01-24 | #1158 | TEST | model | N/A | N/A | Test utilities for Value types. |
| 419c8fd | 2020-01-24 | #1153 | BUILD | other | N/A | N/A | Components update. |
| d9f24e5 | 2020-01-24 | #1161 | BUILD | other | N/A | N/A | Firestore version update. |
| 7f8134b | 2020-01-27 | #1163 | DOCS | other | N/A | N/A | Docs. |
| 9354294 | 2020-01-29 | #1156 | REFACTOR | model | COULD | NO | Protobuf-backed FieldValues (first part). |
| 3893dcb | 2020-01-30 | #1179 | REFACTOR | model | COULD | NO | Simplify Document (ObjectValue + proto) and its (de)serialization in LocalSerializer/RemoteSerializer. |
| 7178184 | 2020-01-31 | #1171 | TEST | other | N/A | N/A | Canonical id stability test. |
| 1548002 | 2020-01-31 | #1177 | REFACTOR | api | COULD | NO | UserDataConverter split into UserDataReader/UserDataWriter (DocumentSnapshot value conversion moves to UserDataWriter). |
| d644fd6 | 2020-01-31 | #1182 | PERSISTENCE-schema | local | COULD | NO | Schema v11: rewriteCanonicalIds - re-derive `targets.canonical_id` from Target.getCanonicalId() for all rows (needs LocalSerializer in SQLiteSchema). Needed only when the canonical id format changes (2827026). If Dart ports Target/limitToLast it MUST add this migration (and keep migrations 9 and 10 numbering). |
| c6b9d88 | 2020-01-31 | - | MERGEBACK | other | N/A | N/A | Merge master into feature branch. |
| e4b4850 | 2020-02-01 | #1178 | REFACTOR | model | COULD | NO | Explicit FieldValue canonicalization (ProtoValues). |
| 5acd873 | 2020-02-03 | #1189 | DOCS | other | N/A | N/A | Typo. |
| af7c37d | 2020-02-04 | #1197 | TEST | other | N/A | N/A | Spec test protos. |
| d1a75a9 | 2020-02-04 | - | MERGEBACK | other | N/A | N/A | Merge. |
| b89694a | 2020-02-04 | #1188 | TEST | other | N/A | N/A | Flaky test fix. |
| 332d41b | 2020-02-04 | - | MERGEBACK | other | N/A | N/A | Merge. |
| f988c70 | 2020-02-06 | #1184 | REFACTOR | model | COULD | NO | Protobuf-backed FieldValues (second part), filters/bounds use Value. |
| 91b40a5 | 2020-02-06 | #1205 | REFACTOR | model | COULD | NO | Transforms (array union/remove, numeric increment, server timestamp) operate on proto Values. |
| 32e1e92 | 2020-02-06 | #1206 | REFACTOR | model | COULD | NO | Drops Array/Reference/Number/Integer/DoubleValue classes. |
| 3c6d8d1 | 2020-02-06 | #1207 | REFACTOR | model | COULD | NO | Drops remaining primitive FieldValue types. |
| 7b0925f | 2020-02-06 | #1208 | REFACTOR | model | COULD | NO | FieldValue becomes test-only. |
| bda327b | 2020-02-07 | #1216 | TEST | model | N/A | N/A | Drops FieldValue from tests. |
| 9775f67 | 2020-02-07 | #1219 | DOCS | other | N/A | N/A | Changelog for FieldValue change. |
| 59deddf | 2020-02-07 | #1221 | TEST | other | N/A | N/A | Android Studio unit test running. |
| 4864c6a | 2020-02-07 | #1222 | REFACTOR | model | COULD | NO | Server timestamp helpers static (ServerTimestamps). |
| fdf249d | 2020-02-07 | #1225 | REFACTOR | model | COULD | NO | Removes value package; ProtoValues renamed (later Values). |
| 1e43a8e | 2020-02-07 | - | MERGEBACK | other | N/A | N/A | Merge of the rewritefieldvalue branch. |
| 939be87 | 2020-02-13 | #1241 | PERF | core | COULD | NO | ImmutableSortedSet.unionWith; SyncEngine.getRemoteKeysForTarget unions synced docs of all queries on a target. Dart core/sync_engine.dart has a single query per target (and an outdated TODO); needed with 2827026. |
| ece89bc | 2020-02-16 | #1250 | BUGFIX-crash | util | COULD | NO | Util random for auto ids switched to SecureRandom. Dart util/util.dart `final Random rand = Random()`; use Random.secure() for document auto-ids. |
| a4edd56 | 2020-02-20 | #1262 | BUILD | other | N/A | N/A | Version bump. |
| 7e1baae | 2020-02-21 | #1174 | REFACTOR | other | N/A | N/A | Lint fixes. |
| 43248ca | 2020-02-21 | #1260 | REFACTOR | other | N/A | N/A | Remove Guava usage (21.4.2). |
| 8fbdcbb | 2020-02-24 | #1271 | TEST | other | N/A | N/A | Test rename. |
| 8254357 | 2020-02-24 | #1274 | REFACTOR | model | N/A | N/A | Internal rename (compareNumbers). |
| edcb9bd | 2020-03-05 | #1317 | BUILD | other | N/A | N/A | Version info. |
| f79cf6b | 2020-03-19 | #1367 | TEST | other | N/A | N/A | Spec test filter flag. |
| 6251d0c | 2020-03-19 | #1373 | TEST | other | N/A | N/A | Spec test logging. |
| 1d836a1 | 2020-03-19 | #1375 | ANDROID-ONLY | remote | N/A | N/A | gRPC connectivity callback runs on the async queue. |
| 5db2238 | 2020-03-24 | #1379 | BUGFIX-correctness | model | SHOULD | NO | Server timestamp gets its own type order (4, between timestamp and string; string..map shifted by 1) in Values.typeOrder/equals/compare, so a pending server timestamp no longer matches/equals real Timestamp values and cannot satisfy timestamp filters locally. Dart model/value/server_timestamp_value.dart still reports typeOrderTimestamp and compares inside timestamp compare. |
| f0bda45 | 2020-04-03 | #1401 | TEST | other | N/A | N/A | Spec tests import. |
| 4491f0a | 2020-04-03 | #1422 | BUGFIX-correctness | remote | SHOULD | NO | WatchChangeAggregator.getTargetIds: when a TargetChange has no explicit targets, iterate only ACTIVE targets (previously every entry in targetStates incl. removed ones). Dart remote/watch_change_aggregator.dart `_getTargetIds` returns `_targetStates.keys`. |
| ef455a6 | 2020-04-06 | #1374 | BUGFIX-correctness | core | SHOULD | NO | Limbo resolution throttling: SyncEngine queues limbo listens (`enqueuedLimboResolutions`) and keeps at most 100 active (`pumpEnqueuedLimboResolutions`); maps renamed active*; getCurrentLimboDocuments -> getActiveLimboDocumentResolutions. 21.4.3 "limits the number of concurrent document lookups". Dart core/sync_engine.dart starts a listen for every limbo doc. |
| 98419c4 | 2020-04-09 | #1444 | TEST | other | N/A | N/A | Flaky transaction tests. |
| caf6c3b | 2020-04-10 | #1438 | BUGFIX-crash | core | SHOULD | NO | Removes hardAssert(view.getLimboDocuments().size()==0) in initializeViewAndComputeSnapshot (no longer holds with mirror queries) and instead tracks limbo changes via updateTrackedLimboDocuments. Dart core/sync_engine.dart:143 still has the assert; needed once limitToLast/mirror queries (2827026) exist. |
| ba41e04 | 2020-04-15 | #1442 | DOCS | other | N/A | N/A | TODO comment. |
| 41ad413 | 2020-04-15 | #1469 | ANDROID-ONLY | remote | N/A | N/A | Robolectric / API 29 connectivity monitor. |
| 8598921 | 2020-04-24 | #1498 | REFACTOR | core | COULD | NO | ComponentProvider/MemoryComponentProvider/SQLiteComponentProvider: FirestoreClient wiring extracted into component providers (groundwork for multi-tab/bundles later). Dart core/firestore_client.dart _initialize is the equivalent; optional. |
| cf02ffc | 2020-05-11 | #1544 | DOCS | other | N/A | N/A | Version info. |
| 41505a7 | 2020-05-11 | #1547 | TEST | other | N/A | N/A | Increment-with-merge test. |
| 08ecaa8 | 2020-05-13 | #1558 | TEST | other | N/A | N/A | Test annotations/ErrorProne. |
| 1a13ce2 | 2020-05-15 | #1561 | REFACTOR | remote | COULD | NO | Log level debug->warn when a stream closes due to an error. Dart remote/datastore/base_stream.dart logs at debug. |
| b1172c9 | 2020-05-19 | #1572 | BUGFIX-correctness | core | SHOULD | N/A | removeSnapshotsInSyncListener runs on the async queue (race fix). Part of d0d0b1c feature; port together. |
| 58e83e6 | 2020-06-08 | #1628 | BUGFIX-correctness | other | SHOULD | NO | FirebaseAuthCredentialsProvider.getToken: when the token changed during the request, retry getToken() instead of failing with ABORTED. Dart auth/firebase_auth_credentials_provider.dart still throws FirestoreError aborted ('getToken aborted due to token change'), failing the first RPC after a sign-in. |
| 037282f | 2020-06-23 | #1534 | BUILD | remote | N/A | N/A | Migrates to protolite runtime (Android). |
| 0eaca5e | 2020-06-24 | #1690 | FEATURE-public-API | api | SHOULD | UNKNOWN | useEmulator(host, port) and unified emulator settings (21.6.0). Dart exposes host/ssl settings; check firestore.dart/FirestoreSettings for an equivalent convenience (no `useEmulator` found). |
| 751684d | 2020-06-24 | #1706 | BUGFIX-correctness | remote | COULD | PARTIAL | RemoteStore network-connectivity restart now calls writeStream/watchStream.inhibitBackoff() so reconnect after connectivity change is immediate (21.6.0). Dart base_stream.dart has inhibitBackoff() but remote_store.dart `_restartNetwork`/_networkEvents don't call it. |
| 4748715 | 2020-06-24 | #1712 | FEATURE-public-API | api | N/A | N/A | Un-hide EmulatorSettings; reverted by db66120 (net no-op). |
| db66120 | 2020-06-30 | #1712 | MERGEBACK | api | N/A | N/A | Revert of 4748715. |

## 4. Dependencies and ordering
- applyRemoteEvent trio: a96334f -> a1d363b -> 5e06078. a96334f introduces the "NoDocument(NONE) => remove" branch after the version checks; a1d363b rewrites the version condition and drops `authoritativeUpdates`; 5e06078 moves the removal branch to the top. Port the end state (see LocalStore at db66120: removal first; else existing==null || v>existing || (v==existing && existing.hasPendingWrites)).
- Index-free chain: 47def6d (code + schema v9 read_time) -> 934a88d (drop synced flag) -> 2a2e789 (QueryEngine/QueryResult API) -> 27c9f93 (query->target map) -> 0778d94 (engine update) -> 6418e58 (removes assert; 21.1.1 regression) -> a744cb7 (v9 migration drops limbo-free version when downgrading/upgrading) -> d8ff6a5 (enable; VERSION 10 migration) -> d644fd6 (v11 canonical ids, only needed with 2827026). 8003a69 (don't double save QueryData) and 5da580d (stats collector removal) support this chain. 0b13b10 reverts an earlier pre-sync v9 attempt (update_time); 47def6d redefines v9 with read_time columns, so the Dart port should not use update_time.
- Query/Target split: 2827026 (squash of three PRs) needs f629ebe (renames) before it, d644fd6 (schema 11) with it, caf6c3b (assert removal), 939be87 (unionWith for getRemoteKeysForTarget). Later chunks may change limitToLast/mirror query details (not checked here).
- waitForPendingWrites: f096bbe (implementation) -> b131334 (public); terminate (2189a5a) is independent but was released together (21.1.0).
- Snapshots-in-sync: d0d0b1c -> d27214f (public) and b1172c9 (remove on queue); QueryStream.onViewSnapshot/onOnlineStateChanged must return bool.
- Transactions: 137fb97 (runner + backoff) with 451a76b (drop retries param); ef38ef7 (VerifyMutation) is independent but needs regenerated protos.
- FieldValue rewrite (baa0a89, e7ac8b9, 9354294, 3893dcb, f988c70, 91b40a5, 32e1e92, 3c6d8d1, 7b0925f, fdf249d, 4864c6a, 8254357, 1548002, e4b4850; merged by 1e43a8e): one feature, port as a unit or not at all. 5db2238 (server timestamp type order, March 2020) can be ported on top of either representation.
- Net-zero pairs: 5dc3bce/534e5b3 (overrideChannelBuilder removed then restored), 4748715/db66120 (EmulatorSettings un-hidden then reverted).
- Cross-chunk: 0eaca5e/751684d (useEmulator, backoff) belong to 21.6.0; later chunks may extend emulator handling and index-free (e.g. further LocalStore/engine changes) - not analysed here (unverified).
