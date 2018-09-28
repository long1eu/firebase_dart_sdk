// File created by
// Lung Razvan <long1eu>
// on 29/09/2018

import 'dart:async';
import 'dart:io';

import 'package:firebase_firestore/src/firebase/firestore/util/database_impl.dart';
import 'package:sqlite/sqlite.dart' as sql;

class DatabaseMock extends Database {
  sql.Database database;
  File path;

  DatabaseMock(String name) {
    path = File('${Directory.current.path}/build/test/$name')
      ..createSync(recursive: true);
    database = sql.Database(path.path);
  }

  @override
  Future<int> delete(String statement, [List<dynamic> arguments]) {
    return database.execute(statement, params: arguments ?? <dynamic>[]);
  }

  @override
  Future<void> execute(String statement, [List<dynamic> arguments]) async {
    await database.execute(statement, params: arguments ?? <dynamic>[]);
  }

  @override
  Future<List<Map<String, dynamic>>> query(String statement,
      [List<void> arguments]) async {
    return database
        .query(statement, params: arguments ?? <dynamic>[])
        .toList()
        .then((List<sql.Row> rows) =>
            rows.map((sql.Row row) => row.toMap()).toList());
  }

  @override
  Future<T> transaction<T>(Future<T> Function(DatabaseExecutor) action,
      {bool exclusive}) async {
    final Completer<T> completer = Completer<T>();
    database.transaction(() async => completer.complete(await action(this)));
    return completer.future;
  }

  @override
  void close() {
    print('close');
    database.close();
    path.renameSync('${path.path}_');
  }
}
