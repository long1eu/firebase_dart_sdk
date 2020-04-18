// File created by
// Lung Razvan <long1eu>
// on 29/09/2018

import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore_vm/cloud_firestore_vm.dart' as dart;
import 'package:moor_ffi/database.dart' as sql;
import 'package:sqflite/sqflite.dart' as sql show getDatabasesPath;

class Database extends dart.Database {
  Database._(this._database, this._path);

  final sql.Database _database;
  final File _path;

  static Future<Database> create(
    String name, {
    int version,
    dart.OnConfigure onConfigure,
    dart.OnCreate onCreate,
    dart.OnVersionChange onUpgrade,
    dart.OnVersionChange onDowngrade,
    dart.OnOpen onOpen,
  }) async {
    version ??= 1;

    final String dir = await sql.getDatabasesPath();
    final File path = File('$dir/$name');
    final bool callOnCreate = !path.existsSync();
    path.createSync(recursive: true);

    final sql.Database database = sql.Database.openFile(path);
    final Database mock = Database._(database, path);

    await onConfigure?.call(mock);
    if (callOnCreate) {
      await onCreate?.call(mock, version);
      database.setUserVersion(version);
    } else {
      final int currentVersion = database.userVersion();
      if (currentVersion < version) {
        await onUpgrade?.call(mock, currentVersion, version);
        database.setUserVersion(version);
      }

      if (currentVersion > version) {
        database.setUserVersion(version);
        await onDowngrade?.call(mock, currentVersion, version);
      }
    }

    await onOpen?.call(mock);
    return mock;
  }

  @override
  Future<int> delete(String statement, [List<dynamic> arguments]) async {
    _database.prepare(statement)
      ..execute(arguments)
      ..close();
    return _database.getUpdatedRows();
  }

  @override
  Future<void> execute(String statement, [List<dynamic> arguments]) async {
    return _database.prepare(statement)
      ..execute(arguments)
      ..close();
  }

  @override
  Future<List<Map<String, dynamic>>> query(String statement,
      [List<void> arguments]) async {
    final sql.PreparedStatement prep = _database.prepare(statement);
    final sql.Result result = prep.select(arguments);
    prep.close();
    return result.toList();
  }

  @override
  void close() {
    _database.close();
  }

  @override
  File get file => _path;
}
