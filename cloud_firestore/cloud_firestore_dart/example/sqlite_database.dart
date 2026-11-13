// A complete `OpenDatabase` for cloud_firestore_dart on top of package:sqlite3.
//
// cloud_firestore_dart does not depend on a SQLite binding: to keep the
// offline cache on disk you pass it a function that opens a database. Copy
// this file into your app, add `sqlite3` to your dependencies (and, in a
// Flutter app, `sqlite3_flutter_libs` so that the native library is bundled),
// and pass `sqliteOpener(directory)` to `Firestore.instanceFor`. See
// offline_persistence.dart for the usage.

import 'dart:ffi';
import 'dart:io';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Returns an [OpenDatabase] that keeps the database files in [directory].
///
/// In a Flutter app use a directory from `path_provider`, for example
/// `getApplicationSupportDirectory()`.
OpenDatabase sqliteOpener(Directory directory) {
  // Before the first use of `sqlite3` in this isolate.
  open.overrideFor(OperatingSystem.linux, openLinuxSqlite);
  return (
    String name, {
    int? version,
    OnConfigure? onConfigure,
    OnCreate? onCreate,
    OnVersionChange? onUpgrade,
    OnVersionChange? onDowngrade,
    OnOpen? onOpen,
  }) async {
    // Firestore passes a name that is unique per app and database, not a full
    // path. Where the file lives is up to the opener.
    final File file = File('${directory.path}/$name.db');
    final bool isNew = !file.existsSync();
    file.parent.createSync(recursive: true);

    final SqliteDatabase db = SqliteDatabase._(
      sqlite.sqlite3.open(file.path),
      file.path,
    );
    try {
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

/// Opens the system SQLite library on Linux.
///
/// `package:sqlite3` 2.x opens `libsqlite3.so`, which only the development
/// package installs (`libsqlite3-dev` on Debian and Ubuntu). A machine with
/// just the runtime package (`libsqlite3-0`) has `libsqlite3.so.0`, so that
/// name is tried next. On Windows `sqlite3.dll` must be next to the
/// executable or on the `PATH`.
DynamicLibrary openLinuxSqlite() {
  try {
    return DynamicLibrary.open('libsqlite3.so');
  } on ArgumentError {
    return DynamicLibrary.open('libsqlite3.so.0');
  }
}

/// One open SQLite connection. Firestore runs its own SQL through it.
class SqliteDatabase implements Database {
  SqliteDatabase._(this._database, this.path);

  final sqlite.Database _database;

  /// The path of the database file. `Firestore.clearPersistence` deletes this
  /// file (and its `-journal`, `-wal` and `-shm` side files).
  @override
  final String path;

  @override
  Future<void> execute(String statement, [List<Object?>? arguments]) async {
    _database.execute(statement, arguments ?? const <Object?>[]);
  }

  @override
  Future<List<Map<String, dynamic>>> query(
    String statement, [
    List<Object?>? arguments,
  ]) async {
    final sqlite.ResultSet rows = _database.select(
      statement,
      arguments ?? const <Object?>[],
    );
    return <Map<String, dynamic>>[
      for (final sqlite.Row row in rows) Map<String, dynamic>.of(row),
    ];
  }

  /// Runs a DELETE and returns the number of rows it removed.
  @override
  Future<int> delete(String statement, [List<Object?>? arguments]) async {
    _database.execute(statement, arguments ?? const <Object?>[]);
    return _database.updatedRows;
  }

  @override
  void close() => _database.dispose();
}
