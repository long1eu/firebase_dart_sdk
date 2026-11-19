// The `OpenDatabase` of cloud_firestore_dart on the Dart VM and in Flutter, on
// top of package:sqlite3. Moved from example/sqlite_database.dart of
// cloud_firestore_dart 0.1.1; the differences are listed in the CHANGELOG.

import 'dart:io';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Returns an [OpenDatabase] that keeps the database files in [directory].
///
/// [pageCacheMb] sets SQLite's page cache of the connection
/// (`PRAGMA cache_size`); SQLite's default is 2 MB. The cache is filled as
/// pages are read, up to that size, once per open cache. It mostly matters
/// when the operating system can't keep the database file in its own file
/// cache (a large cache on a device short of memory).
///
/// Which SQLite library is loaded is up to package:sqlite3: with 3.x the one
/// its build hook bundles, with 2.x its default lookup (see the README).
OpenDatabase nativeSqliteOpener(String directory, {int? pageCacheMb}) {
  return (
    String name, {
    int? version,
    OnConfigure? onConfigure,
    OnCreate? onCreate,
    OnVersionChange? onUpgrade,
    OnVersionChange? onDowngrade,
    OnOpen? onOpen,
  }) async {
    // FirebaseFirestore passes a name that is unique per app and database, not a full
    // path. Where the file lives is up to the opener.
    final File file = File('$directory/$name.db');
    final bool isNew = !file.existsSync();
    file.parent.createSync(recursive: true);

    final SqliteDatabase db = SqliteDatabase._(
      sqlite.sqlite3.open(file.path),
      file.path,
    );
    try {
      if (pageCacheMb != null) {
        // A negative value is a size in KiB, a positive one a number of pages.
        db._database.execute('PRAGMA cache_size = -${pageCacheMb * 1024}');
      }
      // The callbacks run Firestore's schema setup and migrations. They must
      // be called in this order and awaited before the database is returned.
      await onConfigure?.call(db);

      final int wanted = version ?? 1;
      if (isNew) {
        await onCreate?.call(db, wanted);
      } else {
        final int current = db._database.userVersion;
        if (current < wanted) {
          await onUpgrade?.call(db, current, wanted);
        } else if (current > wanted) {
          await onDowngrade?.call(db, current, wanted);
        }
      }
      // The schema version is kept in `PRAGMA user_version`.
      db._database.userVersion = wanted;

      await onOpen?.call(db);
      return db;
    } catch (_) {
      db.close();
      rethrow;
    }
  };
}

/// One open SQLite connection on the Dart VM. FirebaseFirestore runs its own SQL
/// through it.
class SqliteDatabase implements Database {
  SqliteDatabase._(this._database, this.path);

  final sqlite.Database _database;

  /// The prepared statements of the last [_statementCacheSize] distinct queries, least recently used first. Preparing
  /// a statement is about 40 % of the SQLite time of a read of one document by key; Firestore runs the same few
  /// statements again and again. Finalized on [close].
  final Map<String, sqlite.PreparedStatement> _statements =
      <String, sqlite.PreparedStatement>{};
  static const int _statementCacheSize = 64;

  /// The path of the database file. `FirebaseFirestore.clearPersistence` deletes this
  /// file (and its `-journal`, `-wal` and `-shm` side files).
  @override
  final String path;

  @override
  Future<void> execute(String statement, [List<Object?>? arguments]) async {
    _run(() => _database.execute(statement, arguments ?? const <Object?>[]));
  }

  @override
  Future<List<Map<String, dynamic>>> query(
    String statement, [
    List<Object?>? arguments,
  ]) async {
    final sqlite.ResultSet rows = _run(
      () => _select(statement, arguments ?? const <Object?>[]),
    );
    return <Map<String, dynamic>>[
      for (final sqlite.Row row in rows) Map<String, dynamic>.of(row),
    ];
  }

  sqlite.ResultSet _select(String sql, List<Object?> arguments) {
    sqlite.PreparedStatement? statement = _statements.remove(sql);
    // `checkNoTail` as `Database.select` of sqlite3 3.x.
    statement ??= _database.prepare(sql, persistent: true, checkNoTail: true);
    try {
      final sqlite.ResultSet rows = statement.select(arguments);
      // Most recently used last.
      _statements[sql] = statement;
      if (_statements.length > _statementCacheSize) {
        final String oldest = _statements.keys.first;
        // ignore: deprecated_member_use
        _statements.remove(oldest)!.dispose();
      }
      return rows;
    } catch (_) {
      // Not kept after an error, so that a statement is never reused in an unknown state.
      // ignore: deprecated_member_use
      statement.dispose();
      rethrow;
    }
  }

  /// Runs a DELETE and returns the number of rows it removed.
  @override
  Future<int> delete(String statement, [List<Object?>? arguments]) async {
    _run(() => _database.execute(statement, arguments ?? const <Object?>[]));
    return _database.updatedRows;
  }

  /// Reports the errors that may go away on their own as a
  /// [TransientDatabaseException]: another connection holds the lock (also
  /// after Firestore's busy timeout), an I/O error, a full disk. SQLite does
  /// not keep a statement or a transaction that failed with one of these
  /// (FirebaseFirestore rolls the transaction back), so FirebaseFirestore can go offline and
  /// try again later. Every other error is fatal for the operation.
  static T _run<T>(T Function() statement) {
    try {
      return statement();
    } on sqlite.SqliteException catch (e) {
      switch (e.resultCode) {
        case sqlite.SqlError.SQLITE_BUSY:
        case sqlite.SqlError.SQLITE_LOCKED:
        case sqlite.SqlError.SQLITE_IOERR:
        case sqlite.SqlError.SQLITE_FULL:
          throw TransientDatabaseException(e.message, e);
        default:
          rethrow;
      }
    }
  }

  // `dispose()` is the only way to close a database or a statement in sqlite3
  // 2.x; 3.x adds `close()` and deprecates `dispose()`, which still works
  // there.
  @override
  void close() {
    for (final sqlite.PreparedStatement statement in _statements.values) {
      // ignore: deprecated_member_use
      statement.dispose();
    }
    _statements.clear();
    // ignore: deprecated_member_use
    _database.dispose();
  }
}
