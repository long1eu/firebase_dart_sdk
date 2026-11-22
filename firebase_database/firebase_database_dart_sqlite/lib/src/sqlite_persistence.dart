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
/// An [ArgumentError] when [directory] is empty. Delete a cache with [clearSqlitePersistence]; find
/// its file with [SqlitePersistence.pathOf].
DatabasePersistence sqlitePersistence(String directory, {int? cacheSizeBytes}) {
  return databasePersistence(
    opener: SqlitePersistence(directory).open,
    cacheSizeBytes: cacheSizeBytes,
  );
}

/// Deletes the cache files of [databaseUrl] of the app named [appName] in [directory]: the
/// database file, its side files and its moved-aside copies.
///
/// Throws a [StateError] while an instance holds the file (in this process or another: an owner
/// that refreshes its lease during one observation period, about 7.5 s), and a
/// [ClearPersistenceException] listing the files that could not be deleted.
Future<void> clearSqlitePersistence(
  String directory, {
  required String appName,
  required Uri databaseUrl,
}) {
  return SqlitePersistence(
    directory,
  ).clear(PersistenceKey(appName: appName, databaseUrl: databaseUrl));
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
/// during the session (a full disk) makes the instance continue in memory. Each case is logged
/// once, without data.
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
  ///
  /// Clears under the lease (revised after review, 2026-11-22): the lease row is watched for one
  /// observation period ([SqliteLease.observation]); if its owner rewrites it, the owner is alive
  /// and this throws a [StateError]. Otherwise a tombstone row is written in the same transaction
  /// that checks the row did not change, so a connection that opened the file meanwhile goes
  /// memory-only instead of writing into deleted files; then the files are deleted.
  ///
  /// Throws a [StateError] while a store of this object has the file open or another process or
  /// isolate owns it; a [ClearPersistenceException] that lists the files that could not be deleted.
  Future<void> clear(PersistenceKey key) async {
    final String path = pathOf(key);
    if (_openPaths.contains(path)) {
      throw StateError(
        'The offline cache of this database is open; close the database first.',
      );
    }
    if (File(path).existsSync() && !await _tombstone(path)) {
      throw StateError(
        'Another process or isolate is using the offline cache of this database.',
      );
    }
    final List<FileSystemException> failures = SqliteFiles.deleteAll(path);
    if (failures.isNotEmpty) {
      throw ClearPersistenceException(failures);
    }
  }

  /// Watches the lease row of the file at [path] and writes the tombstone when nobody refreshed it.
  /// Returns false when a live owner holds the file; true when the tombstone is written or the file
  /// has no readable lease (a damaged or foreign file is deleted as it is).
  Future<bool> _tombstone(String path) async {
    final sqlite.Database db;
    try {
      db = _options.openDatabase(path);
    } on sqlite.SqliteException {
      return true;
    }
    try {
      db.select('PRAGMA busy_timeout = $busyTimeoutMs');
      final LeaseRow? first = SqliteLease.read(db);
      if (first != null) {
        if (first.ownerId == SqliteLease.clearingOwnerId &&
            first.expiresAtMs >= _options.nowMs()) {
          return false;
        }
        await _options.delay(SqliteLease.observation);
      }
      return SqliteLease.writeTombstone(
        db,
        observed: first,
        nowMs: _options.nowMs(),
      );
    } on sqlite.SqliteException catch (e) {
      // A busy or locked file is in use; any other error means it can not be read as a store.
      return e.resultCode != sqlite.SqlError.SQLITE_BUSY &&
          e.resultCode != sqlite.SqlError.SQLITE_LOCKED;
    } finally {
      // ignore: deprecated_member_use
      db.dispose();
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
