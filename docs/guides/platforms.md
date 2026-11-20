# Platforms

`cloud_firestore_dart` is pure Dart. On the Dart VM (servers, command line tools, Flutter apps
on Android, iOS and desktop) it talks gRPC; in the browser it uses the transport of the JS SDK.
This page has what is known about each platform, and how far each was tested.

In short, read across a row for the transport and the caches of a platform:

| Platform | Transport | Cache without an `openDatabase` | Persistent cache | Tested |
|---|---|---|---|---|
| Dart VM (servers, command line) | gRPC | memory | SQLite file (`cloud_firestore_dart_sqlite`) | macOS, Linux, Windows 11 x64 (one VM, not in CI) |
| Flutter on Android, iOS, desktop | gRPC | memory | SQLite file (`cloud_firestore_dart_sqlite`) | not on Android or iOS; desktop apps on macOS, Linux (Debian 13) and Windows 11 x64, against the emulator |
| Web, dart2wasm | REST and WebChannel over `fetch` | memory | SQLite in WebAssembly, in IndexedDB or OPFS (`cloud_firestore_dart_sqlite`) | Chrome, against the emulator |
| Web, dart2js | REST and WebChannel over `fetch` | memory | the same as dart2wasm | Chrome, against the emulator; integers above 2^53 lose precision |

## The Dart VM and Flutter

Pure Dart on the VM (`dart:io`, `package:grpc`, SQLite through an `OpenDatabase` function you
supply, for example with `package:sqlite3`). Targets Dart `^3.8.0` (the minimum of `grpc` 5). Developed and tested on
macOS. On Linux the unit tests and the standard integration suite (against the emulator) pass in a Debian arm64
container (`tool/linux/run_in_container.sh`), and CI runs them on Ubuntu x64. On Windows 11 x64
(a VM, Dart 3.13.7, 2026-11-17) the unit tests (5947 passed) and the standard integration suite against the
emulator (903 passed, 22 skipped) pass, after fixes to test helpers that assumed POSIX paths, `\n` line ends or
that an open file can be deleted; nothing in `lib/` changed. CI does not run Windows. SQLite commits were much
slower on that VM than on a Mac (about 78 ms each in rollback-journal mode and 24 ms in WAL mode, against 0.3 and 0.1 ms), because
each commit waits for the virtual disk to flush; two to four tests on SQLite (depending on the load) needed more
than their timeouts there and passed with `--ignore-timeouts`. Flutter apps (Android, iOS, desktop) can use it as
a plain Dart package.

- Linux: with `sqlite3` 3.x (Dart 3.10 and later) the opener of `cloud_firestore_dart_sqlite` uses the SQLite that
  the build hook of `sqlite3` bundles; `dart build cli` puts it next to the program, `dart compile exe` does not and
  the program then needs the system library (seen on macOS; the 3.x path was not tried on Linux). `sqlite3` 2.x
  loads `libsqlite3.so`, which only the development package installs (`libsqlite3-dev` on Debian and Ubuntu); with
  just the runtime package (`libsqlite3-0`) it fails with "Failed to load dynamic library 'libsqlite3.so'". The
  README of `cloud_firestore_dart_sqlite` has an override that falls back to `libsqlite3.so.0`.
- Windows: `sqlite3` 3.x bundles SQLite. On Windows 11 with `sqlite3` 3.9.1, `dart run` loaded the
  `sqlite3.dll` of the build hook (SQLite 3.54.1) from `.dart_tool\lib`, and `dart build cli` put it in
  `bundle\lib\` next to the program. `sqlite3` 2.x loads `sqlite3.dll` from next to the executable or the `PATH`
  (`sqlite3_flutter_libs` bundles it in a Flutter app) and, from 2.7.5 on, falls back to `winsqlite3.dll`, which
  Windows ships: with 2.9.4 and no `sqlite3.dll` it loaded `C:\Windows\System32\winsqlite3.dll` (SQLite 3.51.1).
  With both, a cache was written, read back offline by a new process and cleared. SQLite locks files with
  `LockFileEx` there, so two clients on one file behave as on Linux and macOS. `Firestore.clearPersistence()`
  while another process had the cache open emptied it in place, as on the other platforms; once no client had it
  open, it deleted the files. Windows does not delete a file that is still open, so code that deletes the cache
  files itself must close every connection first (a killed isolate never closes its own).
- Windows, `dart run`: a second `dart run` of the same package fails while the first still runs, because it
  tries to replace `.dart_tool\lib\sqlite3.dll`, which the first one has loaded ("Access is denied"). For
  several processes, build once with `dart build cli` and start the executable.

## The web (supported in Chrome)

Web is supported in Chrome; Firefox, Safari and Edge are untested. Browsers have no sockets, so there the client talks to
Firestore the way the JS SDK does: REST/JSON for the one-shot calls and WebChannel for the
listen and write streams, over `fetch`. What to know:

- The cache is in memory by default. To keep it across page loads, pass `sqliteOpener()` of
  [`cloud_firestore_dart_sqlite`](../../cloud_firestore/cloud_firestore_dart_sqlite/): SQLite
  compiled to WebAssembly by `package:sqlite3`. It needs the `sqlite3.wasm` file of that package
  next to your page. It stores the database in one of two places:
  - **IndexedDB** (the default): SQLite runs in the page on a copy of the whole database in
    memory, and the opener waits for IndexedDB at the end of every transaction.
  - **OPFS** (the origin private file system), when you pass the URL of the worker that
    `dart run cloud_firestore_dart_sqlite:setup_web web` compiles as `opfsWorker`. SQLite then runs in that dedicated
    worker on a file it reads as it needs (synchronous access handles, `SimpleOpfsFileSystem`
    of `package:sqlite3`), so the database is not held in memory. No cross-origin isolation
    headers are needed. In a browser without synchronous OPFS access in workers the opener
    falls back to IndexedDB. The first OPFS open of a cache that is in IndexedDB moves it to
    OPFS, pending writes included.

  A third, experimental option needs neither `sqlite3.wasm` nor the package: `indexedDbCacheSettings()` of
  `package:cloud_firestore_dart/indexeddb_cache.dart` stores the cache in the official JS SDK's own
  IndexedDB database and format, so an app can switch between the two SDKs in both directions (about
  121 KB more JavaScript, 34 KB gzipped, only when imported). See
  [The IndexedDB cache](web.md#the-indexeddb-cache-experimental).

  A fourth needs no package either: `keyValueCacheSettings(store: ...)` of
  `package:cloud_firestore_dart/cache_store.dart` keeps the cache in a key-value store the app
  implements, on the VM or the web; `example/cache_store/indexeddb` is such a store on IndexedDB.
  See [A cache in your own storage](custom_cache_store.md).

  One tab at a time with either: a second tab that opens the same cache gets a
  `FirestoreException` with `failedPrecondition` (a Web Lock guards the database) and should use a
  memory cache; `openWithMemoryFallback` of the package does this. `clearPersistence()` deletes
  the IndexedDB database or the OPFS directory. Cost, measured for a small app compiled with
  `dart compile js -O2`: 588 KB (180 KB gzipped) with a memory cache, 807 KB (239 KB gzipped)
  with the persistent cache, plus `sqlite3.wasm`, 759 KB (364 KB gzipped); the OPFS worker is
  174 KB more (`-O2`, 54 KB gzipped, built with `sqlite3` 3.9.1; 185 KB with 2.9.4).
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
    2.4 s to scan 1,000 documents, and worse with the size). `cloud_firestore_dart_sqlite`
    keeps that workaround (`_ReadCopyFileSystem`); `sqlite3` 3.8 fixed the slowness itself.
- Against the emulator, a query that returns more than about 10,000 documents fails on the
  web with `unavailable` (the emulator's WebChannel endpoint drops the stream; over gRPC the
  same query works). Read such collections in pages there. Whether the production backend
  has such a limit was not checked.
- It was verified against the emulator only: 57 tests in Chrome (`tool/test_browser.sh both`
  from the repository root; 56 pass and 1 is skipped with each compiler: under dart2wasm the
  crash harness of the IndexedDB storage, under dart2js the test of 64 bit integers), and the
  whole standard integration suite on the VM over the web transport
  (`tool/test_integration.sh standard --transport=webchannel`). Other browsers and the
  production backend are untested.
- A Flutter web app works the same way: [A Flutter web app](web.md#a-flutter-web-app) and
  [`examples/flutter_web_two_users`](../../examples/flutter_web_two_users/), built with both
  compilers in CI. On Flutter 3.44 pin `sqlite3: 3.3.4` for the IndexedDB cache:
  `cloud_firestore_dart_sqlite` 0.1.2 refuses the 3.5.2 that Flutter 3.44 resolves
  ([The `sqlite3` version](web.md#the-sqlite3-version)).
- Prefer dart2wasm. Compiled to JavaScript, integers above 2^53 lose precision, and shifts are
  32-bit (`1 << 32` is `0`).
- If listeners or writes never complete on some network (a proxy or antivirus that buffers
  streamed responses), set `Settings(webExperimentalForceLongPolling: true)`. The
  client also tries to detect this by itself (`webExperimentalAutoDetectLongPolling`, on by
  default). If such a proxy cuts long-polling requests before the 30 seconds the backend holds
  them, ask for a shorter timeout:
  `webExperimentalLongPollingOptions: WebExperimentalLongPollingOptions(timeoutDuration: Duration(seconds: 25))`
  (5 to 30 seconds, as in the JS SDK).
- Do not compile with `-Dprotobuf.omit_field_names=true` or `-Dprotobuf.omit_enum_names=true`:
  the web transport needs those names, and refuses to start without them.

See [Offline persistence on the web](offline_persistence.md#on-the-web) for how to set up the
IndexedDB cache, and [Firestore Lite](lite.md) for a smaller client.
