// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Schema migration 14: the lookups by document of the garbage collector and of the index backfill use an index
// instead of walking the table (tool/bench/local_store_bench.dart measures the difference).

import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:test/test.dart';

import 'mock/database_mock.dart';

void main() {
  const String name =
      'firebase/firestore/local/sqlite_schema_lookup_indexes_test.db';
  late DatabaseMock db;

  setUp(() async {
    DatabaseMock.deleteDatabaseFiles(name);
    db = await DatabaseMock.create(name)
      ..renamePath = false;
  });

  tearDown(() {
    db.close();
    DatabaseMock.deleteDatabaseFiles(name);
  });

  Future<String> plan(String statement) async {
    final List<Map<String, dynamic>> rows = await db.query(
      'EXPLAIN QUERY PLAN $statement',
    );
    return rows.map((Map<String, dynamic> row) => row['detail']).join('\n');
  }

  test(
    'migration 14 adds the lookup indexes, also to an existing database',
    () async {
      final SQLiteSchema schema = SQLiteSchema(db);
      await schema.runMigrations(0, 13);
      expect(
        await plan("SELECT 1 FROM document_mutations WHERE path = 'p'"),
        isNot(contains('document_mutations_path')),
      );

      await schema.runMigrations(13, 14);
      // Running it again must not fail.
      await schema.runMigrations(13, 14);

      final List<Map<String, dynamic>> indexes = await db.query(
        "SELECT name FROM sqlite_master WHERE type = 'index'",
      );
      expect(
        indexes.map((Map<String, dynamic> row) => row['name']),
        containsAll(<String>[
          'document_mutations_path',
          'index_entries_document_key',
        ]),
      );
    },
  );

  test(
    'the garbage collector finds the mutations of a document by index',
    () async {
      await SQLiteSchema(db).runMigrations();
      // The statement of SQLiteLruReferenceDelegate._mutationQueuesContainKey.
      expect(
        await plan("SELECT 1 FROM document_mutations WHERE path = 'p'"),
        contains('document_mutations_path'),
      );
    },
  );

  test('the index backfill finds the entries of a document by index', () async {
    await SQLiteSchema(db).runMigrations();
    // The statement of SqliteIndexManager._getExistingIndexEntries.
    expect(
      await plan(
        'SELECT array_value, directional_value FROM index_entries '
        'INDEXED BY index_entries_document_key '
        "WHERE index_id = 1 AND document_key = 'k' AND uid = ''",
      ),
      contains('index_id=? AND uid=? AND document_key=?'),
    );
  });
}
