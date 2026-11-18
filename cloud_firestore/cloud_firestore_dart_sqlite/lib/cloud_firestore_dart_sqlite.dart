/// The SQLite offline cache of `cloud_firestore_dart`: one [sqliteOpener] for
/// the Dart VM, Flutter and the browser.
///
/// ```dart
/// final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
///   app: app,
///   // The VM and Flutter: SQLite files in this directory.
///   openDatabase: sqliteOpener(directory: '/path/to/cache'),
///   // A browser: sqliteOpener(), with sqlite3.wasm next to the page.
/// );
/// ```
library;

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

import 'src/opener_stub.dart'
    if (dart.library.io) 'src/opener_io.dart'
    if (dart.library.js_interop) 'src/opener_web.dart';

export 'src/memory_fallback.dart' show openWithMemoryFallback;
export 'src/sqlite_opfs_exception.dart' show SqliteOpfsException;
export 'src/sqlite_web_setup_exception.dart'
    show SqliteWebSetupException, SqliteWebSetupProblem;

/// Returns the [OpenDatabase] of this platform, for
/// `FirebaseFirestore.instanceFor(openDatabase: ...)`.
///
/// The same call compiles everywhere; each platform reads its own arguments
/// and ignores the others.
///
/// **The Dart VM and Flutter** (`dart:io`): one SQLite file per app and
/// database, `<directory>/<name>.db`, through `package:sqlite3`.
///
/// * [directory] is required here (an [ArgumentError] otherwise). In Flutter
///   use a directory from `path_provider`, for example
///   `getApplicationSupportDirectory()`. It is created when missing.
/// * [pageCacheMb] sets SQLite's page cache of the connection
///   (`PRAGMA cache_size`); SQLite's default is 2 MB.
///
/// **A browser** (`dart:js_interop`): SQLite compiled to WebAssembly, with the
/// database in IndexedDB, or in the origin private file system (OPFS) when
/// [opfsWorker] is given and the browser supports it. Supported in Chrome; other
/// browsers are untested.
///
/// * [sqlite3Wasm] is the URL of the `sqlite3.wasm` build of the `sqlite3`
///   package version the app resolves (default: `sqlite3.wasm` next to the
///   page). It is fetched on the first open.
/// * [opfsWorker] is the URL of the OPFS worker compiled to JavaScript
///   (`dart run cloud_firestore_dart_sqlite:setup_web` writes
///   `sqlite_opfs_worker.js`). Without it, or in a browser without
///   synchronous OPFS access in workers, the database is in IndexedDB. The
///   first OPFS open of a cache that is in IndexedDB moves it to OPFS.
/// * [storagePrefix] names the IndexedDB databases and OPFS directories
///   (`<prefix>/<database name>`) and the Web Locks.
/// * [lockTimeout] is how long an open waits for a cache that is open
///   elsewhere: long enough for a page that was just reloaded to be gone,
///   short for a second tab. After it the open fails with a `FirestoreException`
///   with the code `failed-precondition`: one tab at a time (see
///   `openWithMemoryFallback`).
/// * [acceptIndexedDbWriteLoss] opens the IndexedDB storage with `sqlite3`
///   3.4.0 to 3.5.2 anyway. Without it the open fails there with a
///   [SqliteWebSetupException]: the IndexedDB file system of those versions
///   can lose a write that the cache reported as stored when the tab is
///   closed or crashes a moment later. Pin another `sqlite3` instead (the
///   exception says which), or use [opfsWorker].
///
/// A `sqlite3.wasm` that is missing, or the build of another `sqlite3`
/// version than the one the app resolves, fails the open with a
/// [SqliteWebSetupException] that says so.
///
/// Relative URLs are resolved against the page. `FirebaseFirestore.clearPersistence`
/// deletes the file, the IndexedDB database or the OPFS directory.
OpenDatabase sqliteOpener({
  String? directory,
  int? pageCacheMb,
  Uri? sqlite3Wasm,
  Uri? opfsWorker,
  String storagePrefix = 'cloud_firestore_dart',
  Duration lockTimeout = const Duration(seconds: 2),
  bool acceptIndexedDbWriteLoss = false,
}) {
  return platformSqliteOpener(
    directory: directory,
    pageCacheMb: pageCacheMb,
    sqlite3Wasm: sqlite3Wasm ?? Uri.parse('sqlite3.wasm'),
    opfsWorker: opfsWorker,
    storagePrefix: storagePrefix,
    lockTimeout: lockTimeout,
    acceptIndexedDbWriteLoss: acceptIndexedDbWriteLoss,
  );
}
