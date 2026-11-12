// Schema migrations 12 (path length and read time of remote documents, Android SDK migrations 13 and 15) and 13 (field
// index tables, Android SDK migration 16): the upstream SQLiteSchemaTest cases adapted to the port's numbering.

import 'package:cloud_firestore_dart/src/firebase/firestore/local/encoded_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';
import 'mock/database_mock.dart';

void main() {
  late String name;
  late DatabaseMock db;
  late SQLiteSchema schema;

  setUp(() async {
    name = 'firebase/firestore/local/sqlite_schema_index_test.db';
    DatabaseMock.deleteDatabaseFiles(name);
    db = await DatabaseMock.create(name)
      ..renamePath = false;
    schema = SQLiteSchema(db);
  });

  tearDown(() {
    db.close();
    DatabaseMock.deleteDatabaseFiles(name);
  });

  Future<bool> tableExists(String table) async {
    final List<Map<String, dynamic>> rows = await db.query(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
        <Object>[table]);
    return rows.isNotEmpty;
  }

  test('addPathLengths', () async {
    await schema.runMigrations(0, 11);

    final List<ResourcePath> paths = <ResourcePath>[
      path('collA/doc'),
      path('collA/doc/collB/doc')
    ];

    for (final ResourcePath path in paths) {
      await db.execute('INSERT INTO remote_documents (path) VALUES (?)',
          <Object>[EncodedPath.encode(path)]);
    }

    await schema.runMigrations(11, 12);

    final List<Map<String, dynamic>> rows = await db
        .query('SELECT path_length FROM remote_documents ORDER BY path');
    expect(rows.map((Map<String, dynamic> row) => row['path_length']).toList(),
        paths.map((ResourcePath path) => path.length).toList());
  });

  test('usesMultipleBatchesToAddPathLengths', () async {
    await schema.runMigrations(0, 11);

    const int count = SQLiteSchema.migrationBatchSize + 1;
    for (int i = 0; i < count; ++i) {
      final ResourcePath docPath =
          path('coll/doc${i.toString().padLeft(3, '0')}');
      await db.execute('INSERT INTO remote_documents (path) VALUES (?)',
          <Object>[EncodedPath.encode(docPath)]);
    }

    await schema.runMigrations(11, 12);

    final List<Map<String, dynamic>> rows = await db
        .query('SELECT path_length FROM remote_documents ORDER BY path');
    expect(rows, hasLength(count));
    for (final Map<String, dynamic> row in rows) {
      expect(row['path_length'], 2);
    }
  });

  // Android SDK migration 15 (`ensureReadTime`), which has no test of its own upstream.
  test('setsMissingReadTimesToZero', () async {
    await schema.runMigrations(0, 11);

    await db.execute('INSERT INTO remote_documents (path) VALUES (?)',
        <Object>[EncodedPath.encode(path('coll/old'))]);
    await db.execute(
        'INSERT INTO remote_documents (path, read_time_seconds, read_time_nanos) VALUES (?, ?, ?)',
        <Object>[EncodedPath.encode(path('coll/new')), 5, 6]);

    await schema.runMigrations(11, 12);

    final List<Map<String, dynamic>> rows = await db.query(
        'SELECT read_time_seconds, read_time_nanos FROM remote_documents ORDER BY path');
    // 'coll/new' sorts before 'coll/old'.
    expect(rows[0]['read_time_seconds'], 5);
    expect(rows[0]['read_time_nanos'], 6);
    expect(rows[1]['read_time_seconds'], 0);
    expect(rows[1]['read_time_nanos'], 0);
  });

  test('pathLengthMigrationCanRunAgain', () async {
    await schema.runMigrations(0, 12);
    // After a downgrade an older SDK writes documents without a path length.
    await db.execute('INSERT INTO remote_documents (path) VALUES (?)',
        <Object>[EncodedPath.encode(path('coll/doc/sub/doc'))]);

    await schema.runMigrations(11, 12);

    final List<Map<String, dynamic>> rows = await db
        .query('SELECT path_length, read_time_seconds FROM remote_documents');
    expect(rows.single['path_length'], 4);
    expect(rows.single['read_time_seconds'], 0);
  });

  test('createsIndexingTables', () async {
    await schema.runMigrations(0, 12);
    expect(await tableExists('index_configuration'), isFalse);

    await schema.runMigrations(12, 13);
    expect(await tableExists('index_configuration'), isTrue);
    expect(await tableExists('index_entries'), isTrue);
    expect(await tableExists('index_state'), isTrue);

    expect(await schema.getTableColumns('index_configuration'),
        <String>['index_id', 'collection_group', 'index_proto']);
    expect(await schema.getTableColumns('index_state'), <String>[
      'index_id',
      'uid',
      'sequence_number',
      'read_time_seconds',
      'read_time_nanos',
      'document_key',
      'largest_batch_id'
    ]);
    expect(await schema.getTableColumns('index_entries'), <String>[
      'index_id',
      'uid',
      'array_value',
      'directional_value',
      'document_key'
    ]);

    final List<Map<String, dynamic>> indexes = await db.query(
        "SELECT tbl_name FROM sqlite_master WHERE type = 'index' AND name = 'read_time'");
    expect(indexes.single['tbl_name'], 'remote_documents');

    // Running it again is a no-op.
    await schema.runMigrations(12, 13);
  });

  test('indexEntriesAreOrderedByTheirBlobs', () async {
    // The index manager relies on SQLite comparing BLOBs byte by byte (memcmp), unsigned.
    await schema.runMigrations();
    for (final List<int> value in <List<int>>[
      <int>[0x80],
      <int>[0x7f, 0xff],
      <int>[0xff],
      <int>[],
      <int>[0x00],
    ]) {
      await db.execute(
          'INSERT INTO index_entries (index_id, uid, array_value, directional_value, document_key) '
          'VALUES (1, ?, ?, ?, ?)',
          <Object>['', <int>[], value, 'coll/doc']);
    }
    final List<Map<String, dynamic>> rows = await db.query(
        'SELECT directional_value FROM index_entries ORDER BY directional_value');
    expect(
        rows
            .map((Map<String, dynamic> row) =>
                (row['directional_value'] as List<int>).toList())
            .toList(),
        <List<int>>[
          <int>[],
          <int>[0x00],
          <int>[0x7f, 0xff],
          <int>[0x80],
          <int>[0xff],
        ]);
  });
}
