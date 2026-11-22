import 'dart:io';

import 'package:firebase_database_dart_sqlite/src/engine_contract_placeholder.dart';
import 'package:firebase_database_dart_sqlite/src/sqlite_connection.dart';
import 'package:firebase_database_dart_sqlite/src/sqlite_files.dart';
import 'package:firebase_database_dart_sqlite/src/sqlite_lease.dart';
import 'package:firebase_database_dart_sqlite/src/sqlite_open.dart';
import 'package:meta/meta.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// The default size above which the server cache is pruned: 10 MiB, as on Android.
const int defaultCacheSizeBytes = 10 * 1024 * 1024;

/// The smallest allowed cache size: 1 MiB, as on Android.
const int minimumCacheSizeBytes = 1024 * 1024;

/// The largest allowed cache size: 100 MiB, as on Android.
const int maximumCacheSizeBytes = 100 * 1024 * 1024;

/// An offline cache in SQLite files under [directory], for `FirebaseDatabase(persistence: ...)`.
///
/// [directory] is created when missing (mode 0700 on macOS and Linux). Use a directory of the app,
/// for example `getApplicationSupportDirectory()` of `path_provider` plus `firebase_database` in
/// Flutter, or `~/Library/Application Support/<app>/firebase_database` on macOS,
/// `$XDG_DATA_HOME/<app>/firebase_database` on Linux and `%LOCALAPPDATA%\<app>\firebase_database`
/// on Windows.
///
/// [cacheSizeBytes] is the size above which the cached server data is pruned, from
/// [minimumCacheSizeBytes] to [maximumCacheSizeBytes] ([RangeError] otherwise). Pending writes are
/// never pruned.
SqlitePersistence sqlitePersistence(
  String directory, {
  int cacheSizeBytes = defaultCacheSizeBytes,
}) {
  return SqlitePersistence(directory, cacheSizeBytes: cacheSizeBytes);
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
    this.cacheSizeBytes = defaultCacheSizeBytes,
    @visibleForTesting SqliteStoreOptions? options,
  }) : _options = options ?? SqliteStoreOptions() {
    if (directory.isEmpty) {
      throw ArgumentError.value(directory, 'directory', 'must not be empty');
    }
    RangeError.checkValueInInterval(
      cacheSizeBytes,
      minimumCacheSizeBytes,
      maximumCacheSizeBytes,
      'cacheSizeBytes',
    );
  }

  /// The directory of the store files.
  final String directory;

  /// The size above which the server cache is pruned, in bytes.
  final int cacheSizeBytes;

  final SqliteStoreOptions _options;

  /// The paths of the stores of this object that are open and own their file.
  final Set<String> _openPaths = <String>{};

  /// The path of the store file of [databaseUrl] of the app named [appName].
  String pathOf(String appName, Uri databaseUrl) {
    return SqliteFiles.join(
      directory,
      SqliteFiles.fileName(appName, databaseUrl),
    );
  }

  @override
  Future<PersistenceStorageEngine> open(String appName, Uri databaseUrl) async {
    final String fileName = SqliteFiles.fileName(appName, databaseUrl);
    final String path = SqliteFiles.join(directory, fileName);
    if (_openPaths.contains(path)) {
      return engineOverConnection(
        SqliteConnection.memoryOnly(
          reason:
              'Realtime Database offline cache $fileName: another instance of this database is '
              'using it; this instance keeps data in memory only.',
          log: _options.log,
        ),
        cacheSizeBytes: cacheSizeBytes,
      );
    }
    _openPaths.add(path);
    final SqliteConnection connection = await openSqliteStore(
      directory: directory,
      fileName: fileName,
      options: _options,
      onClosed: () => _openPaths.remove(path),
    );
    if (!connection.isDurable) {
      _openPaths.remove(path);
    }
    return engineOverConnection(connection, cacheSizeBytes: cacheSizeBytes);
  }

  /// Deletes the store files of [key]: the database file, its side files and its `.bad-` copies.
  ///
  /// Throws a [StateError] while a store of this object has the file open, or while another process
  /// or isolate holds a live lease on it; a [ClearPersistenceException] that lists the files that
  /// could not be deleted.
  Future<void> clear(PersistenceKey key) async {
    final String path = pathOf(key);
    if (_openPaths.contains(path)) {
      throw StateError(
        'The offline cache of this database is open; close the database first.',
      );
    }
    if (File(path).existsSync() && _heldByLiveOwner(path)) {
      throw StateError(
        'Another process or isolate is using the offline cache of this database.',
      );
    }
    final List<FileSystemException> failures = SqliteFiles.deleteAll(path);
    if (failures.isNotEmpty) {
      throw ClearPersistenceException(failures);
    }
  }

  bool _heldByLiveOwner(String path) {
    final sqlite.Database db;
    try {
      db = _options.openDatabase(path);
    } on sqlite.SqliteException {
      return false;
    }
    try {
      db.select('PRAGMA busy_timeout = $busyTimeoutMs');
      return SqliteLease.isHeldByLiveOwner(db, _options.nowMs());
    } on sqlite.SqliteException {
      return false;
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
