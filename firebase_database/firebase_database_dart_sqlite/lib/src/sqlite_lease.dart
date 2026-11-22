import 'package:sqlite3/sqlite3.dart' as sqlite;

/// The row of the `lease` table: who owns the store file and until when.
final class LeaseRow {
  /// A lease row as stored.
  const LeaseRow({
    required this.ownerId,
    required this.epoch,
    required this.expiresAtMs,
  });

  /// The random id of the owning connection.
  final String ownerId;

  /// Incremented at every change of owner; the fencing token.
  final int epoch;

  /// Wall-clock time in milliseconds since the epoch after which the lease is free.
  final int expiresAtMs;

  /// Whether the lease is still held at [nowMs].
  bool isLiveAt(int nowMs) => expiresAtMs >= nowMs;
}

/// The outcome of [SqliteLease.tryAcquire].
sealed class LeaseAttempt {
  const LeaseAttempt();
}

/// The lease is ours.
final class LeaseAcquired extends LeaseAttempt {
  /// The lease was taken; [previousOwnerVanished] when an expired row of another owner was found.
  const LeaseAcquired({required this.previousOwnerVanished});

  /// Whether the previous owner left without releasing the lease (a crash, a hot restart, a
  /// killed process): the file may need a consistency check.
  final bool previousOwnerVanished;
}

/// Another connection holds the lease.
final class LeaseHeld extends LeaseAttempt {
  /// The lease is held until [expiresAtMs].
  const LeaseHeld({required this.expiresAtMs});

  /// When the current lease expires unless its owner refreshes it.
  final int expiresAtMs;
}

/// One owner per store file, by lease with fencing (decision D19; design section 4).
///
/// The owner writes `(owner_id, epoch, expires_at_ms)` into the single row of `lease` and refreshes
/// it every [refreshInterval]; it is valid for [duration]. Every storage transaction of the owner
/// first checks, inside its own `BEGIN IMMEDIATE`, that the row still names it ([holdsFence]);
/// since SQLite serialises writers, no other connection can take the lease between that check and
/// the commit. The times are wall-clock milliseconds, the only clock that processes share; the
/// clock is injected.
final class SqliteLease {
  /// A lease for the connection [ownerId], reading the time from [nowMs].
  SqliteLease({required this.ownerId, required int Function() nowMs})
    : _nowMs = nowMs;

  /// How long a lease is valid without a refresh (Firestore's `maxPrimaryEligibleAgeMs`).
  static const Duration duration = Duration(seconds: 5);

  /// How often the owner refreshes its lease (Firestore's client metadata refresh).
  static const Duration refreshInterval = Duration(seconds: 4);

  /// Added to the wait for a held lease, so that a late refresh of a live owner is seen.
  static const Duration takeOverSlack = Duration(milliseconds: 250);

  /// The random id of this connection, written into the lease row.
  final String ownerId;

  final int Function() _nowMs;

  int _epoch = 0;

  /// `PRAGMA data_version` when this connection last saw the lease as its own. The value changes
  /// only when another connection commits, so while it is unchanged the lease is still ours.
  int? _knownDataVersion;

  /// The epoch of the lease this connection holds, 0 before [tryAcquire] succeeded.
  int get epoch => _epoch;

  /// Reads the lease row of [db], or null when there is none or the table does not exist.
  static LeaseRow? read(sqlite.Database db) {
    final sqlite.ResultSet tables = db.select(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'lease'",
    );
    if (tables.isEmpty) {
      return null;
    }
    final sqlite.ResultSet rows = db.select(
      'SELECT owner_id, epoch, expires_at_ms FROM lease WHERE id = 0',
    );
    if (rows.isEmpty) {
      return null;
    }
    final sqlite.Row row = rows.first;
    return LeaseRow(
      ownerId: row['owner_id'] as String,
      epoch: row['epoch'] as int,
      expiresAtMs: row['expires_at_ms'] as int,
    );
  }

  /// Whether another connection holds a live lease on [db]. False when the row can not be read.
  static bool isHeldByLiveOwner(sqlite.Database db, int nowMs) {
    try {
      return read(db)?.isLiveAt(nowMs) ?? false;
    } on sqlite.SqliteException {
      return false;
    }
  }

  /// Takes the lease when it is free or expired, in a transaction of its own.
  ///
  /// The schema must exist. Throws the [sqlite.SqliteException] of a failed statement after rolling
  /// back; the opener turns that into a memory-only store.
  LeaseAttempt tryAcquire(sqlite.Database db) {
    db.execute('BEGIN IMMEDIATE');
    try {
      final int now = _nowMs();
      final LeaseRow? current = read(db);
      if (current != null &&
          current.ownerId != ownerId &&
          current.isLiveAt(now)) {
        db.execute('COMMIT');
        return LeaseHeld(expiresAtMs: current.expiresAtMs);
      }
      final int epoch = (current?.epoch ?? 0) + 1;
      db.execute(
        'INSERT OR REPLACE INTO lease (id, owner_id, epoch, expires_at_ms) VALUES (0, ?, ?, ?)',
        <Object?>[ownerId, epoch, now + duration.inMilliseconds],
      );
      db.execute('COMMIT');
      _epoch = epoch;
      _knownDataVersion = _dataVersion(db);
      return LeaseAcquired(
        previousOwnerVanished: current != null && current.ownerId != ownerId,
      );
    } catch (_) {
      _rollbackQuietly(db);
      rethrow;
    }
  }

  /// Whether the lease is still ours. Must run inside the caller's `BEGIN IMMEDIATE`, before any
  /// other statement of the transaction, so that the check and the work commit together.
  bool holdsFence(sqlite.Database db) {
    final int version = _dataVersion(db);
    if (version == _knownDataVersion) {
      return true;
    }
    final LeaseRow? row = read(db);
    final bool ours =
        row != null && row.ownerId == ownerId && row.epoch == _epoch;
    if (ours) {
      _knownDataVersion = version;
    }
    return ours;
  }

  /// Moves the expiry to now plus [duration]. Must run inside a transaction that passed
  /// [holdsFence]. A lease that expired while nobody took it is renewed the same way.
  void extend(sqlite.Database db) {
    db.execute(
      'UPDATE lease SET expires_at_ms = ? WHERE id = 0 AND owner_id = ? AND epoch = ?',
      <Object?>[_nowMs() + duration.inMilliseconds, ownerId, _epoch],
    );
  }

  /// Removes the lease row if it is still ours, in a transaction of its own; best effort.
  void release(sqlite.Database db) {
    try {
      db.execute('BEGIN IMMEDIATE');
      db.execute(
        'DELETE FROM lease WHERE id = 0 AND owner_id = ? AND epoch = ?',
        <Object?>[ownerId, _epoch],
      );
      db.execute('COMMIT');
    } on sqlite.SqliteException {
      _rollbackQuietly(db);
    }
  }

  static int _dataVersion(sqlite.Database db) {
    return db.select('PRAGMA data_version').first.columnAt(0) as int;
  }

  static void _rollbackQuietly(sqlite.Database db) {
    try {
      db.execute('ROLLBACK');
    } on sqlite.SqliteException {
      // No transaction was open.
    }
  }
}
