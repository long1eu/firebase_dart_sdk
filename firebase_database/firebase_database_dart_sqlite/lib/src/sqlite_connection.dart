import 'dart:async';

import 'package:firebase_database_dart/firebase_database_dart.dart'
    show DatabaseLogLevel, DatabaseLogger;
import 'package:firebase_database_dart_sqlite/src/sqlite_lease.dart';
import 'package:firebase_database_dart_sqlite/src/sqlite_schema.dart';
import 'package:meta/meta.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

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

  /// A storage error (disk full, I/O error, corruption) stopped the writes during the session. The
  /// data tables were emptied, best effort, so that the next start does not replay stale writes.
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
/// the connection rolls back, moves to [StoreState.degraded] (or [StoreState.fenced] when the lease
/// was lost), logs one message without data, and from then on [execute] does nothing and [select]
/// returns no rows. The engine needs no error handling of its own: it keeps calling the same
/// methods and checks [isDurable] where it wants to skip work. A failure that can only come from
/// wrong SQL (`SQLITE_ERROR`, a constraint, a type mismatch, misuse) also fails an assertion, so
/// the engine's tests see it; production builds degrade.
final class SqliteConnection {
  /// A connection that owns [database] (at [path]) under [lease]. Called by the opener only, after
  /// the lease was acquired; call [startLeaseRefresh] next.
  SqliteConnection.durable({
    required sqlite.Database database,
    required String this.path,
    required SqliteLease lease,
    required DatabaseLogger log,
    required PeriodicTimerFactory periodicTimer,
    void Function()? onClosed,
  }) : _db = database,
       _lease = lease,
       _log = log,
       _periodicTimer = periodicTimer,
       _onClosed = onClosed,
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
  StoreState _state;
  Timer? _refreshTimer;
  bool _inTransaction = false;
  bool _transactionFailed = false;
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
    _guard(() => _lease!.extend(_db!));
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
    if (!isDurable) {
      return false;
    }
    final sqlite.Database db = _db!;
    final bool started = _guard(() {
      db.execute('BEGIN IMMEDIATE');
      return true;
    }, fallback: false);
    if (!started) {
      return false;
    }
    final bool ours = _guard(() => _lease!.holdsFence(db), fallback: false);
    if (!ours && isDurable) {
      _stopWriting(
        StoreState.fenced,
        'another process or isolate took over the offline cache',
      );
      return false;
    }
    return isDurable;
  }

  /// Commits the transaction [begin] started. Requires an open transaction ([StateError]).
  void commit() {
    _requireTransaction('commit');
    final bool failed = _transactionFailed;
    _inTransaction = false;
    _transactionFailed = false;
    if (!isDurable || failed) {
      return;
    }
    _guard(() => _db!.execute('COMMIT'));
  }

  /// Rolls back the transaction [begin] started. Requires an open transaction ([StateError]).
  void rollback() {
    _requireTransaction('rollback');
    _inTransaction = false;
    _transactionFailed = false;
    if (!isDurable) {
      return;
    }
    _guard(() => _db!.execute('ROLLBACK'));
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
  void close() {
    if (_state == StoreState.closed) {
      return;
    }
    _refreshTimer?.cancel();
    _refreshTimer = null;
    final sqlite.Database? db = _db;
    if (db != null && isDurable) {
      if (_inTransaction) {
        _quietly(() => db.execute('ROLLBACK'));
      }
      _lease!.release(db);
      _quietly(() => db.select('PRAGMA wal_checkpoint(TRUNCATE)'));
    }
    _inTransaction = false;
    _dispose();
    _state = StoreState.closed;
    final void Function()? onClosed = _onClosed;
    _onClosed = null;
    onClosed?.call();
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

  /// Runs [body]; on an [sqlite.SqliteException] stops writing and returns [fallback].
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
    final sqlite.Database db = _db!;
    _quietly(() => db.execute('ROLLBACK'));
    if (next == StoreState.degraded) {
      _wipeQuietly(db);
      _lease!.release(db);
    }
    _dispose();
    _log(
      DatabaseLogLevel.warning,
      'Realtime Database offline cache: $what; this instance keeps data in memory only.',
    );
  }

  /// Empties the data tables if the lease is still ours, so that the next start neither replays
  /// writes whose acknowledgement was never stored nor reads a half-updated cache.
  void _wipeQuietly(sqlite.Database db) {
    try {
      db.execute('BEGIN IMMEDIATE');
      if (_lease!.holdsFence(db)) {
        for (final String table in SqliteSchema.dataTables) {
          db.execute('DELETE FROM $table');
        }
      }
      db.execute('COMMIT');
    } on sqlite.SqliteException {
      _quietly(() => db.execute('ROLLBACK'));
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
