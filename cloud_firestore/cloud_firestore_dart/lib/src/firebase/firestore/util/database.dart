// File created by
// Lung Razvan <long1eu>
// on 28/09/2018

import 'dart:async';

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
/// The callbacks may be called inside a transaction of the opener. Outside of
/// one, Firestore runs the migration in a transaction of its own
/// (`BEGIN EXCLUSIVE`), reads `PRAGMA user_version` in it and migrates from the
/// version it finds there: another client may have migrated the same file
/// since the opener looked.
///
/// See `example/sqlite_database.dart` in this package for a complete
/// implementation on top of `package:sqlite3`.
typedef OpenDatabase =
    Future<Database> Function(
      String path, {
      int version,
      OnConfigure onConfigure,
      OnCreate onCreate,
      OnVersionChange onUpgrade,
      OnVersionChange onDowngrade,
      OnOpen onOpen,
    });

/// Called by an [OpenDatabase] implementation when the stored schema version
/// differs from the requested one.
typedef OnVersionChange =
    Future<void> Function(Database db, int oldVersion, int newVersion);

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
/// Statements use `?` positional placeholders; `arguments` may contain `null`,
/// [int], [double], [String] and `Uint8List` values.
abstract class Database {
  /// The path (or, where there is no file system, the name) this database was
  /// opened with.
  String get path;

  /// Runs SQLite statement without return values
  Future<void> execute(String statement, [List<Object?>? arguments]);

  /// SELECT query
  Future<List<Map<String, dynamic>>> query(
    String statement, [
    List<Object?>? arguments,
  ]);

  /// DELETE query
  /// Returns the number of changes made
  Future<int> delete(String statement, [List<Object?>? arguments]);

  /// Closes the connection. Firestore calls it when the instance terminates.
  void close();
}

/// Thrown by a [Database] when a statement failed for a reason that may go
/// away on its own, and nothing of the failed statement (nor of the
/// transaction it belongs to) was stored: the database was busy or locked, an
/// I/O error occurred, the disk was full, or the storage behind the database
/// is not reachable right now.
///
/// Firestore treats it as the JS SDK treats a failed IndexedDB transaction:
/// the listen or write that needed the database fails with
/// `FirestoreErrorCode.unavailable`, an acknowledgement from the backend is
/// kept and stored again later, and the client goes offline and tries the
/// database again with a backoff until it works. Any other error of a
/// [Database] is fatal for the operation that ran into it.
///
/// Throw it only when the transaction did not take effect: Firestore runs the
/// operation again, and a transaction that was in fact stored would then be
/// applied twice. The openers in `example/` show which SQLite errors
/// qualify.
class TransientDatabaseException implements Exception {
  /// Creates the exception. [cause] is the error of the SQLite binding, if
  /// any.
  TransientDatabaseException(this.message, [this.cause]);

  /// What failed.
  final String message;

  /// The original error, if any.
  final Object? cause;

  @override
  String toString() =>
      'TransientDatabaseException: $message${cause == null ? '' : ' ($cause)'}';
}

/// A [Database] that deletes its own storage for `Firestore.clearPersistence`.
///
/// By default `clearPersistence` deletes the file at [Database.path] and
/// SQLite's side files next to it, which is all a database in a file system
/// needs. Implement this interface when the database is kept somewhere else,
/// for example in IndexedDB in a browser: `clearPersistence` then calls
/// [clearStorage] instead and deletes no file.
abstract interface class ClearableDatabase implements Database {
  /// Deletes everything this database stored. Called after [close], at most
  /// once; the database is not used afterwards. An error fails
  /// `clearPersistence` with `FirestoreErrorCode.unknown`.
  Future<void> clearStorage();
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
