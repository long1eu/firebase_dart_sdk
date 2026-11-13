// Copyright 2025 Google LLC
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

// Schema migration 17 (the "document_type" column of remote documents, Android SDK migration 18, #7295): the upstream
// SQLiteSchemaTest case for it.

import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/encoded_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';
import 'mock/database_mock.dart';
import 'persistence_test_helpers.dart';

final LocalSerializer _serializer = LocalSerializer(
  RemoteSerializer(DatabaseId.forProject('projectId')),
);

Uint8List _createDummyDocument(String name) {
  return _serializer
      .encodeMaybeDocument(doc(name, 1, map(<dynamic>['foo', 'bar'])))
      .writeToBuffer();
}

void main() {
  late String name;
  late DatabaseMock db;
  late SQLiteSchema schema;

  setUp(() async {
    name = 'firebase/firestore/local/sqlite_schema_document_type_test.db';
    DatabaseMock.deleteDatabaseFiles(name);
    db = await DatabaseMock.create(name)
      ..renamePath = false;
    schema = SQLiteSchema(db);
  });

  tearDown(() {
    db.close();
    DatabaseMock.deleteDatabaseFiles(name);
  });

  test(
    'existingDocumentsMatchAfterRemoteDocumentsDocumentTypeColumnAdded',
    () async {
      await schema.runMigrations(0, 1);
      for (int i = 0; i < 3; i++) {
        await db.execute(
          'INSERT INTO remote_documents (path, contents) VALUES (?, ?)',
          <Object>[
            EncodedPath.encode(path('coll/doc$i')),
            _createDummyDocument('coll/doc$i'),
          ],
        );
      }

      // The migration of interest is 17 (18 in the Android SDK), but go to the latest migration to ensure
      // compatibility with the SQLiteRemoteDocumentCache implementation.
      await schema.runMigrations(2, SQLiteSchema.version);
      await db.execute('PRAGMA user_version = ${SQLiteSchema.version}');
      db.close();

      // PORTING NOTE: upstream builds a SQLiteRemoteDocumentCache on the raw database; the port's cache needs a
      // SQLitePersistence, which opens the migrated file.
      final SQLitePersistence persistence = await createSQLitePersistence(name);
      try {
        final ImmutableSortedMap<DocumentKey, Document> results =
            await persistence.remoteDocumentCache.getAllDocumentsMatchingQuery(
              query('coll'),
              IndexOffset.none,
            );
        expect(
          results
              .map((MapEntry<DocumentKey, Document> e) => e.key.path.toString())
              .toSet(),
          <String>{'coll/doc0', 'coll/doc1', 'coll/doc2'},
        );
      } finally {
        await persistence.shutdown();
      }
      db = await DatabaseMock.create(name)
        ..renamePath = false;
    },
  );
}
