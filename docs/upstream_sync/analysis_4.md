# Upstream analysis, chunk 4 (2024-04-25 to 2026-11-11, 139 commits)

## 1. Summary of themes
1. The chunk is dominated by infra: version-catalog and gradle work, minSdk 23 then 24, grpc 1.84 and protobuf 4.36 bumps, and about 20 release mergebacks. All of these are N/A for the Dart port.
2. The biggest item by volume is Firestore Pipelines (Enterprise edition): about 35 commits, from #7590 on 2026-01-05 to window functions on 2026-11-02. These are skipped by decision and get one line each.
3. New value types matter for the port: VectorValue (25.1.0) and the BSON types MinKey, MaxKey, Regex, Int32, Decimal128, ObjectId and BsonTimestamp (27.0.0). Both are encoded as reserved-key maps and change the type-ordering table.
4. Ordering correctness fixes: UTF-8 byte order for strings and map keys (25.1.2, then lazily implemented in 25.1.3 and finalized in 26.0.0), and numeric ordering of `__id<n>__` path segments. Dart currently uses UTF-16 `String.compareTo`.
5. Query semantics: `!=` and `not-in` no longer match null fields (25.1.4). Dart's typeOrder check already excludes null for `!=`; Dart has no not-in.
6. Wire and protocol changes against production today: the .proto sync (25.1.1), FieldValue.maximum/minimum transforms (26.4.0), and a 17MB max inbound message size so 16MB documents can be read (26.5.0). The Dart grpc package appears to have no inbound limit, so this is probably already fine.
7. Large-document work (26.4.1 to 26.6.0): chunked SQLite reads and OOM-safe logging. The chunked read is Android-specific (CursorWindow); the logging truncation could matter in Dart.
8. Persistence: schema v17 (a `globals` table holding the session token, unused elsewhere) and v18 (a `document_type` column to skip tombstones in collection scans). Both are optional for Dart, which has its own schema.
9. Query performance tweaks (26.0.2): hoisting `query.comparator`, a HashMap in DocumentViewChangeSet, ObjectValue memoization, and equals complexity. Mostly COULD.
10. No multi-database or emulator-support commits appear in this chunk; they are in earlier chunks (not checked here).

Important: the Dart port predates the overlay and index work (no overlays, no field indexes, no `!=`/not-in/array-contains-any variants beyond the 2019 set, no Values.kt), so many "in Dart?" answers are NO because the whole surrounding code does not exist yet, not just the fix.

## 2. Top items
1. 28 + 40 (a1cbf93, 84c4d81; 33 ec26a52 is superseded): UTF-8 byte-order string comparison, final algorithm in 84c4d81. MUST, S.
2. 18 (60a5e4c): proto resync and regeneration, a prerequisite for anything wire-new. SHOULD, M.
3. 12 (57aaf39): VectorValue, new type order and map encoding. SHOULD, M.
4. 124 (22f560e): BSON types, with the type-order renumbering. SHOULD, L (the Decimal128/Quadruple part is optional).
5. 105 (36b3e5b): FieldValue.maximum/minimum transforms. SHOULD, M (needs 18 and a production check).
6. 114 (bb270a6) + 107 (e70eaac): 17MB message size, so a large-document read test is needed, plus log truncation. SHOULD/COULD, S.
7. 26 (3dd8ddf): numeric `__id__` path-segment ordering. SHOULD, S.
8. 36 (edcea54): null exclusion for `!=` / not-in. SHOULD, S (partly done already).
9. 38 (fda3351): guard stream close on an already-cancelled call. COULD, S.
10. 50 (5c7a993): `document_type` column and SQLite v18. COULD, M.
11. 59 / 60 (77aa34e, 482ac0e): comparator hoisting and the hash change set. COULD, S each.
12. 102 (4697d40): GC scheduler not started when the cache is unlimited. COULD, S.
13. 77 (2a81fad): ObjectValue equality cost. COULD, S.

## 3. Full table
| sha7 | date | PR# | category | area | relevance | in Dart? | what changed and why it matters for the port |
|---|---|---|---|---|---|---|---|
| a350561 | 2024-04-25 | #5902 | BUILD | other | N/A | N/A | Build/CI/gradle/dependency or version bump; Android tooling only. |
| a90f1bb | 2024-05-02 | #5923 | MERGEBACK | other | N/A | N/A | Release mergeback; no new logic of its own. |
| 2dc4c6e | 2024-06-12 | #6025 | BUILD | other | N/A | N/A | Build/CI/gradle/dependency or version bump; Android tooling only. |
| b793e81 | 2024-06-12 | #6027 | BUILD | other | N/A | N/A | Build/CI/gradle/dependency or version bump; Android tooling only. |
| 0a54f10 | 2024-06-18 | #5941 | PERSISTENCE-schema | local | COULD | NO | Adds a `globals` key/value table (SQLite schema v17) plus GlobalsCache/LocalStore get/setSessionToken. At HEAD nothing else reads the session token (git grep found no consumer), so it is groundwork only. Dart has its own schema (local/sqlite/sqlite_schema.dart); skip unless session tokens are adopted. |
| 6170443 | 2024-06-28 | #6057 | TEST | other | N/A | N/A | Test-only change (test harness / integration or unit tests). |
| 5fd9a73 | 2024-07-02 | #6037 | REFACTOR | core | N/A | N/A | ComponentProvider/RemoteComponentProvider refactor (DI of Datastore, streams, FirestoreClient). Android structure only; Dart wires this in core/firestore_client.dart + remote/datastore/datastore.dart. Also splits WriteStream.onFirst (handshake) from onNext, no behaviour change. |
| 58540de | 2024-07-04 | #6043 | TEST | other | N/A | N/A | Test-only change (test harness / integration or unit tests). |
| cad0339 | 2024-07-15 | #6099 | BUILD | other | N/A | N/A | Build/CI/gradle/dependency or version bump; Android tooling only. |
| d26a5f8 | 2024-07-15 | #6094 | BUILD | other | N/A | N/A | Build/CI/gradle/dependency or version bump; Android tooling only. |
| 4495cc9 | 2024-07-16 | #6100 | REFACTOR | other | N/A | N/A | Spotless formatting across 29 files (incl. RemoteComponenetProvider, SQLiteGlobalsCache); no behaviour change. |
| 57aaf39 | 2024-08-08 | #6154 | FEATURE-public-API | model | SHOULD | NO | VectorValue (25.1.0): a map `{__type__:'__vector__', value:[doubles]}`; new type order (vector=10, map=11) so vectors sort after arrays and before maps, compare by length then elements; index writer type 53; min-vector lower bound. Dart: model/value/field_value.dart (typeOrder consts, ObjectValue detection), user_data_converter.dart, document_snapshot.dart, new vector_value.dart, local ordering. Without it, vectors are read back as plain maps and cache ordering differs from the server. Size M. |
| 08deb69 | 2024-08-12 | #6050 | REFACTOR | api | COULD | UNKNOWN | FirestoreClientProvider centralizes client creation/termination for a FirebaseFirestore instance (and lets listeners/refs survive client restarts). Android lifecycle plumbing; Dart firestore.dart owns the client directly. Low value. |
| f4e5bd0 | 2024-08-23 | #6211 | DOCS | other | N/A | N/A | Docs, changelog, javadoc, formatting or KDoc only. |
| cc3bb8e | 2024-08-26 | #6212 | BUILD | other | N/A | N/A | Build/CI/gradle/dependency or version bump; Android tooling only. |
| fe9d619 | 2024-09-24 | #6141 | REFACTOR | api | N/A | N/A | Removes javax.annotation.Nonnull in files that already use another Nonnull; annotation-only. |
| 065c732 | 2024-10-10 | #6343 | BUILD | other | N/A | N/A | protobuf-java bump for CVE (Android runtime); Dart uses package:protobuf. |
| 60a5e4c | 2024-10-11 | #6369 | PROTOCOL-wire | remote | SHOULD | NO | Synchronizes the .proto files (firestore.proto +358, query.proto, document.proto, write.proto, common.proto, bloom_filter.proto). Dart protos (lib/src/proto, tool/gen_protos.sh) are from 2019 and must be regenerated before anything newer (min/max transforms, BSON/pipeline fields) can be sent. Mostly additive for wire compat. 25.1.1. Size M (regen plus fix generated-name differences). |
| 2f15757 | 2024-10-17 | #6385 | BUILD | other | N/A | N/A | Build/CI/gradle/dependency or version bump; Android tooling only. |
| 1a47ed1 | 2024-10-22 | #6397 | MERGEBACK | other | N/A | N/A | Release mergeback; no new logic of its own. |
| d96507b | 2024-10-24 | #6389 | BUILD | other | N/A | N/A | Build/CI/gradle/dependency or version bump; Android tooling only. |
| 0697dd3 | 2024-10-24 | #6377 | BUILD | other | N/A | N/A | Build/CI/gradle/dependency or version bump; Android tooling only. |
| 442bab2 | 2024-11-04 | #6427 | BUILD | other | N/A | N/A | Build/CI/gradle/dependency or version bump; Android tooling only. |
| 6c76289 | 2024-11-27 | #6532 | BUILD | remote | N/A | N/A | AGP bump; 2-line TestingHooks touch only. |
| 2b072d9 | 2024-12-10 | #6584 | BUILD | other | N/A | N/A | Build/CI/gradle/dependency or version bump; Android tooling only. |
| 3dd8ddf | 2024-12-17 | #6594 | BUGFIX-correctness | model | SHOULD | NO | BasePath.compareTo now sorts segments of the form `__id<digits>__` numerically and before other segments (matches backend ordering of long-typed document ids). Dart: model/base_path.dart compareTo (uses plain String.compareTo) and anything else that orders by path. Not listed in the Android changelog (unverified whether released). Size S. Combine with the UTF-8 comparison from item 28/40. |
| f024090 | 2025-01-03 | #6612 | DOCS | other | N/A | N/A | Docs, changelog, javadoc, formatting or KDoc only. |
| a1cbf93 | 2025-01-15 | #6615 | BUGFIX-correctness | util | MUST | NO | Strings and map keys are now compared in UTF-8 byte order (25.1.2), fixing a server/SDK mismatch for characters outside the BMP. Dart compares UTF-16 code units (String.compareTo in base_path.dart, StringValue/ObjectValue key compare in model/value/*.dart), so ordering differs for surrogate pairs vs U+E000-U+FFFF. Port the FINAL algorithm from item 40, not this eager ByteString version. Size S. |
| 59839ee | 2025-02-04 | #6672 | DOCS | other | N/A | N/A | Docs, changelog, javadoc, formatting or KDoc only. |
| 92f448f | 2025-02-05 | #6671 | BUILD | other | N/A | N/A | Metalava / api.txt regeneration. |
| b4ff466 | 2025-02-07 | #6680 | MERGEBACK | other | N/A | N/A | Release mergeback; no new logic of its own. |
| 4cf2825 | 2025-02-24 | #6716 | BUILD | other | N/A | N/A | protolite-well-known-types dependency bump (Android). |
| ec26a52 | 2025-03-03 | #6706 | PERF | util | MUST | NO | Replaces the eager ByteString.copyFromUtf8 in compareUtf8Strings with lazy per-codepoint encoding (25.1.3). Superseded by item 40; do not port separately. |
| f9d1802 | 2025-03-21 | #6793 | MERGEBACK | other | N/A | N/A | Release mergeback; no new logic of its own. |
| 70c8e89 | 2025-04-10 | #6841 | TEST | other | N/A | N/A | Test-only change (test harness / integration or unit tests). |
| edcea54 | 2025-04-11 | #6859 | BUGFIX-correctness | core | SHOULD | PARTIAL | `!=` and `not-in` filters must not match documents where the field is null (25.1.4). Dart core/filter/field_filter.dart already requires `value.typeOrder == other.typeOrder`, so null never matches `!=`. Dart has no not-in filter at all (those queries were added in earlier chunks); when porting them, add the `!other.hasNullValue()` condition. |
| 24fba9b | 2025-04-15 | #6868 | TEST | other | N/A | N/A | Test-only change (test harness / integration or unit tests). |
| fda3351 | 2025-04-21 | #6894 | BUGFIX-crash | remote | COULD | UNKNOWN | AbstractStream.close: catch IllegalStateException from call.halfClose() when the RPC was already cancelled (25.1.4). Dart remote/datastore/base_stream.dart closes the request controller and cancels subscriptions; verify it cannot throw on a cancelled call. Size S. |
| 2491ec2 | 2025-05-01 | #6913 | MERGEBACK | other | N/A | N/A | Release mergeback; no new logic of its own. |
| 84c4d81 | 2025-07-07 | #7098 | PERF | util | MUST | NO | Final compareUtf8Strings: find first differing UTF-16 code unit; if both or neither are surrogates compare the units, else the surrogate side sorts after. No allocation (26.0.0, also fixes the 25.1.2 regression). Implement this in util/util.dart and use it for paths and map keys. Size S. |
| 1b0a574 | 2025-07-07 | #7109 | REFACTOR | util | N/A | N/A | Uses Integer/Long.compare instead of Util.compareIntegers/Longs; Dart has num.compareTo. |
| 8e1aeb6 | 2025-07-08 | #7113 | DOCS | other | N/A | N/A | Docs, changelog, javadoc, formatting or KDoc only. |
| e184a98 | 2025-07-08 | #7106 | ANDROID-ONLY | other | N/A | N/A | Removes the Kotlin KTX module. |
| 8a814e7 | 2025-07-09 | #7123 | BUILD | other | N/A | N/A | Build/CI/gradle/dependency or version bump; Android tooling only. |
| 7a35528 | 2025-07-09 | #7128 | DOCS | other | N/A | N/A | Docs, changelog, javadoc, formatting or KDoc only. |
| ca09956 | 2025-07-09 | #7119 | BUILD | other | N/A | N/A | minSdk 23. |
| 2c834ef | 2025-07-10 | #7139 | BUILD | other | N/A | N/A | Build/CI/gradle/dependency or version bump; Android tooling only. |
| e1b2c53 | 2025-07-21 | #7171 | MERGEBACK | other | N/A | N/A | Release mergeback; no new logic of its own. |
| ffad30a | 2025-08-29 | #7308 | BUILD | other | N/A | N/A | Build/CI/gradle/dependency or version bump; Android tooling only. |
| 5c7a993 | 2025-09-09 | #7301 | PERSISTENCE-schema | local | COULD | NO | Adds a nullable `document_type` column to remote_documents (schema v18), backfilled lazily, so collection scans can skip NO_DOCUMENT tombstones without parsing them (26.0.1). Dart sqlite_remote_document_cache.dart scans a whole collection and parses every row. Worth doing only if tombstone-heavy collections are a real problem; needs a migration in sqlite_schema.dart. Size M. |
| acaacbd | 2025-09-10 | #7355 | BUILD | other | N/A | N/A | Build/CI/gradle/dependency or version bump; Android tooling only. |
| 60e3bcb | 2025-09-11 | #7361 | BUILD | other | N/A | N/A | Build/CI/gradle/dependency or version bump; Android tooling only. |
| 2083b52 | 2025-09-15 | #7372 | BUILD | other | N/A | N/A | Build/CI/gradle/dependency or version bump; Android tooling only. |
| b6453e8 | 2025-09-16 | #7376 | ANDROID-ONLY | util | N/A | N/A | BackgroundQueue rewritten off Android's AsyncTask pool (26.0.2); no Dart equivalent (isolates not used for row parsing). |
| ae770aa | 2025-09-16 | #7370 | PERF | model | N/A | N/A | ObjectValue memoizes the merged proto with double-checked locking for thread safety (26.0.2). Dart ObjectValue (model/value/object_value.dart) is a different design and single-threaded. |
| e6d6e25 | 2025-09-19 | #7393 | MERGEBACK | other | N/A | N/A | Release mergeback; no new logic of its own. |
| 5e6ec19 | 2025-09-22 | #7402 | DOCS | other | N/A | N/A | Docs, changelog, javadoc, formatting or KDoc only. |
| 623acd6 | 2025-09-23 | #7405 | DOCS | other | N/A | N/A | Docs, changelog, javadoc, formatting or KDoc only. |
| 77aa34e | 2025-09-23 | #7388 | PERF | core | COULD | NO | View hoists `query.comparator()` out of loops (26.0.2). Dart core/query.dart builds a new QueryComparator each time the `comparator` getter is called, and core/view.dart calls it in loops, so the same hoist applies. Size S. |
| 482ac0e | 2025-09-23 | #7389 | PERF | core | COULD | NO | DocumentViewChangeSet uses HashMap instead of a sorted TreeMap (26.0.2). Dart core/document_view_change_set.dart uses a SplayTreeMap; View.applyChanges already re-sorts, but tests may depend on order. Size S. |
| eb8e24a | 2025-09-29 | #7418 | DOCS | other | N/A | N/A | Docs, changelog, javadoc, formatting or KDoc only. |
| 8a8298d | 2025-10-02 | #6235 | FEATURE-public-API | api | N/A | N/A | java.time.Instant support in CustomClassMapper (26.0.2); Java-only. |
| 2d91740 | 2025-10-03 | #7436 | TEST | other | N/A | N/A | Test-only change (test harness / integration or unit tests). |
| e894db1 | 2025-10-09 | #7455 | BUILD | other | N/A | N/A | Build/CI/gradle/dependency or version bump; Android tooling only. |
| 5ddcc4b | 2025-10-10 | #7465 | MERGEBACK | other | N/A | N/A | Release mergeback; no new logic of its own. |
| bb555a2 | 2025-10-30 | #7521 | TEST | other | N/A | N/A | Test-only change (test harness / integration or unit tests). |
| f9495bc | 2025-12-10 | #7593 | BUILD | other | N/A | N/A | Build/CI/gradle/dependency or version bump; Android tooling only. |
| b006a57 | 2026-01-05 | #7590 | FEATURE-public-API | api | N/A | N/A | SKIPPED BY DECISION: Firestore Pipelines (26.1.0, Enterprise edition). Very large: Pipeline/RealtimePipeline, Values.java rewritten as Values.kt, TargetOrPipeline in RemoteSerializer, View/LocalDocumentsView/SyncEngine/EventManager changes for realtime pipelines. |
| d5b66e2 | 2026-01-15 | #7634 | FEATURE-internal | core | N/A | N/A | Pipeline-conversion fix (no exists() for != / not-in). Side effect: core/OrderBy.java drops the hardAssert 'Trying to compare documents on fields that don't exist' in compare(); Dart core/order_by.dart still asserts, harmless. |
| 396ddbe | 2026-01-27 | #7659 | DOCS | other | N/A | N/A | Docs, changelog, javadoc, formatting or KDoc only. |
| 96c0bab | 2026-01-28 | #7680 | DOCS | other | N/A | N/A | Docs, changelog, javadoc, formatting or KDoc only. |
| c773b65 | 2026-01-29 | #7646 | MERGEBACK | other | N/A | N/A | Release mergeback; no new logic of its own. |
| 6404b28 | 2026-01-29 | #7669 | FEATURE-public-API | api | N/A | N/A | SKIPPED (pipelines): regexFind/regexFindAll (26.1.1). |
| 22b4053 | 2026-02-09 | #7644 | REFACTOR | api | N/A | N/A | SKIPPED (pipelines): InternalOptions made internal. |
| d7ac3fe | 2026-02-13 | #7741 | TEST | other | N/A | N/A | Pipeline test race and removal of null/nan expression helpers (26.1.1, pipelines). |
| b3cf9ab | 2026-03-02 | #7858 | MERGEBACK | other | N/A | N/A | Release mergeback; no new logic of its own. |
| 2a81fad | 2026-03-09 | #7884 | PERF | model | COULD | N/A | ObjectValue.equals compared protos with exponential cost for large/deeply nested docs; now Values.equals (26.1.2). The regression was introduced upstream after the Dart sync; Dart's own object_value.dart equality should simply be checked for deep-structure cost. Size S if needed. |
| ed4ef90 | 2026-03-10 | #7836 | FEATURE-public-API | api | N/A | N/A | SKIPPED BY DECISION: Pipelines (expressions, stages, subqueries, search, DML, window functions); changelog 26.1-27.2. |
| f4c17f8 | 2026-03-11 | #7886 | FEATURE-public-API | api | N/A | N/A | SKIPPED BY DECISION: Pipelines (expressions, stages, subqueries, search, DML, window functions); changelog 26.1-27.2. |
| 34bf169 | 2026-03-16 | #7893 | FEATURE-public-API | api | N/A | N/A | SKIPPED BY DECISION: Pipelines (expressions, stages, subqueries, search, DML, window functions); changelog 26.1-27.2. |
| 8a9beaf | 2026-03-17 | #7926 | FEATURE-public-API | api | N/A | N/A | SKIPPED BY DECISION: Pipelines (expressions, stages, subqueries, search, DML, window functions); changelog 26.1-27.2. |
| 3126a86 | 2026-03-19 | #7903 | FEATURE-public-API | api | N/A | N/A | SKIPPED BY DECISION: Pipelines (expressions, stages, subqueries, search, DML, window functions); changelog 26.1-27.2. |
| 79ae4a6 | 2026-03-19 | #7935 | BUILD | other | N/A | N/A | minSdkVersion in AndroidManifest. |
| b20ffc2 | 2026-03-23 | #7947 | MERGEBACK | other | N/A | N/A | Release mergeback; no new logic of its own. |
| d7fe251 | 2026-03-26 | #7974 | FEATURE-public-API | api | N/A | N/A | SKIPPED BY DECISION: Pipelines (expressions, stages, subqueries, search, DML, window functions); changelog 26.1-27.2. |
| 49c7512 | 2026-03-26 | #7982 | FEATURE-public-API | api | N/A | N/A | SKIPPED BY DECISION: Pipelines (expressions, stages, subqueries, search, DML, window functions); changelog 26.1-27.2. |
| df1afc1 | 2026-03-26 | #7964 | TEST | other | N/A | N/A | Test-only change (test harness / integration or unit tests). |
| afbe8b9 | 2026-03-27 | #7736 | FEATURE-public-API | api | N/A | N/A | SKIPPED BY DECISION: Pipelines (expressions, stages, subqueries, search, DML, window functions); changelog 26.1-27.2. |
| 6791661 | 2026-03-27 | #7955 | FEATURE-public-API | api | N/A | N/A | SKIPPED BY DECISION: Pipelines (expressions, stages, subqueries, search, DML, window functions); changelog 26.1-27.2. |
| 6f5d65b | 2026-03-30 | #7994 | TEST | other | N/A | N/A | Test-only change (test harness / integration or unit tests). |
| 292f9d0 | 2026-03-30 | #7987 | FEATURE-public-API | api | N/A | N/A | SKIPPED BY DECISION: Pipelines (expressions, stages, subqueries, search, DML, window functions); changelog 26.1-27.2. |
| 654f761 | 2026-03-30 | #7976 | FEATURE-public-API | api | N/A | N/A | SKIPPED BY DECISION: Pipelines (expressions, stages, subqueries, search, DML, window functions); changelog 26.1-27.2. |
| 1f5b6dd | 2026-03-31 | #7978 | FEATURE-public-API | api | N/A | N/A | SKIPPED BY DECISION: Pipelines (expressions, stages, subqueries, search, DML, window functions); changelog 26.1-27.2. |
| b77cdc3 | 2026-03-31 | #7949 | FEATURE-public-API | api | N/A | N/A | SKIPPED BY DECISION: Pipelines (expressions, stages, subqueries, search, DML, window functions); changelog 26.1-27.2. |
| 47a947e | 2026-03-31 | #7985 | FEATURE-public-API | api | N/A | N/A | SKIPPED BY DECISION: Pipelines (expressions, stages, subqueries, search, DML, window functions); changelog 26.1-27.2. |
| 3e20194 | 2026-03-31 | #7999 | FEATURE-public-API | api | N/A | N/A | SKIPPED BY DECISION: Pipelines (expressions, stages, subqueries, search, DML, window functions); changelog 26.1-27.2. |
| 619471e | 2026-04-07 | #8017 | DOCS | api | N/A | N/A | Pipeline API doc formatting (pipelines skipped). |
| 2eca2cf | 2026-04-07 | #7989 | FEATURE-public-API | api | N/A | N/A | SKIPPED BY DECISION: Pipelines (expressions, stages, subqueries, search, DML, window functions); changelog 26.1-27.2. |
| e163a9b | 2026-04-17 | #8036 | TEST | other | N/A | N/A | Test-only change (test harness / integration or unit tests). |
| b78f1c6 | 2026-04-27 | #8066 | FEATURE-public-API | api | N/A | N/A | SKIPPED BY DECISION: Pipelines (expressions, stages, subqueries, search, DML, window functions); changelog 26.1-27.2. |
| 9a6b0c0 | 2026-04-28 | #8070 | MERGEBACK | other | N/A | N/A | Release mergeback; no new logic of its own. |
| 4697d40 | 2026-05-01 | #8058 | BUGFIX-correctness | core | COULD | PARTIAL | Do not start the GC scheduler when cacheSizeBytes is CACHE_SIZE_UNLIMITED. Dart lru_garbage_collector.dart already treats unlimited as collection disabled; verify core/firestore_client.dart does not start a periodic timer anyway. Size S. |
| 032762d | 2026-05-05 | #8091 | DOCS | other | N/A | N/A | Docs, changelog, javadoc, formatting or KDoc only. |
| b965293 | 2026-05-11 | #8124 | MERGEBACK | other | N/A | N/A | Release mergeback; no new logic of its own. |
| 36b3e5b | 2026-06-09 | #8101 | FEATURE-public-API | api | SHOULD | NO | FieldValue.maximum / FieldValue.minimum (26.4.0): new FieldTransform operations (NUMERIC maximum/minimum) with local-view evaluation (NaN and mixed int/double rules) via NumericTransformOperation base class. Dart: field_value.dart, user_data_converter.dart, model/mutation/numeric_*_transform_operation.dart, remote_serializer.dart encode/decode; needs the proto sync from item 18 and confirmation the backend accepts them in production. Size M. |
| 87a563c | 2026-06-19 | #8328 | MERGEBACK | other | N/A | N/A | Release mergeback; no new logic of its own. |
| e70eaac | 2026-06-26 | #8361 | BUGFIX-crash | util | COULD | NO | Logger truncates protos over 128KB and strings over 4096 chars before formatting, to avoid OOM in debug logging of huge values (26.4.1). Dart util/util.dart/Log call toString on whole messages; relevant mainly with large documents (see items 109/114). Size S. |
| 1b8e620 | 2026-06-29 | #8370 | DOCS | other | N/A | N/A | Docs, changelog, javadoc, formatting or KDoc only. |
| f521ece | 2026-06-29 | #8362 | BUGFIX-crash | local | N/A | N/A | Reads documents over ~1MB from SQLite in SUBSTR chunks to avoid Android's CursorWindow limit (26.4.1). Android-specific; Dart's sqlite3 package has no such row limit. |
| 0726fa7 | 2026-07-09 | #8407 | MERGEBACK | other | N/A | N/A | Release mergeback; no new logic of its own. |
| 1493baa | 2026-07-13 | #8364 | FEATURE-public-API | remote | COULD | NO | Configurable gRPC flow-control window (default raised 64KB to 256KB, OkHttp only) via FirebaseFirestoreSettings/DatabaseInfo (26.5.0). Speeds large-document downloads. package:grpc exposes no such knob on ClientChannel (unverified), so likely N/A. |
| 010ed35 | 2026-07-16 | #8417 | BUILD | other | N/A | N/A | Build/CI/gradle/dependency or version bump; Android tooling only. |
| 0bb16fc | 2026-07-18 | #8448 | DOCS | other | N/A | N/A | Docs, changelog, javadoc, formatting or KDoc only. |
| bb270a6 | 2026-07-22 | #8363 | PROTOCOL-wire | remote | SHOULD | PARTIAL | Raises gRPC max inbound message size from 4MB to 17MB for 16MB documents (26.5.0/26.6.0), a production wire change (the server now returns up to 16MB documents). A grep of package:grpc 4.1.0 found no inbound size limit, so Dart likely receives them already; add a >4MB document read test against the emulator or prod. Also consider memory/logging (item 107). |
| 1b63d4a | 2026-07-24 | #8367 | TEST | other | N/A | N/A | Test-only change (test harness / integration or unit tests). |
| a0b95c2 | 2026-07-29 | #8492 | BUILD | other | N/A | N/A | Build/CI/gradle/dependency or version bump; Android tooling only. |
| 4c212cd | 2026-08-04 | #8502 | MERGEBACK | other | N/A | N/A | Release mergeback; no new logic of its own. |
| ba97c3e | 2026-08-13 | #8525 | BUILD | other | N/A | N/A | Build/CI/gradle/dependency or version bump; Android tooling only. |
| 4c28d33 | 2026-08-20 | #8546 | MERGEBACK | other | N/A | N/A | Release mergeback; no new logic of its own. |
| e83cb8f | 2026-09-09 | #8560 | BUILD | other | N/A | N/A | Build/CI/gradle/dependency or version bump; Android tooling only. |
| d7f867f | 2026-09-17 | #8580 | BUILD | other | N/A | N/A | Build/CI/gradle/dependency or version bump; Android tooling only. |
| 0955b0d | 2026-09-18 | #8607 | BUILD | other | N/A | N/A | Build/CI/gradle/dependency or version bump; Android tooling only. |
| 091ea2f | 2026-09-21 | #8622 | DOCS | other | N/A | N/A | Docs, changelog, javadoc, formatting or KDoc only. |
| 22f560e | 2026-09-21 | #8147 | FEATURE-public-API | model | SHOULD | NO | BSON types (27.0.0): MinKey, MaxKey, RegexValue, Int32Value, Decimal128Value, BsonObjectId, BsonTimestamp, Blob subtype, encoded as reserved-key maps (`__min__`,`__max__`,`__regex__`,`__oid__`,`__int__`,`__decimal128__`,`__request_timestamp__`,`__binary__`). Adds a new type-order table (min key=1 ... max key=17), index encoding and Quadruple (128-bit) arithmetic. Documents written by other SDKs containing these appear as plain maps in Dart and order differently locally. Dart: model/value/*, user_data_converter.dart, document_snapshot.dart, blob.dart. Size L; coordinate with the vector work (item 12) since type order is renumbered. The Quadruple class (1100+ lines) is optional if Decimal128 is skipped. |
| 55f9bd9 | 2026-09-22 | #8623 | TEST | other | N/A | N/A | Test-only change (test harness / integration or unit tests). |
| 0ce3737 | 2026-09-24 | #8638 | BUILD | other | N/A | N/A | Build/CI/gradle/dependency or version bump; Android tooling only. |
| 3199128 | 2026-10-08 | #8679 | MERGEBACK | other | N/A | N/A | Release mergeback; no new logic of its own. |
| 3237cbd | 2026-10-09 | #8524 | FEATURE-public-API | api | N/A | N/A | SKIPPED BY DECISION: Pipelines (expressions, stages, subqueries, search, DML, window functions); changelog 26.1-27.2. |
| a67daae | 2026-10-15 | #8705 | BUILD | other | N/A | N/A | Build/CI/gradle/dependency or version bump; Android tooling only. |
| 0bb74f5 | 2026-10-20 | #8724 | DOCS | other | N/A | N/A | Docs, changelog, javadoc, formatting or KDoc only. |
| 133a7b9 | 2026-10-21 | #8736 | DOCS | other | N/A | N/A | Docs, changelog, javadoc, formatting or KDoc only. |
| 5b34dd9 | 2026-10-23 | #8740 | MERGEBACK | other | N/A | N/A | Release mergeback; no new logic of its own. |
| ee683fe | 2026-10-23 | #8746 | DOCS | api | N/A | N/A | Javadoc updates for DocumentSnapshot / BSON classes. |
| 750d47a | 2026-10-29 | #8751 | FEATURE-public-API | api | N/A | N/A | SKIPPED BY DECISION: Pipelines (expressions, stages, subqueries, search, DML, window functions); changelog 26.1-27.2. |
| a878c85 | 2026-10-30 | #8772 | BUILD | other | N/A | N/A | Build/CI/gradle/dependency or version bump; Android tooling only. |
| 5f2d660 | 2026-11-02 | #8639 | FEATURE-public-API | api | N/A | N/A | SKIPPED BY DECISION: Pipelines (expressions, stages, subqueries, search, DML, window functions); changelog 26.1-27.2. |
| 9933767 | 2026-11-05 | #8797 | BUILD | other | N/A | N/A | Build/CI/gradle/dependency or version bump; Android tooling only. |
| 0c354bf | 2026-11-10 | #8814 | DOCS | other | N/A | N/A | Docs, changelog, javadoc, formatting or KDoc only. |
| 8aa789d | 2026-11-11 | #8821 | MERGEBACK | other | N/A | N/A | Release mergeback; no new logic of its own. |

## 4. Dependencies and ordering
- UTF-8 ordering: port 40 (84c4d81) only; 28 (a1cbf93) introduced the eager version and wired it into BasePath, Values (string values and map keys) and Util; 33 supersedes it; 40 supersedes both. 41/42 are cosmetic follow-ups. Apply 26 (numeric ids) in the same BasePath.compareSegments, since 28 later changed the string branch of that method.
- Vector (12) and BSON (124) must be designed together: 124 renumbers type order (MinKey 1, BsonTimestamp 6, ..., Vector 15, Map 16, MaxKey 17) and replaces the `MIN_VALUE`/`MAX_VALUE` internals with INTERNAL_MIN/MAX in Target.java. Doing 12 first with the 25.1.0 numbering and then 124 means touching the ordering table twice.
- 18 (proto sync) is needed before 105 (min/max transforms), and before anything from 124/pipelines that adds proto fields.
- 105 builds on the NumericTransformOperation base class and rewrites NumericIncrementTransformOperation; 124 later modifies all of them again (Int32/Decimal128 handling), so 105 and 124 touch the same classes.
- 114 (17MB message limit) pairs with 107 (log truncation) and with 109 (chunked SQLite reads); only the first two apply to Dart.
- 5 (schema v17) and 50 (schema v18) are independent; Dart's schema is separate, so do not copy the version numbers.
- 68 (Pipelines) rewrote Values.java into Values.kt and changes RemoteSerializer (TargetOrPipeline), View, SyncEngine, LocalDocumentsView; later chunk-4 changes to Values (124) are in the .kt file. 69 amends 68's query-to-pipeline conversion. All pipeline rows 73-100, 128, 134, 136 build on 68 and are skipped together.
- Cross-chunk: 59/60/55/77 optimise code that earlier chunks introduced (Comparator in View, DocumentViewChangeSet, ObjectValue partial/overlay maps); I did not verify the earlier chunks' content. 36 changes FieldFilter/NotInFilter that earlier chunks introduced (not-in). Nothing in this chunk reverts a commit in the chunk, apart from 129 (a67daae), which reverts the testFixtures change of 118 (ba97c3e).
- Items marked (unverified): the claim that nothing else reads the session token (checked by git grep at the clone's HEAD only); that package:grpc 4.1.0 has no inbound size limit (grep only); the production availability of min/max transforms.
