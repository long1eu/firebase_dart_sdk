# Platforms

`cloud_firestore_dart` is pure Dart. On the Dart VM (servers, command line tools, Flutter apps
on Android, iOS and desktop) it talks gRPC; in the browser it uses the transport of the JS SDK.
This page has what is known about each platform, and how far each was tested.

## The Dart VM and Flutter

Pure Dart on the VM (`dart:io`, `package:grpc`, SQLite through an `OpenDatabase` function you
supply, for example with `package:sqlite3`). Targets Dart `^3.8.0` (the minimum of `grpc` 5). Developed and tested on
macOS. On Linux the unit tests and the standard integration suite (against the emulator) pass in a Debian arm64
container (`tool/linux/run_in_container.sh`), and CI runs them on Ubuntu x64. Windows is
expected to work but is not tested. Flutter apps (Android, iOS, desktop) can use it as a plain Dart package.

- Linux: `package:sqlite3` 2.x loads `libsqlite3.so`, which only the development package installs (`libsqlite3-dev`
  on Debian and Ubuntu); with just the runtime package (`libsqlite3-0`) it fails with "Failed to load dynamic library
  'libsqlite3.so'". The opener in `example/sqlite_database.dart` falls back to `libsqlite3.so.0`.
- Windows: `package:sqlite3` loads `sqlite3.dll`, which Windows does not ship: put it next to the executable or on
  the `PATH` (`sqlite3_flutter_libs` bundles it in a Flutter app). SQLite locks files with `LockFileEx` there, so
  two clients on one file behave as on Linux and macOS, but `Firestore.clearPersistence()` fails with `unknown` while
  any other handle (another isolate or process) still has the file open, where Linux and macOS delete it anyway.

## The web (experimental)

Web support is experimental. Browsers have no sockets, so there the client talks to
Firestore the way the JS SDK does: REST/JSON for the one-shot calls and WebChannel for the
listen and write streams, over `fetch`. What to know:

- The cache is in memory by default. To keep it across page loads, pass the `OpenDatabase` of
  [`example/sqlite_database_web.dart`](../../cloud_firestore/cloud_firestore_dart/example/sqlite_database_web.dart) (copy the file into
  your app): SQLite compiled to WebAssembly by `package:sqlite3`. It needs the `sqlite3.wasm`
  file of that package next to your page. It stores the database in one of two places:
  - **IndexedDB** (the default): SQLite runs in the page on a copy of the whole database in
    memory, and the opener waits for IndexedDB at the end of every transaction.
  - **OPFS** (the origin private file system), when you also copy
    [`example/sqlite_opfs_worker.dart`](../../cloud_firestore/cloud_firestore_dart/example/sqlite_opfs_worker.dart), compile it with
    `dart compile js` and pass its URL as `opfsWorker`. SQLite then runs in that dedicated
    worker on a file it reads as it needs (synchronous access handles, `SimpleOpfsFileSystem`
    of `package:sqlite3`), so the database is not held in memory. No cross-origin isolation
    headers are needed. In a browser without synchronous OPFS access in workers the opener
    falls back to IndexedDB. The first OPFS open of a cache that is in IndexedDB moves it to
    OPFS, pending writes included.

  One tab at a time with either: a second tab that opens the same cache gets a
  `FirestoreError` with `failedPrecondition` (a Web Lock guards the database) and should use a
  memory cache; `openWithMemoryFallback` in that file does this. `clearPersistence()` deletes
  the IndexedDB database or the OPFS directory. Cost, measured for a small app compiled with
  `dart compile js -O2`: 588 KB (180 KB gzipped) with a memory cache, 807 KB (239 KB gzipped)
  with the persistent cache, plus `sqlite3.wasm`, 731 KB (349 KB gzipped); the OPFS worker is
  183 KB more (`-O2`).
  - Crash safety: what a write future acknowledged is stored, and a tab that dies in the middle
    of a transaction loses only that transaction (SQLite's rollback journal is stored too and
    is applied on the next open). Tested by killing a worker at random moments, 2700 times on
    IndexedDB and 1500 times on OPFS. A crash of the browser itself or a power cut is not
    covered.
  - Memory and speed, measured in headless Chrome 157 with documents of about 1 KB
    (`dart run tool/web_storage_benchmark/run.dart`; memory is
    `performance.measureUserAgentSpecificMemory()` of the page and its workers; open; median
    read of one document by id; a query that scans the collection for one document; a full
    scan; memory once open; memory holding the snapshot of the full scan):

    | Documents | Compiler | Storage | Open | Read by id | Filtered | Full scan | Memory open | With the scan |
    |---|---|---|---|---|---|---|---|---|
    | 10,000 | dart2js | IndexedDB | 66 ms | 0.06 ms | 0.10 s | 0.21 s | 20 MB | 66 MB |
    | 10,000 | dart2js | OPFS | 34 ms | 0.14 ms | 0.11 s | 0.19 s | 7 MB | 53 MB |
    | 10,000 | dart2wasm | IndexedDB | 76 ms | 0.10 ms | 0.16 s | 0.09 s | 15 MB | 57 MB |
    | 10,000 | dart2wasm | OPFS | 42 ms | 0.13 ms | 0.09 s | 0.13 s | 3 MB | 46 MB |
    | 100,000 | dart2js | IndexedDB | 1.05 s | 0.09 ms | 0.98 s | 2.0 s | 138 MB | 592 MB |
    | 100,000 | dart2js | OPFS | 52 ms | 0.16 ms | 1.0 s | 2.3 s | 7 MB | 462 MB |
    | 100,000 | dart2wasm | IndexedDB | 0.55 s | 0.17 ms | 1.5 s | 2.2 s | 133 MB | 557 MB |
    | 100,000 | dart2wasm | OPFS | 45 ms | 0.12 ms | 0.83 s | 1.5 s | 3 MB | 427 MB |

    A second run gave the same memory to the MB and times up to twice as long (100,000
    documents: open 0.6 to 1.2 s with IndexedDB, 77 to 166 ms with OPFS). OPFS keeps memory
    flat (a few MB) and opens in well under 0.2 s at any size; IndexedDB holds the whole database (about 1.4 KB per document)
    and opens in time proportional to it. A query that returns 100,000 documents needs about
    0.45 GB with either storage: that is the snapshot, not the storage. Reads cost about the
    same; with OPFS each statement is a round trip to the worker (tens of microseconds).
    The default cache size limit of 100 MB starts evicting unused documents before 100,000.
  - The opener works around a slowness of `sqlite3` 2.9.4 compiled with dart2wasm, where
    every read of the IndexedDB database cost a copy of the whole file (0.7 s to open and
    2.4 s to scan 1,000 documents, and worse with the size). Use the opener as it is in
    `example/`; an older copy without `_ReadCopyFileSystem` is that slow.
- Against the emulator, a query that returns more than about 10,000 documents fails on the
  web with `unavailable` (the emulator's WebChannel endpoint drops the stream; over gRPC the
  same query works). Read such collections in pages there. Whether the production backend
  has such a limit was not checked.
- It was verified against the emulator only: 52 tests in Chrome (`tool/test_browser.sh both`
  from the repository root; 51 pass and 1 is skipped with each compiler: under dart2wasm the
  crash harness of the IndexedDB storage, under dart2js the test of 64 bit integers), and the
  whole standard integration suite on the VM over the web transport
  (`tool/test_integration.sh standard --transport=webchannel`). Other browsers and the
  production backend are untested.
- Prefer dart2wasm. Compiled to JavaScript, integers above 2^53 lose precision.
- If listeners or writes never complete on some network (a proxy or antivirus that buffers
  streamed responses), set `FirestoreSettings(experimentalForceLongPolling: true)`. The
  client also tries to detect this by itself (`experimentalAutoDetectLongPolling`, on by
  default).
- Do not compile with `-Dprotobuf.omit_field_names=true` or `-Dprotobuf.omit_enum_names=true`:
  the web transport needs those names, and refuses to start without them.

See [Offline persistence on the web](offline_persistence.md#on-the-web) for how to set up the
IndexedDB cache, and [Firestore Lite](lite.md) for a smaller client.
