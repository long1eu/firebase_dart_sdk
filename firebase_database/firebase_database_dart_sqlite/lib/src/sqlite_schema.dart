import 'package:sqlite3/sqlite3.dart' as sqlite;

/// The tables of a store file and how its version is numbered.
///
/// `PRAGMA user_version` is `major * 1000 + minor`. A reader opens any file of its own major and
/// treats a higher major as written by a newer version. `PRAGMA application_id` marks the file as a
/// Realtime Database store. Design: `rtdb_storage_engine_design.md` sections 2, 8 and 13a.
///
/// What a minor may change, so that an older reader of the same major keeps working: add tables,
/// indexes, and columns that are nullable or have a `DEFAULT` (created with `IF NOT EXISTS` or
/// `ADD COLUMN`). A minor must never add a `NOT NULL` column without a default, a `CHECK` or a
/// unique index that older `INSERT`s can violate, or change the meaning of an existing column:
/// older code would fail its writes (revised after review, 2026-11-22). Anything else is a new
/// major.
abstract final class SqliteSchema {
  /// `PRAGMA application_id` of a store file: 0x52544442, `RTDB` in ASCII.
  static const int applicationId = 0x52544442;

  /// The major version this code writes and reads.
  static const int major = 1;

  /// The minor version this code writes.
  static const int minor = 0;

  /// `PRAGMA user_version` of a file written by this code.
  static const int userVersion = major * 1000 + minor;

  /// The major version of a stored [version] (`PRAGMA user_version`).
  static int majorOf(int version) => version ~/ 1000;

  /// Every table and index of the schema, created with `IF NOT EXISTS`.
  static const List<String> createStatements = <String>[
    'CREATE TABLE IF NOT EXISTS lease ('
        'id INTEGER PRIMARY KEY CHECK (id = 0), '
        'owner_id TEXT NOT NULL, '
        'epoch INTEGER NOT NULL, '
        'expires_at_ms INTEGER NOT NULL)',
    'CREATE TABLE IF NOT EXISTS server_cache ('
        'path TEXT NOT NULL PRIMARY KEY, '
        'value BLOB NOT NULL) WITHOUT ROWID',
    'CREATE TABLE IF NOT EXISTS user_writes ('
        'id INTEGER PRIMARY KEY, '
        'path TEXT NOT NULL, '
        "type TEXT NOT NULL CHECK (type IN ('o', 'm')), "
        'value BLOB NOT NULL)',
    'CREATE TABLE IF NOT EXISTS tracked_queries ('
        'id INTEGER PRIMARY KEY, '
        'path TEXT NOT NULL, '
        'query_params TEXT NOT NULL, '
        'last_use_ms INTEGER NOT NULL, '
        'complete INTEGER NOT NULL, '
        'active INTEGER NOT NULL)',
    'CREATE TABLE IF NOT EXISTS tracked_keys ('
        'query_id INTEGER NOT NULL, '
        'key TEXT NOT NULL, '
        'PRIMARY KEY (query_id, key)) WITHOUT ROWID',
    // One id per query, as the reference engine of the client checks.
    'CREATE UNIQUE INDEX IF NOT EXISTS tracked_queries_by_query '
        'ON tracked_queries (path, query_params)',
  ];

  /// Sets the file-level settings of a new, empty file. `auto_vacuum` only takes effect before the
  /// first table is created, so this runs before [ensureTables].
  static void prepareNewFile(sqlite.Database db) {
    db.execute('PRAGMA auto_vacuum = INCREMENTAL');
  }

  /// Creates the missing tables and brings `application_id` and `user_version` up to this code.
  ///
  /// Runs in an exclusive transaction and reads the stored version inside it, so two clients that
  /// open a file at the same moment do not both migrate it. A higher minor of the same major is
  /// kept.
  static void ensureTables(sqlite.Database db) {
    db.execute('BEGIN EXCLUSIVE');
    try {
      final int stored = db.userVersion;
      for (final String statement in createStatements) {
        db.execute(statement);
      }
      db.execute('PRAGMA application_id = $applicationId');
      if (stored < userVersion) {
        db.userVersion = userVersion;
      }
      db.execute('COMMIT');
    } catch (_) {
      _rollbackQuietly(db);
      rethrow;
    }
  }

  static void _rollbackQuietly(sqlite.Database db) {
    try {
      db.execute('ROLLBACK');
    } on sqlite.SqliteException {
      // The transaction is already gone; the original error is rethrown by the caller.
    }
  }
}
