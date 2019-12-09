// File created by
// Lung Razvan <long1eu>
// on 28/09/2018

import 'dart:async';
import 'dart:io';

import 'package:firebase_firestore/src/firebase/firestore/local/encoded_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/sqlite_persistence.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/sqlite_schema.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/database_id.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/resource_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/database.dart';
import 'package:firebase_firestore/src/proto/index.dart' as proto;
import 'package:test/test.dart';

import 'mock/database_mock.dart';

void main() {
  Database db;
  SQLiteSchema schema;

  setUp(() async {
    const String name = 'firebase/firestore/local/sqlite_schema_test.db';
    final File file = DatabaseMock.pathForName(name);
    if (file.existsSync()) {
      file.deleteSync();
    }

    db = await DatabaseMock.create(name);
    schema = SQLiteSchema(db);
  });

  tearDown(() => db.close());

  test('canRerunMigrations', () async {
    await schema.runMigrations();
    // Run the whole thing again
    await schema.runMigrations();
    // Run just a piece. Adds a column, make sure it doesn't throw
    await schema.runMigrations(4, 6);
  });

  test('migrationsDontDeleteTablesOrColumns', () async {
    // In order to support users downgrading the SDK we need to make sure that every prior-released version of the SDK
    // can gracefully handle running against an upgraded schema. We can't guarantee this in the general case, but this
    // test at least ensures that no schema upgrade deletes an existing table or column, which would be very likely to
    // break old versions of the SDK relying on that table or column.
    Map<String, Set<String>> tables = <String, Set<String>>{};
    for (int toVersion = 1; toVersion <= SQLiteSchema.version; toVersion++) {
      await schema.runMigrations(toVersion - 1, toVersion);
      final Map<String, Set<String>> newTables = await _getCurrentSchema(schema, db);
      _assertNoRemovals(tables, newTables, toVersion);
      tables = newTables;
    }
  });

  test('canRecoverFromDowngrades', () async {
    for (int downgradeVersion = 0; downgradeVersion < SQLiteSchema.version; downgradeVersion++) {
      // Upgrade schema to current, then upgrade from `downgradeVersion` to current
      await schema.runMigrations();
      await schema.runMigrations(downgradeVersion, SQLiteSchema.version);
    }
  });

  test('createsMutationsTable', () async {
    await schema.runMigrations();
    await _assertNoResultsForQuery(db, 'SELECT uid, batch_id FROM mutations');
    await db.execute("INSERT INTO mutations (uid, batch_id) VALUES ('foo', 1)");

    final List<Map<String, dynamic>> result = await db.query('SELECT uid, batch_id FROM mutations');

    expect(result, isNotEmpty);
    expect(result.first['uid'], 'foo');
    expect(result.first['batch_id'], 1);
    expect(result.length, 1);
  });

  test('deletesAllTargets', () async {
    await schema.runMigrations(0, 2);

    await db.execute('INSERT INTO targets (canonical_id, target_id) VALUES (\'foo1\', 1)');
    await db.execute('INSERT INTO targets (canonical_id, target_id) VALUES (\'foo2\', 2)');
    await db.execute('INSERT INTO target_globals (highest_target_id) VALUES (2)');

    await db.execute('INSERT INTO target_documents (target_id, path) VALUES (1, \'foo/bar\')');
    await db.execute('INSERT INTO target_documents (target_id, path) VALUES (2, \'foo/baz\')');

    await schema.runMigrations(2, 3);

    await _assertNoResultsForQuery(db, 'SELECT * FROM targets');
    await _assertNoResultsForQuery(db, 'SELECT * FROM target_globals');
    await _assertNoResultsForQuery(db, 'SELECT * FROM target_documents');
  });

  test('countsTargets', () async {
    await schema.runMigrations(0, 3);
    const int expected = 50;
    for (int i = 0; i < expected; i++) {
      await db.execute('INSERT INTO targets (canonical_id, target_id) VALUES (?, ?)', <dynamic>['foo$i', i]);
    }
    await schema.runMigrations(3, 5);

    final List<Map<String, dynamic>> data = await db.query('SELECT target_count FROM target_globals LIMIT 1');
    expect(data, isNotEmpty);

    final int targetCount = data.first['target_count'];
    expect(targetCount, expected);
  });

  test('testDatabaseName', () async {
    expect(SQLitePersistence.sDatabaseName('[DEFAULT]', DatabaseId.forProject('my-project')),
        'firestore.%5BDEFAULT%5D.my-project.%28default%29');
    expect(SQLitePersistence.sDatabaseName('[DEFAULT]', DatabaseId.forDatabase('my-project', 'my-database')),
        'firestore.%5BDEFAULT%5D.my-project.my-database');
  });

  test('dropsHeldWriteAcks', () async {
    // This test creates a database with schema version 5 that has two users, both of which have acknowledged mutations
    // that haven't yet been removed from IndexedDb ("heldWriteAcks"). Schema version 6 removes heldWriteAcks, and as
    // such these mutations are deleted.
    await schema.runMigrations(0, 5);

    // User 'userA' has two acknowledged mutations and one that is pending.
    // User 'userB' has one acknowledged mutation and one that is pending.
    await _addMutationBatch(db, 1, 'userA', <String>['docs/foo']);
    await _addMutationBatch(db, 2, 'userA', <String>['docs/foo']);
    await _addMutationBatch(db, 3, 'userB', <String>['docs/bar', 'doc/baz']);
    await _addMutationBatch(db, 4, 'userB', <String>['docs/pending']);
    await _addMutationBatch(db, 5, 'userA', <String>['docs/pending']);

    // Populate the mutation queues' metadata
    await db
        .execute('INSERT INTO mutation_queues (uid, last_acknowledged_batch_id) VALUES (?, ?)', <dynamic>['userA', 2]);
    await db
        .execute('INSERT INTO mutation_queues (uid, last_acknowledged_batch_id) VALUES (?, ?)', <dynamic>['userB', 3]);
    await db
        .execute('INSERT INTO mutation_queues (uid, last_acknowledged_batch_id) VALUES (?, ?)', <dynamic>['userC', -1]);

    await schema.runMigrations(5, 6);

    // Verify that all but the two pending mutations have been cleared by the migration.
    expect((await db.query('SELECT COUNT(*) as count FROM mutations')).first['count'], 2);
    // Verify that we still have two index entries for the pending documents
    expect((await db.query('SELECT COUNT(*) as count FROM document_mutations')).first['count'], 2);
    // Verify that we still have one metadata entry for each existing queue
    expect((await db.query('SELECT COUNT(*) as count FROM mutation_queues')).first['count'], 3);
  });

  test('addsSentinelRows', () async {
    await schema.runMigrations(0, 6);

    const int oldSequenceNumber = 1;
    // Set the highest sequence number to this value so that untagged documents will pick up this value.
    const int newSequenceNumber = 2;
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

    await schema.runMigrations(6, 7);

    final List<Map<String, dynamic>> result = await db.query('''SELECT path, sequence_number
           FROM target_documents
           WHERE target_id = 0;''');

    for (Map<String, dynamic> row in result) {
      final String path = row['path'];
      final int sequenceNumber = row['sequence_number'];

      final int docNum = int.parse(path.split('_')[1]);
      // The even documents were missing sequence numbers, they should now be filled in to have the new sequence number.
      // The odd documents should have their sequence number unchanged, and so be the old value.
      final int expected = docNum % 2 == 1 ? oldSequenceNumber : newSequenceNumber;
      expect(sequenceNumber, expected);
    }
  });
}

Future<void> _assertNoResultsForQuery(Database db, String query, [List<String> args]) async {
  final List<Map<String, dynamic>> result = await db.query(query, args);
  expect(result, isEmpty);
}

Future<Map<String, Set<String>>> _getCurrentSchema(SQLiteSchema schema, Database db) async {
  final Map<String, Set<String>> tables = <String, Set<String>>{};
  final List<Map<String, dynamic>> data = await db.query('SELECT tbl_name FROM sqlite_master WHERE type = \"table\"');
  for (Map<String, dynamic> row in data) {
    final String table = row['tbl_name'];
    final Set<String> columns = <String>{...await schema.getTableColumns(table)};

    tables[table] = columns;
  }

  return tables;
}

void _assertNoRemovals(Map<String, Set<String>> oldSchema, Map<String, Set<String>> newSchema, int newVersion) {
  for (MapEntry<String, Set<String>> entry in oldSchema.entries) {
    final String table = entry.key;
    final Set<String> newColumns = newSchema[table];
    expect(newColumns, isNotNull, reason: 'Table $table was deleted at version $newVersion');
    final Set<String> oldColumns = entry.value;
    for (String column in oldColumns) {
      expect(newColumns.contains(column), isTrue,
          reason: 'Column $column was deleted from table $table at version $newVersion');
    }
  }
}

Future<void> _addMutationBatch(Database db, int batchId, String uid, List<String> docs) async {
  final proto.WriteBatch batch = proto.WriteBatch()..batchId = batchId;

  for (String doc in docs) {
    await db.execute('INSERT INTO document_mutations (uid, path, batch_id) VALUES (?, ?, ?)',
        <dynamic>[uid, EncodedPath.encode(ResourcePath.fromString(doc)), batchId]);

    final proto.Document document = proto.Document()..name = 'projects/projectId/databases/(default)/documents/$doc';
    final proto.Write write = proto.Write()..update = document;
    batch.writes.add(write);
  }

  return db.execute('INSERT INTO mutations (uid, batch_id, mutations) VALUES (?,?,?)',
      <dynamic>[uid, batchId, batch.writeToBuffer()]);
}
