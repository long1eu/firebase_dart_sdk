// File created by
// Lung Razvan <long1eu>
// on 19/10/2018

import 'dart:io';

import 'package:firebase_firestore/firebase_firestore.dart';
import 'package:sqflite/sqflite.dart' as sql;

class DatabaseImplementation extends Database {
  DatabaseImplementation._(this.database);

  sql.Database database;

  bool renamePath = true;

  static Future<DatabaseImplementation> create(String name, String filePath,
      {int version,
      OnConfigure onConfigure,
      OnCreate onCreate,
      OnVersionChange onUpgrade,
      OnVersionChange onDowngrade,
      OnOpen onOpen}) async {
    final bool callOnCreate = !File(filePath).existsSync();
    final sql.Database database = await sql.openDatabase(name);
    final DatabaseImplementation impl = DatabaseImplementation._(database);

    await onConfigure?.call(impl);
    if (callOnCreate) {
      await onCreate?.call(impl, version);
      await impl.execute('PRAGMA user_version = $version;');
    } else {
      final List<Map<String, dynamic>> row =
          await impl.query('PRAGMA user_version;');
      final int currentVersion = row.first.values.first;

      if (currentVersion < version) {
        await onUpgrade?.call(impl, currentVersion, version);
        await impl.execute('PRAGMA user_version = $version;');
      }

      if (currentVersion > version) {
        await impl.execute('PRAGMA user_version = $version;');
        await onDowngrade?.call(impl, currentVersion, version);
      }
    }

    await onOpen?.call(impl);
    return impl;
  }

  @override
  Future<int> delete(String statement, [List<dynamic> arguments]) {
    return database.rawDelete(statement, arguments ?? <dynamic>[]);
  }

  @override
  Future<void> execute(String statement, [List<dynamic> arguments]) async {
    await database.execute(statement, arguments ?? <dynamic>[]);
  }

  @override
  Future<List<Map<String, dynamic>>> query(String statement,
      [List<void> arguments]) async {
    return database.rawQuery(statement, arguments ?? <dynamic>[]);
  }

  @override
  void close() => database.close();
}
