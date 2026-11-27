import 'dart:async';
import 'dart:io';

import 'package:firebase_database_dart/firebase_database_dart.dart'
    show DatabaseLogLevel, DatabaseLogger;
import 'package:firebase_database_dart_sqlite/src/sqlite_lease.dart';
import 'package:meta/meta.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// How long a statement waits for another connection's lock before failing with `SQLITE_BUSY`, in
/// milliseconds. Short, because the store runs on the application's main isolate (revised after
/// review, 2026-11-22: was 5 s).
const int busyTimeoutMs = 1000;

/// How many storage transactions in a row may fail on a busy or locked file before the store gives
/// up and degrades.
const int maxConsecutiveBusy = 3;

/// Creates the periodic timer of the lease refresh; [Timer.periodic] outside tests.
typedef PeriodicTimerFactory =
    Timer Function(Duration period, void Function(Timer timer) tick);

/// What a [SqliteConnection] does with the statements it is given.
enum StoreState {
  /// Statements run against the file; the lease is ours.
  durable,

  /// The file was never opened (another owner, an unreadable file, SQLite too old). Statements are
  /// no-ops and reads return nothing.
  memoryOnly,

  /// Another connection took the lease during the session. The file is theirs now: statements are
  /// no-ops and nothing more is written.
  fenced,

  /// A storage error (disk full, I/O error, corruption, or a file busy [maxConsecutiveBusy] times
  /// in a row) stopped the writes during the session. Nothing is deleted: the file keeps everything
  /// committed before the error, pending writes included. The lease row stays but is no longer
  /// refreshed, so another connection takes the file over after one observation period;
  /// [SqliteConnection.close] releases it when nobody did.
  degraded,

  /// [SqliteConnection.close] was called.
  closed,
}

/// The one SQLite connection of a store: the contract between the open/lease side (builder A) and
/// the engine (builder B, `SqliteStorageEngine`).
///
/// The engine maps the engine interface onto it:
///
/// * `beginTransaction()` → [begin]; `endTransaction()` → [commit] when
///   `setTransactionSuccessful()` was called, else [rollback]. One engine transaction is one
///   SQLite transaction (`BEGIN IMMEDIATE`) that starts with the lease check, so a write never
///   lands in a file that another owner took.
/// * Writes go through [execute] and must be inside a transaction ([StateError] otherwise, the
///   engine's "mutation outside a transaction" rule). Reads go through [select], inside or outside
///   a transaction (`loadUserWrites` at start reads outside one).
///
/// The connection never lets an [sqlite.SqliteException] reach the engine. When a statement fails
/// the connection rolls back the transaction and the rest of it is a no-op:
///
/// * `SQLITE_BUSY` or `SQLITE_LOCKED` (another connection held the file for [busyTimeoutMs]): the
///   store stays durable; only after [maxConsecutiveBusy] such transactions in a row it degrades.
/// * Any other error: [StoreState.degraded] for the rest of the session, one log message without
///   data, nothing deleted. A lost lease: [StoreState.fenced].
///
/// From then on [execute] does nothing and [select] returns no rows. The engine needs no error
/// handling of its own. A failure that can only come from wrong SQL (`SQLITE_ERROR`, a constraint,
/// a type mismatch, misuse) also fails an assertion, so the engine's tests see it; production
/// builds degrade.
final class SqliteConnection {
  /// A connection that owns [database] (at [path]) under [lease]. Called by the opener only, after
  /// the lease was acquired; call [startLeaseRefresh] next. [openDatabase] opens the existing file
  /// again at the [close] of a degraded store; by default `sqlite3.open` without creating it.
  SqliteConnection.durable({
    required sqlite.Database database,
    required String this.path,
    required SqliteLease lease,
    required DatabaseLogger log,
    required PeriodicTimerFactory periodicTimer,
    void Function()? onClosed,
    sqlite.Database Function(String path)? openDatabase,
  }) : _db = database,
       _lease = lease,
       _log = log,
       _periodicTimer = periodicTimer,
       _onClosed = onClosed,
       _openDatabase = openDatabase ?? _openExisting,
       _state = StoreState.durable;

  /// A connection without a file. [reason] is logged once; it must not contain data.
  SqliteConnection.memoryOnly({
    required String reason,
    required DatabaseLogger log,
  }) : _db = null,
       path = null,
       _lease = null,
       _log = log,
       _periodicTimer = null,
       _onClosed = null,
       _openDatabase = null,
       _state = StoreState.memoryOnly {
    _log(DatabaseLogLevel.warning, reason);
  }

  /// How many prepared statements are kept, least recently used dropped first. Preparing was about
  /// 40 % of the SQLite time of a one-row read in the Firestore cache of this repository.
  static const int statementCacheSize = 64;

  /// The path of the database file, or null for a memory-only connection.
  final String? path;

  sqlite.Database? _db;
  final SqliteLease? _lease;
  final DatabaseLogger _log;
  final PeriodicTimerFactory? _periodicTimer;
  void Function()? _onClosed;
  final sqlite.Database Function(String path)? _openDatabase;
  StoreState _state;
  Timer? _refreshTimer;
  bool _inTransaction = false;
  bool _transactionFailed = false;
  bool _sqliteTransactionOpen = false;
  bool _extendedInTransaction = false;
  int _consecutiveBusy = 0;
  final Map<String, sqlite.PreparedStatement> _statements =
      <String, sqlite.PreparedStatement>{};

  /// What the connection does with statements now.
  StoreState get state => _state;

  /// Whether statements still reach the file.
  bool get isDurable => _state == StoreState.durable;

  /// Whether [begin] was called without a matching [commit] or [rollback].
  bool get inTransaction => _inTransaction;

  /// The raw connection, for tests that need to change the file behind the store's back.
  @visibleForTesting
  sqlite.Database? get debugDatabase => _db;

  /// Starts refreshing the lease every [SqliteLease.refreshInterval]. Called once by the opener.
  void startLeaseRefresh() {
    final PeriodicTimerFactory? periodic = _periodicTimer;
    if (!isDurable || periodic == null || _refreshTimer != null) {
      return;
    }
    _refreshTimer = periodic(
      SqliteLease.refreshInterval,
      (Timer _) => refreshLease(),
    );
  }

  /// Extends the lease in a transaction of its own; moves to [StoreState.fenced] when another
  /// connection took it. Runs from the refresh timer; tests call it directly. Does nothing inside a
  /// transaction (the timer can not fire there, a test could) or when not durable.
  void refreshLease() {
    if (!isDurable || _inTransaction) {
      return;
    }
    if (!begin()) {
      rollback();
      return;
    }
    // The timer always rewrites the row, so a live owner writes it at least every refresh
    // interval; once per transaction: `begin` may already have rewritten it (extendIfDue).
    if (!_extendedInTransaction) {
      _guard(() => _lease!.extend(_db!));
    }
    commit();
  }

  /// Starts a transaction: `BEGIN IMMEDIATE`, then the lease check.
  ///
  /// Returns true when the transaction runs against the file, false when statements of this
  /// transaction will be no-ops (not durable, or the lease was just found lost). Either way the
  /// caller ends it with [commit] or [rollback]. A [StateError] when a transaction is already open
  /// (the engine interface does not nest).
  bool begin() {
    if (_inTransaction) {
      throw StateError('A storage transaction is already in progress.');
    }
    _inTransaction = true;
    _transactionFailed = false;
    _extendedInTransaction = false;
    if (!isDurable) {
      return false;
    }
    final sqlite.Database db = _db!;
    final bool started = _guard(() {
      db.execute('BEGIN IMMEDIATE');
      _sqliteTransactionOpen = true;
      return true;
    }, fallback: false);
    if (!started || !isDurable) {
      return false;
    }
    bool ours;
    try {
      ours = _guard(() => _lease!.holdsFence(db), fallback: false);
    } on Object {
      // A lease row this code can not read is not ours (revised after review, 2026-11-22).
      ours = false;
    }
    if (!isDurable || _transactionFailed) {
      return false;
    }
    if (!ours) {
      _stopWriting(
        StoreState.fenced,
        'another process or isolate took over the offline cache',
      );
      return false;
    }
    _extendedInTransaction = _guard(
      () => _lease!.extendIfDue(db),
      fallback: false,
    );
    return isDurable && !_transactionFailed;
  }

  /// Commits the transaction [begin] started. Requires an open transaction ([StateError]), except
  /// after [close], when it does nothing.
  ///
  /// Returns whether the transaction reached the file: false when it was refused (a busy file),
  /// failed, was fenced, or the connection is not durable.
  bool commit() {
    if (_state == StoreState.closed) {
      return false;
    }
    _requireTransaction('commit');
    final bool failed = _transactionFailed;
    _inTransaction = false;
    _transactionFailed = false;
    if (!isDurable || failed || !_sqliteTransactionOpen) {
      return false;
    }
    final bool committed = _guard(() {
      _db!.execute('COMMIT');
      _sqliteTransactionOpen = false;
      return true;
    }, fallback: false);
    if (committed) {
      _consecutiveBusy = 0;
    }
    return committed;
  }

  /// Rolls back the transaction [begin] started. Requires an open transaction ([StateError]),
  /// except after [close], when it does nothing.
  void rollback() {
    if (_state == StoreState.closed) {
      return;
    }
    _requireTransaction('rollback');
    _inTransaction = false;
    _transactionFailed = false;
    if (!isDurable || !_sqliteTransactionOpen) {
      return;
    }
    _guard(() {
      _db!.execute('ROLLBACK');
      _sqliteTransactionOpen = false;
    });
  }

  /// Runs a statement that returns no rows, with [parameters] bound in order.
  ///
  /// Must be inside a transaction ([StateError] otherwise). A no-op when the connection is not
  /// durable or an earlier statement of this transaction failed.
  void execute(String sql, [List<Object?> parameters = const <Object?>[]]) {
    _requireTransaction('execute');
    if (!isDurable || _transactionFailed) {
      return;
    }
    _guard(() => _cached(sql).execute(parameters));
  }

  /// Runs a query with [parameters] bound in order and returns its rows; none when the connection
  /// is not durable, an earlier statement of this transaction failed, or this query fails.
  Iterable<sqlite.Row> select(
    String sql, [
    List<Object?> parameters = const <Object?>[],
  ]) {
    if (!isDurable || _transactionFailed) {
      return const <sqlite.Row>[];
    }
    return _guard<Iterable<sqlite.Row>>(
      () => _cached(sql).select(parameters),
      fallback: const <sqlite.Row>[],
    );
  }

  /// The number of rows changed by the last [execute]; 0 when it did not run.
  int get changes => isDurable ? _db!.updatedRows : 0;

  /// Rolls back an open transaction, releases the lease, checkpoints the write-ahead log and closes
  /// the file. Idempotent; never throws.
  ///
  /// A degraded store opens the file once more ([_finishDegraded]): when it is provably still this
  /// connection's, it deletes the rows of [removeWriteIds] (pending writes the client removed after
  /// the storage error) and releases the lease.
  void close({Iterable<int> removeWriteIds = const <int>[]}) {
    if (_state == StoreState.closed) {
      return;
    }
    _refreshTimer?.cancel();
    _refreshTimer = null;
    final sqlite.Database? db = _db;
    if (db != null && isDurable) {
      if (_sqliteTransactionOpen) {
        _quietly(() => db.execute('ROLLBACK'));
        _sqliteTransactionOpen = false;
      }
      _withoutBusyWait(db, () {
        _lease!.release(db);
        _quietly(() => db.select('PRAGMA wal_checkpoint(TRUNCATE)'));
      });
    }
    if (_state == StoreState.degraded) {
      _finishDegraded(removeWriteIds.toList());
    }
    _inTransaction = false;
    _dispose();
    _state = StoreState.closed;
    final void Function()? onClosed = _onClosed;
    _onClosed = null;
    onClosed?.call();
  }

  /// At the close of a degraded store: opens the file again (never creating it) and, in one
  /// transaction, when the lease row still names this connection ([SqliteLease.isStillOurs]),
  /// deletes the rows of [ids] and the lease row. When another connection or a clear took the file
  /// since the error, or the file is gone, nothing is changed. Never throws; waits at most
  /// [busyTimeoutMs] for the lock.
  void _finishDegraded(List<int> ids) {
    final String? file = path;
    final sqlite.Database Function(String path)? reopen = _openDatabase;
    if (file == null || reopen == null) {
      return;
    }
    final String what =
        '${ids.length} write(s) the server answered after the storage error';
    sqlite.Database? db;
    try {
      db = reopen(file);
      db.select('PRAGMA busy_timeout = $busyTimeoutMs');
      db.execute('BEGIN IMMEDIATE');
      if (!_lease!.isStillOurs(db)) {
        db.execute('ROLLBACK');
        if (ids.isNotEmpty) {
          _log(
            DatabaseLogLevel.info,
            'Realtime Database offline cache: the file was taken over or cleared after the '
            'storage error; $what were left in it.',
          );
        }
        return;
      }
      _deleteUserWrites(db, ids);
      _lease.releaseInTransaction(db);
      db.execute('COMMIT');
      if (ids.isNotEmpty) {
        _log(
          DatabaseLogLevel.info,
          'Realtime Database offline cache: $what were removed from the file.',
        );
      }
    } on sqlite.SqliteException catch (e) {
      final sqlite.Database? opened = db;
      if (opened != null) {
        _quietly(() => opened.execute('ROLLBACK'));
      }
      if (ids.isNotEmpty && File(file).existsSync()) {
        _log(
          DatabaseLogLevel.warning,
          'Realtime Database offline cache: $what could not be removed from the file (SQLite '
          'result code ${e.resultCode}); the next start may send them again.',
        );
      }
    } finally {
      // ignore: deprecated_member_use
      _quietly(() => db?.dispose());
    }
  }

  static sqlite.Database _openExisting(String path) =>
      sqlite.sqlite3.open(path, mode: sqlite.OpenMode.readWrite);

  static void _deleteUserWrites(sqlite.Database db, List<int> ids) {
    if (ids.isEmpty) {
      return;
    }
    final sqlite.PreparedStatement delete = db.prepare(
      'DELETE FROM user_writes WHERE id = ?',
    );
    try {
      for (final int id in ids) {
        delete.execute(<Object?>[id]);
      }
    } finally {
      // ignore: deprecated_member_use
      delete.dispose();
    }
  }

  void _requireTransaction(String operation) {
    if (!_inTransaction) {
      throw StateError('$operation called outside a storage transaction.');
    }
  }

  sqlite.PreparedStatement _cached(String sql) {
    sqlite.PreparedStatement? statement = _statements.remove(sql);
    statement ??= _db!.prepare(sql, persistent: true, checkNoTail: true);
    _statements[sql] = statement;
    if (_statements.length > statementCacheSize) {
      final String oldest = _statements.keys.first;
      // ignore: deprecated_member_use
      _statements.remove(oldest)!.dispose();
    }
    return statement;
  }

  /// Runs [body]; on an [sqlite.SqliteException] handles the error and returns [fallback].
  T _guard<T>(T Function() body, {T? fallback}) {
    try {
      return body();
    } on sqlite.SqliteException catch (e) {
      _onStorageError(e);
      return fallback as T;
    }
  }

  void _onStorageError(sqlite.SqliteException error) {
    _transactionFailed = true;
    if (_isBusy(error)) {
      _consecutiveBusy++;
      if (_consecutiveBusy < maxConsecutiveBusy) {
        _rollbackQuietly();
        _log(
          DatabaseLogLevel.info,
          'Realtime Database offline cache: the file was busy (SQLite result code '
          '${error.resultCode}); one storage transaction was not saved.',
        );
        return;
      }
    }
    _stopWriting(
      StoreState.degraded,
      'a storage error (SQLite result code ${error.resultCode}) stopped the offline cache',
    );
    assert(
      !_isProgrammingError(error),
      'A statement of the SQLite store failed with result code ${error.resultCode}: '
      'the SQL or its parameters are wrong.',
    );
  }

  static bool _isBusy(sqlite.SqliteException error) {
    return error.resultCode == sqlite.SqlError.SQLITE_BUSY ||
        error.resultCode == sqlite.SqlError.SQLITE_LOCKED;
  }

  static bool _isProgrammingError(sqlite.SqliteException error) {
    switch (error.resultCode) {
      case sqlite.SqlError.SQLITE_ERROR:
      case sqlite.SqlError.SQLITE_CONSTRAINT:
      case sqlite.SqlError.SQLITE_MISMATCH:
      case sqlite.SqlError.SQLITE_MISUSE:
      case sqlite.SqlError.SQLITE_RANGE:
        return true;
      default:
        return false;
    }
  }

  void _stopWriting(StoreState next, String what) {
    if (!isDurable) {
      return;
    }
    _state = next;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    // Nothing is deleted: the failed transaction was rolled back, so the file is consistent as of
    // its last commit and keeps the pending writes. A degraded store keeps its lease row (no longer
    // refreshed): at close it proves that nobody took the file since (see close).
    _rollbackQuietly();
    _dispose();
    _log(
      DatabaseLogLevel.warning,
      'Realtime Database offline cache: $what; this instance keeps data in memory only.',
    );
  }

  void _rollbackQuietly() {
    final sqlite.Database? db = _db;
    if (db != null && _sqliteTransactionOpen) {
      _quietly(() => db.execute('ROLLBACK'));
    }
    _sqliteTransactionOpen = false;
  }

  /// Runs best-effort clean-up with `busy_timeout` 0, so that it never waits on the main isolate.
  static void _withoutBusyWait(sqlite.Database db, void Function() body) {
    _quietly(() => db.select('PRAGMA busy_timeout = 0'));
    try {
      body();
    } finally {
      _quietly(() => db.select('PRAGMA busy_timeout = $busyTimeoutMs'));
    }
  }

  void _dispose() {
    for (final sqlite.PreparedStatement statement in _statements.values) {
      // ignore: deprecated_member_use
      _quietly(statement.dispose);
    }
    _statements.clear();
    final sqlite.Database? db = _db;
    _db = null;
    if (db != null) {
      // ignore: deprecated_member_use
      _quietly(db.dispose);
    }
  }

  static void _quietly(void Function() body) {
    try {
      body();
    } on sqlite.SqliteException {
      // Best effort: the connection is being given up.
    }
  }
}
