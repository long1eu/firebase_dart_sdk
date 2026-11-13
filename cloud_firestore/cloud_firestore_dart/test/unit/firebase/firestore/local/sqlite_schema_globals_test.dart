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

// Schema migration 16 (Android migration 17): the `globals` table of the globals cache.

import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:test/test.dart';

import 'mock/database_mock.dart';

void main() {
  const String name = 'firebase/firestore/local/sqlite_schema_globals_test.db';
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

  Future<bool> globalsTableExists() async {
    final List<Map<String, dynamic>> rows = await db.query(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'globals'",
    );
    return rows.isNotEmpty;
  }

  test('migration 16 creates the globals table from version 15', () async {
    final SQLiteSchema schema = SQLiteSchema(db);
    await schema.runMigrations(0, 15);
    expect(await globalsTableExists(), isFalse);

    await schema.runMigrations(15, 16);
    expect(await globalsTableExists(), isTrue);

    await db.execute(
      'INSERT OR REPLACE INTO globals (name, value) VALUES (?, ?)',
      <Object?>[
        'sessionToken',
        Uint8List.fromList(<int>[1, 2, 3]),
      ],
    );
    // Running it again (a downgrade and upgrade) keeps the table and its rows.
    await schema.runMigrations(15, 16);
    final List<Map<String, dynamic>> rows = await db.query(
      'SELECT name, value FROM globals',
    );
    expect(rows, hasLength(1));
    expect(rows.single['name'], 'sessionToken');
    expect(rows.single['value'], <int>[1, 2, 3]);
  });

  test('a new database has the globals table', () async {
    await SQLiteSchema(db).runMigrations();
    expect(await globalsTableExists(), isTrue);
  });
}
