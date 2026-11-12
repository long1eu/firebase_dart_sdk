# Analysis of chunk 3 (142 commits, 2023-02-15 to 2024-04-24)

Method: subject triage of all 142 commits, `git show --numstat` on `src/main` for all, diffs read for the non-trivial logic changes (46e5549, c989076, 2d2e008, a014114, 42a6951, 080e1fc, f314ff7, 5ea5bd0, c83d5e5, abfa774, 24197b5). Everything in the Dart port was checked by grep under `cloud_firestore_vm/lib/src/firebase/firestore`. Release versions are from `runs/android_firestore_changelog.md`; where the layout is ambiguous I say so. Statements about code I did not open are marked (unverified).

## 1. Summary
1. Chunk 3 spans Android Firestore 24.5.0 to ~25.0.0. It is dominated by features that need groundwork from chunks 0-2 (overlays, field indexes, composite filters) which the Dart port lacks entirely.
2. OR queries become public (8d99ce0). The Dart port has no CompositeFilter classes and no DNF logic (only an AND constant in `remote_serializer.dart`).
3. Aggregation queries: Sum/Avg protos (a4a9625), the SDK implementation (26de539), server aliases (abfa774), public API (ffdee32). Dart has no aggregation support at all (no `RunAggregationQuery`).
4. Bloom filter / `expected_count` resume optimisation (c83d5e5, with test hooks 800d290, 965ac2f, 3d4cfed) is a single large wire-level feature; dependent fix a014114 (limbo handling during reset).
5. Multiple inequality filters (c5a894c, 25.0.0) change core Query assumptions; the proto needs nothing new.
6. Persistent cache indexing (a5e7062, c5cd536, 6349a09, 2d2e008): needs the whole field-index stack, large and optional.
7. Cache config API (24197b5) and memory LRU GC (9a9a02b): mostly settings plumbing; Dart already has memory LRU.
8. Correctness fixes worth taking alone: SQLite LRU orphan-removal infinite loop (42a6951), DocumentSnapshot equality (080e1fc), nested server timestamp growth (c989076).
9. Protocol/production concern: App Check provider (3e5cd47); Dart sends no App Check header.
10. About 100 commits are tests, docs, build, release, Kotlin/Android-only or mergebacks (no port value).

## 2. Top items (size is for the Dart port)
1. **42a6951** (MUST, S): SQLite LRU `removeOrphanedDocuments` could loop forever; Dart `sqlite_lru_reference_delegate.dart:149` has the same unpaged query.
2. **3e5cd47** (MUST, M): App Check token provider and header; Dart sends none (`channel_options_provider.dart`). Production projects with enforcement reject the client.
3. **c83d5e5** (SHOULD, L): bloom filter + `expected_count` (protos `Target.expected_count`, `ExistenceFilter.unchanged_names`, `bloom_filter.proto` from the gap analysis); cuts reads on resume, also needs spec tests 84894be to verify.
4. **a014114** (SHOULD, S): avoid limbo resolution while a target is pending reset; depends on c83d5e5.
5. **c989076** (SHOULD, S): stop nesting server-timestamp previous values (stack overflow / unbounded growth).
6. **080e1fc** (SHOULD, S): DocumentSnapshot `==` compares data, not internal document state (`document_snapshot.dart:356`).
7. **26de539 + abfa774 + ffdee32 + a4a9625** (SHOULD, M): count/sum/avg aggregation query end to end (proto item: `StructuredAggregationQuery`, `RunAggregationQuery`).
8. **8d99ce0** (SHOULD, L): public OR/AND filters (proto item: `CompositeFilter.OR`, needs DNF and per-disjunct targets).
9. **c5a894c** (SHOULD, M-L): multiple inequality filters; core/query.dart and validation.
10. **b77c218** (SHOULD, M): `ListenSource.CACHE` snapshot listener option.
11. **24197b5** (SHOULD, S-M): new cache settings API shape.
12. **46e5549** (COULD, S): refresh persisted target data periodically when limbo-free version advances.
13. **9a9a02b** (COULD, S): memory LRU GC settings plumbing.
14. **a5e7062 + c5cd536 + 6349a09** (COULD, L): auto persistent cache index creation; depends on index stack from chunks 0-2.
15. **622d65b** (COULD, S): equals on filters (with the filter classes).
16. **e9d0de9** (SHOULD, S): multi-DB public API; mostly present.

## 3. Table

| sha7 | date | PR# | category | area | relevance | in Dart? | what changed and why it matters for the port |
|---|---|---|---|---|---|---|---|
| a4a9625 | 2023-02-15 | 4677 | PROTOCOL-wire | remote | SHOULD | NO | Adds `Sum`/`Avg` to `StructuredAggregationQuery` protos (gap analysis: RunAggregationQuery sum/avg). Dart res/protos has no aggregation protos at all; proto refresh is the prerequisite (S). |
| 7d98d5f | 2023-02-15 | 4678 | BUILD | other | N/A | N/A | Build/versioning/changelog/release housekeeping (classified by subject). |
| 5ea5bd0 | 2023-02-15 | 4231 | REFACTOR | core | COULD | N/A | Removes `Query.containsCompositeFilters()` and relaxes validation (multiple IN, OR). Dart has no CompositeFilter classes (only an AND constant in remote_serializer.dart); belongs to the OR feature (see 8d99ce0). |
| e2d3607 | 2023-02-21 | 4706 | BUILD | other | N/A | N/A | Build/versioning/changelog/release housekeeping (classified by subject). |
| df07a40 | 2023-02-22 | 4709 | BUILD | other | N/A | N/A | Build/versioning/changelog/release housekeeping (classified by subject). |
| bb62df1 | 2023-02-27 | 4714 | DOCS | api | N/A | N/A | Dackka plugin; javadoc edits only. |
| 5c11b8a | 2023-02-27 | 4705 | TEST | core | N/A | N/A | getCanonicalId test uses Query API. |
| 46e7a69 | 2023-03-03 | 4742 | BUILD | other | N/A | N/A | Build/versioning/changelog/release housekeeping (classified by subject). |
| 8d99ce0 | 2023-03-06 | 4692 | FEATURE-public-API | api | SHOULD | NO | Makes `Filter.or/and` and `Query.where(Filter)` public (OR queries, changelog 24.5.0 / 24.4.5 layout ambiguous). Needs CompositeFilter, DNF (LogicUtils) and per-disjunct targets/index-backed OR; touches Dart query.dart, core/query.dart, core/filter/*, local/* (L; groundwork lives in chunks 0-2, unverified here). Proto: `CompositeFilter.Operator.OR` (gap analysis). |
| 46e5549 | 2023-03-06 | 4533 | PERF | local | COULD | NO | LocalStore persists target data when lastLimboFreeSnapshotVersion advances by >= RESUME_TOKEN_MAX_AGE_SECONDS so later resumes use a fresher token. No such logic in Dart local/local_store.dart (grep). S. |
| 02b3365 | 2023-03-06 | 4741 | BUILD | other | N/A | N/A | Build/versioning/changelog/release housekeeping (classified by subject). |
| 5318bd9 | 2023-03-08 | 4715 | BUGFIX-crash | model | N/A | N/A | First attempt at StackOverflow fix for nested server timestamps; reverted by 7bbe823, redone in c989076. |
| 7bbe823 | 2023-03-09 | 4761 | BUGFIX-crash | model | N/A | N/A | Reverts 5318bd9; net effect nil. |
| 436b03f | 2023-03-10 | 4697 | BUILD | other | N/A | N/A | Build/versioning/changelog/release housekeeping (classified by subject). |
| 8655160 | 2023-03-11 | 4770 | TEST | core | N/A | N/A | Spec tests validate query purpose. |
| 8a92291 | 2023-03-13 | 4758 | REFACTOR | local | N/A | N/A | LocalStore refactor, no behaviour change. |
| c989076 | 2023-03-20 | 4771 | BUGFIX-crash | model | SHOULD | NO | Final fix (24.5.0/24.6.0): a server timestamp over an existing server timestamp keeps only the original previous value (no t3->t2->t1->42 chain). Dart model/value/server_timestamp_value.dart (and the server-timestamp transform operation) need the same (S). |
| 47e7a88 | 2023-03-20 | 4799 | TEST | remote | N/A | N/A | Query resume with existence filter integration test. |
| 3d4cfed | 2023-03-24 | - | TEST | remote | N/A | N/A | Test improvement; adds test-only TestingHooks and a small WatchChangeAggregator hook (part of bloom filter testing). |
| eaefea8 | 2023-04-03 | 4619 | BUILD | other | N/A | N/A | Build/versioning/changelog/release housekeeping (classified by subject). |
| 26de539 | 2023-04-04 | 4735 | FEATURE-public-API | api | SHOULD | NO | First Android sum/avg: AggregateField, AggregateQuery/Snapshot, RemoteSerializer.encodeStructuredAggregationQuery, Datastore.runAggregateQuery (still non-public; public in ffdee32, 24.9.1). Dart has no AggregateQuery or RunAggregationQuery: new API files + remote/datastore/firestore_client.dart + datastore.dart + remote_serializer.dart (M for count+sum+avg). Proto: Aggregation Count/Sum/Avg. |
| caf55ca | 2023-04-04 | 4844 | BUILD | other | N/A | N/A | Build/versioning/changelog/release housekeeping (classified by subject). |
| c062de8 | 2023-04-04 | 4804 | ANDROID-ONLY | api | N/A | N/A | Kotlin Flows. |
| 73db13a | 2023-04-06 | 4850 | TEST | api | N/A | N/A | Kotlin PropertyName test. |
| 24197b5 | 2023-04-14 | 4869 | FEATURE-public-API | api | SHOULD | NO | New cache config API (`LocalCacheSettings`, `MemoryCacheSettings`, `PersistentCacheSettings` in FirebaseFirestoreSettings, 24.6.0). Dart firestore_settings.dart has the old persistence/cache-size flags only. S-M, API shape only. |
| f314ff7 | 2023-04-14 | 4824 | BUGFIX-correctness | bundle | N/A | N/A | Bundled-query decode builds a Query (LIMIT_TO_FIRST) then toTarget, fixing limitToLast bundle resume. Dart has no bundle support (no bundle/ dir), skip unless bundles are ported. |
| 3e5cd47 | 2023-04-17 | 4782 | FEATURE-internal | api | MUST | NO | FirebaseAppCheckTokenProvider and FirestoreMultiDbComponent wiring so the SDK sends the App Check token (X-Firebase-AppCheck). Dart auth/ has only the auth token provider and remote/datastore/channel_options_provider.dart sends no App Check header, so projects enforcing App Check reject the client (gap analysis part 4). M (needs App Check interop in Dart). |
| 0451fa0 | 2023-04-19 | 4909 | BUILD | other | N/A | N/A | Build/versioning/changelog/release housekeeping (classified by subject). |
| 31176ce | 2023-04-19 | 4908 | BUILD | other | N/A | N/A | Build/versioning/changelog/release housekeeping (classified by subject). |
| 9a9a02b | 2023-04-19 | 4724 | FEATURE-public-API | local | COULD | PARTIAL | Memory LRU GC settings (`MemoryLruGcSettings`, `MemoryEagerGcSettings`, 24.6.0). Dart already has local/memory/memory_lru_reference_delegate.dart and lru_garbage_collector.dart; only the settings plumbing is missing (S). |
| 2547367 | 2023-04-25 | 4922 | FEATURE-public-API | api | COULD | NO | `AggregateQuerySnapshot.createWithCount()` for mocking; needs AggregateQuerySnapshot first. |
| 1b43eb2 | 2023-04-25 | - | TEST | core | N/A | N/A | Spec tests port: bundle readTime/resumeToken. |
| 84894be | 2023-04-25 | 4929 | TEST | remote | COULD | N/A | Spec tests port of the JS bloom-filter resumption work (existence_filter_spec_test.json +7000 lines). Best verification artifact when porting c83d5e5. |
| 11d97e8 | 2023-04-25 | 4931 | TEST | remote | N/A | N/A | Spec tests: targetPurpose as strings (test harness only). |
| 8171ac5 | 2023-04-25 | 4921 | BUILD | other | N/A | N/A | Build/versioning/changelog/release housekeeping (classified by subject). |
| c2a50cf | 2023-04-26 | 4935 | BUILD | other | N/A | N/A | Build/versioning/changelog/release housekeeping (classified by subject). |
| f47a0dd | 2023-04-26 | 4936 | BUILD | other | N/A | N/A | Build/versioning/changelog/release housekeeping (classified by subject). |
| fcf0b2c | 2023-04-27 | 4952 | BUILD | other | N/A | N/A | Build/versioning/changelog/release housekeeping (classified by subject). |
| 07f2567 | 2023-04-28 | 4956 | BUILD | other | N/A | N/A | Build/versioning/changelog/release housekeeping (classified by subject). |
| e65680d | 2023-04-28 | 4959 | DOCS | api | N/A | N/A | Doc fixes for 24.6.0 cache settings. |
| 34af203 | 2023-05-01 | 4966 | BUILD | other | N/A | N/A | Build/versioning/changelog/release housekeeping (classified by subject). |
| abfa774 | 2023-05-01 | 4961 | PROTOCOL-wire | remote | SHOULD | NO | Aggregation aliases: client sends short server aliases `aggregate_N`, remaps results to user aliases, dedupes identical aggregates (server rejects arbitrary aliases). Port with 26de539 (Datastore + RemoteSerializer, S). |
| 8f1a33f | 2023-05-02 | 4969 | BUILD | other | N/A | N/A | Build/versioning/changelog/release housekeeping (classified by subject). |
| b1f2130 | 2023-05-03 | 4972 | BUILD | other | N/A | N/A | Build/versioning/changelog/release housekeeping (classified by subject). |
| 5c2b381 | 2023-05-04 | 4975 | REFACTOR | remote | N/A | N/A | TestingHooks cleanup (test-only). |
| c83d5e5 | 2023-05-08 | 4982 | PROTOCOL-wire | remote | SHOULD | NO | Bloom-filter resume optimisation (24.6.1): `TargetData.expectedCount` (proto `Target.expected_count=12`), new `BloomFilter` (205 lines), `ExistenceFilter.unchangedNames` (proto `ExistenceFilter.unchanged_names`, bloom_filter.proto), WatchChangeAggregator tries bloom-filter based fix before full reset, `RemoteEvent.targetMismatches` set->map, SyncEngine initialises the view before remoteStore.listen, new QueryPurpose. Whether expectedCount is persisted: unverified. Dart: remote/existence_filter.dart, watch_change_aggregator.dart, remote_serializer.dart (existence filter TODO), local/query_data.dart, local/query_purpose.dart, core/sync_engine.dart. Needs proto refresh. L. Not required for correctness (mismatch still resets the target) but cuts read cost on reconnect. |
| 2d2e008 | 2023-05-26 | 5034 | BUGFIX-correctness | model | COULD | N/A | TargetIndexMatcher: equality plus inequality on the same field matched wrongly. Dart has no TargetIndexMatcher/FieldIndex (grep), so only relevant if the field-index stack is ported. |
| b39de05 | 2023-05-30 | 5041 | TEST | model | N/A | N/A | Tests for filters on the same field (2d2e008). |
| cf98ca7 | 2023-05-31 | 5032 | REFACTOR | remote | N/A | N/A | Readability tweak in RemoteSerializer. |
| 8d21a34 | 2023-06-01 | 5035 | MERGEBACK | other | N/A | N/A | Mergeback, no functional change. |
| aac9ef8 | 2023-06-01 | 5047 | BUILD | other | N/A | N/A | Build/versioning/changelog/release housekeeping (classified by subject). |
| 7b940f8 | 2023-06-02 | 5017 | BUILD | other | N/A | N/A | Build/versioning/changelog/release housekeeping (classified by subject). |
| e9d0de9 | 2023-06-09 | 4015 | FEATURE-public-API | api | SHOULD | PARTIAL | Exposes multi-DB (24.7.0). Dart already has DatabaseId.forDatabase, firestore_multi_db_component.dart and a database parameter (firestore.dart:99); verify public factory only. |
| dd710a7 | 2023-06-21 | 5088 | TEST | core | N/A | N/A | Spec test sync with JS PR 7372. |
| e3dc1ad | 2023-06-26 | 5099 | BUGFIX-crash | core | N/A | N/A | Thread-safe memoization in core.Query (ConcurrentModificationException, 24.7.0). Dart is single-isolate per instance; no change. |
| 9aa45a5 | 2023-06-30 | 5114 | BUILD | other | N/A | N/A | Build/versioning/changelog/release housekeeping (classified by subject). |
| 1e44257 | 2023-07-05 | 5132 | PERF | core | COULD | UNKNOWN | Removes an unused compareTo() in core/View; trivial, check core/view.dart. |
| fca527d | 2023-07-06 | 5139 | DOCS | api | N/A | N/A | Multi-DB doc format. |
| 52ca562 | 2023-07-06 | 5135 | TEST | remote | N/A | N/A | Bloom filter unicode test. |
| 593f4cd | 2023-07-06 | 5144 | BUILD | other | N/A | N/A | Build/versioning/changelog/release housekeeping (classified by subject). |
| bb0ac26 | 2023-07-14 | 5127 | BUILD | other | N/A | N/A | Build/versioning/changelog/release housekeeping (classified by subject). |
| 800d290 | 2023-07-14 | 5145 | REFACTOR | remote | COULD | N/A | Test hooks + WatchChangeAggregator tweaks for bloom filter testing. Port with c83d5e5. |
| c77027e | 2023-07-14 | 5163 | DOCS | api | N/A | N/A | Valid backend values list (docs). |
| c4b5a92 | 2023-07-14 | 5158 | DOCS | api | N/A | N/A | Multi-DB docs. |
| 9471221 | 2023-07-17 | 5167 | TEST | remote | N/A | N/A | Test change. |
| 77ab6f7 | 2023-07-17 | 5161 | BUGFIX-correctness | api | N/A | N/A | Builder.set return type in Memory*GcSettings (Java API); part of 9a9a02b. |
| b8dc203 | 2023-07-18 | 5168 | TEST | remote | N/A | N/A | Disable bloom filter tests on emulator. |
| 965ac2f | 2023-07-20 | 5177 | REFACTOR | remote | COULD | N/A | WatchChangeAggregator/TestingHooks alignment with web SDK. Port with c83d5e5. |
| 79d24f0 | 2023-07-20 | 5169 | BUILD | other | N/A | N/A | Build/versioning/changelog/release housekeeping (classified by subject). |
| 933d191 | 2023-07-20 | 5181 | BUILD | other | N/A | N/A | Build/versioning/changelog/release housekeeping (classified by subject). |
| 2827bac | 2023-07-24 | 5184 | TEST | remote | N/A | N/A | Test change. |
| a5e7062 | 2023-07-26 | 4987 | FEATURE-public-API | index | COULD | NO | Auto cache index creation (24.8.0): `PersistentCacheIndexManager`, QueryEngine/`QueryContext` decide to create indexes when scans are costly, TargetIndexMatcher.buildTargetIndex. Needs the whole field-index stack (SQLite field indexes, overlays, index-aware QueryEngine); Dart sqlite_index_manager.dart only has collection-parent index (FieldIndex grep = 0). L, depends on chunk 0-2 groundwork (schema from earlier chunks, unverified). |
| c5cd536 | 2023-07-27 | 5162 | FEATURE-public-API | index | COULD | NO | `deleteAllIndexes()` on PersistentCacheIndexManager; part of a5e7062 port (S after that). |
| 824195e | 2023-07-28 | 5209 | REFACTOR | local | N/A | N/A | Variable rename. |
| 622d65b | 2023-07-28 | 5210 | BUGFIX-correctness | api | COULD | NO | Implements `equals` on Filter (24.7.1). Dart would implement == on filter classes when they are added. |
| 8ce2dfc | 2023-07-31 | 5206 | BUILD | other | N/A | N/A | Build/versioning/changelog/release housekeeping (classified by subject). |
| 70e7771 | 2023-08-01 | 5216 | BUILD | other | N/A | N/A | Build/versioning/changelog/release housekeeping (classified by subject). |
| d5b05f2 | 2023-08-03 | 5219 | TEST | index | N/A | N/A | Test comment. |
| f2a0fa3 | 2023-08-16 | 5227 | BUILD | other | N/A | N/A | Build/versioning/changelog/release housekeeping (classified by subject). |
| d27ff15 | 2023-08-17 | 5213 | TEST | index | N/A | N/A | Persistent cache indexing coverage. |
| ecb313c | 2023-08-29 | 5285 | MERGEBACK | other | N/A | N/A | Mergeback, no functional change. |
| 6349a09 | 2023-08-31 | 5256 | FEATURE-public-API | index | COULD | NO | Public auto index creation API (24.8.0); finalises a5e7062. |
| 66041ec | 2023-09-04 | 5293 | BUILD | other | N/A | N/A | Build/versioning/changelog/release housekeeping (classified by subject). |
| 7bfaf83 | 2023-09-05 | 5298 | DOCS | api | N/A | N/A | Docs for auto index creation. |
| 87c1f02 | 2023-09-08 | 5309 | BUILD | other | N/A | N/A | Build/versioning/changelog/release housekeeping (classified by subject). |
| dfa22c7 | 2023-09-11 | 5308 | TEST | remote | N/A | N/A | Integration tests for existence filter. |
| c5a894c | 2023-09-12 | 5194 | FEATURE-public-API | core | SHOULD | NO | Multiple inequality (25.0.0): Query inequality filter list, implicit orderBy over all inequality fields, TargetIndexMatcher with several inequalities, validation relaxed. No new proto (server side). Dart core/query.dart assumes a single inequality field; core/query.dart, query.dart validation, matches() and orderBys derivation change (M-L). Interacts with CompositeFilter/OR. |
| 7da4e0a | 2023-09-14 | 5330 | BUILD | other | N/A | N/A | Build/versioning/changelog/release housekeeping (classified by subject). |
| 924641b | 2023-09-15 | 5332 | MERGEBACK | other | N/A | N/A | Mergeback, no functional change. |
| 43eec0e | 2023-09-15 | 5337 | BUILD | other | N/A | N/A | Build/versioning/changelog/release housekeeping (classified by subject). |
| d4a56bb | 2023-09-18 | 5342 | MERGEBACK | other | N/A | N/A | Mergeback, no functional change. |
| 5e974c4 | 2023-09-27 | 5276 | ANDROID-ONLY | api | N/A | N/A | KTX packaging into main module. |
| dd56689 | 2023-09-29 | 5323 | DOCS | api | N/A | N/A | Doc fixes. |
| 22c314f | 2023-10-02 | 5346 | TEST | api | N/A | N/A | Re-enable OR integration tests. |
| fa6f5c6 | 2023-10-02 | 5377 | BUILD | other | N/A | N/A | Build/versioning/changelog/release housekeeping (classified by subject). |
| 26eb260 | 2023-10-05 | 5352 | TEST | index | N/A | N/A | Composite index tests against production. |
| 209ee0c | 2023-10-10 | 5389 | BUILD | other | N/A | N/A | Deprecation message for common. |
| a135c51 | 2023-10-10 | 5390 | BUILD | other | N/A | N/A | Build/versioning/changelog/release housekeeping (classified by subject). |
| 5241ce7 | 2023-10-12 | 5383 | TEST | core | N/A | N/A | MIEQ negative tests. |
| 157147f | 2023-10-13 | 5409 | BUILD | other | N/A | N/A | Fix deprecation message. |
| 406c057 | 2023-10-13 | 5419 | BUILD | other | N/A | N/A | Build/versioning/changelog/release housekeeping (classified by subject). |
| ffdee32 | 2023-10-16 | 5217 | FEATURE-public-API | api | SHOULD | NO | Public sum()/average() (24.9.1): AggregateField.sum/average, getLong/getDouble on snapshot, Query.aggregate(...), core/Query changes for aggregates. Port with 26de539 + abfa774 (M). |
| 7932756 | 2023-10-19 | 5444 | MERGEBACK | other | N/A | N/A | Mergeback, no functional change. |
| 1c45fd5 | 2023-10-20 | 5421 | DOCS | other | N/A | N/A | ReadMe composite index guidance. |
| 1ec75d4 | 2023-10-23 | 5462 | BUILD | other | N/A | N/A | Build/versioning/changelog/release housekeeping (classified by subject). |
| f6b5ecb | 2023-10-25 | 5470 | TEST | index | N/A | N/A | Move sum/avg composite index tests. |
| 4d283b3 | 2023-10-27 | 5483 | MERGEBACK | other | N/A | N/A | Mergeback, no functional change. |
| 7f53ce4 | 2023-11-16 | 5556 | ANDROID-ONLY | other | N/A | N/A | Copyright format in Kotlin files. |
| a014114 | 2023-11-21 | 5506 | BUGFIX-correctness | core | SHOULD | NO | 24.10.1: when a target is pending reset after an existence filter mismatch, View.applyChanges skips limbo computation and does not report SYNCED. Dart core/view.dart:199 and sync_engine.dart:448 need a `targetIsPendingReset` argument; depends on RemoteEvent.targetMismatches map from c83d5e5 (else never true). S. |
| dacdc3c | 2023-12-05 | 5587 | DOCS | other | N/A | N/A | Comment wording across 49 files, no logic. |
| 42a6951 | 2023-12-05 | 5585 | BUGFIX-crash | local | MUST | NO | 24.10.1: SQLite LRU removeOrphanedDocuments could loop forever when it kept re-selecting rows it did not delete; now pages with `path > ?`. Dart local/sqlite/sqlite_lru_reference_delegate.dart:149 has the same unpaged pattern (same hang risk, unverified by running). S. |
| 080e1fc | 2023-12-06 | 5588 | BUGFIX-correctness | api | SHOULD | NO | 24.10.0: DocumentSnapshot equals compares document data instead of full document state. Dart document_snapshot.dart:356 uses `document == other.document`. S. |
| 82213a1 | 2023-12-08 | 5592 | MERGEBACK | other | N/A | N/A | Mergeback, no functional change. |
| 3d88f62 | 2023-12-12 | 5573 | BUGFIX-crash | local | COULD | UNKNOWN | 24.10.1: LocalDocumentsView mutated an immutable `Collections.emptyMap()`. Java-specific; check local_documents_view.dart does not share a const map (S). |
| 2f546b2 | 2023-12-14 | 5600 | TEST | api | N/A | N/A | TODO comments in tests. |
| a8310ed | 2023-12-14 | 5601 | TEST | api | N/A | N/A | Test variable rename. |
| 16a90fa | 2023-12-14 | 5602 | TEST | api | N/A | N/A | Test name. |
| 4dcae02 | 2024-01-10 | 5634 | DOCS | api | N/A | N/A | Count API docs. |
| 5c1465f | 2024-01-19 | 5648 | MERGEBACK | other | N/A | N/A | Mergeback, no functional change. |
| 9b48edd | 2024-01-25 | 5660 | TEST | bundle | N/A | N/A | Bundle test with empty array/map. |
| 5c24573 | 2024-01-31 | 5631 | BUILD | other | N/A | N/A | Build/versioning/changelog/release housekeeping (classified by subject). |
| 5ef5cdd | 2024-01-31 | 5626 | BUGFIX-correctness | util | N/A | N/A | POJO CustomClassMapper bridge methods (Java/Kotlin); reverted by a4ca0cb. |
| 5125155 | 2024-02-09 | 5702 | MERGEBACK | other | N/A | N/A | Mergeback, no functional change. |
| a4ca0cb | 2024-02-12 | 5704 | ANDROID-ONLY | util | N/A | N/A | Reverts 5ef5cdd. |
| 6a97c30 | 2024-02-12 | 5707 | BUILD | other | N/A | N/A | Build/versioning/changelog/release housekeeping (classified by subject). |
| 833a1cc | 2024-02-20 | 5706 | BUGFIX-correctness | util | N/A | N/A | CustomClassMapper setter annotations (24.10.3). Java POJO mapping; no Dart equivalent. |
| 950e66d | 2024-02-20 | 5715 | BUILD | other | N/A | N/A | Build/versioning/changelog/release housekeeping (classified by subject). |
| d1fbda4 | 2024-02-28 | 5744 | MERGEBACK | other | N/A | N/A | Mergeback, no functional change. |
| b77c218 | 2024-03-11 | 5690 | FEATURE-public-API | api | SHOULD | NO | 24.11.0 `ListenSource.CACHE` / `SnapshotListenOptions`: EventManager, QueryListener, SyncEngine listen to cache only (no remote target). Dart core/event_manager.dart, sync_engine.dart, query.dart, document_reference.dart. M. |
| e40b749 | 2024-03-22 | 5797 | DOCS | api | N/A | N/A | Javadoc. |
| 30b10ab | 2024-03-22 | 5798 | MERGEBACK | other | N/A | N/A | Mergeback, no functional change. |
| 9e0a82e | 2024-03-26 | 5810 | REFACTOR | util | N/A | N/A | long.compare in NumberComparisonHelper (Java API level). |
| 6c3fc22 | 2024-03-29 | 5729 | TEST | index | N/A | N/A | Move MIEQ composite index tests. |
| 98682cc | 2024-04-08 | 5832 | ANDROID-ONLY | other | N/A | N/A | Kotlin compile fix. |
| 18db6bd | 2024-04-09 | 5842 | REFACTOR | other | N/A | N/A | Timestamp moved to firebase-common (Android modularisation). |
| 98f2f9a | 2024-04-11 | 5850 | BUILD | other | N/A | N/A | Build/versioning/changelog/release housekeeping (classified by subject). |
| bcaf4c3 | 2024-04-11 | 5851 | BUILD | other | N/A | N/A | Build/versioning/changelog/release housekeeping (classified by subject). |
| 1d717ea | 2024-04-16 | 5853 | FEATURE-public-API | api | N/A | N/A | Timestamp <-> java.time.Instant (25.0.0); Dart uses DateTime. |
| ddae42d | 2024-04-22 | 5877 | BUILD | other | N/A | N/A | minSdk 21. |
| 8dc53fa | 2024-04-22 | 5886 | BUILD | other | N/A | N/A | Build/versioning/changelog/release housekeeping (classified by subject). |
| 4583328 | 2024-04-24 | 5895 | BUILD | other | N/A | N/A | Build/versioning/changelog/release housekeeping (classified by subject). |
| 389a2d6 | 2024-04-24 | 5892 | BUILD | other | N/A | N/A | Build/versioning/changelog/release housekeeping (classified by subject). |

## 4. Dependencies and ordering
- **Aggregations:** a4a9625 (protos) -> 26de539 (impl) -> abfa774 (server aliases) -> 2547367 (createWithCount) -> ffdee32 (public sum/avg). Port as one unit; count itself came earlier (chunk 0-2, not read here).
- **Bloom filter resume:** c83d5e5 is the core. 800d290, 965ac2f, 3d4cfed (test hooks/aggregator tweaks), spec tests 84894be/1b43eb2/11d97e8 go with it. a014114 (limbo fix) requires `targetMismatches` as a map from c83d5e5. Requires the proto refresh from the gap analysis (`bloom_filter.proto`, `Target.expected_count`, `ExistenceFilter.unchanged_names`). Interacts with 46e5549 (target data persistence cadence).
- **OR / MIEQ / indexing:** 5ea5bd0 and 8d99ce0 (OR public) rely on CompositeFilter and DNF from earlier chunks (not read here). c5a894c (MIEQ) builds on that plus TargetIndexMatcher; 2d2e008 fixes TargetIndexMatcher and only matters with the index stack. a5e7062 -> c5cd536 -> 6349a09 (auto indexing) depend on the field index/overlay work from chunks 0-2.
- **Cache settings:** 24197b5 and 9a9a02b (+77ab6f7 builder fix, e65680d docs) are one API family.
- **Reverted / superseded:** 5318bd9 reverted by 7bbe823, redone as c989076. 5ef5cdd reverted by a4ca0cb, then 833a1cc fixes the setter-annotation regression. Any relation to commits in other chunks is not guessed here.
- **Independent small fixes:** 42a6951, 080e1fc, c989076, 46e5549 can be ported alone.
