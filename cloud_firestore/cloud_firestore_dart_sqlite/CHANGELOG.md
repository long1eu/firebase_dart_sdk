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
