// Copyright 2019 Google LLC
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

// Additional SQLiteSchemaTest cases: the upstream test the Dart port lacks
// (addsSentinelRowsForLargeNumberOfDocuments), an addsSentinelRows variant that
// uses encoded paths exactly as upstream does, and every (from, to) migration
// combination from version 0 up to the current schema version.

import 'dart:io';

import 'package:cloud_firestore_vm/src/firebase/firestore/local/encoded_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/database.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';
import 'mock/database_mock.dart';

void main() {
  late Database db;
  late SQLiteSchema schema;

  Future<void> open(String name) async {
    final File file = DatabaseMock.pathForName(name);
    if (file.existsSync()) {
      file.deleteSync();
    }
    db = await DatabaseMock.create(name);
    schema = SQLiteSchema(db);
  }

  setUp(() => open('firebase/firestore/local/sqlite_schema_extra_test.db'));

  tearDown(() => db.close());

  test('addsSentinelRowsForLargeNumberOfDocuments', () async {
    // This test only verifies that we add sentinel rows for documents even if
    // the number of documents exceeds our batch size.
    await schema.runMigrations(0, 6);

    // Set up some documents (we only need the keys). Note this count is higher
    // than the batch size during migration, which is 100.
    const int documentCount = 250;
    for (int i = 0; i < documentCount; i++) {
      final String p = 'coll/doc_$i';
      await db.execute('INSERT INTO remote_documents (path) VALUES (?)',
          <String>[EncodedPath.encode(path(p))]);
    }

    List<Map<String, dynamic>> result =
        await db.query('SELECT COUNT(*) as count FROM target_documents');
    expect(result.first['count'], 0);

    await schema.runMigrations(6, 7);

    result = await db.query('SELECT COUNT(*) as count FROM target_documents');
    expect(result.first['count'], documentCount);
  });

  test('addsSentinelRowsWithEncodedPaths', () async {
    await schema.runMigrations(0, 6);

    const int oldSequenceNumber = 1;
    // Set the highest sequence number to this value so that untagged documents
    // will pick up this value.
    const int newSequenceNumber = 2;
    await db.execute(
        'UPDATE target_globals SET highest_listen_sequence_number = ?',
        <int>[newSequenceNumber]);

    // Set up some documents (we only need the keys). For the odd ones, add
    // sentinel rows.
    for (int i = 0; i < 10; i++) {
      final String encodedPath = EncodedPath.encode(path('docs/doc_$i'));
      await db.execute('INSERT INTO remote_documents (path) VALUES (?)',
          <String>[encodedPath]);
      if (i % 2 == 1) {
        await db.execute(
            'INSERT INTO target_documents (target_id, path, sequence_number) VALUES (0, ?, ?)',
            <dynamic>[encodedPath, oldSequenceNumber]);
      }
    }

    await schema.runMigrations(6, 7);

    final List<Map<String, dynamic>> rows = await db.query(
        'SELECT path, sequence_number FROM target_documents WHERE target_id = 0');
    expect(rows, hasLength(10));
    for (Map<String, dynamic> row in rows) {
      final String last =
          EncodedPath.decodeResourcePath(row['path'] as String).last;
      final int sequenceNumber = row['sequence_number'] as int;
      final int docNum = int.parse(last.split('_')[1]);
      // The even documents were missing sequence numbers, they should now be
      // filled in to have the new sequence number. The odd documents should have
      // their sequence number unchanged, and so be the old value.
      expect(sequenceNumber,
          docNum % 2 == 1 ? oldSequenceNumber : newSequenceNumber);
    }
  });

  test('everyMigrationRangeSucceedsOnAFreshDatabase', () async {
    for (int from = 0; from < SQLiteSchema.version; from++) {
      for (int to = from + 1; to <= SQLiteSchema.version; to++) {
        db.close();
        await open('firebase/firestore/local/sqlite_schema_range_${from}_$to.db');
        await schema.runMigrations(0, from);
        await schema.runMigrations(from, to);
        // The remaining steps and a full re-run must also work.
        await schema.runMigrations(to, SQLiteSchema.version);
        await schema.runMigrations();
      }
    }
  });

  test('everyStepCanBeRunTwiceInARow', () async {
    for (int toVersion = 1; toVersion <= SQLiteSchema.version; toVersion++) {
      await schema.runMigrations(toVersion - 1, toVersion);
      await schema.runMigrations(toVersion - 1, toVersion);
    }
  });
}
