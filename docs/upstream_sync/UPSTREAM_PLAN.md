# Upstream sync plan for cloud_firestore_dart

## Status at the end of the revival

Updated 2026-11-13 at `main` (`606a73c`). The port was at `576da00e85` (2019-07-23); behaviour has now been brought forward to
roughly the current upstream `main` (checked against a clone whose `main` was at `51b35e869`, 2026-11-11), for the
items marked done. Everything is ported in Dart, not copied, and verified with unit tests, the shared spec tests and
the local emulator. Against production Firestore only the production verification kit (`tool/verify_production`)
was run, on a Standard edition database: in its latest run 13 of its 15 checks passed and 2 were skipped, and an
earlier run found one bug of the SDK (-0.0 read over the web transport lost its sign), since fixed; the results are in
[`tool/verify_production/README.md`](../../tool/verify_production/README.md). The integration suite was not run
against production, and the Enterprise edition features were run against the emulator in Enterprise edition only. The per-commit tables below are the original triage and were not
rewritten; the table here is the current state.

| Plan item | State |
|---|---|
| Wave 0: proto resync | done |
| Wave 1: correctness fixes (applyRemoteEvent, transaction precondition, empty-cache initial snapshot, UTF-8 ordering, pending server timestamp type order, limbo dequeue/throttle, existence-filter mismatch, late credential change, small fixes, listen order, local mutation version NONE) | done as merged waves (core-fixes, remote-fixes, model-fixes, local-mutation-version, chunks123-small); not every sub-row re-verified individually |
| Wave 2: keepalive, idle timeout, App Check header, `x-goog-request-params` | done (keepalive, 1 minute idle, App Check plumbing; App Check enforcement untestable on the emulator). BatchGetDocuments logical termination: done (`TransactionClient.lookup` completes once every key is answered, unit tested). Reads of more than 4 MB in one response: integration test `transport_limits_test.dart` (12 documents near 1 MiB, every transport); single documents above 1 MiB need production (`large_document_test.dart`) |
| Wave 3: `!=` / `not-in`, update_transforms (TransformMutation removed), count/sum/avg, waitForPendingWrites, terminate, snapshotsInSync, transaction backoff and `TransactionOptions`, limitToLast, min/max transforms | done |
| Wave 4: bundles and named queries, OR queries / multiple inequality filters / Query-Target split, bloom filters, vector values | done |
| Wave 4: index-free queries (read time on remote documents, upstream 21.3.0) | done (SQLite schema 10; `2f53c69`) |
| Wave 4: document overlays (upstream 24.0.0) | done (SQLite schema 11, with a migration that builds the overlays from existing mutation queues; `2f53c69`) |
| Wave 4: client-side index engine, auto-indexing | done: index value encoding, `FieldIndex` model and configuration parsing (`ab398b4`), target index bounds and `TargetIndexMatcher` (`6a7c99c`), SQLite schema 12 and 13 with the index manager (`b8fc0ab`), the backfiller and the three-step query engine (`8cff87f`), and the public API `setIndexConfiguration` / `PersistentCacheIndexManager` with automatic index creation (`994df46`). Schema 14 adds two lookup indexes of the port's own (`c4958ab`). SQLite persistence only; the index entries differ from Android's in two places where its encoding returns wrong results (see `docs/ARCHITECTURE.md`) |
| BSON value types | done (`9709a29`, `c9ade8d`); Enterprise edition emulator only |
| Read-only transactions | done, and beyond the client SDKs: `TransactionOptions.readOnly` runs a read-only transaction of the backend (`BeginTransaction`, reads with its id, `Rollback`), with queries, aggregations and an optional read time (`d97ff59`). The Android and JS client SDKs have no such mode; emulator-verified only |
| Verify documents read in a transaction (upstream ef38ef7) | done (`58674f9`) |
| Persistence clearing | done (`Firestore.clearPersistence()` on a terminated instance; `ee0ee5b`) |
| Pipelines | preview, in a separate library (`99f3706`, `02444ca`, `5d732eb`): server-executed only, Enterprise edition emulator only. Search, window functions, local evaluation and real-time pipelines are not done |
| Web | not part of the Android plan; experimental. The RPCs are behind a transport interface (`76f975a`, `41e9b46`); the web transport is REST for unary calls and a WebChannel client over `fetch` for the streams (`6d95cf5`), hardened with long polling, timeouts, retransmission and session cleanup (`9d7d257`, `9fafdc2`), and there is an opt-in persistent cache, SQLite as WebAssembly on IndexedDB (`e10c909`, `e17faf9`, `606a73c`). 54 browser tests in Chrome (53 pass and 1 is skipped with each compiler, per [platforms](../guides/platforms.md)) and the standard integration suite on the VM over the web transport, against the emulator. Chrome only; no browser was run against a production backend (the production verification kit used the web transport against production from the VM) |
| Firestore Lite | not part of the Android plan; experimental (`b184f30`): a second library without cache and listeners, as `firebase/firestore/lite` of the JS SDK, over gRPC on the VM and REST on the web |
| Kotlin/ktx, Android-only | skipped by design |

Not from upstream, found while testing:

- The client no longer resets a call that the backend may be finishing (`5174ba2`, `5497721`), because
  `package:http2` then terminated the whole connection and a transaction commit that had been applied could be retried.
- The transport connector fails the reconnect that follows a connection lost before any call started (`dd2668d`),
  because `package:grpc` otherwise reconnects about 43 times per second to a peer that accepts and closes.
- Local filter and transform evaluation follows the backend where upstream does not (`eec6cf2`), a limbo document
  that the backend confirms but does not match is dropped from the view (`4c72e9e`), and an acknowledged write with
  an unchanged version is applied to the cache (`36f35e3`). These are deliberate deviations; `docs/ARCHITECTURE.md`
  lists them with their tests.
- A built-in connectivity change detector for the VM (`ea747eb`), in place of Android's network callback.

A production verification kit exists (`tool/verify_production`, `36f35e3`). It was run against a real Standard
edition database: 13 of its 15 checks passed and 2 were skipped (one needs an Enterprise edition database, the other a
Web API key); see [`tool/verify_production/README.md`](../../tool/verify_production/README.md) for each result and for
the two checks that fail on the emulators because of the emulators.

Still open from the original "Open / unverified" list: `0eaca5e` (`useEmulator`) is covered by
`FirestoreSettings.withEmulator` but not compared line by line; the inbound message size question is answered: package:grpc (5.2.0) has no limit on a response message (`GrpcHttpDecoder` allocates what the length prefix says), so the 17 MiB of Android and JS is not needed; it is not enforced either.

---

Baseline: the port last synced with firebase-android-sdk commit `576da00e85` (2019-07-23).
707 commits touched `firebase-firestore` since; 706 analysed (the sync-point commit itself is skipped).
Sources: `analysis_0.md` .. `analysis_4.md` (one per chunk, full tables) in this directory.

## Totals across the five chunks

| Relevance | Commits |
|---|---|
| MUST | 19 (about 14 distinct items; several are one change split over commits or superseded) |
| SHOULD | 68 |
| COULD | 150 |
| N/A (Android-only, build, docs, mergebacks, Pipelines) | 469 |

## How much to trust this

- Agents triaged most rows by subject and only read the diffs of non-trivial `src/main` changes; rows they did not read are marked (unverified) in the analysis files.
- "In Dart?" answers come from grep, not from running anything.
- Checked by me directly in the Dart tree: the regenerated protos do NOT contain NOT_EQUAL / NOT_IN / update_transforms / composite OR / RunAggregationQuery; `local_store.dart` applyRemoteEvent still has the pre-fix condition (about lines 377-381); `BasePath.compareTo` uses UTF-16 `String.compareTo`; `sync_engine.dart` has no enqueued-limbo queue or limbo throttle.
- One MUST row was WRONG and is corrected here: chunk 3's `42a6951` ("GC can loop forever"). That bug lives in Android's *batched* `removeOrphanedDocuments` (LIMIT loop re-selecting pinned rows). Dart's version is the older single-query, single-pass one and cannot loop. Downgraded to COULD: Dart loads every orphan path at once (memory/latency on huge caches); if batching is ever added it must page with `path > ?`.

## Dependency order

```
Wave 0  proto resync  ──────────────►  Wave 3 features needing new messages
Wave 1  independent correctness fixes (can start now, in parallel)
Wave 2  production readiness (headers, keepalive, App Check)
Wave 4  big optional epics (each needs schema migrations)
```

### Wave 0: prerequisite

0. **Resync protos** with current googleapis `google/firestore/v1` and the Android cache protos
   (`firebase/firestore/proto/{target,mutation,maybe_document}`). Use `tool/gen_protos.sh`
   (protoc_plugin pinned at 21.1.2; the Homebrew protoc is broken, see the script). Commits f5ac43c, 42c8d72, 924aaa2, df6a201, 60a5e4c.
   Size M. Blocks: NOT_EQUAL/NOT_IN, update_transforms, count/sum/avg, OR, bloom filters, min/max transforms.

### Wave 1: correctness fixes (no new protos), do first

| # | Fix | Upstream | Dart files | Size |
|---|---|---|---|---|
| 1 | applyRemoteEvent: a manufactured NoDocument(NONE) from a failed limbo resolution must REMOVE the doc, check it FIRST; other docs only written when strictly newer or equal-with-pending-writes. Port as one change. | a96334f, 5e06078, a1d363b | local/local_store.dart | S |
| 2 | Transaction write to a doc read as missing: use Precondition.exists(false), not updateTime(NONE); ALREADY_EXISTS retryable | a0fcca1 | core/transaction.dart, core/sync_engine.dart | S |
| 3 | Initial snapshot must be raised from an EMPTY local cache result for a previously synced target (ViewSnapshot.hasCachedResults + resume token threading) | 6498bd0 | core/query_stream.dart, view.dart, view_snapshot.dart, sync_engine.dart, remote/target_change.dart | S-M |
| 4 | UTF-8 byte-order string comparison for paths and map keys. Port ONLY the final algorithm (84c4d81); a1cbf93 and ec26a52 are superseded. Plus numeric `__id<n>__` segment ordering. | 84c4d81 (+ chunk 4 item 26) | util/util.dart, model/base_path.dart, model/value/* | S |
| 5 | Pending server timestamp needs its own type order (between timestamp and string) | 5db2238 | model/value/server_timestamp_value.dart | S |
| 6 | Limbo: dequeue enqueued limbo resolutions when their query stops (fixes get() never completing); throttle to max 100 concurrent limbo listens | c9fefbe, ef455a6 | core/sync_engine.dart | M |
| 7 | Existence-filter mismatch must clear resume token and last-limbo-free version (Dart has targetMismatches but never uses it) | 618b08c | local/local_store.dart | M |
| 8 | Credential change before client init finishes (late syncEngine); retry getToken on invalidation instead of failing ABORTED | 0213e1e, 58e83e6 | core/firestore_client.dart, auth/firebase_auth_credentials_provider.dart | S-M |
| 9 | Small fixes: DocumentSnapshot equality compares data not doc state (080e1fc); no nested server-timestamp previous values (c989076); DatabaseId/DocumentKey fromName length asserts (b5d06cd); int and nested map equality (55e6921); drop client-side null/NaN filter restrictions (1dc2837; changes the integration test `queriesWithNullOrNaNFiltersOtherThanEqualityFail`) | as listed | model/*, core/filter/field_filter.dart, document_snapshot.dart | S each |
| 10 | remote listen order (upstream sends it first, Dart last) | 055df3e | core/sync_engine.dart | S |
| 11 | Local delete keeps the document version instead of NONE (behaviour change; verify with spec tests first, depends on the MutableDocument refactor) | 9b67604, 979000c | model/mutation | M, risky |

Also worth doing here, from our own findings (not upstream): lazy `hardAssert` messages (measured ~25% of key construction time), and re-checking the one flaky integration test.

### Wave 2: production readiness

- `x-goog-request-params` header (624be9c): remote/datastore/channel_options_provider.dart. S
- gRPC keepalive and idle handling (our gap analysis; no upstream commit). S
- App Check token provider and `X-Firebase-AppCheck` header (3e5cd47; an earlier revert/re-add nets to nothing). M, needs an App Check interop piece. Projects that enforce App Check reject the client until this exists.
- BatchGetDocuments logical termination (b564bee), `TransactionOptions(maxAttempts)` (672c6dc). S each.
- Large documents: add a >4MB read test; truncate large logged values (chunk 4 item 107).

### Wave 3: features (after Wave 0)

| Feature | Upstream | Size | Notes |
|---|---|---|---|
| `!=` and `not-in` operators | 924aaa2, 1ee3caa, 2d829f3, 6879f54 (21.7.0) | M-L | also change query validation, serializer, Query API |
| Transforms folded into set/patch writes (`update_transforms`) | df6a201, d40e7f1 (22.0.2) | L | deletes TransformMutation; LocalSerializer must squash legacy stored transform writes; needs cache proto resync |
| count() via RunAggregationQuery, then sum/avg | a50da9f, f2e4bd0, a4a9625, 26de539, abfa774, ffdee32 | M | new AggregateQuery/Snapshot/Source types; add to api_modernization_plan.md |
| waitForPendingWrites, terminate, addSnapshotsInSyncListener, transaction retry with backoff, VerifyMutation | release notes 21.1.0-21.2.0 | M each | `Write.verify` needed |
| limitToLast | 2827026 and 21.3.1 | L | needs the Query/Target split and schema v11 (canonical_id rewrite, d644fd6) |
| min/max field-value transforms | chunk 4 item 105 | M | production support unverified |

### Wave 4: large optional epics (each needs a schema migration)

Dart's SQLite schema is at **v8**. Upstream is far beyond it.
- **v9** `read_time_seconds/nanos` on remote_documents + drop the limbo-free snapshot version; goes with index-free queries (47def6d). Index-free is performance only.
- **v10** clears data hit by the 21.1.0 "read time of zero" regression; only relevant if v9 is ported.
- **v11** rewrites `canonical_id` in `targets` (d644fd6); only if the Query/Target split is ported.
- Bundles and named queries (6ce7880 and others, 22.1.0-23.0.3): new tables. L.
- OR queries, DNF rewrite, multiple inequality filters (8d99ce0, c5a894c; groundwork in chunks 0-2): L. Needs the Query/Target split.
- Bloom-filter resume optimisation (c83d5e5, a014114): L. Not needed for correctness; cuts reads on reconnect.
- Client-side index engine, overlays, persistent-cache auto-indexing, schema 16+ (about 60 commits in chunk 2 plus chunk 3): one XL epic. Optional.
- Vector values and BSON-style value types (chunk 4 items 12 and 124): M-L; local ordering differs from the server until done.

### Skip
Pipelines (about 35 commits), Kotlin/ktx, Android connectivity/SSL/Robolectric, build and CI.

## Open / unverified

- 6d360f0 (arrays in IN values), 0eaca5e (`useEmulator`), 751684d (inhibitBackoff on connectivity change), 1e44257 and 3d88f62: not checked end to end.
- Exact release versions for some features (changelog layout ambiguous).
- Any row an agent marked (unverified) in its analysis file.
- A few "UNKNOWN" rows in chunk 1 are now resolved: the protos lack NOT_EQUAL/NOT_IN and update_transforms.
