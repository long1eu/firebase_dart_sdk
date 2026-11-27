import 'dart:io';

import 'package:firebase_database_dart/firebase_database_dart.dart'
    show DatabaseLogger, DatabasePersistence;
import 'package:firebase_database_dart/storage_engine.dart';
import 'package:firebase_database_dart_sqlite/src/sqlite_connection.dart';
import 'package:firebase_database_dart_sqlite/src/sqlite_files.dart';
import 'package:firebase_database_dart_sqlite/src/sqlite_lease.dart';
import 'package:firebase_database_dart_sqlite/src/sqlite_open.dart';
import 'package:firebase_database_dart_sqlite/src/sqlite_storage_engine.dart';
import 'package:meta/meta.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// An offline cache in SQLite files under [directory], for `FirebaseDatabase(persistence: ...)`.
///
/// [directory] is created when missing. On macOS and Linux its last level then gets mode 0700;
/// parent directories created with it get the default mode, and an existing directory is left as
/// it is. Use a directory of the app, for example `getApplicationSupportDirectory()` of
/// `path_provider` plus `firebase_database` in Flutter, or
/// `~/Library/Application Support/<app>/firebase_database` on macOS,
/// `$XDG_DATA_HOME/<app>/firebase_database` on Linux and `%LOCALAPPDATA%\<app>\firebase_database`
/// on Windows.
///
/// [cacheSizeBytes] is the size above which the client prunes the cached server data: 1 MiB to
/// 100 MiB, 10 MiB when null ([ArgumentError] outside, from [databasePersistence]). It counts the
/// bytes of the cached paths and values, not the size of the file: pending writes, tracked queries
/// and SQLite's own space are not in it. Pending writes are never pruned.
///
/// With [cacheServerData] false only the pending writes are stored: they survive a restart and are
/// sent again, and no new server data is written. Server data and tracked queries that an earlier
/// run with [cacheServerData] true stored stay in the file. [clearSqlitePersistence] deletes them,
/// with the rest of the file.
///
/// An [ArgumentError] when [directory] is empty. Without a usable SQLite library (none could be
/// loaded, or one older than 3.24.0) the store keeps its data in memory only and logs one warning;
/// `FirebaseDatabase.persistenceEnabled` reads false once the store is open. Delete a cache with
/// [clearSqlitePersistence]; find its file with [SqlitePersistence.pathOf].
DatabasePersistence sqlitePersistence(
  String directory, {
  int? cacheSizeBytes,
  bool cacheServerData = true,
}) {
  return databasePersistence(
    opener: SqlitePersistence(directory).open,
    cacheSizeBytes: cacheSizeBytes,
    cacheServerData: cacheServerData,
  );
}

/// Deletes the cache files of [databaseUrl] of the app named [appName] in [directory]: the
/// database file, its side files and its moved-aside copies. Close the `FirebaseDatabase` first.
///
/// [databaseUrl] is normalised by [persistenceDatabaseUrl], which maps a URL onto the key
/// `FirebaseDatabase` builds: `FirebaseDatabase.databaseUrl` clears its own files, and so do the
/// spellings of a production URL that the constructor accepts (a trailing `/`, `wss://`, the case
/// of the host, port 443, a `?ns=` equal to the first label of the host). An emulator cache is
/// named by `http://<host>[:<port>]?ns=<namespace>` (`https` on a cloud workstation), with the
/// host and port of the constructor's `emulatorHost`, not those of its database URL. An emulator
/// URL must carry `?ns=`; `FirebaseDatabase.databaseUrl` always has it. The cloud-workstation
/// cases where a spelling names another cache are described at [persistenceDatabaseUrl]. Fails
/// with an [ArgumentError] for a URL that is not a database URL and for an emulator URL without
/// `?ns=`.
///
/// When the file has a lease row (an open instance, or one that ended without closing, as after
/// a crash or a hot restart), the call first watches it for about 7.5 s. Fails with a
/// [StateError] while an instance holds the file (in this process or another: it refreshes the
/// row in that time) or another clear of it is running, and with a [ClearPersistenceException]
/// listing the files that could not be deleted; see [SqlitePersistence.clear].
Future<void> clearSqlitePersistence(
  String directory, {
  required String appName,
  required Uri databaseUrl,
}) async {
  final Uri normalised;
  try {
    normalised = persistenceDatabaseUrl(databaseUrl);
  } on FormatException catch (e) {
    throw ArgumentError(e.message, 'databaseUrl');
  }
  return SqlitePersistence(
    directory,
  ).clear(PersistenceKey(appName: appName, databaseUrl: normalised));
}

/// The engine over an opened [connection]: a [SqliteStorageEngine]
/// (lib/src/sqlite_storage_engine.dart and the row files next to it). Not exported. Warnings
/// about stored data go to [logger].
PersistenceStorageEngine engineOverConnection(
  SqliteConnection connection, {
  required DatabaseLogger logger,
}) {
  return SqliteStorageEngine(connection, logger: logger);
}

/// SQLite files of the offline cache, one per app and database URL, in one directory.
///
/// `FirebaseDatabase` calls [open] once, when it starts, and its calls wait for the open. One
/// process or isolate owns a file at a time: another one that opens the same database keeps its
/// data in memory, and the opened store says so through its `isDurable`.
///
/// [open] waits about 7.5 s when the file has the lease row of another owner. When that owner
/// refreshes the row meanwhile, it is running and this store keeps its data in memory. Otherwise
/// it ended without closing, as after a crash or a Flutter hot restart, and this store takes the
/// file over; when that owner ran in another process, the file is checked with
/// `PRAGMA quick_check` first and moved aside if damaged. After a clean close [open] does not wait.
///
/// Nothing that goes wrong with the file reaches the app as an error. A damaged file, a file of
/// something else and a file written by a newer major version are moved aside
/// (`<file>.bad-<time>`, the newest one kept) with the pending writes in them, and the cache starts
/// empty. A damaged or newer file that another process or isolate is using is left as it is, and
/// so is a file that can not be moved aside; this store then keeps its data in memory.
///
/// A storage error during the session (a full disk, or a file another connection keeps locked for
/// three storage transactions in a row) makes the store continue in memory. The file keeps the
/// writes that were pending at the error; writes made after it are not saved. The pending ones the
/// server answers before the instance closes are deleted from the file at close, when the file is
/// still this store's (no other instance took it over, no clear deleted it) and can be written
/// then. The others are sent again at the next start; so are the answered ones after a crash, or
/// when the file still fails at close. An instance that takes the file over loads them at its open
/// and sends them itself. The degraded store keeps its lease row without refreshing it, so another
/// instance takes the file over after one observation period. When another process or isolate
/// takes the file over during the session, this store continues in memory and writes nothing more
/// to the file. Every case above that moves a file aside or leaves the store in memory logs a
/// warning without data to the client's logger.
final class SqlitePersistence {
  /// SQLite files in [directory]; see [sqlitePersistence].
  SqlitePersistence(
    this.directory, {
    @visibleForTesting SqliteStoreOptions? options,
  }) : _options = options ?? SqliteStoreOptions() {
    if (directory.isEmpty) {
      throw ArgumentError.value(directory, 'directory', 'must not be empty');
    }
  }

  /// The directory of the store files.
  final String directory;

  final SqliteStoreOptions _options;

  /// The paths of the stores of this object that are open and own their file.
  final Set<String> _openPaths = <String>{};

  /// The tombstones that a failed clear in this isolate could not remove, by absolute file path. A
  /// later clear of the file takes such a tombstone as its own, and [open] removes it first.
  static final Map<String, LeaseRow> _failedClearTombstones =
      <String, LeaseRow>{};

  /// The path of the store file of [key].
  String pathOf(PersistenceKey key) {
    return SqliteFiles.join(
      directory,
      SqliteFiles.fileName(key.appName, key.databaseUrl),
    );
  }

  /// Opens the store of [key]; what `FirebaseDatabase` calls once at Repo start (this method has
  /// the client's opener type). Never fails: a store that can not own its file comes back with
  /// `isDurable` false, at once when this object already has the store of [key] open. Waits about
  /// 7.5 s when the file has the lease row of another owner (see the class). Messages go to
  /// [logger] when given, else to the logger of the options.
  Future<PersistenceStorageEngine> open(
    PersistenceKey key, {
    DatabaseLogger? logger,
  }) async {
    final SqliteStoreOptions options = logger == null
        ? _options
        : _options.withLogger(logger);
    final String fileName = SqliteFiles.fileName(key.appName, key.databaseUrl);
    final String path = SqliteFiles.join(directory, fileName);
    if (_openPaths.contains(path)) {
      return engineOverConnection(
        SqliteConnection.memoryOnly(
          reason:
              'Realtime Database offline cache $fileName: another instance of this database is '
              'using it; this instance keeps data in memory only.',
          log: options.log,
        ),
        logger: options.log,
      );
    }
    _openPaths.add(path);
    final String absolute = File(path).absolute.path;
    final LeaseRow? leftOver = _failedClearTombstones[absolute];
    if (leftOver != null && _removeTombstone(path, leftOver)) {
      _failedClearTombstones.remove(absolute);
    }
    final SqliteConnection connection = await openSqliteStore(
      directory: directory,
      fileName: fileName,
      options: options,
      onClosed: () => _openPaths.remove(path),
    );
    if (!connection.isDurable) {
      _openPaths.remove(path);
    }
    return engineOverConnection(connection, logger: options.log);
  }

  /// Deletes the store files of [key]: the database file, its side files and its `.bad-` copies.
  /// [key] is used as given: it is the key `FirebaseDatabase` passes to [open].
  ///
  /// Clears under the lease: when the file has the lease row of an owner (not the tombstone of a
  /// clear), the row is watched for one observation period ([SqliteLease.observation], 7.5 s); if
  /// its owner rewrites it, the owner is alive and this throws a [StateError]. Otherwise a
  /// tombstone row is written in the same transaction that checks the row did not change, so a
  /// connection that opens the file meanwhile goes memory-only instead of writing into deleted
  /// files; then the files are deleted.
  ///
  /// Throws a [StateError] while a store of this object has the file open, another connection
  /// (another object, isolate or process) owns it or is writing to it, or another clear of it is
  /// running (its tombstone lives at most [SqliteLease.tombstoneDuration]; that error is thrown at
  /// once and says when to retry). Throws a [ClearPersistenceException] that lists the files that
  /// could not be deleted. When a side file (`-wal`, `-shm`, `-journal`) could not be deleted, the
  /// database file is not tried: it stays, and is not listed. The tombstone is then removed when
  /// the database file is still there, so the file can be opened, and the clear retried, at once.
  /// When the file can not be written at that moment either, a retry of the clear or an open in
  /// this isolate removes it; until then a clear in another isolate or process fails with that
  /// [StateError] and an open there keeps its data in memory.
  Future<void> clear(PersistenceKey key) async {
    final String path = pathOf(key);
    if (_openPaths.contains(path)) {
      throw StateError(
        'The offline cache of this database is open; close the database first.',
      );
    }
    LeaseRow? tombstone;
    if (File(path).existsSync()) {
      final ({String? refusal, LeaseRow? tombstone}) result = await _tombstone(
        path,
      );
      final String? refusal = result.refusal;
      if (refusal != null) {
        throw StateError(refusal);
      }
      tombstone = result.tombstone;
    }
    final String absolute = File(path).absolute.path;
    final List<FileSystemException> failures = SqliteFiles.deleteAll(path);
    if (failures.isEmpty) {
      _failedClearTombstones.remove(absolute);
      return;
    }
    if (tombstone != null && File(path).existsSync()) {
      if (_removeTombstone(path, tombstone)) {
        _failedClearTombstones.remove(absolute);
      } else {
        _failedClearTombstones[absolute] = tombstone;
      }
    }
    throw ClearPersistenceException(failures);
  }

  /// Watches the lease row of the file at [path] and writes the tombstone when nobody refreshed it.
  ///
  /// Returns the written tombstone row, or none when the file has no readable lease table (a
  /// damaged or foreign file is deleted as it is); or the message of the [StateError] that refuses
  /// the clear.
  Future<({String? refusal, LeaseRow? tombstone})> _tombstone(
    String path,
  ) async {
    const ({String? refusal, LeaseRow? tombstone}) noLease = (
      refusal: null,
      tombstone: null,
    );
    const ({String? refusal, LeaseRow? tombstone}) inUse = (
      refusal:
          'The offline cache of this database is in use: by an open database (in this isolate '
          'or another isolate or process) or by another clear; close the database first.',
      tombstone: null,
    );
    final sqlite.Database db;
    try {
      db = _options.openDatabase(path);
    } on sqlite.SqliteException {
      return noLease;
    }
    try {
      db.select('PRAGMA busy_timeout = $busyTimeoutMs');
      final LeaseRow? first = SqliteLease.read(db);
      final LeaseRow? leftOver =
          _failedClearTombstones[File(path).absolute.path];
      final bool ownLeftOver =
          first != null && leftOver != null && first.sameAs(leftOver);
      if (first != null && !ownLeftOver) {
        final int now = _options.nowMs();
        if (first.ownerId == SqliteLease.clearingOwnerId &&
            first.expiresAtMs >= now) {
          // By the clearing side's clock, so only roughly ours.
          final int seconds = ((first.expiresAtMs - now) / 1000).ceil().clamp(
            1,
            SqliteLease.tombstoneDuration.inSeconds,
          );
          return (
            refusal:
                'Another clear of the offline cache of this database is running, or one failed '
                'and could not remove its mark from the file; retry in about $seconds s, when '
                'the mark expires.',
            tombstone: null,
          );
        }
        await _options.delay(SqliteLease.observation);
      }
      if (!SqliteLease.writeTombstone(
        db,
        observed: first,
        nowMs: _options.nowMs(),
      )) {
        return inUse;
      }
      return (refusal: null, tombstone: SqliteLease.read(db));
    } on sqlite.SqliteException catch (e) {
      // A busy or locked file is in use; any other error means it can not be read as a store.
      if (e.resultCode == sqlite.SqlError.SQLITE_BUSY ||
          e.resultCode == sqlite.SqlError.SQLITE_LOCKED) {
        return inUse;
      }
      return noLease;
    } finally {
      // ignore: deprecated_member_use
      db.dispose();
    }
  }

  /// Removes [tombstone] from the file at [path] after a failed deletion. Returns false when the
  /// file could not be written; the tombstone then stays until it expires
  /// ([SqliteLease.tombstoneDuration]) or this isolate removes it later.
  bool _removeTombstone(String path, LeaseRow tombstone) {
    try {
      final sqlite.Database db = _options.openDatabase(path);
      try {
        db.select('PRAGMA busy_timeout = $busyTimeoutMs');
        SqliteLease.removeTombstone(db, tombstone);
        return true;
      } finally {
        // ignore: deprecated_member_use
        db.dispose();
      }
    } on sqlite.SqliteException {
      return false;
    }
  }
}

/// [SqlitePersistence.clear] could not delete some files of the store.
final class ClearPersistenceException implements Exception {
  /// The deletions that failed.
  ClearPersistenceException(this.failures);

  /// One entry per file whose deletion failed. When a side file (`-wal`, `-shm`, `-journal`)
  /// failed, the database file was not tried: it is still there, and is not listed.
  final List<FileSystemException> failures;

  @override
  String toString() {
    final String paths = failures
        .map((FileSystemException e) => e.path)
        .join(', ');
    return 'ClearPersistenceException: could not delete ${failures.length} file(s) of the offline '
        'cache: $paths';
  }
}
