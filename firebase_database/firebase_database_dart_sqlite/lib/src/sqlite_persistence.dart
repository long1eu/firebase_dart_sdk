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
/// [directory] is created when missing (mode 0700 on macOS and Linux). Use a directory of the app,
/// for example `getApplicationSupportDirectory()` of `path_provider` plus `firebase_database` in
/// Flutter, or `~/Library/Application Support/<app>/firebase_database` on macOS,
/// `$XDG_DATA_HOME/<app>/firebase_database` on Linux and `%LOCALAPPDATA%\<app>\firebase_database`
/// on Windows.
///
/// [cacheSizeBytes] is the size above which the client prunes the cached server data: 1 MiB to
/// 100 MiB, 10 MiB when null ([ArgumentError] outside, from [databasePersistence]). Pending writes
/// are never pruned.
///
/// With [cacheServerData] false only the pending writes are stored: they survive a restart and are
/// sent again, and no server data is kept on disk.
///
/// An [ArgumentError] when [directory] is empty. Delete a cache with [clearSqlitePersistence]; find
/// its file with [SqlitePersistence.pathOf].
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
/// database file, its side files and its moved-aside copies.
///
/// [databaseUrl] is normalised by [persistenceDatabaseUrl], the function `FirebaseDatabase` keys
/// its cache with: `FirebaseDatabase.databaseUrl` clears its own files, and so do the spellings of
/// a production URL that the constructor accepts (a trailing `/`, `wss://`, the case of the host,
/// port 443, a `?ns=` equal to the first label of the host). An emulator cache is named by
/// `http://<host>[:<port>]?ns=<namespace>` (`https` on a cloud workstation). The one spelling that
/// names another cache is described at [persistenceDatabaseUrl]. Fails with an [ArgumentError] for
/// a URL that is not a database URL.
///
/// Fails with a [StateError] while an instance holds the file (in this process or another: an
/// owner that refreshes its lease during one observation period, about 7.5 s) or another clear of
/// it is running, and with a [ClearPersistenceException] listing the files that could not be
/// deleted; see [SqlitePersistence.clear].
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

/// SEAM between builder A and builder B: the engine over an opened [connection]. Builder B owns
/// [SqliteStorageEngine] (lib/src/sqlite_storage_engine.dart and the row files next to it).
/// Warnings about stored data go to [logger].
PersistenceStorageEngine engineOverConnection(
  SqliteConnection connection, {
  required DatabaseLogger logger,
}) {
  return SqliteStorageEngine(connection, logger: logger);
}

/// SQLite files of the offline cache, one per app and database URL, in one directory.
///
/// `FirebaseDatabase` calls [open] once, when it starts. One process or isolate owns a file at a
/// time: another one that opens the same database keeps its data in memory, and the opened store
/// says so through its `isDurable`. Nothing that goes wrong with the file reaches the app as an
/// error: a file written by a newer version, a damaged file or a file of something else is moved
/// aside (`<file>.bad-<time>`, the newest one kept) and the cache starts empty; a storage error
/// during the session (a full disk) makes the instance continue in memory. The file then keeps
/// the writes that were pending at the error, and the next start sends them again. Of those, the
/// ones the server answers before the instance closes are removed at close, but only when no other
/// instance took the file over and no clear deleted it meanwhile, and the file can be written then;
/// in every other case (also after a crash) they are sent again. Each case is logged once, without
/// data.
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
  /// `isDurable` false. Messages go to [logger] when given, else to the logger of the options.
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
  /// Clears under the lease: the lease row is watched for one observation period
  /// ([SqliteLease.observation]); if its owner rewrites it, the owner is alive and this throws a
  /// [StateError]. Otherwise a tombstone row is written in the same transaction that checks the row
  /// did not change, so a connection that opens the file meanwhile goes memory-only instead of
  /// writing into deleted files; then the files are deleted.
  ///
  /// Throws a [StateError] while a store of this object has the file open, another process or
  /// isolate owns it, or another clear of it is running (its tombstone lives at most
  /// [SqliteLease.tombstoneDuration]). Throws a [ClearPersistenceException] that lists the files
  /// that could not be deleted. The tombstone is then removed when the database file is still
  /// there, so the file can be opened, and the clear retried, at once. When the file can not be
  /// written at that moment either, a retry of the clear or an open in this isolate removes it.
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

  /// One entry per file that could not be deleted.
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
