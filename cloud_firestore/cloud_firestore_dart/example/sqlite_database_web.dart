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
//    tab (or twice in one page) fails, after two seconds of waiting for the
//    lock, with a [FirestoreError] with the code `failedPrecondition`. Catch it and create the instance without
//    `openDatabase` (a memory cache) for that tab, as in
//    `openWithMemoryFallback` below.
//  * Crash safety. SQLite runs in memory and the IndexedDB file system of
//    package:sqlite3 copies its files, the rollback journal included, to
//    IndexedDB in the background, in the order SQLite wrote them and one
//    IndexedDB transaction per file. This opener waits for the copies at the
//    end of every transaction, so what a write future acknowledged is
//    stored. A tab that dies in the middle of a transaction leaves a journal
//    behind and SQLite rolls that transaction back on the next open; the
//    setup of a new or upgraded cache is one transaction as well. Tested by
//    killing a worker at random moments (test/browser, 2700 kills): the
//    database always passed `PRAGMA integrity_check`, had every acknowledged
//    transaction, and at most one that was not acknowledged yet. Not covered:
//    a crash of the browser itself or a power cut, where IndexedDB may lose
//    its last transactions.
//  * Memory and speed. The whole database is read into memory when it is
//    opened and stays there. Measured in Chrome with documents of about
//    1 KB: 10,000 cached documents are a 17 MB database that opens in 0.1 s
//    and is scanned in 0.4 s; 100,000 are 160 MB, open in 1.2 s compiled
//    with dart2wasm (0.6 s with dart2js), take about 0.5 GB of JavaScript
//    heap once open and 4 s to scan (2.5 s with dart2js).
//  * `Firestore.clearPersistence()` deletes the IndexedDB database.

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:sqlite3/wasm.dart' as sqlite;
import 'package:web/web.dart' as web;

/// Returns an [OpenDatabase] that keeps each database in IndexedDB.
///
/// [sqlite3Wasm] is the URL of the `sqlite3.wasm` file of the sqlite3 package
/// version in use; it is fetched on the first open. [storagePrefix] names the
/// IndexedDB databases (`<prefix>/<database name>`) and the Web Locks.
/// [lockTimeout] is how long an open waits for a database that is open
/// elsewhere before it fails: long enough for the page that was just reloaded
/// to be gone, short for a second tab.
OpenDatabase sqliteWebOpener({
  required Uri sqlite3Wasm,
  String storagePrefix = 'cloud_firestore_dart',
  Duration lockTimeout = const Duration(seconds: 2),
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
    final Future<void> Function()? releaseLock = await _tryLock(
      storageName,
      lockTimeout,
    );
    if (releaseLock == null) {
      throw FirestoreError(
        'The offline cache "$name" is already open in another tab (or in this '
        'one). It can only be used by one tab at a time: use a memory cache '
        'in this tab.',
        FirestoreErrorCode.failedPrecondition,
      );
    }

    sqlite.IndexedDbFileSystem? fileSystem;
    sqlite.VirtualFileSystem? registered;
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
      registered = _ReadCopyFileSystem(fileSystem);
      sqlite3.registerVirtualFileSystem(registered);

      const String file = '/database';
      db = SqliteWebDatabase._(
        sqlite3.open(file, vfs: registered.name),
        sqlite3,
        fileSystem,
        registered,
        storageName,
        releaseLock,
      );

      // Keep every changed page in memory until its transaction commits.
      // SQLite would otherwise write pages of a large transaction to the
      // database file early, and the IndexedDB file system may store such a
      // page before the journal record that can undo it (it merges queued
      // writes to the same file), which a tab that dies at that moment could
      // not recover from.
      db._database.execute('PRAGMA cache_spill = OFF');

      // The callbacks run Firestore's schema setup and migrations. They must
      // be called in this order and awaited before the database is returned.
      await onConfigure?.call(db);

      // The setup and the schema version it leads to are one transaction (as
      // in Android's SQLiteOpenHelper): a tab that is closed while a new
      // cache is being created, or upgraded, leaves the old state behind and
      // the next open starts over, instead of finding half of the tables. A
      // database without any table is new, whatever was stored of it.
      final int wanted = version ?? 1;
      db._database.execute('BEGIN IMMEDIATE');
      try {
        final int current = db._database.userVersion;
        final bool isNew =
            current == 0 &&
            db._database.select('SELECT 1 FROM sqlite_master LIMIT 1').isEmpty;
        if (isNew) {
          await onCreate?.call(db, wanted);
        } else if (current < wanted) {
          await onUpgrade?.call(db, current, wanted);
        } else if (current > wanted) {
          await onDowngrade?.call(db, current, wanted);
        }
        // The schema version is kept in `PRAGMA user_version`.
        db._database.userVersion = wanted;
        db._database.execute('COMMIT');
      } catch (_) {
        if (!db._database.autocommit) {
          db._database.execute('ROLLBACK');
        }
        rethrow;
      }
      await fileSystem.flush();

      await onOpen?.call(db);
      return db;
    } catch (_) {
      if (db != null) {
        db.close();
      } else {
        if (registered != null) {
          sqlite3?.unregisterVirtualFileSystem(registered);
        }
        await fileSystem?.close();
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

/// Makes the reads of [_inner] cost what they read.
///
/// SQLite hands a read a view of its WebAssembly memory to fill. The file
/// systems of sqlite3 2.9.4 fill it with `setRange` from a view of the whole
/// file, and compiled with dart2wasm that converts the whole file to a
/// JavaScript array first, on every read: 26 ms per read of 16 bytes from a
/// 1.2 MB database, and SQLite reads 16 bytes of the file header for every
/// statement. Reading into a list of Dart's own first, and copying only that,
/// took 1000 statements from 26 s to 10 ms. Compiled with dart2js the extra
/// copy is not measurable.
final class _ReadCopyFileSystem extends sqlite.BaseVirtualFileSystem {
  _ReadCopyFileSystem(this._inner) : super(name: '${_inner.name}-read-copy');

  final sqlite.VirtualFileSystem _inner;

  @override
  int xAccess(String path, int flags) => _inner.xAccess(path, flags);

  @override
  void xDelete(String path, int syncDir) => _inner.xDelete(path, syncDir);

  @override
  String xFullPathName(String path) => _inner.xFullPathName(path);

  @override
  sqlite.XOpenResult xOpen(sqlite.Sqlite3Filename path, int flags) {
    final sqlite.XOpenResult opened = _inner.xOpen(path, flags);
    return (outFlags: opened.outFlags, file: _ReadCopyFile(opened.file));
  }

  @override
  void xSleep(Duration duration) => _inner.xSleep(duration);
}

class _ReadCopyFile implements sqlite.VirtualFileSystemFile {
  _ReadCopyFile(this._inner);

  final sqlite.VirtualFileSystemFile _inner;

  @override
  void xRead(Uint8List target, int fileOffset) {
    final Uint8List copy = Uint8List(target.length);
    try {
      _inner.xRead(copy, fileOffset);
    } finally {
      // Also after a short read, which zero-fills the rest and then throws.
      target.setRange(0, target.length, copy);
    }
  }

  @override
  void xWrite(Uint8List buffer, int fileOffset) =>
      _inner.xWrite(buffer, fileOffset);

  @override
  int xCheckReservedLock() => _inner.xCheckReservedLock();

  @override
  void xClose() => _inner.xClose();

  @override
  int get xDeviceCharacteristics => _inner.xDeviceCharacteristics;

  @override
  int xFileSize() => _inner.xFileSize();

  @override
  void xLock(int mode) => _inner.xLock(mode);

  @override
  void xSync(int flags) => _inner.xSync(flags);

  @override
  void xTruncate(int size) => _inner.xTruncate(size);

  @override
  void xUnlock(int mode) => _inner.xUnlock(mode);
}

/// The databases of this page that are being closed, by storage name.
final Map<String, Future<void>> _closing = <String, Future<void>>{};

/// Takes the Web Lock [name], waiting up to [wait] for it. Returns the
/// function that releases it (its future completes when the lock is free
/// again), or null when the lock is still held then, by this or by another
/// tab.
Future<Future<void> Function()?> _tryLock(String name, Duration wait) {
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

  // Not `ifAvailable`: the lock of a page that was just reloaded or closed
  // is released a moment after the page is gone, so the request waits for
  // [wait] before it is given up.
  final web.AbortController giveUp = web.AbortController();
  final Timer timer = Timer(wait, () => giveUp.abort());

  // The lock is held until the promise the callback returns is settled.
  JSPromise<JSAny?>? granted(web.Lock? lock) {
    timer.cancel();
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
      .request(name, web.LockOptions(signal: giveUp.signal), granted.toJS)
      .toDart
      .then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          timer.cancel();
          if (result.isCompleted) {
            return;
          }
          if (giveUp.signal.aborted) {
            // Still held after [wait]: by another tab, or by this page.
            result.complete(null);
          } else {
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
    this._registeredFileSystem,
    this.path,
    this._releaseLock,
  );

  final sqlite.CommonDatabase _database;
  final sqlite.WasmSqlite3 _sqlite3;
  final sqlite.IndexedDbFileSystem _fileSystem;
  final sqlite.VirtualFileSystem _registeredFileSystem;
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
        _sqlite3.unregisterVirtualFileSystem(_registeredFileSystem);
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
