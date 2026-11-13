// The browser counterpart of sqlite3_database.dart: the same [DatabaseMock]
// on top of the WebAssembly build of the `sqlite3` package, so that the unit
// tests of the SQLite layer can run in a browser:
//
//   dart test -p chrome -c dart2js test/unit/firebase/firestore/local/sqlite_query_cache_test.dart
//
// The databases live in one in-memory file system of the page (the tests check
// SQL, not storage). It needs test/browser/sqlite3.wasm, see
// test/browser/web_persistence_test.dart.

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/util/database.dart';
import 'package:sqlite3/wasm.dart' as sql;

/// What `DatabaseMock.pathForName` returns here: there is no file.
class DatabaseFile {
  const DatabaseFile(this.path);

  final String path;

  bool existsSync() => DatabaseMock._files.xAccess(path, 0) != 0;
}

class DatabaseMock extends Database {
  DatabaseMock._(this.database, this.file);

  final sql.CommonDatabase database;
  final DatabaseFile file;

  /// Whether the database is deleted when [close] is called, so the next open
  /// of the same name starts from a fresh one.
  bool renamePath = true;

  static final sql.InMemoryFileSystem _files = sql.InMemoryFileSystem();
  static Future<sql.WasmSqlite3>? _sqlite3;

  /// `<package root>/test/browser/sqlite3.wasm`, from the URL of the test page
  /// (which is somewhere below `<package root>/test/`).
  static Uri get _wasmUrl {
    final String base = Uri.base.toString();
    final int test = base.indexOf('/test/');
    if (test < 0) {
      throw StateError('Cannot find the package root in $base');
    }
    return Uri.parse('${base.substring(0, test)}/test/browser/sqlite3.wasm');
  }

  static Future<sql.WasmSqlite3> _load() {
    return _sqlite3 ??= () async {
      final sql.WasmSqlite3 sqlite3 = await sql.WasmSqlite3.loadFromUrl(
        _wasmUrl,
      );
      sqlite3.registerVirtualFileSystem(_files, makeDefault: true);
      return sqlite3;
    }();
  }

  static DatabaseFile pathForName(String name) => DatabaseFile('/$name');

  /// Deletes the database for [name] and its journal.
  static void deleteDatabaseFiles(String name) {
    final String base = pathForName(name).path;
    for (final String suffix in <String>['', '-journal', '-wal', '-shm']) {
      if (_files.xAccess('$base$suffix', 0) != 0) {
        _files.xDelete('$base$suffix', 0);
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
    final sql.WasmSqlite3 sqlite3 = await _load();

    final DatabaseFile file = pathForName(name);
    final bool callOnCreate = !file.existsSync();
    final sql.CommonDatabase database = sqlite3.open(file.path);
    final DatabaseMock mock = DatabaseMock._(database, file);

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
  Future<List<Map<String, dynamic>>> query(
    String statement, [
    List<Object?>? arguments,
  ]) async {
    final sql.ResultSet result = database.select(
      statement,
      arguments ?? const <Object?>[],
    );
    return result.map(Map<String, dynamic>.of).toList();
  }

  @override
  void close() {
    database.dispose();
    if (renamePath) {
      deleteDatabaseFiles(file.path.substring(1));
    }
  }

  @override
  String get path => file.path;
}
