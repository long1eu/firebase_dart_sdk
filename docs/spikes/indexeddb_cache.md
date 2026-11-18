# Spike: an IndexedDB cache engine on the web

Status: measurement only, no engine was built. Written 2026-11-18 on branch
`spike/indexeddb-cache`.

The question: should `cloud_firestore_dart` get a third `Persistence` engine written directly on
IndexedDB, as the official JS SDK has, so that a web app with a persistent cache no longer
downloads `sqlite3.wasm`? This document gives the numbers for that decision, and how each was
taken.

Machine and tools for every measurement below, unless a section says otherwise:

- MacBook with an Apple M5, 32 GB, macOS 27.2.
- Dart 3.12.2 (the SDK of the repository's size check), `package:sqlite3` 3.9.1 and its
  `sqlite3.wasm` (the version `pubspec.lock` resolves; checksum pinned in
  `tool/build_web_test_assets.sh`).
- Google Chrome 157.0.8103.79, headless (`--headless=new`), a fresh profile per run.
- Pages served from `127.0.0.1` by `tool/bench/web_idb/run.dart`; no backend is contacted (the
  emulator address in the pages is a closed port, and the network is not needed for any of it).

The sources are in `tool/bench/web_idb/`:

| File | What it does |
| --- | --- |
| `size/memory_app.dart`, `size/sqlite_app.dart` | The small app of `tool/size/full_app.dart`, with the memory cache and with the SQLite cache. |
| `size/size.dart` | Compiles both with dart2js `-O2` and dart2wasm `-O2`, prints raw and gzipped sizes and the dart2js `--dump-info` split by library group. |
| `web/engine.dart` | The raw engine benchmark (point 3) and the transaction lifetime test (point 4). |
| `web/startup.dart` | The start-up measurement (point 2). |
| `web/index.html` | Loads a page compiled with dart2js (`c=js`) or dart2wasm (`c=wasm`). |
| `run.dart` | `dart run.dart build` compiles the pages and copies `sqlite3.wasm` and the OPFS worker; `dart run.dart [txtest] [engine] [startup]` serves them, drives one headless Chrome through the plan and prints medians. Raw results go to `out/results.jsonl` (git-ignored). |
| `js_import/` | The JS SDK compatibility check (point 6). |

To run them: `tool/build_web_test_assets.sh` (fetches `sqlite3.wasm`, compiles the OPFS worker),
then `cd tool/bench/web_idb && dart pub get && dart size/size.dart && dart run.dart build && dart run.dart`.

**Noise.** The machine was shared with other work while these ran (load averages of 10 to 20 on
`uptime`). The first engine pass, taken while another Chrome and a JS build were running,
was two to four times slower for IndexedDB than a later pass; the tables below use the later,
quieter passes and give the range next to each median. The ranges are wide: read the ratios as
"about", not to the percent. A run on the Mac mini would tighten them.

## 1. Download size

Measured with `tool/bench/web_idb/size/size.dart`: the app of `tool/size/full_app.dart` (set,
update, get, a query, count, a batch, a transaction) once with `MemoryCacheSettings` and once
with `sqliteOpener(...)` of `cloud_firestore_dart_sqlite`. dart2js with `-O2` and
`--dump-info` (as `tool/check_size.sh`), dart2wasm with its default `-O2`. Gzip is Dart's
`gzip.encode` (level 6), as in `tool/size/check_size.dart`. Bytes.

| File | Memory cache | SQLite cache | Difference |
| --- | ---: | ---: | ---: |
| `app.js` (dart2js -O2) | 706,854 | 959,181 | +252,327 |
| `app.js` gzipped | 215,241 | 286,216 | +70,975 |
| `app.wasm` (dart2wasm -O2) | 657,804 | 952,099 | +294,295 |
| `app.wasm` gzipped | 256,355 | 358,324 | +101,969 |
| `app.mjs` (dart2wasm loader) | 16,020 | 30,199 | +14,179 |
| `app.mjs` gzipped | 4,256 | 6,594 | +2,338 |
| `sqlite3.wasm` (sqlite3 3.9.1) | | 758,836 | +758,836 |
| `sqlite3.wasm` gzipped | | 364,658 | +364,658 |
| `sqlite_opfs_worker.js` (OPFS only, dart2js -O2 by `setup_web`) | | 174,128 | +174,128 |
| `sqlite_opfs_worker.js` gzipped | | 54,364 | +54,364 |

So a web app pays today, on top of the memory cache:

| Persistent cache | dart2js raw | dart2js gzipped | dart2wasm raw | dart2wasm gzipped |
| --- | ---: | ---: | ---: | ---: |
| IndexedDB storage (app code + `sqlite3.wasm`) | 1,011,163 | 435,633 | 1,067,310 | 468,965 |
| OPFS storage (+ the worker) | 1,185,291 | 489,997 | 1,241,438 | 523,329 |

`sqlite3.wasm` is 759 KB with sqlite3 3.9.1; the guides still say 731 KB (349 KB gzipped),
which was the 2.9.4 build. The memory app is also larger than the 651,311 that
`tool/size/check_size.dart` records for main `1645e672`; the library has grown since.

Where the +252 KB of dart2js code goes (the `--dump-info` size of each library, summed by
group; the dump does not attribute about 60 KB of each program to any library):

| Library group | Memory app | SQLite app | Difference |
| --- | ---: | ---: | ---: |
| `cloud_firestore_dart` `local/sqlite/` (the engine) | 2,189 | 101,712 | +99,523 |
| `package:cloud_firestore_dart_sqlite` (opener, setup checks) | 0 | 24,608 | +24,608 |
| `package:sqlite3` (the Dart side of the driver) | 0 | 44,247 | +44,247 |
| the rest of `cloud_firestore_dart` (index manager, ordered-code writers, serializer paths, LRU GC: only used with a persistent cache) | 316,973 | 356,939 | +39,966 |
| `local/memory/` | 19,375 | 19,235 | -140 |
| everything else (Dart runtime, protobuf, collections) | 310,735 | 343,255 | +32,520 |

**Estimate (not measured): an IndexedDB engine.** It would replace `local/sqlite/` with code
of about the same shape (the same caches, the same lease and client metadata, the same
schema setup), drop `package:sqlite3` and `package:cloud_firestore_dart_sqlite`, and add a
small wrapper over `package:web`'s IndexedDB types. Reasoning, dart2js:

- The engine: `local/sqlite/` is 99.5 KB, of which roughly 10 to 20 KB is SQL text (the SQL
  string literals of the sources add up to about 7 KB of statements; with the schema and its
  migrations more). An IndexedDB engine has no SQL, but writes by hand what SQLite does for
  free: cursor loops for range scans and joins, maintenance of the secondary indexes, key
  encoding. Assume 90 to 130 KB.
- The persistence-only parts of `cloud_firestore_dart` (+40 KB) stay.
- Of "everything else" (+32.5 KB) part goes with `package:sqlite3` (JS interop helpers,
  `dart:js_util`, typed data paths) and part stays (protobuf, collections). Assume half stays.
- The driver goes: -68.9 KB (`package:sqlite3` and the opener package).
- A wrapper and opener over IndexedDB (promises to futures, transactions, Web Lock, delete):
  10 to 15 KB.

That gives +165 to +210 KB of dart2js output over the memory app (90 to 130 for the engine,
40 and 16 kept, 10 to 15 for the wrapper, and about 8 KB of the output that the dump does not
attribute to a library), about +46 to +59 KB gzipped at the 0.28 gzip ratio of today's
difference, and no `sqlite3.wasm`, no worker. dart2wasm, scaled by the same factor (0.65 to
0.83 of today's difference): +200 to +255 KB for the module and loader, +68 to +87 KB gzipped.
Against today's IndexedDB storage that saves about 800 to 845 KB raw and 377 to 390 KB gzipped
with dart2js, and about 810 to 865 KB raw and 382 to 401 KB gzipped with dart2wasm; against
OPFS, add the worker's 174 KB (54 KB gzipped).

## 2. Start-up

Measured with `web/startup.dart`: one page load per measurement, in one headless Chrome.
The time is `performance.now()` (milliseconds since `performance.timeOrigin`, the start of
the navigation) when `doc('bench/doc').get(GetOptions(source: Source.cache))` completed with
the document found, and the same at the start of `main` (so the difference is the cache open
plus the first read). Before the measured loads a seed load wrote the document as a pending
write with the network disabled and terminated the client. Each measured load terminates its
client before going to the next one (not timed), so the Web Lock of the cache is free.

- Cold: the page and everything it loads come from `/cold/...` with
  `Cache-Control: no-store`: `sqlite3.wasm` (and the worker) are fetched and compiled again on
  every load (the resource timing entries show the 759,136 bytes transferred each time).
- Warm: from `/warm/...` with `max-age=3600`; the first warm load fills the HTTP cache and is
  not counted (the entries then show 0 bytes transferred).
- Memory: the same page with `MemoryCacheSettings` and a query of the empty collection from
  the cache (there is no stored document), for the start of a client without a database.
- The server is on 127.0.0.1 and does not compress: the download itself takes 2 to 10 ms.

Medians of 7 loads, milliseconds (the range of the 7 in brackets):

| Compiler | Cache | `main` starts | First read done | Open + first read |
| --- | --- | ---: | ---: | ---: |
| dart2js | memory, cold | 34 | 36 | 1.8 [1.7-6.9] |
| dart2js | memory, warm | 12 | 13 | 1.7 [1.6-1.8] |
| dart2js | SQLite on IndexedDB, cold | 24 | 48 | 22 [20-29] |
| dart2js | SQLite on IndexedDB, warm | 9 | 37 | 26 [21-40] |
| dart2js | SQLite on OPFS, cold | 26 | 69 | 43 [34-56] |
| dart2js | SQLite on OPFS, warm | 9 | 42 | 33 [30-44] |
| dart2wasm | memory, cold | 18 | 19 | 0.3 [0.2-4.9] |
| dart2wasm | memory, warm | 11 | 12 | 0.2 [0.2-0.4] |
| dart2wasm | SQLite on IndexedDB, cold | 23 | 55 | 34 [22-47] |
| dart2wasm | SQLite on IndexedDB, warm | 12 | 45 | 35 [24-72] |
| dart2wasm | SQLite on OPFS, cold | 18 | 52 | 32 [29-35] |
| dart2wasm | SQLite on OPFS, warm | 10 | 38 | 29 [27-37] |

What this says:

- On a local server, cold and warm differ by little: fetching and compiling `sqlite3.wasm`
  from 127.0.0.1 costs a few milliseconds, inside the noise. On a real network the download
  dominates. Computed, not measured: 365 KB gzipped is about 0.3 s at 10 Mbit/s and about 1.8
  s at 1.6 Mbit/s, once per cold HTTP cache (and the OPFS worker's 54 KB on top).
- Today the persistent cache adds about 22 to 35 ms (IndexedDB storage) and 29 to 43 ms (OPFS)
  to the first cache read of a page, with a database of one document. The memory cache needs
  0.2 to 2 ms.
- The IndexedDB storage reads the whole database into memory when it opens, so that part
  grows with the cache. Point 3 measures it for 10,000 records of 1 KB (10 MB): 44 to 52 ms
  (medians) to open and read one row again; the comment in `sqlite_database_web.dart` gives 0.5 to 1.2 s
  for 100,000 documents. OPFS does not grow that way (23 to 32 ms at 10 MB).
- **Estimate** for an IndexedDB engine: opening an IndexedDB database of 10 MB and reading one
  record took 0.2 to 0.4 ms (point 3, `reopen_and_get`); the engine also reads a few rows at
  start (target globals, the mutation queue's metadata, the client metadata and the primary
  lease), each a transaction of about 0.1 to 0.3 ms. So the start-up of an IndexedDB engine
  would be the memory cache's plus roughly 2 to 5 ms, independent of the cache size, and no
  download. Not measured, since the engine does not exist.

## 3. Raw engine speed

Measured with `web/engine.dart`, compiled with dart2js `-O2` and dart2wasm `-O2`. Records of
1 KB of random bytes under string keys `cNN/dNNNNN` (10 prefixes of 1,000). Every statement or
request is awaited before the next, as the cache's Dart code does.

- **IndexedDB**: one object store, string keys, `Uint8Array` values, through `package:web`.
  Transactions with the default durability (as the JS SDK opens them). Every point read is
  its own read-only transaction; the scan is a cursor over `IDBKeyRange.bound(prefix,
  prefix + '￿')`.
- **SQLite on IndexedDB** and **SQLite on OPFS**: the real opener of the cache,
  `sqliteWebOpener` of `cloud_firestore_dart_sqlite` (`opfsWorker` for OPFS), through the
  `Database` interface the persistence uses: `BEGIN IMMEDIATE` / `COMMIT`, table
  `docs (path TEXT PRIMARY KEY, contents BLOB) WITHOUT ROWID`, the scan a `SELECT ... WHERE
  path >= ? AND path < ? ORDER BY path`. So the IndexedDB storage includes the wait for the
  copy to IndexedDB at every commit, and OPFS a message to the worker per statement, as in the
  cache.

Operations: `insert_tx1` 10,000 inserts, one transaction each; `insert_tx100` 10,000 inserts in
100 transactions; `get` 1,000 point reads; `scan` one range scan of 1,000 keys (the median of
10, per scan); `delete_tx1` 1,000 deletes, one transaction each; `reopen_and_get` closing the
database of 9,000 records and opening it again, then one read (the wasm module is already
loaded). IndexedDB only: `insert_tx1_strict` with `durability: 'strict'`, and
`insert_tx100_pipelined`, the 100 puts of a transaction issued without awaiting each one.

Medians, milliseconds for the whole operation (the scan: per scan), range in brackets.
IndexedDB: 7 runs; the SQLite storages: 5 runs (`out/results.jsonl` of `dart run.dart engine
--engines=idb --runs=7` and `--engines=sqlite-idb,sqlite-opfs --runs=5`).

dart2js:

| Operation | IndexedDB | SQLite on IndexedDB | SQLite on OPFS |
| --- | ---: | ---: | ---: |
| `insert_tx1` (10,000 transactions) | 2,664 [1,722-3,459] | 27,948 [23,265-33,556] | 20,037 [15,832-24,305] |
| `insert_tx1_strict` | 5,663 [4,057-8,172] | | |
| `insert_tx100` (100 transactions, each put awaited) | 950 [774-1,288] | 1,997 [1,301-3,368] | 633 [485-3,223] |
| `insert_tx100_pipelined` | 703 [650-1,091] | | |
| `get` (1,000 point reads) | 104 [77-258] | 8.7 [8.4-11.1] | 39 [31-61] |
| `scan` (1,000 keys by prefix) | 7.0 [5.9-14.4] | 1.3 [1.2-2.0] | 2.2 [2.0-2.5] |
| `delete_tx1` (1,000 transactions) | 164 [127-261] | 1,683 [1,166-4,442] | 949 [850-1,541] |
| `reopen_and_get` (10 MB database) | 0.2 [0.1-0.3] | 52 [45-135] | 32 [27-41] |

dart2wasm:

| Operation | IndexedDB | SQLite on IndexedDB | SQLite on OPFS |
| --- | ---: | ---: | ---: |
| `insert_tx1` (10,000 transactions) | 2,432 [1,950-2,846] | 20,884 [11,387-22,669] | 26,106 [17,407-42,521] |
| `insert_tx1_strict` | 4,978 [4,095-5,892] | | |
| `insert_tx100` (100 transactions, each put awaited) | 936 [829-1,033] | 2,091 [1,739-2,430] | 571 [485-1,010] |
| `insert_tx100_pipelined` | 696 [591-1,049] | | |
| `get` (1,000 point reads) | 91 [71-128] | 7.0 [6.5-9.9] | 34 [32-40] |
| `scan` (1,000 keys by prefix) | 6.6 [5.7-8.4] | 2.0 [1.9-2.4] | 3.0 [2.9-3.3] |
| `delete_tx1` (1,000 transactions) | 158 [134-211] | 1,121 [1,037-2,192] | 4,260 [888-7,366] |
| `reopen_and_get` (10 MB database) | 0.2 [0.2-0.4] | 44 [40-89] | 23 [22-25] |

Per operation, from the medians: a small write transaction costs about 0.25 ms on IndexedDB
(0.5 ms with `strict` durability) against 2 to 2.8 ms with either SQLite storage; a point read
about 0.1 ms on IndexedDB (each in a transaction of its own) against 0.008 ms with SQLite on
IndexedDB (the database is in memory) and 0.035 to 0.04 ms on OPFS (a message to the worker).

What it says:

- Writes: IndexedDB commits small transactions 7 to 11 times faster than either SQLite
  storage. The SQLite cost is the commit: the IndexedDB storage waits for the copy of the
  journal and the changed pages to IndexedDB, OPFS flushes the journal and the file. With 100
  writes per transaction IndexedDB is 2 to 3 times faster than SQLite on IndexedDB and 1.1 to
  1.6 times slower than SQLite on OPFS (whose statements run in memory pages until the commit).
- Reads: IndexedDB is slower, 12 to 13 times than the in-memory SQLite of the IndexedDB
  storage and about 2.6 times than OPFS, for point reads; 3 to 5 times and 2 to 3 times for the
  ordered scan. In absolute terms it is 0.1 ms per read and 7 ms per 1,000-record scan.
- Open: constant and below a millisecond on IndexedDB; SQLite on IndexedDB reads the whole
  database (here 10 MB) first, OPFS starts a worker and the wasm module.
- dart2js and dart2wasm are within the noise of each other for IndexedDB.
- The first pass of this benchmark (taken on a busier machine; its raw results are not committed)
  gave IndexedDB 4.6 to 11 s for `insert_tx1` and 0.34 to 0.39 s for `get`, and SQLite on
  IndexedDB 28 to 57 s: the ratios moved by a factor of up to two between passes, the
  direction did not.

Not measured: a real engine's transactions (several stores, secondary indexes kept by hand,
values of real document size and shape); reads batched in one transaction, as the cache's
operations do (the per-transaction overhead of a read would mostly go).

## 4. Does an IndexedDB transaction survive the awaits of `runTransaction`?

An IndexedDB transaction stays active while a request of it is pending or while the task or
microtask checkpoint that a request's event started has not finished. When control returns to
the event loop with no pending request, the transaction commits on its own, and any later
request on it throws `TransactionInactiveError`.

Measured with `web/engine.dart?engine=txtest`: a readwrite transaction puts `a`, awaits the
thing below, then puts `b`; afterwards a new transaction reads both back. Same result with
dart2js and dart2wasm, in Chrome 157:

| Await between the two puts | Result |
| --- | --- |
| (a) an IndexedDB request of the same transaction, wrapped in a `Completer` | survives |
| (b) `Future.value()`, a completed `Completer`'s future, an `async` function without awaits | survives |
| (c) `Future.microtask`, 1,000 chained `scheduleMicrotask`, a resolved JS `Promise` (`toDart`) | survives |
| (d) `Future.delayed(Duration.zero)`, `Timer.run`, `Future(() {})` | **closed**: `TransactionInactiveError`; `a` is committed, `b` is not |
| (e1) a chain: request, `Future.value`, microtask, request, 10 awaited `async` calls | survives |
| (e2) a chain ending in `Future.delayed(Duration.zero)` | **closed**, `a` committed |
| (f) `Stream.fromIterable(...).toList()` | survives |
| (g) 50 ms of synchronous work | survives |

Why: both compilers run Dart's microtasks on the browser's microtask queue (dart2wasm's loader
calls `queueMicrotask`; dart2js uses a `MutationObserver` callback, also a microtask), so a
continuation after a completed future, or after an IndexedDB request whose success event
completed the future, runs before the transaction can commit. A `Timer` is a `setTimeout`, a
new task: the transaction has committed by then.

Two consequences:

- The failure is not a rollback. The writes made before the timer are committed, the rest
  throws. An engine has to treat a `TransactionInactiveError` as a broken contract (fatal),
  not retry the operation (it would apply the first half twice). The JS SDK has the same
  hazard and avoids it by never leaving its `PersistencePromise` chain inside a transaction.
- An IndexedDB transaction names its object stores when it starts. The engine would open
  every transaction on all stores (readwrite), which serializes them; the persistence already
  serializes its transactions with a lock (`SQLitePersistence._lock`), so nothing is lost.

What the local store does inside a transaction. Grep of `lib/src/firebase/firestore/local/`
(everything but the SQLite file helpers) for `Future.delayed`, `Timer`, `Timer.run`,
`Future(() ...)`, `.timeout(`, isolates, `compute(`, `dart:io`, `fetch(`: no hit inside a
transaction. The `TimerTask`s (`lru_garbage_collector.dart`, `index_backfiller.dart`,
`client_metadata_refresher.dart`) schedule whole transactions; they do not wait inside one.
`runTransaction` / `runPrimaryTransaction` are called from `local_store.dart` (22 times),
`index_backfiller.dart` and the SQLite persistence itself; the bodies only await the caches of
the same persistence. `SQLitePersistence._runTransaction` takes its lock (a semaphore,
completed by futures, not timers) before `BEGIN` and calls `onTransactionCommitted` after
`COMMIT`, both outside the transaction. `FirebaseFirestore.runTransaction` (the user's
transaction) runs over the network and never inside a persistence transaction.

**Answer:** the contract can be met in Chrome with both compilers, as long as the engine's
own code awaits only IndexedDB requests and futures, and two guards go with it: a debug check
that fails a transaction whose body touched a closed IndexedDB transaction (the engine sees the
`TransactionInactiveError`), and a rule in the persistence code that nothing inside
`runTransaction` waits on a timer, an isolate or I/O (a test can enforce it by running the
local store tests on a fake persistence that throws on any timer during a transaction, with
`package:fake_async`). Not tested: Safari and Firefox (the spec behaviour is the same, but
older Safari versions closed transactions across promise microtasks; the JS SDK's
`PersistencePromise` exists partly for that).

## 5. Multi-tab

What the JS SDK needed (read from `indexeddb_persistence.ts` and `shared_client_state.ts`,
firebase-js-sdk `main` at `dd0bfd99`, `@firebase/firestore` 4.20.0):

- A primary lease in the `owner` store (`{ownerId, allowTabSynchronization,
  leaseTimestampMs}`), checked and extended inside the IndexedDB transactions that need the
  primary; 5 s lease, refreshed every 4 s.
- One row per tab in `clientMetadata` (`{clientId, updateTimeMs, networkEnabled,
  inForeground}`), refreshed every 4 s; clients older than 30 minutes are removed.
- LocalStorage for the messages between tabs, with the `storage` event as the notification:
  `firestore_clients_<key>_<clientId>`, `firestore_mutations_<key>_<batchId>[_<user>]`,
  `firestore_targets_<key>_<targetId>`, `firestore_online_state_<key>`,
  `firestore_sequence_number_<key>`, `firestore_bundle_loaded_v2_<key>`, and
  `firestore_zombie_<key>_<clientId>` written by a closing tab so the next one can take the
  lease at once. No Web Locks.

What this port has:

- `sqlite_client_metadata.dart` (373 lines) and `client_metadata_refresher.dart` (47) port
  the lease and the client rows onto the SQLite tables `primary_client` (`owner_id,
  allow_synchronization, lease_timestamp_ms`) and `clients` (`client_id, update_time_ms,
  network_enabled, in_foreground`): the same fields as the JS stores. They are used today on
  the VM, where several isolates or processes share one SQLite file.
- `shared_client_state.dart` (986 lines) ports `WebStorageSharedClientState` with the same
  LocalStorage key formats, over the abstract `SharedClientStateStorage`
  (`shared_client_state_storage.dart`, 129 lines). The only implementation is
  `InMemorySharedClientStateStorage` (one isolate), used by the spec and fuzz tests; there is
  no `window.localStorage` implementation, and on the web the opener allows one tab per cache
  (Web Lock).

Could it sit on IndexedDB: yes. The client metadata and the lease are a few reads and writes
of two small tables inside the persistence's transactions; on IndexedDB they become two
object stores with the same fields, and `sqlite_client_metadata.dart` would be rewritten
against the engine's transaction type (about the same size; estimate). The shared client
state is storage-agnostic already; multi-tab on the web would need a
`SharedClientStateStorage` over `window.localStorage` and its `storage` event (about 100 to
150 lines; estimate) plus the wiring that today only the tests do. None of it depends on SQLite.
Multi-tab is a separate decision from the engine: the IndexedDB engine can start with the same
one-tab Web Lock the SQLite opener has.

## 6. Compatibility with the official JS SDK's cache

The goal: a web app that used the JS SDK with IndexedDB persistence switches to this SDK on
the same browser profile, and keeps its pending writes and cached documents. Read from the
firebase-js-sdk sources named in point 5 (`indexeddb_schema.ts`, `indexeddb_sentinels.ts`,
`indexeddb_schema_converter.ts`, `local_serializer.ts`, `shared_client_state.ts`), and checked
in Chrome with `firebase` 12.19.0 from npm.

### The JS SDK's database

- Name: `firestore/<persistenceKey>/<projectId>[.<databaseId>]/main`; the persistence key is
  the app name, `[DEFAULT]` by default, and `.<databaseId>` is only there for a non-default
  database. Seen in Chrome: `firestore/[DEFAULT]/demo-idb/main`.
- Schema version 18 (`SCHEMA_VERSION`). The converter migrates from any version 1 to 18;
  the store list of version 11 and up is in `getObjectStores()`.
- Values are structured-clone JS objects holding proto3 JSON (`JsonProtoSerializer` with
  `useProto3Json`), not protobuf bytes: timestamps inside protos as ISO strings with nine
  fraction digits, int64 as strings, bytes and resume tokens as base64 strings, document
  names fully qualified. The wrappers' own timestamps are `{seconds, nanoseconds}`; the
  `readTime` part of a key is a `[seconds, nanos]` pair. `userId` is `""` when signed out.
- Resource paths inside keys use `encodeResourcePath`: each segment followed by
  `\u0001\u0001`, with `\0` written as `\u0001\u0010` and `\u0001` as `\u0001\u0011`; the
  empty path is `\u0001\u0001`. `documentMutations`, `targetDocuments.path` and the index
  entries use it; `remoteDocumentsV14` and `documentOverlays` use split arrays and strings.

| JS store | Key and indexes | This port's table (`sqlite_schema.dart`, version 20) | Difference |
| --- | --- | --- | --- |
| `owner` | key `'owner'` | `primary_client` | same fields |
| `clientMetadata` | keyPath `clientId` | `clients` | same fields |
| `mutationQueues` | keyPath `userId` | `mutation_queues` | same idea |
| `mutations` | keyPath `batchId` (autoIncrement); index `userMutationsIndex [userId, batchId]` unique | `mutations (uid, batch_id, mutations BLOB)` | JS: `{userId, batchId, localWriteTimeMs, baseMutations, mutations}` with proto3-JSON `Write`s; port: a `WriteBatch` protobuf |
| `documentMutations` | key `[userId, encodedPath, batchId]`, value `{}` | `document_mutations (uid, path, batch_id)` | different path encoding (port: `encoded_path.dart`) |
| `remoteDocumentsV14` | keyPath `[prefixPath, collectionGroup, readTime, documentId]`; indexes `documentKeyIndex`, `collectionGroupIndex` | `remote_documents` (path, `contents` = `MaybeDocument` protobuf, read time columns, document type, path length) | port keyed by path with a read-time column; JS keys split the path |
| `remoteDocumentGlobal` | key `'remoteDocumentGlobalKey'`, `{byteSize}` | none | port has no byte-size row |
| `targets` | keyPath `targetId`; index `queryTargetsIndex [canonicalId, targetId]` unique | `targets` (`target_proto` BLOB, `resume_token` BLOB) | JS: proto3-JSON query, base64 token |
| `targetDocuments` | keyPath `[targetId, path]`; index `documentTargetsIndex [path, targetId]` | `target_documents` | path encoding |
| `targetGlobal` | key `'targetGlobalKey'` | `target_globals` | same fields |
| `collectionParents` | keyPath `[collectionId, parent]` | `collection_parents` | same idea |
| `bundles`, `namedQueries` | keyPath `bundleId`, `name` | `bundles`, `named_queries` | JSON vs protobuf |
| `documentOverlays` | keyPath `[userId, collectionPath, documentId]`; two indexes | `document_overlays` (`overlay_mutation` BLOB) | JSON vs protobuf |
| `indexConfiguration`, `indexState`, `indexEntries` | see `indexeddb_schema.ts` | same names | same concept, different encodings |
| `globals` | keyPath `name` | `globals` | same idea |
| none | | `persistence_epoch`, `data_migrations` | port only |

### Versions on disk

IndexedDB upgrades a database only when a client opens it, so a profile can hold any version
the app's JS SDK last opened it with. Pending writes have been in `mutations`, in today's
shape, since version 5. Cached documents are in `remoteDocumentsV14` from version 13 on; older
databases have the `remoteDocuments` store. Porting the JS migrations (the version 13 rewrite
of remote documents and the version 14 overlays are the large ones) is only needed to read
documents of databases older than 13. An importer can instead read `mutations` from any
version 5 and up and take documents only from 13 and up (or 18 only); documents are a cache
and the backend refills it.

### Can a Dart tab and an old JS tab share the database?

Only if the Dart engine writes the JS formats exactly (option A below) and speaks the same
LocalStorage protocol: the lease and client fields match, but the JS SDK has no Web Lock and
relies on the `owner` lease and LocalStorage. With this port's own format (SQLite, or an
IndexedDB engine with its own schema), they are two separate databases and nothing is shared;
the Dart SDK must take the JS database over exclusively: import once when no JS tab is active
(the `owner` lease older than 5 s, no `clientMetadata` row newer than 30 minutes, no live
`firestore_clients_*` key), then mark it imported (delete it, or keep a marker).

### The two options

Line counts today: this port's `local/sqlite/*.dart` is 5,926 lines in 18 files; the JS SDK's
`indexeddb_*.ts` (schema, sentinels, converter, persistence) 2,963 lines plus
`local_serializer.ts` 629, `simple_db.ts` 945, and its IndexedDB caches (mutation queue 685,
remote documents 692, targets 439, overlays 244, bundles 103, index manager 1,137, LRU 267).

- **(A) An IndexedDB engine on the JS SDK's schema as its own format.** Estimate: 5,000 to
  6,500 lines of Dart in 15 to 20 files: persistence, lease and client metadata 1,200 to
  1,500; the caches 1,800; the index manager on IndexedDB entries 1,000 to 1,200; schema
  creation and the JS migrations 600 to 900; a transaction wrapper over `package:web` 500 to
  700; a proto3-JSON local serializer 400 to 600; a LocalStorage `SharedClientStateStorage`
  100 to 150. The switch needs no migration, and a Dart tab could even share the profile with a
  JS tab. The cost: the format is owned by another project; every new JS schema version has
  to be followed, and the Android-shaped code of this port (protobuf rows, SQL queries) has to
  be rewritten against JSON rows and IndexedDB keys.
- **(B) A one-time importer** that reads the JS database and writes into this port's cache,
  whatever engine that is. Estimate: 400 to 900 lines in 4 to 6 files: pending writes only 300
  to 400 (shown to work, below), plus remote documents and targets 200 to 300, plus overlays
  and index state about 300 (not needed: the port rebuilds overlays from the mutation queue).
  It has to handle databases older than version 18 (above), a JS tab that is still open, and
  marking the import done. After the switch, JS and Dart tabs cannot share the profile.

### The check

`tool/bench/web_idb/js_import/` (needs `npm install` there; `run_page.sh` serves `static/` and
runs a page in headless Chrome with a fixed profile):

1. `writer.js`, bundled with esbuild, runs the official SDK (`firebase` 12.19.0) with
   `persistentLocalCache` and `persistentSingleTabManager`, project `demo-idb`,
   `disableNetwork()` first. It loads a bundle with one document `items/cached1` (offline
   writes alone never create rows in the remote document cache), then queues without awaiting
   a `setDoc` with every value type and a `serverTimestamp()`, a `setDoc` and an `updateDoc`
   with `increment`, `arrayUnion` and a dotted field path, and a `deleteDoc`; a
   `getDocFromCache` afterwards shows they are stored. Four mutation batches in the database.
2. `reader.dart`, compiled with dart2js, opens `firestore/[DEFAULT]/demo-idb/main` on the same
   origin (at version 18, without upgrading it), reads `remoteDocumentsV14` and `mutations`,
   and converts each row: `JSON.stringify` then `jsonDecode`, `mergeFromProto3Json` into the
   port's generated `proto.Document` / `proto.Write` classes (they accept the JS proto3 JSON as
   it is), wraps them into `proto.MaybeDocument` / `proto.WriteBatch`, and decodes them with the
   port's unchanged `LocalSerializer`.

Result: the decode works. The cached document came out as a synced `Document` with the right
version and every value type (array, bytes, double, geo point, nested map with null, integer,
reference, string, timestamp). The four batches came out as `MutationBatch`es: a `SetMutation`
with a server-timestamp transform, a `SetMutation`, a `PatchMutation` with its field mask and
the increment and array-union transforms, and a `DeleteMutation`. Not exercised: deleted
(`noDocument`) and `unknownDocument` rows (the reader's `noDocument` branch is a sketch), and
the `targets`, `targetDocuments`, `documentOverlays` and `owner` stores.

## Summary

| Question | Measured or estimated | Result |
| --- | --- | --- |
| Bytes saved, IndexedDB storage, dart2js | estimate from measured parts | about 800 to 845 KB raw, 377 to 390 KB gzipped, of today's 1,011 KB / 436 KB |
| Bytes saved, IndexedDB storage, dart2wasm | estimate from measured parts | about 810 to 865 KB raw, 382 to 401 KB gzipped, of today's 1,067 KB / 469 KB |
| Bytes saved, OPFS storage | estimate | the above plus the worker, 174 KB raw / 54 KB gzipped |
| Start-up, cache open + first read, today | measured, local server | SQLite on IndexedDB 22 to 35 ms, on OPFS 29 to 43 ms; memory cache 0.2 to 1.8 ms |
| Start-up, IndexedDB engine | estimate | memory cache + 2 to 5 ms, not growing with the cache size, and no `sqlite3.wasm` download (365 KB gzipped: about 0.3 s at 10 Mbit/s, computed) |
| Start-up difference | estimate | about 17 to 40 ms less on a local server, plus the download on a real network; SQLite on IndexedDB also grows with the cache (44 to 52 ms at 10 MB) |
| `insert_tx1`, SQLite time / IndexedDB time | measured | 10.5x and 7.5x (dart2js: SQLite on IndexedDB, on OPFS); 8.6x and 10.7x (dart2wasm) |
| `insert_tx100` (awaited puts) | measured | 2.1x and 0.67x (dart2js); 2.2x and 0.61x (dart2wasm) |
| `get` | measured | 0.08x and 0.38x (dart2js); 0.08x and 0.37x (dart2wasm): IndexedDB slower |
| `scan` of 1,000 keys | measured | 0.19x and 0.31x (dart2js); 0.30x and 0.45x (dart2wasm): IndexedDB slower |
| `delete_tx1` | measured | 10x and 5.8x (dart2js); 7.1x and 27x (dart2wasm, noisy) |
| `reopen_and_get`, 10 MB | measured | 0.2 ms on IndexedDB against 23 to 52 ms |
| Transaction across awaits (point 4) | measured, Chrome 157, both compilers | survives futures, microtasks, IndexedDB requests and chains of them; closes on any timer (`Future.delayed`, `Timer.run`, `Future(() {})`), committing what came before. The local store awaits no timer, isolate or I/O inside a transaction: the contract can be met |
| Multi-tab (point 5) | read from code | the JS SDK needs a lease and client rows in IndexedDB plus LocalStorage messages; this port has both pieces storage-agnostic or on two small tables, and could move them onto IndexedDB; not needed for a first engine |
| JS SDK cache (point 6) | measured decode, estimated sizes | schema 18, proto3 JSON values; pending writes and cached documents decode into this port's model with its own serializer. Importer (B) 400 to 900 lines; engine on the JS schema (A) 5,000 to 6,500 lines |

### Estimates, not measurements

- The size of an IndexedDB engine's code (point 1): 90 to 130 KB of dart2js output for the
  engine, half of the "everything else" growth kept, 10 to 15 KB for the wrapper; dart2wasm
  scaled by the same factor. Everything else in point 1 is measured.
- The start-up of an IndexedDB engine (2 to 5 ms over the memory cache) and the download
  time of `sqlite3.wasm` on a real network (arithmetic, not a throttled run).
- The line counts of options A and B (point 6), and of a LocalStorage
  `SharedClientStateStorage` and an IndexedDB client metadata (point 5).
- That an engine's real transactions keep the ratios of point 3, which measured one store of
  1 KB blobs.

### Not measured on this machine

- Other browsers: everything ran in Chrome 157 only. In particular point 4 (transaction
  lifetime across microtasks) is not checked in Safari or Firefox.
- A real network: the server was on 127.0.0.1 without compression; no throttled run.
- A quiet machine: the load average was 10 to 20 during the runs, hence the wide ranges.
- Memory use of the engines.
- Point 6: deleted and unknown documents, targets, target documents, overlays and the
  `owner` store of a JS database were not read; databases older than version 18 were not
  tried.
