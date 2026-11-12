// File created by
// Lung Razvan <long1eu>
// on 28/09/2018

import 'dart:async';
import 'dart:io';

import 'package:meta/meta.dart';

/// Opens (creating it if needed) the SQLite database called [path] for the
/// offline cache. Pass one to `Firestore.instanceFor(openDatabase: ...)`; this
/// package does not depend on a SQLite binding itself. Without it the cache is
/// kept in memory only.
///
/// [path] is a database name chosen by Firestore (unique per app and
/// database), not a full file path: the opener decides where the file lives.
///
/// The opener must, in this order: call [onConfigure]; if the file is new, call
/// [onCreate] with [version] and store [version] as the schema version
/// (`PRAGMA user_version`); otherwise call [onUpgrade] or [onDowngrade] when the
/// stored version is lower or higher than [version] and then store [version];
/// finally call [onOpen]. The callbacks run Firestore's own schema migrations,
/// so they must be awaited before the returned future completes.
///
/// See `test/util/sqlite3_database.dart` in the package repository for an
/// implementation on top of `package:sqlite3`.
typedef OpenDatabase = Future<Database> Function(String path,
    {int version,
    OnConfigure onConfigure,
    OnCreate onCreate,
    OnVersionChange onUpgrade,
    OnVersionChange onDowngrade,
    OnOpen onOpen});

/// Called by an [OpenDatabase] implementation when the stored schema version
/// differs from the requested one.
typedef OnVersionChange = Future<void> Function(
    Database db, int oldVersion, int newVersion);
/// Called by an [OpenDatabase] implementation when the database file is new.
typedef OnCreate = Future<void> Function(Database db, int version);
/// Called by an [OpenDatabase] implementation once the database is ready.
typedef OnOpen = Future<void> Function(Database db);
/// Called by an [OpenDatabase] implementation first, before any migration.
typedef OnConfigure = Future<void> Function(Database db);

/// A connection to one SQLite database, returned by an [OpenDatabase]
/// function. This is the only part of the SQLite layer that is public: you
/// implement it over the SQLite binding of your choice; Firestore runs its own
/// SQL through it.
///
/// Statements use `?` positional placeholders; [arguments] may contain `null`,
/// [int], [double], [String] and `Uint8List` values.
abstract class Database {
  /// The file backing this database.
  File get file;

  /// Runs SQLite statement without return values
  Future<void> execute(String statement, [List<Object?>? arguments]);

  /// SELECT query
  Future<List<Map<String, dynamic>>> query(String statement,
      [List<Object?>? arguments]);

  /// DELETE query
  /// Returns the number of changes made
  Future<int> delete(String statement, [List<Object?>? arguments]);

  /// Closes the connection. Firestore calls it when the instance terminates.
  void close();
}

/// Not used by the SDK; kept out of the public API.
@internal
enum ConflictAlgorithm {
  /// When a constraint violation occurs, an immediate ROLLBACK occurs, thus ending the current transaction, and the
  /// command aborts with a return code of SQLITE_CONSTRAINT. If no transaction is active (other than the implied
  /// transaction that is created on every command) then this algorithm works the same as ABORT.
  rollback,

  /// When a constraint violation occurs,no ROLLBACK is executed so changes from prior commands within the same
  /// transaction are preserved. This is the default behavior.
  abort,

  /// When a constraint violation occurs, the command aborts with a return code SQLITE_CONSTRAINT. But any changes to
  /// the database that the command made prior to encountering the constraint violation are preserved and are not backed
  /// out.
  fail,

  /// When a constraint violation occurs, the one row that contains the constraint violation is not inserted or changed.
  /// But the command continues executing normally. Other rows before and after the row that contained the constraint
  /// violation continue to be inserted or updated normally. No error is returned.
  ignore,

  /// When a UNIQUE constraint violation occurs, the pre-existing rows that are causing the constraint violation are
  /// removed prior to inserting or updating the current row. Thus the insert or update always occurs. The command
  /// continues executing normally. No error is returned. If a NOT NULL constraint violation occurs, the NULL value is
  /// replaced by the default value for that column. If the column has no default value, then the ABORT algorithm is
  /// used. If a CHECK constraint violation occurs then the IGNORE algorithm is used. When this conflict resolution
  /// strategy deletes rows in order to satisfy a constraint, it does not invoke delete triggers on those rows. This
  /// behavior might change in a future release.
  replace,
}
