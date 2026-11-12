import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore_vm/src/firebase/firestore/util/database.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// A file backed [Database] implemented on top of the `sqlite3` package. Used
/// by the tests that need a real SQLite database.
///
/// [DatabaseMock.create] has the signature of [OpenDatabase], so it can be
/// passed wherever an [OpenDatabase] is expected.
class DatabaseMock extends Database {
  DatabaseMock._(this.database, this.path);

  final sql.Database database;
  final File path;

  /// Whether the database file is renamed when [close] is called, so the next
  /// open of the same name starts from a fresh file.
  bool renamePath = true;

  static File pathForName(String name) {
    return File('${Directory.current.path}/build/test/$name');
  }

  /// Deletes the database file for [name] (as resolved by [pathForName]) and
  /// its journal, WAL and shared memory side files.
  static void deleteDatabaseFiles(String name) {
    final String base = pathForName(name).path;
    for (final String suffix in <String>['', '-journal', '-wal', '-shm']) {
      final File file = File('$base$suffix');
      if (file.existsSync()) {
        file.deleteSync();
      }
    }
  }

  static Future<DatabaseMock> create(
    String name, {
    int? version,
    OnConfigure? onConfigure,
    OnCreate? onCreate,
    OnVersionChange? onUpgrade,
    OnVersionChange? onDowngrade,
    OnOpen? onOpen,
  }) async {
    final int targetVersion = version ?? 1;

    final File path = pathForName(name);
    final bool callOnCreate = !path.existsSync();
    path.createSync(recursive: true);

    final sql.Database database = sql.sqlite3.open(path.path);
    final DatabaseMock mock = DatabaseMock._(database, path);

    await onConfigure?.call(mock);
    if (callOnCreate) {
      await onCreate?.call(mock, targetVersion);
      database.userVersion = targetVersion;
    } else {
      final int currentVersion = database.userVersion;
      if (currentVersion < targetVersion) {
        await onUpgrade?.call(mock, currentVersion, targetVersion);
        database.userVersion = targetVersion;
      }

      if (currentVersion > targetVersion) {
        database.userVersion = targetVersion;
        await onDowngrade?.call(mock, currentVersion, targetVersion);
      }
    }

    await onOpen?.call(mock);
    return mock;
  }

  @override
  Future<int> delete(String statement, [List<Object?>? arguments]) async {
    database.execute(statement, arguments ?? const <Object?>[]);
    return database.updatedRows;
  }

  @override
  Future<void> execute(String statement, [List<Object?>? arguments]) async {
    database.execute(statement, arguments ?? const <Object?>[]);
  }

  @override
  Future<List<Map<String, dynamic>>> query(String statement,
      [List<Object?>? arguments]) async {
    final sql.ResultSet result =
        database.select(statement, arguments ?? const <Object?>[]);
    return result.map(Map<String, dynamic>.of).toList();
  }

  @override
  void close() {
    database.dispose();
    if (renamePath) {
      path.renameSync('${path.path}_');
    }
  }

  @override
  File get file => path;
}
