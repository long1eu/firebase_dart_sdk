import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:firebase_database_dart/firebase_database_dart.dart'
    show DatabaseLogLevel, DatabaseLogger;
import 'package:firebase_database_dart_sqlite/src/posix_file_mode.dart';
import 'package:firebase_database_dart_sqlite/src/sqlite_connection.dart';
import 'package:firebase_database_dart_sqlite/src/sqlite_files.dart';
import 'package:firebase_database_dart_sqlite/src/sqlite_lease.dart';
import 'package:firebase_database_dart_sqlite/src/sqlite_schema.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// The oldest SQLite this store runs on: 3.24.0. Older libraries get a memory-only store.
const int minimumSqliteVersionNumber = 3024000;

/// What the opener takes from its environment; every member can be replaced in tests.
final class SqliteStoreOptions {
  /// The options of a real run unless a member is given.
  SqliteStoreOptions({
    int Function()? nowMs,
    Future<void> Function(Duration duration)? delay,
    PeriodicTimerFactory? periodicTimer,
    DatabaseLogger? log,
    String Function()? newOwnerId,
    this.sqliteVersionNumber,
    sqlite.Database Function(String path)? openDatabase,
  }) : nowMs = nowMs ?? _wallClockMs,
       delay = delay ?? _wait,
       periodicTimer = periodicTimer ?? Timer.periodic,
       log = log ?? _silent,
       newOwnerId = newOwnerId ?? _randomOwnerId,
       openDatabase = openDatabase ?? _openFile;

  /// Wall-clock time in milliseconds since the epoch: lease times and quarantine names.
  final int Function() nowMs;

  /// Waits for a held lease to expire.
  final Future<void> Function(Duration duration) delay;

  /// Creates the lease refresh timer.
  final PeriodicTimerFactory periodicTimer;

  /// Receives one message per state change of a store; never data.
  final DatabaseLogger log;

  /// Creates the random owner id of a connection.
  final String Function() newOwnerId;

  /// The version number of the SQLite library to assume; null reads it from `package:sqlite3`.
  final int? sqliteVersionNumber;

  /// Opens (and creates) the database file at a path.
  final sqlite.Database Function(String path) openDatabase;

  /// These options with [log] as the logger.
  SqliteStoreOptions withLogger(DatabaseLogger log) {
    return SqliteStoreOptions(
      nowMs: nowMs,
      delay: delay,
      periodicTimer: periodicTimer,
      log: log,
      newOwnerId: newOwnerId,
      sqliteVersionNumber: sqliteVersionNumber,
      openDatabase: openDatabase,
    );
  }

  static int _wallClockMs() => DateTime.now().millisecondsSinceEpoch;

  static Future<void> _wait(Duration duration) =>
      Future<void>.delayed(duration);

  static void _silent(DatabaseLogLevel level, String message) {}

  static sqlite.Database _openFile(String path) => sqlite.sqlite3.open(path);

  /// `<process id>:<32 random hex digits>`: the process part tells a hot restart (same process)
  /// from a crash.
  static String _randomOwnerId() {
    final Random random = Random.secure();
    final StringBuffer buffer = StringBuffer('$pid:');
    for (int i = 0; i < 16; i++) {
      buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}

/// Opens the store file [fileName] in [directory] and takes its lease (design sections 4, 8, 10).
///
/// Never throws and never crashes the app: whatever goes wrong ends in a memory-only connection
/// with one log message. In order:
///
/// 1. A SQLite older than [minimumSqliteVersionNumber]: memory-only.
/// 2. [directory] is created when missing, with mode 0700 on macOS and Linux (an existing directory
///    is left as it is: it belongs to the app). The file is created empty with mode 0600 before
///    SQLite opens it; an existing file loses its group and other bits.
/// 3. The file is classified: new, ours (same major version), written by a newer major, foreign
///    (another `application_id`), or unreadable. A newer or unreadable file is left alone when a
///    live owner is observed in it (another version is running on it) and the store is memory-only;
///    otherwise it is moved aside with its write-ahead log and the store starts empty. A foreign
///    file is always moved aside.
/// 4. Write-ahead logging, `synchronous = FULL`, the tables of this version.
/// 5. The lease: taken at once when free; when held, the row is watched for
///    [SqliteLease.observation]: unchanged, it is taken over; rewritten, the store is memory-only.
///    When the previous owner vanished without releasing it and ran in another process, the file
///    is checked with `PRAGMA quick_check` and moved aside if damaged. A file that
///    `clearSqlitePersistence` is deleting is never taken.
///
/// [onClosed] runs when the returned connection is closed (not for a memory-only connection).
Future<SqliteConnection> openSqliteStore({
  required String directory,
  required String fileName,
  required SqliteStoreOptions options,
  void Function()? onClosed,
}) async {
  final _StoreOpener opener = _StoreOpener(
    directory,
    fileName,
    options,
    onClosed,
  );
  try {
    return await opener.open(afterMoveAside: false);
  } on Object catch (e) {
    return opener.memoryOnly('it could not be opened (${e.runtimeType})');
  }
}

enum _FileKind { fresh, current, newer, foreign, unreadable }

final class _StoreOpener {
  _StoreOpener(this.directory, this.fileName, this.options, this.onClosed)
    : path = SqliteFiles.join(directory, fileName),
      fileMode = PosixFileMode.forCurrentPlatform();

  final String directory;
  final String fileName;
  final String path;
  final SqliteStoreOptions options;
  final void Function()? onClosed;
  final PosixFileMode? fileMode;

  SqliteConnection memoryOnly(String why) {
    return SqliteConnection.memoryOnly(
      reason:
          'Realtime Database offline cache $fileName: $why; '
          'this instance keeps data in memory only.',
      log: options.log,
    );
  }

  Future<SqliteConnection> open({required bool afterMoveAside}) async {
    final int version =
        options.sqliteVersionNumber ?? sqlite.sqlite3.version.versionNumber;
    if (version < minimumSqliteVersionNumber) {
      return memoryOnly('SQLite $version is older than 3.24.0');
    }
    _prepareDirectory();
    _preparePrivateFile();

    final sqlite.Database db = options.openDatabase(path);
    bool handedOver = false;
    try {
      db.select('PRAGMA busy_timeout = $busyTimeoutMs');
      final _FileKind kind = _classify(db);
      switch (kind) {
        case _FileKind.fresh:
          SqliteSchema.prepareNewFile(db);
          _useWriteAheadLog(db);
          SqliteSchema.ensureTables(db);
        case _FileKind.current:
          _useWriteAheadLog(db);
          SqliteSchema.ensureTables(db);
        case _FileKind.newer:
        case _FileKind.unreadable:
          if (await SqliteLease.isHeldByLiveOwner(
            db,
            nowMs: options.nowMs,
            delay: options.delay,
          )) {
            return memoryOnly(
              kind == _FileKind.newer
                  ? 'it was written by a newer version, which is using it'
                  : 'it is damaged and another process or isolate is using it',
            );
          }
          _disposeQuietly(db);
          handedOver = true;
          return await _quarantine(
            kind == _FileKind.newer
                ? 'it was written by a newer version'
                : 'it is damaged',
            afterMoveAside: afterMoveAside,
          );
        case _FileKind.foreign:
          _disposeQuietly(db);
          handedOver = true;
          return await _quarantine(
            'it is not a Realtime Database cache',
            afterMoveAside: afterMoveAside,
          );
      }
      db.select('PRAGMA synchronous = FULL');
      db.select('PRAGMA temp_store = MEMORY');

      final SqliteLease lease = SqliteLease(
        ownerId: options.newOwnerId(),
        nowMs: options.nowMs,
      );
      // Liveness by observation: an owner that does not rewrite its row within one observation
      // period is gone (revised after review, 2026-11-22).
      LeaseAttempt attempt = lease.tryAcquire(db);
      if (attempt is LeaseHeld) {
        await options.delay(SqliteLease.observation);
        attempt = lease.tryAcquire(db, observed: attempt.observed);
      }
      switch (attempt) {
        case LeaseCleared():
          return memoryOnly('it is being deleted');
        case LeaseHeld():
          return memoryOnly('another process or isolate owns it');
        // A hot restart (same process) did not crash the process: no check needed.
        case LeaseAcquired(
              previousOwnerVanished: true,
              previousOwnerSameProcess: false,
            )
            when !_passesQuickCheck(db):
          lease.release(db);
          _disposeQuietly(db);
          handedOver = true;
          return await _quarantine(
            'it is damaged',
            afterMoveAside: afterMoveAside,
          );
        case LeaseAcquired():
          break;
      }

      final SqliteConnection connection = SqliteConnection.durable(
        database: db,
        path: path,
        lease: lease,
        log: options.log,
        periodicTimer: options.periodicTimer,
        onClosed: onClosed,
      );
      handedOver = true;
      connection.startLeaseRefresh();
      return connection;
    } on sqlite.SqliteException catch (e) {
      if (_isDamage(e)) {
        _disposeQuietly(db);
        handedOver = true;
        return _quarantine('it is damaged', afterMoveAside: afterMoveAside);
      }
      return memoryOnly(
        'it could not be opened (SQLite result code ${e.resultCode})',
      );
    } finally {
      if (!handedOver) {
        _disposeQuietly(db);
      }
    }
  }

  Future<SqliteConnection> _quarantine(
    String why, {
    required bool afterMoveAside,
  }) {
    if (afterMoveAside) {
      return Future<SqliteConnection>.value(
        memoryOnly('$why, also after a fresh start'),
      );
    }
    final DateTime now = DateTime.fromMillisecondsSinceEpoch(
      options.nowMs(),
      isUtc: true,
    );
    if (!SqliteFiles.moveAside(path, now)) {
      return Future<SqliteConnection>.value(
        memoryOnly('$why and could not be moved aside'),
      );
    }
    options.log(
      DatabaseLogLevel.warning,
      'Realtime Database offline cache $fileName: $why; it was moved aside and the cache starts '
      'empty.',
    );
    return open(afterMoveAside: true);
  }

  void _prepareDirectory() {
    final Directory dir = Directory(directory);
    if (dir.existsSync()) {
      return;
    }
    dir.createSync(recursive: true);
    fileMode?.setMode(directory, PosixFileMode.privateDirectory);
  }

  void _preparePrivateFile() {
    final File file = File(path);
    if (!file.existsSync()) {
      try {
        file.createSync(exclusive: true);
      } on FileSystemException {
        // Created by another process or isolate in the meantime; its mode is checked below.
      }
    }
    final PosixFileMode? mode = fileMode;
    if (mode != null &&
        !mode.makePrivate(path, mode: PosixFileMode.privateFile)) {
      options.log(
        DatabaseLogLevel.warning,
        'Realtime Database offline cache $fileName: its file mode could not be set.',
      );
    }
  }

  _FileKind _classify(sqlite.Database db) {
    final int applicationId;
    final int userVersion;
    final int tables;
    try {
      applicationId =
          db.select('PRAGMA application_id').first.columnAt(0) as int;
      userVersion = db.userVersion;
      tables =
          db
                  .select(
                    "SELECT count(*) FROM sqlite_master WHERE type = 'table'",
                  )
                  .first
                  .columnAt(0)
              as int;
    } on sqlite.SqliteException catch (e) {
      if (_isDamage(e)) {
        return _FileKind.unreadable;
      }
      rethrow;
    }
    if (applicationId == 0 && userVersion == 0 && tables == 0) {
      return _FileKind.fresh;
    }
    if (applicationId != SqliteSchema.applicationId) {
      return _FileKind.foreign;
    }
    if (SqliteSchema.majorOf(userVersion) > SqliteSchema.major) {
      return _FileKind.newer;
    }
    return _FileKind.current;
  }

  void _useWriteAheadLog(sqlite.Database db) {
    final Object? current = db.select('PRAGMA journal_mode').first.columnAt(0);
    if ('$current'.toLowerCase() == 'wal') {
      return;
    }
    final Object? mode = db
        .select('PRAGMA journal_mode = WAL')
        .first
        .columnAt(0);
    if ('$mode'.toLowerCase() != 'wal') {
      options.log(
        DatabaseLogLevel.info,
        'Realtime Database offline cache $fileName: the file system keeps journal mode "$mode".',
      );
    }
  }

  bool _passesQuickCheck(sqlite.Database db) {
    try {
      final sqlite.ResultSet rows = db.select('PRAGMA quick_check');
      return rows.isNotEmpty && '${rows.first.columnAt(0)}' == 'ok';
    } on sqlite.SqliteException {
      return false;
    }
  }

  static bool _isDamage(sqlite.SqliteException e) {
    return e.resultCode == sqlite.SqlError.SQLITE_CORRUPT ||
        e.resultCode == sqlite.SqlError.SQLITE_NOTADB;
  }

  static void _disposeQuietly(sqlite.Database db) {
    try {
      // ignore: deprecated_member_use
      db.dispose();
    } on sqlite.SqliteException {
      // Closing a file that is being given up.
    }
  }
}
