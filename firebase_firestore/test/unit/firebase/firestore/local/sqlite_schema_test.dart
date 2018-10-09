// File created by
// Lung Razvan <long1eu>
// on 28/09/2018

import 'dart:async';

import 'package:firebase_firestore/src/firebase/firestore/local/sqlite_persistence.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/sqlite_schema.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/database_id.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/database.dart';
import 'package:test/test.dart';

import 'mock/database_mock.dart';

void main() {
  Database db;
  SQLiteSchema schema;

  setUp(() async {
    db = await DatabaseMock.create(
        'firebase/firestore/local/sqlite_schema_test.db');
    schema = SQLiteSchema(db);
    await schema.runMigrations();
  });

  tearDown(() => db.close());

  Future<void> _assertNoResultsForQuery(String query,
      [List<String> args]) async {
    final List<Map<String, dynamic>> result = await db.query(query, args);

    expect(result, isEmpty);
  }

  test('createsMutationsTable', () async {
    await _assertNoResultsForQuery('SELECT uid, batch_id FROM mutations');
    await db.execute("INSERT INTO mutations (uid, batch_id) VALUES ('foo', 1)");

    final List<Map<String, dynamic>> result =
        await db.query('SELECT uid, batch_id FROM mutations');

    expect(result, isNotEmpty);
    expect(result.first['uid'], 'foo');
    expect(result.first['batch_id'], 1);
    expect(result.length, 1);
  });

  test('testDatabaseName', () async {
    expect(
        SQLitePersistence.sDatabaseName(
            '[DEFAULT]', DatabaseId.forProject('my-project')),
        'firestore.%5BDEFAULT%5D.my-project.%28default%29');
    expect(
        SQLitePersistence.sDatabaseName(
            '[DEFAULT]', DatabaseId.forDatabase('my-project', 'my-database')),
        'firestore.%5BDEFAULT%5D.my-project.my-database');
  });
}
