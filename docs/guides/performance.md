# Performance and cache tuning

This page lets you predict what a read, a listener or a write costs in `cloud_firestore_dart`, and choose the
settings that keep it small: how the client answers a query from its cache, when persistent cache indexes help,
how large the cache may grow and how garbage collection keeps it there, how listeners are shared, and when to
use counts, batches, bundles, `Source.cache` or the Lite library instead. Each section says what the client
does (from the source, file names relative to `cloud_firestore/cloud_firestore_dart/lib/src/firebase/firestore/`)
and then what to do.

The runnable examples are in
[`example/performance/`](../../cloud_firestore/cloud_firestore_dart/example/performance/):

| File | Shows |
|---|---|
| `cache_vs_server.dart` | One query timed from the server and from the cache, with each kind of cache; a second listener on the same query. |
| `cache_index_inspection.dart` | Automatic cache indexes: which plan a cache query took, when an index was created, the background fill, a configured index. |
| `cache_size_and_gc.dart` | A 1 MB cache threshold, and what the first garbage collection run removes. |
| `bundle_first_paint.dart` | A bundle made from a query snapshot, loaded into an empty cache for the first screen. |

```sh
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run example/performance/cache_vs_server.dart
```

## About the numbers

Every number on this page is one measurement, not a benchmark result you can rely on: one run, on one machine,
with no repetition across days. Unless a line says otherwise it was taken on 2026-11-15 on an Apple M5 with
32 GB of memory, macOS 27.2, Dart 3.12.2 (JIT, `dart run`), with the benchmarks of `tool/bench/` in the
repository. These benchmarks call the local store directly, without a backend, and run SQLite with
`synchronous = OFF` (commits do not wait for the disk) so that runs are comparable; a real app waits for the
disk on every commit. The examples' timings come from the Firestore emulator on the same machine, which answers
far faster than a backend across the internet. Compare numbers with each other, not with your production app,
and measure your own app before you tune it.

## How a query is answered from the cache

Every query that the client answers locally goes through the query engine (`local/default_query_engine.dart`):
`get(Source.cache)`, any `get()` while the client is offline, and the first snapshot of every listener before
the backend has answered. It tries three plans, in this order, and the result is the same with each:

1. **A persistent cache index** (SQLite cache only), if one covers the query. See the next section.
2. **The previous result of the query.** The client stores, for every query it has listened to, the keys of
   the documents the backend said match it, and the snapshot version at which the query was last in sync and
   free of unresolved documents. It reads only those documents, plus the documents of the collection that
   changed after that version, and filters them again. This is used only for queries that were in sync with
   the backend at least once; a limit query falls back to a scan when the document at the edge of its window
   changed or stopped matching.
3. **A scan of the collection**: every cached document of the collection (not of its subcollections) is read,
   decoded and matched. A limit is applied after the scan, so `orderBy('x').limit(10)` reads the whole cached
   collection.

Queries that match the whole collection (no filters, no limit, no cursors, no ordering other than by
document id) always scan; there is nothing to save.

When the cache is trusted and when the backend is asked:

- `get()` (the default source) listens to the query, and when the client is online waits for the backend's
  answer before it completes; offline it completes with the cache result. A `get()` therefore costs a full
  listen: a target on the listen stream, the backend's result, and then the target is released.
- A listener first raises what the cache has (`metadata.isFromCache == true`), then the backend's result.
  When it listens again to a query it listened to before, it sends the resume token it stored, and the backend
  can send only what changed since then. When the backend reports that the number of documents does not
  match (an existence filter), the client works out which cached documents were removed (with a bloom filter
  when the backend sends one) or forgets the resume token and receives the whole result again.
- Documents that the cache holds for a query but the backend no longer sends are looked up one by one
  ("limbo resolution", at most 100 at a time, `core/sync_engine.dart`).

Measured (`local_store_bench.dart 100000`: 10 collections of 10,000 documents of a few fields, 54 MB file):

| Query on the SQLite cache | Time |
|---|---|
| 1,000 of 10,000 documents, previous result | 11.5 ms |
| the same query, scan of the collection | 25.8 ms |
| the whole collection (10,000 documents) | 42.9 ms |
| one document by key (`readDocument`, average of 1,000) | 21 us |

**What to do.** Keep the queries your screens open stable, so that they have a previous result to start
from. Query narrow collections: a cache scan reads the whole collection, so one collection of 100,000
documents that every screen filters is slower to read from the cache than several smaller ones. If you read a
large collection with a limit or with filters that match few documents, from the cache, often, add a cache
index (next section).

## Persistent cache indexes

A persistent cache index is a table in the SQLite cache that maps field values to document keys. It exists
only on the device, never changes what a query returns, and does not exist for a memory cache
(`firestore.persistentCacheIndexManager` is null then). [Offline persistence](offline_persistence.md#persistent-cache-indexes)
has the API; this section is about the cost.

What the client does:

- **Automatic creation** is off by default and not stored; turn it on after every start with
  `enableIndexAutoCreation()`. After a cache query was answered by a scan, the client creates an index for it
  when the scan read at least 100 documents and more than twice as many documents as it returned.
- Because a scan returns every match before the limit is applied, a limit query without selective filters
  (for example `orderBy('total', Direction.descending).limit(5)` on a large collection) returns as many documents
  as it read, and never gets an index automatically. Configure one with the deprecated
  `setIndexConfiguration` instead.
- **Filling** (`local/index_backfiller.dart`) runs in the background, on the client's queue: the first run 15
  seconds after the instance was created, then one run per minute, each run indexing at most **50 documents**
  across all collections. A new index on a collection of 10,000 cached documents is therefore complete after
  about 200 minutes of the app running. Until then a query uses the index for the documents it covers and reads
  the others: through the `read_time` column when fewer than 5,000 documents in the whole cache changed after
  the index's position, otherwise by a scan of the collection.
- **Cost on writes.** Writing a document does not write index entries. A document that changes (from the
  backend or from your own acknowledged write) is behind the index's position and is indexed again by a later
  fill run; until then queries read it separately. Removing a document (garbage collection, a delete from the
  backend) deletes its entries in the same transaction. So the write path is not slower, but every change
  costs one more index update later, and a collection that changes faster than 50 documents a minute keeps
  queries reading the changed documents separately.
- **Cost in space.** Every index adds one row per document that has the indexed fields (one per array element
  for `array-contains`).
- Queries with inequalities on several fields are never served by an index (scanned, as in the JS SDK).

Measured (`index_bench.dart 50000 --reps=3`: one collection of 50,000 documents, five fields; the fill was run
in a loop, not at the rate of the scheduler):

| | Scan | Index |
|---|---|---|
| `a == 7` (1 % of the documents) | 149.8 ms | 3.9 ms |
| `r` in a range (1 %) | 151.9 ms | 4.3 ms |
| `array-contains` (2 %) | 157.4 ms | 6.6 ms |
| `orderBy('order', descending).limit(10)` | 305.3 ms, resident memory +234 MB | 0.35 ms |
| `a == 7` with 10 % of the documents not yet indexed | | 26.5 ms |

Four indexes (five entries per document) took 51.5 us per document to fill and grew the file from 22.8 MB to
51.9 MB. With automatic creation, the `orderBy` + `limit` query got no index.

**The known gap.** A query served by an index can leave out a document in one rare case, described in
[Parity, known limitations](../parity.md#known-limitations) (item 15): watch sends a document in a later
snapshot at the same version as an earlier one, after the index was already brought up to date for that
version, and the document's id sorts before the documents indexed last. The document is then missing from
`get(Source.cache)`, the first snapshot of a new listener and a refilled limit window, until it changes
again. It has not been seen against the emulator or production, the JS and Android SDKs have the same gap, and
queries that no index serves are not affected.

**What to do.**

- Turn on automatic creation if your app reads a large cached collection with selective queries offline or
  with `Source.cache`, and the cache lives across many app starts (a persistent cache on a phone or a
  desktop). The index pays off only once it is filled, which takes minutes to hours of running time.
- For `orderBy` + `limit` queries on large collections, configure an index for the ordered field with
  `setIndexConfiguration` (deprecated, as in the other SDKs; it replaces the whole configuration).
- Do not turn it on for short-lived processes or for small collections (under a few thousand documents a scan
  takes a few milliseconds, see above).
- `deleteAllIndexes()` removes them all, for example if the file has grown too large.

```dart
await firestore.persistentCacheIndexManager?.enableIndexAutoCreation();

// An index for a query that automatic creation skips (deprecated API).
// ignore: deprecated_member_use
await firestore.setIndexConfiguration('''
{
  "indexes": [
    {
      "collectionGroup": "orders",
      "queryScope": "COLLECTION",
      "fields": [{"fieldPath": "total", "order": "DESCENDING"}]
    }
  ],
  "fieldOverrides": []
}''');
```

`example/performance/cache_index_inspection.dart` raises the log level and shows the query engine's decisions:
on 2,000 cached documents the first `status == 'open'` query "scans 2000 local documents and returns 40", the
SDK creates an index, and 16 seconds later the first fill run has indexed 50 documents.

## Cache size and garbage collection

What the client does (`local/lru_garbage_collector.dart`):

- The threshold is `PersistentCacheSettings(sizeBytes: ...)` (or `MemoryLruGcSettings(sizeBytes: ...)` for a
  memory cache): **100 MB** by default, at least 1 MB, or `FirestoreSettings.cacheSizeUnlimited` to never
  collect.
- The first check runs **one minute** after the instance starts, then every **five minutes**, on the primary
  client only (see [Several clients on one cache](multiple_clients.md)). There is no call that runs it.
- A check compares the size of the SQLite file (page count times page size) with the threshold. Below it,
  nothing happens. Above it, the run removes the least recently used **10 %** of the queries and of the
  documents that no query holds, **at most 1,000**, and the documents that only those queries held. Queries
  with an active listener, and documents with pending writes, are never removed.
- SQLite does not shrink the file when rows are deleted; it reuses the free pages. The size the collector
  compares is that of the file, free pages included, so once a cache has passed the threshold, every run
  removes another 10 % until the data that remains no longer needs the space it had.
- A memory cache with `MemoryLruGcSettings` computes its size by serializing every cached document, query and
  pending write at every check. The default memory cache (`MemoryEagerGcSettings`) has no checks: a document
  leaves the cache as soon as no listener and no pending write needs it.

Measured (`lru_gc_bench.dart 50000`, 27 MB file, all 50,000 documents released): one run with the default
parameters removed 1,000 documents in 46 ms; removing the other 49,000 in one run took 356 ms.
`local_store_bench.dart 100000` measured about 10 us per removed document.

**What to do.**

- Keep the default (100 MB) unless you know the size of your working set. A run removes at most 1,000 entries
  every five minutes, so set the threshold above what your app needs between two starts, not below it: a
  threshold far below the data the app reads keeps the collector removing documents that the next screen will
  download again.
- Use `cacheSizeUnlimited` only when the data the app can read is bounded.
- On the web with the IndexedDB storage, the whole database is in memory while it is open: the threshold is
  also a memory budget there (see [Offline persistence on the web](offline_persistence.md#on-the-web)).

```dart
final FirestoreSettings settings = FirestoreSettings(
  cacheSettings: PersistentCacheSettings(sizeBytes: 200 * 1024 * 1024),
);
```

`example/performance/cache_size_and_gc.dart` sets 1 MB, writes about 3 MB, releases 50 queries and keeps one
listener: the first run removes 5 queries and their 50 documents, and the files do not get smaller.

## Memory cache or SQLite cache

| | Memory, eager GC (default without an `openDatabase`) | Memory, LRU GC | SQLite |
|---|---|---|---|
| Survives a restart | no | no | yes |
| `get(Source.cache)` after a `get()` | finds nothing (the documents left with the listener) | finds the documents | finds the documents |
| Offline answers for queries listened to before | only while a listener holds them | yes, up to the threshold | yes, up to the threshold |
| Cache indexes | no | no | yes |
| Cost | memory per document | memory, plus a full serialization every five minutes | a disk write per change, file on disk |

`example/performance/cache_vs_server.dart` on 1,000 documents (emulator, same machine): a query for 100
documents took 16 to 38 ms from the server and 2 to 4 ms from the cache with each kind of cache, and the eager
memory cache returned 0 documents from the cache.

**What to do.** Servers, tools and short-lived processes: the default memory cache, or [Lite](#the-lite-library).
Apps that are opened again and must work offline: SQLite. A memory cache with LRU GC only when you want reads
from the cache within one run but no file.

## Listeners

What the client does (`core/event_manager.dart`):

- All listeners of one instance share one listen stream. Each **distinct query** is one target on it, and the
  client keeps one view per query: the documents, sorted, matched against every change.
- Listeners on **equal queries** (same path, filters, orders, limits and cursors, even from different
  `Query` objects) share that target and view. A second listener gets its first snapshot from the existing
  view, without a request (`cache_vs_server.dart`: 0 ms, not from cache).
- `MetadataChanges.include` does not add work on the network or in the view; it delivers more events to your
  code (every change of `hasPendingWrites` and `isFromCache`).
- A listener with `ListenSource.cache` has no target on the backend: it sees local writes and what other
  listeners bring into the cache.
- When the last listener of a query is cancelled the target is released, and the stream is closed after one
  minute without targets.

**What to do.**

- Listen once per query and share the stream inside your app (a `StreamController.broadcast`, a state
  management object) instead of building a listener per widget; if you cannot, build equal queries, which
  share a target anyway.
- Cancel listeners you no longer show. Each active target costs backend reads for every change it receives.
- Use `MetadataChanges.include` only where you show pending or offline state.
- For views derived from data that another listener already follows, listen with `ListenSource.cache`:

```dart
final Stream<QuerySnapshot<Map<String, Object?>>> local = users
    .where('online', isEqualTo: true)
    .getSnapshotsWithOptions(const SnapshotListenOptions(source: ListenSource.cache));
```

## Limits and pagination

A large result costs on both sides: the backend sends (and bills) every document, and the client stores,
decodes, sorts and keeps it in the view. A cache query without an index still scans the whole collection, but
a limit keeps the view and the snapshot small. The `orderBy` + `limit` scan above held 234 MB more memory for
a while because it decoded 50,000 documents.

**What to do.** Show pages: a `limit` and a cursor from the last document of the previous page.

```dart
final QuerySnapshot<Map<String, Object?>> page1 =
    await users.orderBy('name').limit(25).get();
final QuerySnapshot<Map<String, Object?>> page2 = await users
    .orderBy('name')
    .startAfterDocument(page1.docs.last)
    .limit(25)
    .get();
```

## Counts and aggregations

`count()`, `sum()` and `average()` run on the backend only (`aggregate_query.dart`). The client never computes
them from its cache, does not store their result, and has no listener for them: offline the future fails with
`unavailable`. The backend sends one small result instead of the documents.

**What to do.** Use `count()` instead of reading a query to count it. Keep reading documents when you show
them anyway, or when the number must work offline (count `snapshot.length` of a listener you have).

```dart
final AggregateQuerySnapshot snapshot = await users.where('active', isEqualTo: true).count().get();
print(snapshot.getCount());
```

## Writes and batches

What the client does:

- Every write is applied to the cache at once (one local transaction) and sent on the write stream. Up to 10
  batches are in flight at the same time (`remote/remote_store.dart`), so separate writes do not wait for each
  other's round trip.
- A `WriteBatch` is one local transaction, one request to the backend, and atomic: all of it or none.
- The client does not limit the size of a batch. The backend limits the size of a request; a batch that is
  too large is rejected as a whole, after it was applied locally, and its local changes are rolled back.
- Everything a client does runs in order on one queue, so a large batch delays the reads and listeners of the
  same instance while it is applied.

Measured (`local_store_bench.dart 100000`, local store only, without the disk wait): 500 writes of one
document each took 104 us each; one batch of 500 took 32.3 ms (65 us per write). Acknowledging them took
177 us each, or 35.8 ms for the batch.

**What to do.** Use a batch when the writes must succeed together. For throughput alone, separate writes are
pipelined and a batch saves little on the client. Keep batches to hundreds of writes, not tens of thousands:
split a large import into batches and `await` each one, so that a failure costs one batch and the queue stays
free for the rest of the app.

## Bundles for the first screen

A bundle is a file of documents and named queries, made on a server, that `loadBundle` writes into the cache.
After it, the first screen comes from the cache without waiting for the backend, and a listener on the
bundle's named query starts from the bundle's read time, so the backend only sends what changed since. Loading
the same bundle again is skipped after reading its metadata (the cache has a bundle with that id that is as
new).

`QuerySnapshot.toJson()` writes a bundle (its `bundle` field) with the query under the name in `bundleName`;
a server SDK such as the Node.js Admin SDK builds the same format. `example/performance/bundle_first_paint.dart`
makes one from a 20-document query on a "server" instance: on an empty SQLite cache, loading it and reading the
named query from the cache took 50 to 75 ms (including opening the file), and the listener raised the bundled
result at once and the backend's update 36 to 41 ms later (emulator).

```dart
final LoadBundleTaskProgress progress = await firestore.loadBundle(bundleBytes).future;
final Query<Map<String, Object?>>? latest = await firestore.getNamedQuery('latest-stories');
final QuerySnapshot<Map<String, Object?>> firstScreen = await latest!.get(Source.cache);
```

**What to do.** Use a bundle for data that many users read on their first start (a catalogue, the front page)
and serve it from a CDN. Not worth it for per-user data, or for apps whose cache is already warm.

## Reading from the cache only

`get(Source.cache)` never contacts the backend: a document read is a lookup by key (21 us above), a query goes
through the plans of the first section. A document that is not in the cache fails with `unavailable`; a
document the cache knows to be missing returns a snapshot with `exists == false`. `get(Source.server)` still
listens (one target), and fails with `unavailable` when the result could only come from the cache.

**What to do.** Use `Source.cache` for data you know a listener keeps current, or to show something at once
while the normal `get()` runs.

```dart
final DocumentSnapshot<Map<String, Object?>> cached = await users.doc('ada').get(Source.cache);
```

## Transport

On the Dart VM and in Flutter the client uses gRPC over HTTP/2 (`remote/datastore/grpc_channel.dart`,
`keep_alive_transport.dart`):

- one gRPC channel per instance for all streams and calls;
- a keepalive ping every 30 seconds while calls are active, the connection dropped when a ping gets no
  answer within 20 seconds, so a half-dead connection is replaced; no pings while idle;
- a connection attempt times out after 15 seconds;
- the listen and write streams are closed after one minute without targets or writes;
- `FirestoreSettings.grpcFlowControlWindow`, 256 KiB by default (as in the Android and JS SDKs): a larger
  window helps large reads on a connection with a long round trip, at the cost of one round trip before the
  first request of a new connection.

In the browser the client uses WebChannel for the listen and write streams and REST for one-shot calls
([Platforms](platforms.md#the-web-experimental)). It switches a stream to long polling when the first response
does not arrive within 10 seconds (`experimentalAutoDetectLongPolling`, on by default), which is how a
buffering proxy shows. Long polling works on every network but makes a new request for every batch of changes.

**What to do.** Keep the defaults. Set `experimentalForceLongPolling: true` only for users behind a proxy that
breaks streaming, since it skips the 10 second detection; there is nothing to tune for gRPC keepalive.

## Startup with a large cache

What happens when an instance with a SQLite cache starts: the file is opened, schema migrations run if the SDK
version changed (once), and the local store loads its state. Documents are not read until a query asks for
them. Measured with `local_store_bench.dart 100000` (54 MB file, 501 pending write batches): reopening took
3.0 ms; with the one-time migration that builds pending-write overlays, 49 ms for 1,000 documents. The first
snapshot of each listener then costs one cache query (first section).

Background work starts later: the index fill after 15 seconds, garbage collection after one minute.

On the web, the IndexedDB storage reads the whole database into memory when it opens (about 1 second for
100,000 documents); the OPFS storage opens in well under 0.2 seconds at any size
([Offline persistence on the web](offline_persistence.md#on-the-web)).

**What to do.** Nothing on the VM. On the web, use OPFS for large caches, or keep the IndexedDB cache small
with the threshold.

## The Lite library

`package:cloud_firestore_dart/lite.dart` has no cache, no listeners and no sync engine: one request per call.
There is no local store to open, no queue of background work and no listen stream, and a web program that uses
only Lite is smaller ([Firestore Lite](lite.md) has the sizes). Use it in servers, tools and functions that
read and write but never listen or work offline.

## Checklist

- Persistent cache for apps that must work offline; default memory cache or Lite for servers and tools.
- One listener per query, shared; equal queries share a target anyway; cancel what you no longer show.
- `limit` and cursors instead of large results; `count()` instead of reading to count.
- Batches for atomicity, in sizes of hundreds.
- Cache indexes only for large, long-lived caches with selective queries; a configured index for `orderBy` +
  `limit` queries.
- Keep the 100 MB default unless you know your working set; never set the threshold far below it.
- A bundle for shared data on the first start.
