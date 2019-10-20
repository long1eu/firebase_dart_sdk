// File created by
// Lung Razvan <long1eu>
// on 28/09/2018

import 'dart:async';
import 'dart:io';

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
    final String name = 'firebase/firestore/local/sqlite_schema_test.db';
    final File file = DatabaseMock.pathForName(name);
    if (file.existsSync()) {
      file.deleteSync();
    }

    db = await DatabaseMock.create(name);
    schema = SQLiteSchema(db);
  });

  tearDown(() => db.close());

  Future<void> _assertNoResultsForQuery(String query, [List<String> args]) async {
    final List<Map<String, dynamic>> result = await db.query(query, args);

    expect(result, isEmpty);
  }

  test('createsMutationsTable', () async {
    await schema.runMigrations();
    await _assertNoResultsForQuery('SELECT uid, batch_id FROM mutations');
    await db.execute("INSERT INTO mutations (uid, batch_id) VALUES ('foo', 1)");

    final List<Map<String, dynamic>> result = await db.query('SELECT uid, batch_id FROM mutations');

    expect(result, isNotEmpty);
    expect(result.first['uid'], 'foo');
    expect(result.first['batch_id'], 1);
    expect(result.length, 1);
  });

  test('testDatabaseName', () async {
    await schema.runMigrations();
    expect(SQLitePersistence.sDatabaseName('[DEFAULT]', DatabaseId.forProject('my-project')),
        'firestore.%5BDEFAULT%5D.my-project.%28default%29');
    expect(
        SQLitePersistence.sDatabaseName(
            '[DEFAULT]', DatabaseId.forDatabase('my-project', 'my-database')),
        'firestore.%5BDEFAULT%5D.my-project.my-database');
  });

  test('addsSentinelRows', () async {
    await schema.runMigrations(0, 1);

    final int oldSequenceNumber = 1;
    // Set the highest sequence number to this value so that untagged documents
    // will pick up this value.
    final int newSequenceNumber = 2;
    await db.execute(
      '''UPDATE target_globals
         SET highest_listen_sequence_number = ?''',
      <int>[newSequenceNumber],
    );

    // Set up some documents (we only need the keys)
    // For the odd ones, add sentinel rows.
    for (int i = 0; i < 10; i++) {
      final String path = 'docs/doc_$i';
      await db.execute('INSERT INTO remote_documents (path) VALUES (?)', <String>[path]);
      if (i % 2 == 1) {
        await db.execute(
          '''INSERT INTO target_documents (target_id, path, sequence_number)
             VALUES (0, ?, ?)''',
          <dynamic>[path, oldSequenceNumber],
        );
      }
    }

    await schema.runMigrations(1, 2);

    final List<Map<String, dynamic>> result = await db.query('''SELECT path, sequence_number
           FROM target_documents
           WHERE target_id = 0;''');

    for (Map<String, dynamic> row in result) {
      final String path = row['path'];
      final int sequenceNumber = row['sequence_number'];

      final int docNum = int.parse(path.split("_")[1]);
      // The even documents were missing sequence numbers, they should now be
      // filled in to have the new sequence number. The odd documents should
      // have their sequence number unchanged, and so be the old value.
      final int expected = docNum % 2 == 1 ? oldSequenceNumber : newSequenceNumber;
      expect(sequenceNumber, expected);
    }
  });
}
