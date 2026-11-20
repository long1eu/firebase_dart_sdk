## 0.1.3

- The constraint on `cloud_firestore_dart` is `>=0.2.0 <0.4.0` instead of `^0.2.0`, so that the package can be used with
  `cloud_firestore_dart` 0.3.0.
- The native database keeps the prepared statements of its last 64 distinct queries: a read of one
  document from the cache is about a third faster.

## 0.1.2

- **The IndexedDB storage refuses `sqlite3` 3.4.0 to 3.5.2.** With them it could lose writes it had
  acknowledged when the tab was closed or crashed a moment later (their `IndexedDbFileSystem.flush()`
  waits for nothing while a batch of writes is in progress; see 0.1.1), and a fresh Flutter app gets
  3.5.2: Flutter 3.44 pins `meta` 1.18, and `sqlite3` 3.6.0 needs 1.19. Before its first IndexedDB open
  a page now checks what `flush()` does (a few milliseconds, in a scratch IndexedDB database it deletes
  again), and with those versions the open fails with a `SqliteWebSetupException`
  (`SqliteWebSetupProblem.unsafeSqlite3`) whose message names the cause and the ways out: pin a safe
  `sqlite3` (`sqlite3: 3.3.4` or `^2.7.3` with Flutter 3.44, `^3.6.0` where `meta` 1.19 is allowed),
  or use the OPFS storage. `sqliteOpener(acceptIndexedDbWriteLoss: true)` opens anyway. The Dart VM,
  Flutter on other platforms and the OPFS storage do not run the check.
- **A `sqlite3.wasm` that does not fit is named.** When `sqlite3.wasm` cannot be loaded the open now
  fails with a `SqliteWebSetupException` that says why: missing (`wasmMissing`, with the HTTP status),
  not WebAssembly (often the page a server sends for a missing file), or the build of another `sqlite3`
  release (`wasmVersionMismatch`, with the major line of the file: a 2.x build with a 3.x package, or
  the reverse, failed with a `LinkError` or `TypeError` about an import before). For the OPFS worker
  too. A file of another minor version that happens to load is not detected.
- `openWithMemoryFallback` rethrows a `SqliteWebSetupException` instead of falling back to a memory
  cache: it is a mistake of the build that a memory cache would hide in every tab.
- README: records the first Windows run (Windows 11 x64, 2026-11-17): the Dart VM with `sqlite3` 3.9.1, which
  loads the build hook's `sqlite3.dll`, and with 2.9.4, which falls back to the `winsqlite3.dll` of Windows; and
  two Flutter Windows apps with 3.5.2. No code change.

## 0.1.1

- **Fix: the IndexedDB storage in a browser could lose acknowledged writes with `sqlite3` 3.x.**
  Affected: browser apps on 0.1.0 that use the IndexedDB storage (`sqliteOpener()` without
  `opfsWorker`, or with it in a browser without synchronous OPFS in workers) and resolve
  `sqlite3` 3.4.0 or later (pub picks the newest 3.x on Dart 3.10 or later). When the tab was
  killed or crashed shortly after a write, that write could be missing on the next page load
  although its future had completed. Lost were whole transactions at the end, never a part of
  one: the database stayed intact. The opener waited for the IndexedDB file system of `sqlite3`
  with one `flush()`, which since `sqlite3` 3.6.0 returns when the batch of writes in progress is
  stored, not the writes queued behind it. It now waits for those too (see the README for what
  each `sqlite3` version does). Not affected: `sqlite3` 2.7.3 to 3.3.4, the OPFS storage, the
  Dart VM and Flutter.
- `sqlite3` 3.4.0 to 3.5.2 cannot be made safe this way: their `flush()` does not wait at all
  while writes are in progress. Do not use them with the IndexedDB storage; pub only picks them
  when you pin them.
- With `sqlite3` 3.x a write transaction on the IndexedDB storage now waits for IndexedDB, which
  it did not before: in Chrome the median went from 0.6 to 1.3 ms to 1.2 to 1.7 ms per
  transaction (`tool/web_storage_benchmark` of the repository, noisy). With 2.x the extra
  `flush()` made no measurable difference.

## 0.1.0

First version, for `cloud_firestore_dart` 0.2 (`FirebaseFirestore`, `Settings`,
`FirestoreException`). The SQLite openers that `cloud_firestore_dart` 0.1.1 kept in its `example/` folder
for apps to copy (`sqlite_database.dart`, `sqlite_database_web.dart`, `sqlite_opfs_worker.dart`),
moved into a package. Their logic is unchanged; what differs:

- **One function for every platform:** `sqliteOpener({directory, pageCacheMb, sqlite3Wasm,
  opfsWorker, storagePrefix, lockTimeout})` replaces `sqliteOpener(Directory, {pageCacheMb})` on
  the VM and `sqliteWebOpener(...)` in the browser. `directory` is a path `String` (no `dart:io`
  type, so the call compiles on the web); `sqlite3Wasm` defaults to `sqlite3.wasm`. The storage
  names, the file names and the Web Lock names are the ones of the copied files, so a cache
  written by them is opened again.
- **`openWithMemoryFallback`** takes the `OpenDatabase` to try (`openDatabase: sqliteOpener(...)`)
  instead of `sqlite3Wasm` and `opfsWorker`, and works on every platform.
- **`sqlite3` 2.7.3 to 3.x.** The VM opener no longer imports `package:sqlite3/open.dart`, which
  3.x removed, and so no longer overrides the library lookup on Linux. With 3.x the library comes
  from the build hook of `sqlite3`. With 2.x the default lookup of `sqlite3` applies: this fixes
  Flutter on Linux, where the override made the copied opener load the system SQLite instead of
  the one `sqlite3_flutter_libs` bundles; a plain Dart program on a Linux machine without
  `libsqlite3.so` needs the override the README shows.
- `close()` still calls `dispose()`, the only close of 2.x (deprecated, not removed, in 3.x).
- **The OPFS worker** is the library `package:cloud_firestore_dart_sqlite/opfs_worker.dart`
  (`runOpfsWorker`), and `dart run cloud_firestore_dart_sqlite:setup_web [web dir]` compiles it to
  `<web dir>/sqlite_opfs_worker.js` and prints the URL of the matching `sqlite3.wasm`.
- The browser-only classes (`SqliteWebDatabase`, `SqliteOpfsDatabase`, `inspectOpfsDatabase`,
  `sqliteWebOpener`) are in `package:cloud_firestore_dart_sqlite/web.dart`.
