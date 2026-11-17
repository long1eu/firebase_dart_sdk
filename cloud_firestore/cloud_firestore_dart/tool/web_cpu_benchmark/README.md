# Web CPU benchmark: dart2js or dart2wasm

Runs the client work of `cloud_firestore_dart` in headless Chrome, compiled with
`dart compile js -O2` and with `dart compile wasm -O2`, and prints one table that puts the two
compilers side by side. It answers one question: for this library, in a browser, where is
dart2wasm faster, slower or the same as dart2js? The results and the recommendation are in
[docs/guides/performance.md](../../../../docs/guides/performance.md#dart2js-or-dart2wasm-in-the-browser).

No emulator and no backend: every client has its network disabled, and its cache is filled from
a bundle built in the page.

## Run it

From `cloud_firestore/cloud_firestore_dart`, after `tool/build_web_test_assets.sh` (repository
root) has fetched `sqlite3.wasm` and compiled the OPFS worker:

```sh
dart run tool/web_cpu_benchmark/run.dart --runs 7 --reps 5 --out /tmp/wasm_bench.jsonl
```

| Option | Default | What it does |
|---|---|---|
| `--runs` | 7 | Runs per compiler. Each run is a new Chrome with an empty profile. |
| `--reps` | 5 | Measured repetitions of each case inside a run, after one warm-up. |
| `--suites` | `cpu,sqlite,startup` | Which pages to run (below). |
| `--storages` | `indexeddb,opfs` | The SQLite storages of the `sqlite` suite. |
| `--sqlite-docs` | 10000 | Documents in the SQLite cache. |
| `--compilers` | `dart2js,dart2wasm` | Which builds to run. |
| `--out` | none | Also writes every report as one JSON line to this file. |
| `--chrome-flags` | none | More Chrome flags, space separated. |

`CHROME` sets the Chrome binary (default: Google Chrome in `/Applications` on macOS). The
full run (7 runs, 5 repetitions) takes about an hour on an Apple M5.

## Method

- The compilers alternate: dart2js runs first in even runs, dart2wasm in odd ones, so that a
  slow minute of the machine hits both.
- Each case runs once to warm up, then `--reps` times; the page reports the median of those.
  The table gives, per compiler, the **median, minimum and maximum of the per-run values** over
  the runs, and the ratio of the medians.
- The verdict column says `wasm lower` or `js lower` only when the ranges of the two compilers
  do not overlap (the maximum of one is below the minimum of the other); otherwise
  `within spread`. Do not read a difference into a ratio whose verdict is `within spread`.
- The page is served with cross-origin isolation (COOP and COEP), so that `performance.now()`
  has its finest resolution and `performance.measureUserAgentSpecificMemory` is available.
  Chrome runs with `--headless=new` and `--enable-blink-features=ForceEagerMeasureMemory`.

## The cases

Times are in milliseconds unless the name ends with `_us` (microseconds per operation).

**`cpu` suite** (`page.dart?suite=cpu`), memory cache:

| Case | What it measures |
|---|---|
| `ser_<shape>_remote_encode_us` | A user map to the bytes sent to the backend: `UserDataConverter.parseSetData`, `RemoteSerializer.encodeValue`, `writeToBuffer`. |
| `ser_<shape>_remote_decode_us` | Those bytes back: `Value.fromBuffer`, `RemoteSerializer.decodeValue`. |
| `ser_<shape>_local_encode_us` | A document to the bytes a persistent cache stores: `LocalSerializer.encodeMaybeDocument`, `writeToBuffer`. |
| `ser_<shape>_local_decode_us` | Those bytes back to the document's data. |
| `ser_<shape>_bytes` | The size of the encoded value (dart2js encodes an integral `double` such as `3.0` as an integer, so its bytes can differ). |
| `mem_<n>_bundle_load` | Loading a bundle of `n` documents of about 250 bytes into the memory cache (once per run, no warm-up). |
| `mem_<n>_filter` | `where('n', isEqualTo: n / 2).get(Source.cache)`: a scan of `n` documents, one result. |
| `mem_<n>_orderby_limit` | `orderBy('n', descending: true).limit(10).get(Source.cache)`. |
| `mem_<n>_listener_first` | The first snapshot of a listener on `where('g', isEqualTo: 3)` (a tenth of the documents). |
| `write_500_fanout_<k>` | A batch of 500 `set` calls, from `commit()` until each of `k` listeners (each on its own query, so each has its own view) has a snapshot with all 500 documents. The commit itself never completes: the network is off. A new client every repetition. |
| `remote_event_1000` | `SyncEngine.handleRemoteEvent` with a remote event that modifies 1,000 documents of a listened query, on a memory cache, until the view snapshot is raised: applying the changes to the cache and computing the view. The watch stream is not involved (the remote store is a stub). |
| `memory_before_mb`, `memory_50000_mb`, `memory_50000_delta_mb` | `performance.measureUserAgentSpecificMemory()` before and after loading 50,000 documents into a memory cache. It counts the JavaScript heap, which holds the WasmGC objects of dart2wasm as well, array buffers and WebAssembly memories, so the two compilers are measured the same way. |

The shapes: `small` (four scalar fields), `1kb` (six small maps and a 300 character string),
`50kb` (400 small maps; the `leaf` maps of `tool/bench/serialization_bench.dart`, whose
serializers and `deep` shape the page imports), `deep20` (maps nested 20 levels, the backend's
limit).

**`sqlite` suite** (`page.dart?suite=sqlite&storage=...`): the three queries of the memory cache
on a SQLite cache of 10,000 documents (`cloud_firestore_dart_sqlite`'s web opener), in IndexedDB
or in OPFS, right after the bundle filled it: `<storage>_<n>_filter`, `_orderby_limit`,
`_listener_first`, `_bundle_load`.

**`startup` suite** (`startup.dart`): what the playground does when it opens (a client on a
memory cache, `disableNetwork()`, one listener), loaded three times in the same profile: `cold`
(empty HTTP cache), `warm` (second load: files from the HTTP cache) and `hot` (third load: V8's
code caches are populated too). Times are from the start of the navigation:
`startup_<load>_main` (Dart `main` starts), `_ready` (`disableNetwork()` done),
`_first_snapshot`, and `_boot_to_snapshot`, from the first script of the page to the first
snapshot (without the navigation and the HTML, which do not depend on the compiler). For dart2js, `_parse_to_main` is from the end of the script download to
`main`. For dart2wasm, `_load_compile` is `compileStreaming` (download and compilation overlap),
`_instantiate` the instantiation and `_to_main` the rest until `main`. The sizes of the two
start-up builds are in the first line of the output.

## Files

| File | What it is |
|---|---|
| `run.dart` | Compiles the pages, serves them, starts Chrome for every run, prints the table. |
| `page.dart` | The `cpu` and `sqlite` suites. |
| `startup.dart` | The start-up page. |
