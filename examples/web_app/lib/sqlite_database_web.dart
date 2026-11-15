// A complete `OpenDatabase` for cloud_firestore_dart in a browser, on top of
// the WebAssembly build of package:sqlite3, with the database stored in
// IndexedDB, or in the origin private file system (OPFS). The counterpart of
// sqlite_database.dart for the web.
//
// EXPERIMENTAL. Verified in Chrome against the emulator only.
//
// To use it: copy this file into your app, add `sqlite3` and `web` to your
// dependencies, put the `sqlite3.wasm` file of the same sqlite3 version next
// to your page (from https://github.com/simolus3/sqlite3.dart/releases) and
// pass `sqliteWebOpener(...)` to `Firestore.instanceFor`:
//
//     final Firestore firestore = Firestore.instanceFor(
//       app: app,
//       openDatabase: sqliteWebOpener(sqlite3Wasm: Uri.parse('sqlite3.wasm')),
//     );
//
// For OPFS, also copy sqlite_opfs_worker.dart, compile it to JavaScript as
// its header says and pass its URL as `opfsWorker`:
//
//     sqliteWebOpener(
//       sqlite3Wasm: Uri.parse('sqlite3.wasm'),
//       opfsWorker: Uri.parse('sqlite_opfs_worker.js'),
//     )
//
// Which storage:
//
//  * IndexedDB (the default, and the fallback). SQLite runs in the page on
//    a copy of the whole database in memory, which package:sqlite3 copies
//    back to IndexedDB file by file.
//  * OPFS (with `opfsWorker`). SQLite runs in a dedicated worker of its own
//    on a file in OPFS, through synchronous access handles
//    (`SimpleOpfsFileSystem` of package:sqlite3), and reads from the file
//    what it needs: the database is not in memory. Every statement is a
//    message to the worker and back. No cross-origin isolation is needed.
//    In a browser without synchronous OPFS access in workers the opener uses
//    IndexedDB instead (decided by the worker from what the browser offers,
//    never because an open failed). The first OPFS open of a cache that is
//    in IndexedDB moves it, pending writes included, and deletes the
//    IndexedDB database once the move committed.
//
// What to know:
//
//  * One tab at a time. The client has no way to share its cache between
//    tabs, so the database is guarded with a Web Lock: opening it in a second
//    tab (or twice in one page) fails, after two seconds of waiting for the
//    lock, with a [FirestoreError] with the code `failedPrecondition`. Catch
//    it and create the instance without `openDatabase` (a memory cache) for
//    that tab, as in `openWithMemoryFallback` below.
//  * Crash safety. With IndexedDB, SQLite runs in memory and the IndexedDB
//    file system of package:sqlite3 copies its files, the rollback journal
//    included, to IndexedDB in the background, in the order SQLite wrote them
//    and one IndexedDB transaction per file. This opener waits for the copies
//    at the end of every transaction, so what a write future acknowledged is
//    stored. With OPFS, SQLite writes its journal and its database file
//    itself and flushes them at the end of every transaction, as on disk. A
//    tab that dies in the middle of a transaction leaves a journal behind and
//    SQLite rolls that transaction back on the next open; the setup of a new
//    or upgraded cache is one transaction as well. Tested by killing a worker
//    at random moments (test/browser, 2700 kills on IndexedDB, 1500 on OPFS):
//    the database always passed `PRAGMA integrity_check`, had every
//    acknowledged transaction, and at most one that was not acknowledged yet.
//    Not covered: a crash of the browser itself or a power cut.
//  * When IndexedDB fails (IndexedDB storage). A transaction is committed in
//    memory before it is copied to IndexedDB. When the wait for the copy
//    fails, the next transaction fails with a [TransientDatabaseException]
//    until a wait succeeds; the client goes offline meanwhile and retries (see
//    `SqliteWebDatabase._stored`). With sqlite3 2.9.4 only a closed IndexedDB
//    file system makes the wait fail: the file system does not report a copy
//    that failed.
//  * When OPFS fails (OPFS storage). SQLite reports the I/O error of the
//    statement that ran into it. The worker reports BUSY, LOCKED, IOERR and
//    FULL as a [TransientDatabaseException] (the client goes offline and
//    retries) when nothing can have been stored: a statement inside a
//    transaction other than its COMMIT, a COMMIT that left the transaction
//    open, a read. An error at a COMMIT that ended the transaction may come
//    after the commit point, so it is fatal for the operation instead of
//    being retried and applied twice. As on the VM, a permanent I/O error
//    (a broken file) keeps the client offline.
//  * Memory and speed, measured in Chrome with documents of about 1 KB
//    (tool/web_storage_benchmark): with IndexedDB the whole database is read
//    into memory when it is opened and stays there, 133 to 138 MB for
//    100,000 cached documents, and the open takes 0.5 to 1.2 s. With OPFS the
//    page and the worker hold 3 to 8 MB once open, whatever the size, and the
//    open takes 45 to 170 ms. Reads by id take 0.1 to 0.2 ms with both. A
//    query that scans 100,000 documents takes 1 to 2 s with both, and its
//    snapshot of 100,000 documents needs about 0.45 GB with either storage.
//  * `Firestore.clearPersistence()` deletes the IndexedDB database or the
//    OPFS directory (and an IndexedDB database of the same name left from
//    before).

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:sqlite3/wasm.dart' as sqlite;
import 'package:web/web.dart' as web;

/// Returns an [OpenDatabase] that keeps each database in IndexedDB, or in the
/// origin private file system (OPFS) when [opfsWorker] is given and the
/// browser supports it.
///
/// [sqlite3Wasm] is the URL of the `sqlite3.wasm` file of the sqlite3 package
/// version in use; it is fetched on the first open. [storagePrefix] names the
/// IndexedDB databases and OPFS directories (`<prefix>/<database name>`) and
/// the Web Locks. [lockTimeout] is how long an open waits for a database that
/// is open elsewhere before it fails: long enough for the page that was just
/// reloaded to be gone, short for a second tab.
///
/// [opfsWorker] is the URL of sqlite_opfs_worker.dart compiled to JavaScript
/// (see that file). With it the database is a file in OPFS that SQLite reads
/// from as it needs, in that dedicated worker, instead of a copy of the whole
/// database in memory ([SqliteOpfsDatabase]). In a browser without
/// synchronous OPFS access in workers the opener uses IndexedDB as without
/// it ([SqliteWebDatabase]). The first OPFS open of a cache that exists in
/// IndexedDB only moves it to OPFS, pending writes included.
OpenDatabase sqliteWebOpener({
  required Uri sqlite3Wasm,
  Uri? opfsWorker,
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

    if (opfsWorker != null) {
      final SqliteOpfsDatabase? opened;
      try {
        opened = await _openOpfs(
          worker: Uri.base.resolveUri(opfsWorker),
          sqlite3Wasm: Uri.base.resolveUri(sqlite3Wasm),
          storageName: storageName,
          releaseLock: releaseLock,
          // The Web Lock keeps other tabs out, so files that are still busy
          // belong to the worker of a page that is gone: the browser ends it
          // a moment later, usually well within a second, rarely after more
          // than two (seen in test/browser/web_persistence_crash_test.dart).
          handleTimeout: _opfsHandleTimeout,
          version: version,
          onConfigure: onConfigure,
          onCreate: onCreate,
          onUpgrade: onUpgrade,
          onDowngrade: onDowngrade,
          onOpen: onOpen,
        );
      } catch (_) {
        await releaseLock();
        rethrow;
      }
      if (opened != null) {
        return opened;
      }
      // No synchronous OPFS access in this browser: IndexedDB, as without a
      // worker. The lock is still held.
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
///
/// `Firestore.instanceFor` returns at once and opens the cache in the
/// background, so the error of a cache that can't be opened comes from the
/// first operation, not from `instanceFor`. This waits for a first operation
/// that only reads the cache (looking up a named query that does not exist),
/// and on `failedPrecondition` terminates that instance (which frees the app
/// for a new one) and creates one with a memory cache.
Future<Firestore> openWithMemoryFallback({
  required FirebaseApp app,
  required Uri sqlite3Wasm,
  Uri? opfsWorker,
  FirestoreSettings? settings,
}) async {
  final Firestore persistent = Firestore.instanceFor(
    app: app,
    openDatabase: sqliteWebOpener(
      sqlite3Wasm: sqlite3Wasm,
      opfsWorker: opfsWorker,
    ),
    settings: settings,
  );
  try {
    await persistent.getNamedQuery('openWithMemoryFallback');
    return persistent;
  } on FirestoreError catch (e) {
    if (e.code != FirestoreErrorCode.failedPrecondition) {
      rethrow;
    }
    await persistent.terminate();
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
///
/// The Web Lock of the database is held from the open to the close, and lost
/// with the page: no other client has the database open meanwhile
/// ([ExclusiveDatabase]).
class SqliteWebDatabase implements ClearableDatabase, ExclusiveDatabase {
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

  /// The error of the last wait for IndexedDB that failed, until a wait
  /// succeeds.
  Object? _unstored;

  /// Waits until what the statement changed is stored in IndexedDB, unless a
  /// transaction is open: its end is what makes the changes durable.
  ///
  /// The changes are already committed in memory when this waits, so a
  /// failure here is not reported for this statement (Firestore would treat
  /// the transaction as not applied and run it again). It is kept, and the
  /// next statement that starts outside a transaction (in practice the
  /// `BEGIN` of the next transaction) waits again and fails with a
  /// [TransientDatabaseException] while IndexedDB still fails: the client
  /// then goes offline and retries until IndexedDB works. A tab closed in the
  /// meantime loses the transactions IndexedDB did not store.
  Future<void> _stored() async {
    if (!_database.autocommit) {
      return;
    }
    try {
      await _fileSystem.flush();
      _unstored = null;
    } catch (e) {
      _unstored = e;
    }
  }

  /// Fails with a [TransientDatabaseException] while what was committed
  /// before can not be stored in IndexedDB (see [_stored]).
  Future<void> _checkStored() async {
    if (_unstored == null || !_database.autocommit) {
      return;
    }
    try {
      await _fileSystem.flush();
      _unstored = null;
    } catch (e) {
      _unstored = e;
      throw TransientDatabaseException(
        'IndexedDB did not store the last transaction',
        e,
      );
    }
  }

  @override
  Future<void> execute(String statement, [List<Object?>? arguments]) async {
    await _checkStored();
    _database.execute(statement, arguments ?? const <Object?>[]);
    await _stored();
  }

  @override
  Future<List<Map<String, dynamic>>> query(
    String statement, [
    List<Object?>? arguments,
  ]) async {
    await _checkStored();
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
    await _checkStored();
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

// --- OPFS ------------------------------------------------------------------

/// Opens [storageName] in OPFS, in a new dedicated [worker] running
/// sqlite_opfs_worker.dart. Returns null, having changed nothing, when the
/// browser has no synchronous OPFS access in workers.
///
/// The caller holds the Web Lock of [storageName]; the returned database
/// releases it with [releaseLock] when it is closed. When the open fails the
/// lock is left to the caller.
Future<SqliteOpfsDatabase?> _openOpfs({
  required Uri worker,
  required Uri sqlite3Wasm,
  required String storageName,
  required Future<void> Function() releaseLock,
  required Duration handleTimeout,
  int? version,
  OnConfigure? onConfigure,
  OnCreate? onCreate,
  OnVersionChange? onUpgrade,
  OnVersionChange? onDowngrade,
  OnOpen? onOpen,
}) async {
  final _OpfsWorker? connection = _OpfsWorker.start(worker);
  if (connection == null) {
    return null;
  }
  try {
    final JSObject loaded =
        (await connection.call(
              'load',
              JSObject()
                ..['wasm'] = sqlite3Wasm.toString().toJS
                ..['path'] = storageName.toJS
                ..['waitMs'] = handleTimeout.inMilliseconds.toJS,
            ))!
            as JSObject;
    if (!(loaded['supported']! as JSBoolean).toDart) {
      connection.terminate();
      return null;
    }

    // A cache that is in IndexedDB only, from before OPFS was used: it is
    // moved, so that its pending writes are not lost.
    bool imported = false;
    if (!(loaded['exists']! as JSBoolean).toDart) {
      imported = await _importFromIndexedDb(connection, storageName);
    }

    await connection.call('open');
    final SqliteOpfsDatabase db = SqliteOpfsDatabase._(
      connection,
      storageName,
      releaseLock,
    );

    await onConfigure?.call(db);

    // The setup and the schema version it leads to are one transaction, as
    // for IndexedDB above.
    final int wanted = version ?? 1;
    await db.execute('BEGIN IMMEDIATE');
    try {
      final int current =
          (await db.query('PRAGMA user_version')).single.values.first as int;
      final bool isNew =
          current == 0 &&
          (await db.query('SELECT 1 FROM sqlite_master LIMIT 1')).isEmpty;
      if (isNew) {
        await onCreate?.call(db, wanted);
      } else if (current < wanted) {
        await onUpgrade?.call(db, current, wanted);
      } else if (current > wanted) {
        await onDowngrade?.call(db, current, wanted);
      }
      await db.execute('PRAGMA user_version = $wanted');
      await db.execute('COMMIT');
    } catch (_) {
      await connection.call('rollback');
      rethrow;
    }
    if (imported) {
      // It is in OPFS now.
      await sqlite.IndexedDbFileSystem.deleteDatabase(storageName);
    }

    await onOpen?.call(db);
    return db;
  } catch (_) {
    try {
      await connection.call('close');
    } catch (_) {
      // The worker failed; terminating it closes its files as well.
    }
    connection.terminate();
    rethrow;
  }
}

/// Copies the IndexedDB database [storageName] of the IndexedDB storage, if
/// there is one, to the OPFS files of [connection] before they are opened.
/// Returns whether there was one.
Future<bool> _importFromIndexedDb(
  _OpfsWorker connection,
  String storageName,
) async {
  final List<String>? stored = await sqlite.IndexedDbFileSystem.databases();
  if (stored == null || !stored.contains(storageName)) {
    return false;
  }
  final sqlite.IndexedDbFileSystem fileSystem =
      await sqlite.IndexedDbFileSystem.open(
        dbName: storageName,
        vfsName: 'indexeddb-import-${_fileSystems++}',
      );
  final Uint8List? database;
  final Uint8List? journal;
  try {
    Uint8List? read(String file) {
      if (fileSystem.xAccess(file, 0) == 0) {
        return null;
      }
      final sqlite.VirtualFileSystemFile opened = fileSystem
          .xOpen(
            sqlite.Sqlite3Filename(file),
            sqlite.SqlFlag.SQLITE_OPEN_READWRITE,
          )
          .file;
      try {
        final Uint8List bytes = Uint8List(opened.xFileSize());
        opened.xRead(bytes, 0);
        return bytes;
      } finally {
        opened.xClose();
      }
    }

    database = read('/database');
    journal = read('/database-journal');
  } finally {
    await fileSystem.close();
  }
  if (database == null || database.isEmpty) {
    return false;
  }
  final JSUint8Array databaseBytes = database.toJS;
  final JSUint8Array? journalBytes = journal?.toJS;
  await connection.call(
    'import',
    JSObject()
      ..['database'] = databaseBytes
      ..['journal'] = journalBytes,
    <JSObject>[
      databaseBytes['buffer']! as JSObject,
      if (journalBytes != null) journalBytes['buffer']! as JSObject,
    ],
  );
  return true;
}

/// Opens the OPFS database [storageName] as it is, without the Web Lock,
/// the schema steps or the IndexedDB import of [sqliteWebOpener]: to look at
/// a database that nothing else has open (tests, debugging). Returns null
/// when the browser has no synchronous OPFS access in workers.
Future<SqliteOpfsDatabase?> inspectOpfsDatabase({
  required Uri opfsWorker,
  required Uri sqlite3Wasm,
  required String storageName,
}) async {
  final _OpfsWorker? connection = _OpfsWorker.start(
    Uri.base.resolveUri(opfsWorker),
  );
  if (connection == null) {
    return null;
  }
  try {
    final JSObject loaded =
        (await connection.call(
              'load',
              JSObject()
                ..['wasm'] = Uri.base.resolveUri(sqlite3Wasm).toString().toJS
                ..['path'] = storageName.toJS
                ..['waitMs'] = _opfsHandleTimeout.inMilliseconds.toJS,
            ))!
            as JSObject;
    if (!(loaded['supported']! as JSBoolean).toDart) {
      connection.terminate();
      return null;
    }
    await connection.call('open');
    return SqliteOpfsDatabase._(connection, storageName, () async {});
  } catch (_) {
    connection.terminate();
    rethrow;
  }
}

/// How long an OPFS open waits for files that the worker of a closed page
/// still holds.
const Duration _opfsHandleTimeout = Duration(seconds: 10);

/// An error that SQLite (or the file system) reported in the OPFS worker.
///
/// The errors that may go away on their own, and after which nothing of the
/// failed statement or its transaction can have been stored, come as a
/// [TransientDatabaseException] with this as its cause instead (the worker
/// decides, see sqlite_opfs_worker.dart): Firestore then goes offline and
/// retries. An I/O error at a COMMIT that may have stored the transaction
/// stays a [SqliteOpfsException], fatal for the operation, because running it
/// again would apply it twice.
class SqliteOpfsException implements Exception {
  SqliteOpfsException(this.message, [this.resultCode]);

  /// The message of SQLite, without the statement or its arguments.
  final String message;

  /// The primary SQLite result code, when SQLite reported the error.
  final int? resultCode;

  @override
  String toString() => 'SqliteOpfsException: $message';
}

/// The messages to and from one worker running sqlite_opfs_worker.dart.
class _OpfsWorker {
  _OpfsWorker._(this._script, this._worker) {
    _worker.onmessage = _onMessage.toJS;
    _worker.onerror = _onError.toJS;
    _worker.onmessageerror = _onError.toJS;
  }

  /// Null in a context without workers.
  static _OpfsWorker? start(Uri script) {
    if (!globalContext.has('Worker')) {
      return null;
    }
    return _OpfsWorker._(script, web.Worker(script.toString().toJS));
  }

  final Uri _script;
  final web.Worker _worker;
  final Map<int, Completer<JSAny?>> _pending = <int, Completer<JSAny?>>{};
  int _next = 0;
  Object? _failure;

  Future<JSAny?> call(
    String op, [
    JSObject? request,
    List<JSObject> transfer = const <JSObject>[],
  ]) {
    if (_failure != null) {
      return Future<JSAny?>.error(_failure!);
    }
    final int id = _next++;
    final JSObject message = (request ?? JSObject())
      ..['id'] = id.toJS
      ..['op'] = op.toJS;
    final Completer<JSAny?> reply = Completer<JSAny?>();
    _pending[id] = reply;
    if (transfer.isEmpty) {
      _worker.postMessage(message);
    } else {
      _worker.postMessage(message, transfer.toJS);
    }
    return reply.future;
  }

  void _onMessage(web.MessageEvent event) {
    final JSObject reply = event.data! as JSObject;
    final Completer<JSAny?>? completer = _pending.remove(
      (reply['id']! as JSNumber).toDartInt,
    );
    if (completer == null) {
      return;
    }
    if (reply.has('error')) {
      final SqliteOpfsException error = SqliteOpfsException(
        (reply['error']! as JSString).toDart,
        (reply['code'] as JSNumber?)?.toDartInt,
      );
      completer.completeError(
        (reply['transient'] as JSBoolean?)?.toDart ?? false
            ? TransientDatabaseException(
                'SQLite in the OPFS worker failed (code ${error.resultCode})',
                error,
              )
            : error,
      );
    } else {
      completer.complete(reply['result']);
    }
  }

  void _onError(web.Event event) {
    event.preventDefault();
    final String detail = event.isA<web.ErrorEvent>()
        ? (event as web.ErrorEvent).message
        : 'the script could not be loaded or a message could not be read';
    _fail(StateError('The OPFS worker $_script failed: $detail'));
  }

  void _fail(Object error) {
    _failure ??= error;
    final List<Completer<JSAny?>> waiting = _pending.values.toList();
    _pending.clear();
    for (final Completer<JSAny?> completer in waiting) {
      completer.completeError(error);
    }
  }

  void terminate() {
    _worker.terminate();
    _fail(StateError('The OPFS worker was terminated'));
  }
}

/// One open SQLite database in OPFS, kept by its own dedicated worker.
/// Firestore runs its own SQL through it. Like [SqliteWebDatabase] it holds
/// the Web Lock of the database while it is open ([ExclusiveDatabase]).
class SqliteOpfsDatabase implements ClearableDatabase, ExclusiveDatabase {
  SqliteOpfsDatabase._(this._worker, this.path, this._releaseLock);

  final _OpfsWorker _worker;
  final Future<void> Function() _releaseLock;

  /// The OPFS directory of the database.
  @override
  final String path;

  /// Completes when the worker closed the files and the lock is released.
  Future<void>? _closed;

  JSObject _statement(String statement, List<Object?>? arguments) {
    final JSObject request = JSObject()..['sql'] = statement.toJS;
    if (arguments != null && arguments.isNotEmpty) {
      request['args'] = <JSAny?>[
        for (final Object? value in arguments) _encodeValue(value),
      ].toJS;
    }
    return request;
  }

  @override
  Future<void> execute(String statement, [List<Object?>? arguments]) async {
    await _worker.call('execute', _statement(statement, arguments));
  }

  @override
  Future<List<Map<String, dynamic>>> query(
    String statement, [
    List<Object?>? arguments,
  ]) async {
    final JSObject result =
        (await _worker.call('query', _statement(statement, arguments)))!
            as JSObject;
    final List<String> columns = <String>[
      for (final JSString column
          in (result['columns']! as JSArray<JSString>).toDart)
        column.toDart,
    ];
    final List<JSArray<JSAny?>> rows =
        (result['rows']! as JSArray<JSArray<JSAny?>>).toDart;
    return <Map<String, dynamic>>[
      for (final JSArray<JSAny?> row in rows) _row(columns, row.toDart),
    ];
  }

  static Map<String, dynamic> _row(List<String> columns, List<JSAny?> values) {
    final Map<String, dynamic> row = <String, dynamic>{};
    for (int i = 0; i < columns.length; i++) {
      row[columns[i]] = _decodeValue(values[i]);
    }
    return row;
  }

  /// Runs a DELETE and returns the number of rows it removed.
  @override
  Future<int> delete(String statement, [List<Object?>? arguments]) async {
    final JSNumber rows =
        (await _worker.call('delete', _statement(statement, arguments)))!
            as JSNumber;
    return rows.toDartInt;
  }

  @override
  void close() {
    if (_closed != null) {
      return;
    }
    final Future<void> closed = () async {
      try {
        await _worker.call('close');
      } finally {
        _worker.terminate();
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

  /// Completes when [close] has ended the worker and released the lock (at
  /// once when it was not called). Never fails.
  Future<void> get whenClosed => (_closed ?? Future<void>.value()).then<void>(
    (_) {},
    onError: (Object _) {},
  );

  /// Deletes the OPFS directory (and an IndexedDB database of the same name
  /// that may be left from before), for `Firestore.clearPersistence`.
  @override
  Future<void> clearStorage() async {
    close();
    await _closed;
    await sqlite.SimpleOpfsFileSystem.deleteFromStorage(path);
    await sqlite.IndexedDbFileSystem.deleteDatabase(path);
  }
}

const bool _isWasm = bool.fromEnvironment('dart.tool.dart2wasm');

JSAny? _encodeValue(Object? value) {
  if (value == null) {
    return null;
  } else if (value is int &&
      value <= 9007199254740991 &&
      value >= -9007199254740991) {
    return value.toJS;
  } else if (value is double) {
    // Compiled to JavaScript every number is a double (and an int): only
    // those that are not safe integers get here.
    return JSObject()..['d'] = value.toJS;
  } else if (value is int) {
    return JSObject()..['i'] = value.toString().toJS;
  } else if (value is String) {
    return value.toJS;
  } else if (value is Uint8List) {
    return value.toJS;
  } else if (value is bool) {
    return (value ? 1 : 0).toJS;
  }
  throw ArgumentError.value(value, 'value', 'Not a SQLite value');
}

Object? _decodeValue(JSAny? value) {
  if (value == null) {
    return null;
  } else if (value.typeofEquals('number')) {
    return (value as JSNumber).toDartInt;
  } else if (value.typeofEquals('string')) {
    return (value as JSString).toDart;
  } else if (value.isA<JSUint8Array>()) {
    final Uint8List view = (value as JSUint8Array).toDart;
    // Compiled with dart2wasm `toDart` is a view of the JavaScript array whose
    // every element access is a call into JavaScript: Firestore decodes the
    // blob byte by byte, so it gets a copy of its own.
    return _isWasm ? Uint8List.fromList(view) : view;
  }
  final JSObject object = value as JSObject;
  if (object.has('i')) {
    return int.parse((object['i']! as JSString).toDart);
  }
  return (object['d']! as JSNumber).toDartDouble;
}
