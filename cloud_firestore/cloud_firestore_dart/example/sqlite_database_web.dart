// A complete `OpenDatabase` for cloud_firestore_dart in a browser, on top of
// the WebAssembly build of package:sqlite3, with the database stored in
// IndexedDB. The counterpart of sqlite_database.dart for the web.
//
// EXPERIMENTAL. Verified in Chrome against the emulator only.
//
// To use it: copy this file into your app, add `sqlite3` and `web` to your
// dependencies, put the `sqlite3.wasm` file of the same sqlite3 version next
// to your page (from https://github.com/simolus3/sqlite3.dart/releases) and
// pass `sqliteWebOpener(...)` to `Firestore.instanceFor`:
//
//     final Firestore firestore = await Firestore.instanceFor(
//       app: app,
//       openDatabase: sqliteWebOpener(sqlite3Wasm: Uri.parse('sqlite3.wasm')),
//     );
//
// What to know:
//
//  * One tab at a time. The client has no way to share its cache between
//    tabs, so the database is guarded with a Web Lock: opening it in a second
//    tab (or twice in one page) fails with a [FirestoreError] with the code
//    `failedPrecondition`. Catch it and create the instance without
//    `openDatabase` (a memory cache) for that tab, as in
//    `openWithMemoryFallback` below.
//  * Durability. SQLite runs in memory and its pages are copied to IndexedDB
//    in the background. This opener waits for the copy at the end of every
//    transaction, so what a write future acknowledged is stored. A tab that
//    is killed in the middle of a transaction can lose that transaction, and
//    IndexedDB does not write the pages of one SQLite transaction atomically.
//  * The whole database is read into memory when it is opened.
//  * `Firestore.clearPersistence()` deletes the IndexedDB database.

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:sqlite3/wasm.dart' as sqlite;
import 'package:web/web.dart' as web;

/// Returns an [OpenDatabase] that keeps each database in IndexedDB.
///
/// [sqlite3Wasm] is the URL of the `sqlite3.wasm` file of the sqlite3 package
/// version in use; it is fetched on the first open. [storagePrefix] names the
/// IndexedDB databases (`<prefix>/<database name>`) and the Web Locks.
OpenDatabase sqliteWebOpener({
  required Uri sqlite3Wasm,
  String storagePrefix = 'cloud_firestore_dart',
}) {
  Future<sqlite.WasmSqlite3>? loading;

  return (
    String name, {
    int? version,
    OnConfigure? onConfigure,
    OnCreate? onCreate,
    OnVersionChange? onUpgrade,
    OnVersionChange? onDowngrade,
    OnOpen? onOpen,
  }) async {
    final String storageName = '$storagePrefix/$name';

    // `close()` cannot be awaited by its caller. A database of this page that
    // is still being closed (`terminate()` followed by a new instance) is
    // waited for instead of being reported as open.
    await _closing[storageName];

    // One open database per name, in this tab and in every other.
    final Future<void> Function()? releaseLock = await _tryLock(storageName);
    if (releaseLock == null) {
      throw FirestoreError(
        'The offline cache "$name" is already open in another tab (or in this '
        'one). It can only be used by one tab at a time: use a memory cache '
        'in this tab.',
        FirestoreErrorCode.failedPrecondition,
      );
    }

    sqlite.IndexedDbFileSystem? fileSystem;
    sqlite.WasmSqlite3? sqlite3;
    SqliteWebDatabase? db;
    try {
      // A failed download is tried again on the next open.
      sqlite3 = await (loading ??= sqlite.WasmSqlite3.loadFromUrl(sqlite3Wasm)
          .onError<Object>((Object error, StackTrace stackTrace) {
            loading = null;
            Error.throwWithStackTrace(error, stackTrace);
          }));

      // Reads the database into memory. A file system of its own per open
      // database, registered under a name of its own.
      fileSystem = await sqlite.IndexedDbFileSystem.open(
        dbName: storageName,
        vfsName: 'indexeddb-${_fileSystems++}',
      );
      sqlite3.registerVirtualFileSystem(fileSystem);

      const String file = '/database';
      final bool isNew = fileSystem.xAccess(file, 0) == 0;
      db = SqliteWebDatabase._(
        sqlite3.open(file, vfs: fileSystem.name),
        sqlite3,
        fileSystem,
        storageName,
        releaseLock,
      );

      // The callbacks run Firestore's schema setup and migrations. They must
      // be called in this order and awaited before the database is returned.
      await onConfigure?.call(db);

      final int wanted = version ?? 1;
      if (isNew) {
        await onCreate?.call(db, wanted);
      } else {
        final int current = db._database.userVersion;
        if (current < wanted) {
          await onUpgrade?.call(db, current, wanted);
        } else if (current > wanted) {
          await onDowngrade?.call(db, current, wanted);
        }
      }
      // The schema version is kept in `PRAGMA user_version`.
      db._database.userVersion = wanted;
      await fileSystem.flush();

      await onOpen?.call(db);
      return db;
    } catch (_) {
      if (db != null) {
        db.close();
      } else {
        if (fileSystem != null) {
          sqlite3?.unregisterVirtualFileSystem(fileSystem);
          await fileSystem.close();
        }
        await releaseLock();
      }
      rethrow;
    }
  };
}

/// Creates the instance with the offline cache in IndexedDB, or with a memory
/// cache when another tab has that cache open.
Future<Firestore> openWithMemoryFallback({
  required FirebaseApp app,
  required Uri sqlite3Wasm,
  FirestoreSettings? settings,
}) async {
  try {
    return await Firestore.instanceFor(
      app: app,
      openDatabase: sqliteWebOpener(sqlite3Wasm: sqlite3Wasm),
      settings: settings,
    );
  } on FirestoreError catch (e) {
    if (e.code != FirestoreErrorCode.failedPrecondition) {
      rethrow;
    }
    return Firestore.instanceFor(
      app: app,
      settings: (settings ?? FirestoreSettings()).copyWith(
        cacheSettings: const MemoryCacheSettings(),
      ),
    );
  }
}

int _fileSystems = 0;

/// The databases of this page that are being closed, by storage name.
final Map<String, Future<void>> _closing = <String, Future<void>>{};

/// Takes the Web Lock [name] if nobody holds it. Returns the function that
/// releases it (its future completes when the lock is free again), or null
/// when the lock is held, by this or by another tab.
Future<Future<void> Function()?> _tryLock(String name) {
  final web.LockManager? locks = _lockManager;
  if (locks == null) {
    throw UnsupportedError(
      'The Web Locks API is not available (it needs a secure context). '
      'Without it a second tab cannot be kept from opening the same offline '
      'cache.',
    );
  }
  final Completer<Future<void> Function()?> result =
      Completer<Future<void> Function()?>();
  final Completer<void> release = Completer<void>();
  // Settled by the browser once the lock is released.
  late final Future<void> requestDone;

  // The lock is held until the promise the callback returns is settled.
  JSPromise<JSAny?>? granted(web.Lock? lock) {
    if (lock == null) {
      result.complete(null);
      return null;
    }
    result.complete(() {
      if (!release.isCompleted) {
        release.complete();
      }
      return requestDone;
    });
    return release.future.then<JSAny?>((_) => null).toJS;
  }

  requestDone = locks
      .request(name, web.LockOptions(ifAvailable: true), granted.toJS)
      .toDart
      .then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          if (!result.isCompleted) {
            result.completeError(error, stackTrace);
          }
        },
      );
  return result.future;
}

web.LockManager? get _lockManager {
  // A window or a worker.
  final JSObject navigator = globalContext.getProperty<JSObject>(
    'navigator'.toJS,
  );
  return navigator.getProperty<web.LockManager?>('locks'.toJS);
}

/// One open SQLite database in IndexedDB. Firestore runs its own SQL through
/// it.
class SqliteWebDatabase implements ClearableDatabase {
  SqliteWebDatabase._(
    this._database,
    this._sqlite3,
    this._fileSystem,
    this.path,
    this._releaseLock,
  );

  final sqlite.CommonDatabase _database;
  final sqlite.WasmSqlite3 _sqlite3;
  final sqlite.IndexedDbFileSystem _fileSystem;
  final Future<void> Function() _releaseLock;

  /// The name of the IndexedDB database.
  @override
  final String path;

  /// Completes when everything is stored and the lock is released.
  Future<void>? _closed;

  /// Waits until what the statement changed is stored in IndexedDB, unless a
  /// transaction is open: its end is what makes the changes durable.
  Future<void> _stored() {
    return _database.autocommit ? _fileSystem.flush() : Future<void>.value();
  }

  @override
  Future<void> execute(String statement, [List<Object?>? arguments]) async {
    _database.execute(statement, arguments ?? const <Object?>[]);
    await _stored();
  }

  @override
  Future<List<Map<String, dynamic>>> query(
    String statement, [
    List<Object?>? arguments,
  ]) async {
    final sqlite.ResultSet rows = _database.select(
      statement,
      arguments ?? const <Object?>[],
    );
    return <Map<String, dynamic>>[
      for (final sqlite.Row row in rows) Map<String, dynamic>.of(row),
    ];
  }

  /// Runs a DELETE and returns the number of rows it removed.
  @override
  Future<int> delete(String statement, [List<Object?>? arguments]) async {
    _database.execute(statement, arguments ?? const <Object?>[]);
    final int rows = _database.updatedRows;
    await _stored();
    return rows;
  }

  @override
  void close() {
    if (_closed != null) {
      return;
    }
    final Future<void> closed = () async {
      try {
        _database.dispose();
        _sqlite3.unregisterVirtualFileSystem(_fileSystem);
        // Finishes the copies to IndexedDB that are still queued.
        await _fileSystem.close();
      } finally {
        await _releaseLock();
      }
    }();
    _closed = closed;
    // Never fails, so that the next open can simply wait for it.
    late final Future<void> pending;
    pending = closed.then<void>((_) {}, onError: (Object _) {}).whenComplete(
      () {
        if (identical(_closing[path], pending)) {
          _closing.remove(path);
        }
      },
    );
    _closing[path] = pending;
  }

  /// Deletes the IndexedDB database, for `Firestore.clearPersistence`.
  @override
  Future<void> clearStorage() async {
    close();
    await _closed;
    await sqlite.IndexedDbFileSystem.deleteDatabase(path);
  }
}
