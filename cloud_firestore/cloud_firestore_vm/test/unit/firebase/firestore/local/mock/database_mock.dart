// File created by
// Lung Razvan <long1eu>
// on 29/09/2018

import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore_vm/src/firebase/firestore/util/database.dart';
import 'package:moor_ffi/database.dart' as sql;

class DatabaseMock extends Database {
  DatabaseMock._(this.database, this.path);

  sql.Database database;
  File path;

  bool renamePath = true;

  static File pathForName(String name) {
    return File('${Directory.current.path}/build/test/$name');
  }

  static Future<DatabaseMock> create(String name,
      {int version,
      OnConfigure onConfigure,
      OnCreate onCreate,
      OnVersionChange onUpgrade,
      OnVersionChange onDowngrade,
      OnOpen onOpen}) async {
    version ??= 1;

    final File path = pathForName(name);
    final bool callOnCreate = !path.existsSync();
    path.createSync(recursive: true);

    final sql.Database database = sql.Database.openFile(path);
    final DatabaseMock mock = DatabaseMock._(database, path);

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
    database.prepare(statement)
      ..execute(arguments)
      ..close();
    return database.getUpdatedRows();
  }

  @override
  Future<void> execute(String statement, [List<dynamic> arguments]) async {
    return database.prepare(statement)
      ..execute(arguments)
      ..close();
  }

  @override
  Future<List<Map<String, dynamic>>> query(String statement,
      [List<void> arguments]) async {
    final sql.PreparedStatement prep = database.prepare(statement);
    final sql.Result result = prep.select(arguments);
    prep.close();
    return result.toList();
  }

  @override
  void close() {
    database.close();
    if (renamePath) {
      path.renameSync('${path.path}_');
    }
  }

  @override
  File get file => path;
}
