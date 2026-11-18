# Spike: a year offline, what grows and what it costs

> **Status.** Measured on 2026-11-18, before any fix. Items 1 and 4 of the list at the end (the query plan of the
> pending writes and the keys kept per batch) are fixed in the change that adds this document; the numbers below
> are those before the fix, and the changelog of `cloud_firestore_dart` has the ones after.
>
> **Update, 2026-11-18, later the same day.** Most of the list at the end has landed since (#58 to #68 and
> two commits without a number, see the notes at each item). **The numbers in this document are historical:
> they describe the code before those changes, and several are now wrong by orders of magnitude.** The same
> tool, `tool/bench/offline_forever_bench.dart`, was run again on the current code, on the same machine, with the
> same shapes; the numbers, and what an app should switch on, are in
> [Long offline use, measured](../guides/long_offline.md). Nothing below was rewritten.

**The answer.** Yes for writes and reads by key, no for queries as the library is today. An app on a SQLite
cache can stay offline for a year: a write costs the same 0.15 to 0.2 ms with 10 million pending writes as with
10,000, a document read by key stays at 20 to 35 us, reopening the cache takes a few milliseconds at any size, and
nothing is lost (the pending writes are never garbage collected). What does not hold is the cost of queries.
Because of one SQLite query plan, every collection query reads every pending write of the user, not only those of
its collection: a query of a collection of 10 documents takes 0.9 ms with 10,000 pending writes, 246 ms with
1 million and 1.4 to 1.5 s with 10 million (11 to 13 s for the first query after the app starts). A collection group query over many small collections multiplies that by the
number of collections (230 seconds for 10,000 collections and 100,000 pending writes). Three more costs grow badly:
an `orderBy` + `limit` query never uses a cache index while its documents have pending writes, the background
index fill blocks the client for seconds per run when a collection group has many pending writes, and a document
updated thousands of times with a `serverTimestamp` (or any transform) takes quadratic time to send once the
network is back (10,000 updates: 8 minutes against the emulator; 100,000: about 12 hours). The query and index
costs are fixable inside the library with small changes (an index and a query plan); the transform case needs a
larger one. The list, by value, is at the end.

## What was measured, and how

`tool/bench/offline_forever_bench.dart` (new). The `pending` and `hot` modes call the local store directly, as the
other benchmarks of `tool/bench/` do, because writing ten million documents through the public API holds a
future per write in memory and is not what an app does. The `drain` modes use the public API (`disableNetwork`,
writes, `enableNetwork`, `waitForPendingWrites`) against a private Firestore emulator.

- Documents: three fields (`a` = i % 100, `order` a random integer, a 200 character string), ids of 20 random
  characters like `doc()`. One `set` per batch, each in a collection picked at random, so all collections fill at
  the same pace. The remote document cache is empty: every document exists only as a mutation batch and an
  overlay.
- Shapes: collections of 1,000 (`c1k`), collections of 100,000 (`c100k`), and collections of 10 (`small`, all named
  `items` below `s/p<i>`, the shape of per-user or per-item subcollections). A collection `tiny` of 10 documents is
  written halfway through, for "a whole small collection" in the first two shapes.
- Queries: on collection `c0` for the first two shapes, on the collection group `items` for the small shape:
  `a == 7` (1 %), `orderBy('order', descending).limit(10)`, the whole small collection, the whole collection. The
  time is the median of three runs (one run when the first took more than 5 seconds).
- With `--index`: two cache indexes (`a` ascending, `order` descending) on the queried collection group, one fill
  run as the scheduler does it (50 documents), then the rest in runs of 1,000.
- The mixed case (`--ack`): every batch acknowledged (as the backend would), then one global snapshot of watch that
  sends the documents of the four queries and marks them current, as after one listen. Then the same reads.
- Conditions: one run of each, on 2026-11-18, on the Mac mini (Apple M4 Pro, 14 cores, 64 GB, macOS 27.2), Dart
  3.12.2 compiled ahead of time (`dart compile exe`; `performance.md` uses `dart run`, which adds about 300 MB of
  compiler memory and a warm-up), SQLite with `synchronous = OFF` (as the other benchmarks; an app waits for the
  disk on each commit), the database in the system temporary directory on the internal SSD. The machine was shared
  with other agents (load average 5 to 13) and up to four of these runs ran at the same time, so single numbers can
  be off by tens of percent; growth over two orders of magnitude is what the numbers show reliably. Emulator:
  cloud-firestore-emulator 1.21.0 on the same machine, Java 21, so the round trip is well under a millisecond.
- Not run: the mixed case and the cache indexes of the small shape at 10 million (acknowledging ten million
  batches takes about an hour), the small shape with 1 million documents and indexes (the first fill run took 6.5 s for 50 documents; a
  full fill would have taken hours), its collection group queries (extrapolated below), and a drain of 100,000
  updates of one document with a transform (extrapolated from 10,000 and from the local acknowledgement cost).

## Measurements

Pending writes only (never acknowledged). Times per write and per read are averages, query times medians.

### Collections of 1,000 (`c1k`)

| | 10,000 | 100,000 | 1,000,000 | 10,000,000 |
|---|---|---|---|---|
| write, writes 1,001 to 2,000 | 212 us | 294 us | 210 us | 177 us |
| write, last 1,000 | 151 us | 155 us | 211 us | 152 us |
| all writes | 2 s | 17 s | 185 s | 1,989 s |
| file size | 9.3 MB | 95 MB | 955 MB | 9.7 GB |
| resident memory after the writes | 42 MB | 79 MB | 459 MB | 3.5 GB |
| reopen | 2.2 ms | 4.4 ms | 4.1 ms | 3.3 ms |
| one document by key | 18 us | 20 us | 33 us | 22 us |
| `a == 7` on c0 (about 1,000 documents), scan | 6.3 ms | 22 ms | 258 ms | 10.9 s (first query after reopen) |
| `orderBy.limit(10)` on c0, scan | 7.7 ms | 24 ms | 256 ms | 1.6 s |
| whole `tiny` (10 documents) | 0.87 ms | 18 ms | 246 ms | 1.5 s |
| whole c0 | 6.6 ms | 22 ms | 257 ms | 1.8 s |
| `a == 7`, cache index | 0.22 ms | 0.24 ms | 0.60 ms | 3.8 ms |
| `orderBy.limit(10)`, cache index | 13.7 ms | 12.5 ms | 18 ms | 16 ms |
| index fill, one scheduled run (50 documents) | 2.6 ms | 5.1 ms | 24 ms | 287 ms |
| garbage collection run | 0.19 ms | 0.19 ms | 0.24 ms | 0.19 ms |

### Collections of 100,000 (`c100k`)

| | 10,000 | 100,000 | 1,000,000 | 10,000,000 |
|---|---|---|---|---|
| write, writes 1,001 to 2,000 | 119 us | 182 us | 175 us | 163 us |
| write, last 1,000 | 95 us | 134 us | 224 us | 131 us |
| file size | 9.3 MB | 94 MB | 943 MB | 9.5 GB |
| reopen | 0.65 ms | 2.0 ms | 3.4 ms | 2.7 ms |
| one document by key | 26 us | 30 us | 29 us | 26 us |
| documents in c0 | 10,000 | 100,000 | 99,697 | 99,513 |
| `a == 7` on c0, scan | 46 ms | 696 ms | 1,030 ms | 12.7 s (first query after reopen) |
| `orderBy.limit(10)` on c0, scan | 60 ms | 1,042 ms | 1,354 ms | 8.1 s |
| whole `tiny` (10 documents) | 0.84 ms | 17 ms | 192 ms | 1.4 s |
| whole c0 | 93 ms | 1,050 ms | 1,355 ms | 2.1 s |
| `a == 7`, cache index | 2.2 ms | 14 ms | 13 ms | 11 ms |
| `orderBy.limit(10)`, cache index | 229 ms | 3,067 ms | 3,209 ms | 2.4 s |
| index fill, one scheduled run (50 documents) | 5.4 ms | 32 ms | 124 ms | 136 ms |
| index fill, per document (runs of 1,000) | 53 us | 104 us | 182 us | 193 us |

The `orderBy.limit(10)` scan held about 150 MB more memory while it ran with an index on 100,000 documents (it reads
every document through the index, see below).

### Collections of 10 (`small`, collection group `items`)

| | 10,000 (1,000 collections) | 100,000 (10,000) | 1,000,000 (100,000) | 10,000,000 (1,000,000) |
|---|---|---|---|---|
| all writes | 1 s | 17 s | 188 s | 1,929 s |
| file size | 10 MB | 104 MB | 1,047 MB | 10.5 GB |
| reopen | 0.67 ms | 3.7 ms | 1.9 ms | 1.5 ms |
| one document by key | 25 us | 23 us | 25 us | 19 us |
| whole small collection (10 documents) | 1.0 ms | 19 ms | 162 ms | 10.5 s (first query after reopen, one run) |
| collection group `a == 7`, scan | 1.0 s | 230 s | not run (about 5 hours) | not run |
| collection group `orderBy.limit(10)`, scan | 1.3 s | 229 s | not run | not run |
| collection group `a == 7`, cache index | 47 ms | 508 ms | not run | not run |
| collection group `orderBy.limit(10)`, cache index | 248 ms | 3.5 s | not run | not run |
| index fill, one scheduled run (50 documents) | 95 ms | 822 ms | 6.5 s | not run |
| index fill, per document (runs of 1,000) | 147 us | 902 us | not run | not run |

### The mixed case: the same documents acknowledged, the queries in sync once, read offline

| | c1k 10,000 | c1k 100,000 | c1k 1,000,000 | c100k 100,000 | c100k 1,000,000 | small 100,000 | small 1,000,000 |
|---|---|---|---|---|---|---|---|
| acknowledgement, average | 419 us | 386 us | 346 us | 328 us | 329 us | 308 us | 330 us |
| one document by key | 44 us | 36 us | 31 us | 40 us | 49 us | 29 us | 29 us |
| `a == 7` | 0.31 ms | 0.28 ms | 0.19 ms | 12 ms | 9.2 ms | 451 ms (group) | not run |
| `orderBy.limit(10)` | 0.30 ms | 0.26 ms | 0.19 ms | 0.25 ms | 0.18 ms | 465 ms (group) | not run |
| whole small collection | 0.13 ms | 0.12 ms | 0.09 ms | 0.10 ms | 0.07 ms | 0.11 ms | 0.08 ms |
| whole collection c0 | 7.2 ms | 5.7 ms | 4.1 ms | 894 ms | 876 ms | | |
| garbage collection run (threshold 1 byte) | 44 ms | 335 ms | 6.5 s | 82 ms | 6.2 s | 122 ms | 1.2 s |

### One document updated many times (`hot`)

| | 10,000 updates | 100,000 updates | 10,000 with `serverTimestamp` | 100,000 with `serverTimestamp` |
|---|---|---|---|---|
| update, last 1,000 | 98 us | 103 us | 107 us | 111 us |
| file size | 4.6 MB | 23 MB | 4.9 MB | 24 MB |
| reopen | 0.75 ms | 1.4 ms | 0.75 ms | 1.6 ms |
| read the document | 15 us | 15 us | 17 us | 16 us |
| query its collection | 0.05 ms | 0.05 ms | 0.05 ms | 0.05 ms |
| reject the newest write | 65 ms | 733 ms | 73 ms | 749 ms |
| acknowledge one write (local store) | 0.17 ms | 0.17 ms | 77 ms | 900 ms |

### Reconnecting (public API, private emulator)

| | writes offline | drain (`enableNetwork` until `waitForPendingWrites`) | per write |
|---|---|---|---|
| 1,000 documents | 124 us | 1.9 s (includes the first connection) | 1.9 ms |
| 10,000 documents | 135 us | 4.2 s | 0.42 ms |
| 100,000 documents | 167 us | 40 s | 0.40 ms |
| one document, 10,000 updates | 160 us | 5.1 s | 0.51 ms |
| one document, 100,000 updates | 145 us | 261 s | 2.6 ms |
| one document, 10,000 updates with `serverTimestamp` | 189 us | 493 s | 49 ms |
| one document, 100,000 updates with `serverTimestamp` | | not run: about 12 hours (see below) | |

## Where the cost goes, and how it grows

File and line references are to `cloud_firestore/cloud_firestore_dart/lib/src/firebase/firestore/`.

### A local write: constant

`LocalStore.writeLocally` (`local/local_store.dart:355`) reads the remote documents and overlays of the written
keys by primary key (`:363`, `:373`), appends one batch to the mutation queue (`:399`,
`local/sqlite/sqlite_mutation_queue.dart:221`: one row in `mutations`, one per key in `document_mutations`, the
collection parent cached in memory, `local/sqlite/sqlite_index_manager.dart:125`) and writes one overlay per key
(`local/sqlite/sqlite_document_overlay_cache.dart:94`). All are B-tree inserts, logarithmic in the size of the
tables; measured, flat from 10,000 to 10 million pending writes (160 to 220 us, without the disk wait).

Two things grow with every write and are not on disk:

- **Memory, linear in the writes of one session.** `writeLocally` keeps the keys of every batch in
  `_documentKeysByBatchId` (`local/local_store.dart:404`), which is documented as multi-client only
  (`:213`) but is filled in every client and emptied only for batches that other clients wrote
  (`core/sync_engine.dart:1327`). Measured: about 0.45 KB per write (459 MB after 1 million writes, 3.5 GB after
  10 million). With the bench dropping the entries after each write (`--forget-batch-keys`, which calls
  `removeCachedMutationBatchMetadata`), 300,000 writes ended at 24 MB instead of 105 MB (on the laptop). It is
  freed by a restart, so it matters only for long sessions. Through the public API each pending write also holds
  its future until it is acknowledged (`core/sync_engine.dart:421`), which is unavoidable.
- **The file, linear in the pending writes:** about 0.95 KB per pending document with a 200 character field (the
  batch and the overlay each hold the whole document, plus three indexes). Garbage collection cannot remove any of
  it (below), so `cacheSizeBytes` does not bound it.

### A query from the cache: linear in all pending writes of the user, not in the collection

The query engine (`local/default_query_engine.dart:87`) tries a cache index, then the previous result, then a scan.

- **The previous result never applies**: it needs `lastLimboFreeSnapshotVersion`, which only a query that was in
  sync with the backend has (`local/default_query_engine.dart:257`).
- **The scan** (`local/local_documents_view.dart:439`) reads the overlays of the collection with
  `getOverlaysForCollection` (`local/sqlite/sqlite_document_overlay_cache.dart:155`):
  `WHERE uid = ? AND collection_path = ? AND largest_batch_id > ?`, with -1 for a scan. SQLite has two candidate
  indexes, the primary key `(uid, collection_path, document_id)` and `batch_id_overlay (uid, largest_batch_id)`
  (`local/sqlite/sqlite_schema.dart:663`), and without statistics it picks `batch_id_overlay` with the range
  `largest_batch_id > -1`, which is every overlay of the user (`EXPLAIN QUERY PLAN` on a copy of the schema shows
  it; reading one collection of about 1,000 among 100,000 overlays took 10.6 ms that way and 1.2 ms when forced
  onto the primary key). So every collection query visits every pending write and decodes those of its
  collection. Measured on a collection of 10: 0.9 ms, 18 ms, 246 ms, 1.4 to 1.5 s for 10 thousand, 100 thousand, 1
  million and 10 million pending writes: linear in the queue, 0.15 to 0.25 us per pending write. With 10 million
  the first query after a reopen took 11 to 13 seconds, while the 9.7 GB file was read into the page cache of the
  system; the machine had the memory to keep it there, a phone would not.
- **A collection group query** runs one collection query per parent collection
  (`local/local_documents_view.dart:402`, parents from `collection_parents`,
  `local/sqlite/sqlite_index_manager.dart:142`), so it costs collections times pending writes: quadratic when the
  documents are spread over small collections. 1,000 collections and 10,000 writes: 1 s; 10,000 and 100,000: 230 s;
  100,000 and 1 million would be about 100,000 x 0.16 s, 4 to 5 hours, so it was not run.
- **The limit is applied after the scan** (the engine returns every match, the view keeps 10), so
  `orderBy.limit(10)` costs the same as the whole collection.

**Cache indexes do cover documents that exist only as overlays.** The fill (`local/index_backfiller.dart:62`) asks
`getNextDocuments` (`local/local_documents_view.dart:221`), which, once there are no remote documents left after
the index offset, returns the overlays of the collection group in batch id order
(`local/sqlite/sqlite_document_overlay_cache.dart:175`); the offset then carries the largest batch id, and a query
reads only the overlays of newer batches separately (`local/local_documents_view.dart:447`). Measured: `a == 7`
drops from 258 ms to 0.6 ms at 1 million, and one newer write costs nothing visible. But:

- **A limit query never uses the index while the edge document has a pending write.** `_needsRefill` returns true
  when the document at the edge of the limit `hasPendingWrites` (`local/default_query_engine.dart:350`), and the
  index plan then runs again without the limit (`:204`): every matching document is read through the index and
  decoded. With only pending writes that is always the case, so `orderBy.limit(10)` with an index is slower than
  the scan (3.2 s against 1.35 s on 100,000 documents, plus 150 MB). The same rule makes the previous result
  useless in the mixed case until watch has sent the documents again, because an acknowledged document keeps
  `hasCommittedMutations` until then.
- **Each fill run reads all later pending writes of the user, of every collection.**
  `getOverlaysForCollectionGroup` filters on `collection_group` and `largest_batch_id > ?` and orders by
  `largest_batch_id, collection_path, document_id`; the only indexes are `(uid, largest_batch_id)` and
  `(uid, collection_group)`, and SQLite walks `(uid, largest_batch_id)` from the offset over the overlays of every
  collection, keeps those of the group and sorts them in a temporary B-tree, whatever the limit of 50. One scheduled
  run, on the client's queue once a minute: 95 ms, 822 ms and 6.5 s for a group of 10 thousand, 100 thousand and 1
  million pending writes (small shape); 287 ms for a group of only 937 documents among 10 million pending writes
  (`c1k`). A complete fill is quadratic: 902 us per document at 100,000 in the small shape, 9.1 ms per document for
  the 937 documents of `c0` at 10 million, hours for a large group at 1 million. While a run is going, every read
  and write of the instance waits.
- Not measured but the same mechanism: a write after the fill is read as a newer overlay until a fill run passes
  it, so an app that keeps writing while offline keeps paying for the fill every minute.

### A document read: constant

`LocalDocumentsView.getDocument` (`local/local_documents_view.dart:63`) reads the overlay by primary key and skips the
remote document for a set or delete overlay (`:526`). 18 to 33 us at every scale, also for a document with 100,000
pending updates (the overlay is one row, whatever the number of batches).

### Reopening: constant

`LocalStore.start` (`local/local_store.dart:224`) checks the overlay migration flag, loads the index configuration
and reads `MAX(batch_id)` per user (`local/sqlite/sqlite_mutation_queue.dart:76`). Nothing reads the queue or the
overlays: 2 to 4 ms at 1 million, 2.7 to 3.3 ms at 10 million. Not measured: a user change (sign-in or sign-out) decodes
the whole queue of both users and computes every changed document (`local/local_store.dart:298` and `:348`), linear
in the queue.

### Garbage collection with only pending writes: nothing to do, forever

A run (`local/lru_garbage_collector.dart:65`) compares the file size with the threshold; above it, it counts and
removes documents that only a sentinel row holds (`local/sqlite/sqlite_lru_reference_delegate.dart:75`, `:188`).
Pending documents have no sentinel (one is written when a batch is acknowledged,
`local/sqlite/sqlite_lru_reference_delegate.dart:144`) and are pinned by `document_mutations` anyway (`:149`). So a
run costs 0.2 ms and removes nothing at every scale; once the file is over 100 MB the run repeats every five
minutes without ever bringing it below. In the mixed case the acknowledged documents that no query holds become
collectable, and a run costs time linear in the cached documents (6.2 to 6.5 s at 1 million, every five minutes,
on the client's queue): that is the normal LRU cost, not specific to being offline.

### Reconnecting: linear in the queue, with one quadratic case

- **Sending.** The remote store keeps at most 10 batches in flight (`remote/remote_store.dart:213`) and refills the
  pipeline after each acknowledgement with one `getNextMutationBatch` (`:956`, an indexed `LIMIT 1`,
  `local/sqlite/sqlite_mutation_queue.dart:303`). Each batch is one write on the stream; there is no merging.
- **Each acknowledgement** (`local/local_store.dart:456`) writes the documents of the batch into the remote cache
  (`:1165`), deletes the batch and its index rows and writes a sentinel
  (`local/sqlite/sqlite_mutation_queue.dart:498`), deletes the overlays of that batch id through
  `(uid, largest_batch_id)`, and returns the local view of the batch's documents. All by key: constant, 0.3 to 0.4
  ms at every queue length. `performConsistencyCheck` (`local/sqlite/sqlite_mutation_queue.dart:545`) scans
  `document_mutations` only when the queue becomes empty.
- **The quadratic case: transforms on a document with many pending writes.** For every document whose mutation
  had transform results (`serverTimestamp`, `increment`, array unions), the acknowledgement recalculates the
  overlay (`local/local_store.dart:468`, `:510`), which reads and decodes every pending batch that touches the
  document (`local/local_documents_view.dart:282`,
  `local/sqlite/sqlite_mutation_queue.dart:383`). The acknowledgement of each of U pending updates of one document
  then costs O(U), the whole drain O(U squared): 77 ms per acknowledgement with 10,000 pending (8 minutes to drain
  against the emulator, against 5 seconds without the transform), 900 ms with 100,000 (about 100,000 x 0.45 s,
  12 hours, for one document). A rejected write (`local/local_store.dart:477`) always recalculates, so it costs the
  same O(U) (733 ms at 100,000), and so does the first remote event that changes the existence of such a document
  (`local/local_documents_view.dart:169`).
- **The hot document without transforms** costs 0.17 ms per acknowledgement locally at any count, but the drain
  against the emulator slowed from 0.5 ms to 2.6 ms per write between 10,000 and 100,000 updates: that growth is in
  the emulator, not in the client. The production backend also limits sustained writes to one document (about one
  per second), which was not measured.
- **Extrapolating a year.** With a local backend the drain runs at 2,500 writes a second (0.4 ms each). Against
  production it is bounded by the 10 batches in flight: with a 50 ms round trip, at most 200 writes a second, so
  100,000 pending writes take about 8 minutes and 1 million about 1.4 hours, during which the app works normally
  but the queue (and with it the query cost above) shrinks only at that rate.

## What the growth looks like

| Cost | Grows with | Measured from the smallest to the largest scale |
|---|---|---|
| a local write | constant (log of the tables) | 0.15 to 0.22 ms |
| memory of a session | linear in the writes of that session | 0.45 KB per write |
| file size | linear in pending documents, never collected | 0.95 KB per document |
| reopen | constant | 1 to 4 ms |
| read by key | constant | 15 to 35 us |
| any collection query | linear in all pending writes of the user, plus the collection | 10 documents: 0.9 ms to 1.4 to 1.5 s |
| collection group query over small collections | collections x pending writes (quadratic) | 1 s to 230 s (100x the data) |
| `orderBy.limit` with pending writes | the whole collection, even with an index | 3.2 s on 100,000 |
| `==` filter with an index | the result | 0.2 to 14 ms |
| one index fill run | pending writes after the index offset, in all collections | 2.6 ms to 6.5 s |
| a complete index fill | quadratic in pending writes | 36 us to 9.1 ms per document |
| garbage collection, pending only | constant, removes nothing | 0.2 ms |
| an acknowledgement | constant | 0.3 to 0.4 ms |
| an acknowledgement with a transform | batches pending on the same document | 77 ms to 900 ms |
| a rejection | batches pending on the same document | 65 ms to 733 ms |
| a drain | linear, bounded by 10 in flight; quadratic per hot document with transforms | 0.4 ms per write locally |

## What would lift each limit, by value

1. **Read the overlays of a collection through the primary key** (`sqlite_document_overlay_cache.dart:155`): add an
   index `(uid, collection_path, largest_batch_id)`, or write the condition so that `batch_id_overlay` cannot be
   used for a scan (`largest_batch_id > ?` only when the offset is not -1, or `+largest_batch_id`), or run
   `ANALYZE` once. This removes the "every pending write" term from every collection query (246 ms to about 1 ms for
   a small collection at 1 million) and turns the collection group case from quadratic into linear. Likewise an
   index `(uid, collection_group, largest_batch_id)` makes one fill run read 50 rows instead of sorting the group
   (6.5 s to milliseconds) and the full fill linear. The Android SDK creates the same two overlay indexes (`SQLiteSchema.java:713`), so
   it probably has the same plan; worth a look before choosing the fix.
   > **Landed** in #58 (and #68, which reads the newest pending writes of a collection through the batch id index again,
   > after #58 made an indexed query read every overlay of the collection): a unary `+` keeps the read of a collection on the primary key, and schema 20 adds
   > `(uid, collection_group, largest_batch_id)` for the index fill (built once on open, about 1 s for 1,000,000
   > pending writes). A fill over many small collections was also made cheaper in #65. The collection group
   > case is no longer quadratic in the overlay reads, but it is still one query per parent collection.
2. **Let a limit query use an index when the edge document's pending write is already in the index**
   (`default_query_engine.dart:350`): the overlay's batch id is at or below the index offset, so its indexed
   values are current. Then `orderBy.limit(10)` on 100,000 pending documents reads 10 documents instead of all.
   > **Landed** in #59: a limit query is served from the index when the pending writes at the edge are already in it.
3. **Acknowledgements with transforms on a document with many pending writes**: recalculate the overlay from the
   remote document plus the remaining batches only when the acknowledged batch is the last one touching the
   document, or keep the transform results and patch the stored overlay instead of replaying the queue
   (`local_store.dart:468`, `local_documents_view.dart:282`). The cheaper alternatives, for an app: avoid
   `serverTimestamp` on a document that is updated thousands of times offline, or let the library squash
   consecutive single-document batches while offline (this changes what the backend sees: one write instead of
   thousands, and security rules evaluated once).
   > **Landed**: acknowledgements recalculate the overlay from a summary of the remaining writes (#62), and
   > `mergeUnsentWrites` (#63, with `serverTimestamp`, `increment` and array transforms in #64, and the merge of a queue
   > that already exists at start in `e6bef0a1` and `a72fa833`) squashes the repeated writes of a document, as
   > the last alternative of this item proposed. It is opt-in and changes what the backend sees.
4. **Empty `_documentKeysByBatchId` in a single client** (`local_store.dart:404`), as JS does when a batch is
   acknowledged or rejected: removes the 0.45 KB per write of a long session.
   > **Landed** in #58: the local store forgets the keys of a batch when it is acknowledged or rejected.
5. **Collection group queries over many parents**: one query on the overlays by `collection_group` (the column
   exists) instead of one per parent (`local_documents_view.dart:402`). After item 1 this is still one SQL query per
   parent collection, linear in the number of collections.
   > **Not landed as described**: still one read per parent collection. The cost per parent fell with #58, and
   > #65 made the index fill over many small collections cheaper.
6. **The file**: each pending document is stored twice (batch and overlay). Nothing in the library can collect
   pending writes; an app that expects years offline should budget about 1 KB per pending document plus its
   payload, or acknowledge them through a backend. Not worth changing the format for.
   > **Not changed.** The file still grows by about 1 KB per pending document; `mergeUnsentWrites` (#63) removes
   > the writes that repeat a document, not the ones to different documents.
7. **A user change** decodes the whole queue (`local_store.dart:298`): linear, not measured, only on sign-in and
   sign-out.
   > **Not changed**, and still not measured.
