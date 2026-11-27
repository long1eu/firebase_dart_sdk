import 'package:sqlite3/sqlite3.dart' as sqlite;

/// The row of the `lease` table: who owns the store file.
final class LeaseRow {
  /// A lease row as stored.
  const LeaseRow({
    required this.ownerId,
    required this.epoch,
    required this.expiresAtMs,
  });

  /// A row whose columns do not have the types this code writes (a damaged or foreign file). It
  /// names no owner, so it is never "ours", and an unchanged one is taken over like a dead owner's.
  const LeaseRow.unreadable() : ownerId = '', epoch = -1, expiresAtMs = -1;

  /// The id of the owning connection: `<process id>:<random hex>`, or
  /// [SqliteLease.clearingOwnerId].
  final String ownerId;

  /// Incremented at every change of owner; the fencing token.
  final int epoch;

  /// The owner's wall-clock time in milliseconds after which it promised to have refreshed. It
  /// changes at every refresh; liveness is decided by watching it change, never by comparing it
  /// with another process's clock (revised after review, 2026-11-22).
  final int expiresAtMs;

  /// Whether [other] is the same row, unchanged.
  bool sameAs(LeaseRow other) =>
      ownerId == other.ownerId &&
      epoch == other.epoch &&
      expiresAtMs == other.expiresAtMs;
}

/// The outcome of [SqliteLease.tryAcquire].
sealed class LeaseAttempt {
  const LeaseAttempt();
}

/// The lease is ours.
final class LeaseAcquired extends LeaseAttempt {
  /// The lease was taken over from an owner that did not release it when
  /// [previousOwnerVanished]; [previousOwnerSameProcess] when that owner had this process id.
  const LeaseAcquired({
    required this.previousOwnerVanished,
    required this.previousOwnerSameProcess,
  });

  /// Whether the previous owner left without releasing the lease (a crash, a hot restart, a
  /// killed process).
  final bool previousOwnerVanished;

  /// Whether that owner ran in this process (a Flutter hot restart): the process did not crash,
  /// so the file needs no consistency check.
  final bool previousOwnerSameProcess;
}

/// Another connection holds the lease, or held it when [observed] was read.
final class LeaseHeld extends LeaseAttempt {
  /// The row as read; pass it back to [SqliteLease.tryAcquire] after a wait.
  const LeaseHeld({required this.observed});

  /// The row seen now: if it is unchanged after [SqliteLease.observation], its owner is gone.
  final LeaseRow observed;
}

/// The file is being deleted by `clearSqlitePersistence`: never take it.
final class LeaseCleared extends LeaseAttempt {
  /// The file carries a live tombstone.
  const LeaseCleared();
}

/// One owner per store file, by lease with fencing (decision D19; design section 4, revised after
/// review, 2026-11-22).
///
/// The owner writes `(owner_id, epoch, expires_at_ms)` into the single row of `lease` and rewrites
/// it at least every [refreshInterval]: from a timer, and inside any storage transaction that runs
/// more than half a refresh interval after the last write ([extendIfDue]). Another connection
/// decides whether the owner is alive by observation: it reads the row, waits [observation] and
/// reads again; an unchanged row means the owner stopped refreshing. No two clocks are compared, so
/// a clock that jumps does not strand a file or hand a live owner's file to someone else.
///
/// Every storage transaction of the owner first checks, inside its own `BEGIN IMMEDIATE`, that the
/// row still names it ([holdsFence]); since SQLite serialises writers, no other connection can take
/// the lease between that check and the commit.
final class SqliteLease {
  /// A lease for the connection [ownerId], reading the time from [nowMs].
  SqliteLease({required this.ownerId, required int Function() nowMs})
    : _nowMs = nowMs;

  /// The expiry an owner writes: now plus this. Only for diagnostics and the tombstone; liveness is
  /// observed, not computed.
  static const Duration duration = Duration(seconds: 15);

  /// The longest gap between two writes of the row by a live owner.
  static const Duration refreshInterval = Duration(seconds: 5);

  /// How late a refresh may be (a slow frame, a GC pause, a throttled timer) and still be seen.
  static const Duration takeOverSlack = Duration(milliseconds: 2500);

  /// How long another connection watches the row before taking it over.
  static const Duration observation = Duration(milliseconds: 7500);

  /// The owner id of the tombstone that `clearSqlitePersistence` writes before deleting the files.
  static const String clearingOwnerId = 'cleared';

  /// How long a tombstone keeps other connections away (by the clearing process's clock). A clear
  /// whose deletion failed leaves the file usable again after this.
  static const Duration tombstoneDuration = Duration(minutes: 1);

  /// The random id of this connection, written into the lease row.
  final String ownerId;

  final int Function() _nowMs;

  int _epoch = 0;
  int _lastWrittenExpiresMs = 0;
  int _lastExtendedAtMs = 0;

  /// `PRAGMA data_version` when this connection last saw the lease as its own. The value changes
  /// only when another connection commits, so while it is unchanged the lease is still ours.
  int? _knownDataVersion;

  /// The epoch of the lease this connection holds, 0 before [tryAcquire] succeeded.
  int get epoch => _epoch;

  /// The process part of an owner id (`<process id>:<random>`), or null.
  static String? processOf(String ownerId) {
    final int colon = ownerId.indexOf(':');
    return colon <= 0 ? null : ownerId.substring(0, colon);
  }

  /// Reads the lease row of [db]: null when there is none or the table does not exist, and
  /// [LeaseRow.unreadable] when its columns have other types. Throws the [sqlite.SqliteException]
  /// of an unreadable file.
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
    final Object? owner = row['owner_id'];
    final Object? epoch = row['epoch'];
    final Object? expires = row['expires_at_ms'];
    if (owner is! String || epoch is! int || expires is! int) {
      return const LeaseRow.unreadable();
    }
    return LeaseRow(ownerId: owner, epoch: epoch, expiresAtMs: expires);
  }

  /// Whether a live connection holds [db]: the row changes within [observation] (waited with
  /// [delay]), or it is a tombstone that has not expired at [nowMs]. False when there is no row or
  /// it can not be read.
  static Future<bool> isHeldByLiveOwner(
    sqlite.Database db, {
    required int Function() nowMs,
    required Future<void> Function(Duration duration) delay,
  }) async {
    try {
      final LeaseRow? first = read(db);
      if (first == null) {
        return false;
      }
      if (_isLiveTombstone(first, nowMs())) {
        return true;
      }
      await delay(observation);
      final LeaseRow? second = read(db);
      return second != null && !second.sameAs(first);
    } on sqlite.SqliteException {
      return false;
    }
  }

  /// Takes the lease, in a transaction of its own, when there is no row, the row is ours, or the
  /// row is still [observed] (read [observation] ago: its owner stopped refreshing).
  ///
  /// The schema must exist. Throws the [sqlite.SqliteException] of a failed statement after rolling
  /// back; the opener turns that into a memory-only store.
  LeaseAttempt tryAcquire(sqlite.Database db, {LeaseRow? observed}) {
    db.execute('BEGIN IMMEDIATE');
    try {
      final int now = _nowMs();
      final LeaseRow? current = read(db);
      if (current != null && _isLiveTombstone(current, now)) {
        db.execute('COMMIT');
        return const LeaseCleared();
      }
      final bool free =
          current == null ||
          current.ownerId == ownerId ||
          (observed != null && current.sameAs(observed));
      if (!free) {
        db.execute('COMMIT');
        return LeaseHeld(observed: current);
      }
      final int epoch = (current == null || current.epoch < 0)
          ? 1
          : current.epoch + 1;
      final int expires = now + duration.inMilliseconds;
      db.execute(
        'INSERT OR REPLACE INTO lease (id, owner_id, epoch, expires_at_ms) VALUES (0, ?, ?, ?)',
        <Object?>[ownerId, epoch, expires],
      );
      db.execute('COMMIT');
      _epoch = epoch;
      _lastWrittenExpiresMs = expires;
      _lastExtendedAtMs = now;
      _knownDataVersion = _dataVersion(db);
      final bool vanished = current != null && current.ownerId != ownerId;
      final String? previousProcess = current == null
          ? null
          : processOf(current.ownerId);
      return LeaseAcquired(
        previousOwnerVanished: vanished,
        previousOwnerSameProcess:
            vanished &&
            previousProcess != null &&
            previousProcess == processOf(ownerId),
      );
    } catch (_) {
      _rollbackQuietly(db);
      rethrow;
    }
  }

  /// Whether the lease is still ours. Must run inside the caller's `BEGIN IMMEDIATE`, before any
  /// other statement of the transaction, so that the check and the work commit together. A row
  /// that does not read as this code writes it is not ours.
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

  /// Rewrites the row so that observers see a live owner. Must run inside a transaction that passed
  /// [holdsFence]. The written value always differs from the previous one, also when the clock
  /// stands still or goes back.
  void extend(sqlite.Database db) {
    final int now = _nowMs();
    int expires = now + duration.inMilliseconds;
    if (expires <= _lastWrittenExpiresMs) {
      expires = _lastWrittenExpiresMs + 1;
    }
    db.execute(
      'UPDATE lease SET expires_at_ms = ? WHERE id = 0 AND owner_id = ? AND epoch = ?',
      <Object?>[expires, ownerId, _epoch],
    );
    _lastWrittenExpiresMs = expires;
    _lastExtendedAtMs = now;
  }

  /// [extend] when more than half a [refreshInterval] passed since the last write of the row, so
  /// that an owner busy in storage transactions keeps its lease even when its timer is late.
  ///
  /// Returns whether the row was rewritten.
  bool extendIfDue(sqlite.Database db) {
    final int sinceLast = _nowMs() - _lastExtendedAtMs;
    if (sinceLast < 0 || sinceLast >= refreshInterval.inMilliseconds ~/ 2) {
      extend(db);
      return true;
    }
    return false;
  }

  /// Removes the row if it is still ours, in a transaction of its own; best effort.
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

  /// Writes the tombstone of `clearSqlitePersistence` if the row is still [observed] (or absent),
  /// in a transaction of its own. Returns false when a live owner wrote the row in the meantime.
  static bool writeTombstone(
    sqlite.Database db, {
    required LeaseRow? observed,
    required int nowMs,
  }) {
    db.execute('BEGIN IMMEDIATE');
    try {
      final LeaseRow? current = read(db);
      final bool unchanged =
          current == null || (observed != null && current.sameAs(observed));
      if (unchanged) {
        final int epoch = current == null || current.epoch < 0
            ? 1
            : current.epoch + 1;
        db.execute(
          'INSERT OR REPLACE INTO lease (id, owner_id, epoch, expires_at_ms) VALUES (0, ?, ?, ?)',
          <Object?>[
            clearingOwnerId,
            epoch,
            nowMs + tombstoneDuration.inMilliseconds,
          ],
        );
      }
      db.execute('COMMIT');
      return unchanged;
    } catch (_) {
      _rollbackQuietly(db);
      rethrow;
    }
  }

  /// Deletes the lease row when it is still [tombstone] (written by [writeTombstone]), in a
  /// transaction of its own. Throws the [sqlite.SqliteException] of a failed statement after
  /// rolling back.
  static void removeTombstone(sqlite.Database db, LeaseRow tombstone) {
    db.execute('BEGIN IMMEDIATE');
    try {
      db.execute(
        'DELETE FROM lease WHERE id = 0 AND owner_id = ? AND epoch = ? AND expires_at_ms = ?',
        <Object?>[tombstone.ownerId, tombstone.epoch, tombstone.expiresAtMs],
      );
      db.execute('COMMIT');
    } catch (_) {
      _rollbackQuietly(db);
      rethrow;
    }
  }

  static bool _isLiveTombstone(LeaseRow row, int nowMs) =>
      row.ownerId == clearingOwnerId && row.expiresAtMs >= nowMs;

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
