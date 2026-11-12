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

// Schema migration 10 (read time on remote documents, Android SDK migrations 9 and 10): the upstream SQLiteSchemaTest
// cases for the index-free migration, adapted to the port's numbering, plus an upgrade of a version 9 database with
// existing data through SQLitePersistence and LocalStore.

import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/encoded_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_purpose.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/database.dart';
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:test/test.dart';

import '../../../../util/test_util.dart';
import 'mock/database_mock.dart';
import 'persistence_test_helpers.dart';

final LocalSerializer _serializer =
    LocalSerializer(RemoteSerializer(DatabaseId.forProject('projectId')));

Uint8List _createDummyDocument(String name) {
  return _serializer
      .encodeMaybeDocument(doc(name, 1, map(<dynamic>['foo', 'bar'])))
      .writeToBuffer();
}

Uint8List _createDummyQueryTargetWithLimboFreeVersion(int targetId) {
  return _serializer
      .encodeQueryData(QueryData(
        query('coll').toTarget(),
        targetId,
        1,
        QueryPurpose.listen,
        version(1),
        Uint8List(0),
        null,
        version(1),
      ))
      .writeToBuffer();
}

Future<List<proto.Target>> _readTargets(Database db) async {
  final List<Map<String, dynamic>> rows = await db
      .query('SELECT target_id, target_proto FROM targets ORDER BY target_id');
  return rows.map((Map<String, dynamic> row) {
    final proto.Target target = proto.Target.fromBuffer(row['target_proto']);
    expect(target.targetId, row['target_id']);
    return target;
  }).toList();
}

void main() {
  late String name;
  late DatabaseMock db;
  late SQLiteSchema schema;

  setUp(() async {
    name = 'firebase/firestore/local/sqlite_schema_read_time_test.db';
    DatabaseMock.deleteDatabaseFiles(name);
    db = await DatabaseMock.create(name)
      ..renamePath = false;
    schema = SQLiteSchema(db);
  });

  tearDown(() {
    db.close();
    DatabaseMock.deleteDatabaseFiles(name);
  });

  test('addsReadTimeColumns', () async {
    await schema.runMigrations(0, 9);
    expect(await schema.getTableColumns('remote_documents'),
        <String>['path', 'contents']);

    await schema.runMigrations(9, 10);
    expect(await schema.getTableColumns('remote_documents'),
        <String>['path', 'contents', 'read_time_seconds', 'read_time_nanos']);
  });

  test('dropsLastLimboFreeSnapshotIfPreviouslyDowngraded', () async {
    await schema.runMigrations(0, 10);

    for (int targetId = 1; targetId <= 3; targetId++) {
      await db.execute(
          'INSERT INTO targets (target_id, canonical_id, target_proto) VALUES (?, ?, ?)',
          <Object>[
            targetId,
            'id$targetId',
            _createDummyQueryTargetWithLimboFreeVersion(targetId)
          ]);
    }

    // A downgrade leaves the schema untouched (an older SDK writes documents without read time), the next upgrade
    // runs migration 10 again.
    await schema.runMigrations(9, 10);

    final List<proto.Target> targets = await _readTargets(db);
    expect(targets, hasLength(3));
    for (proto.Target target in targets) {
      expect(target.hasLastLimboFreeSnapshotVersion(), isFalse);
    }
  });

  test('keepsLastLimboFreeSnapshotIfNotDowngraded', () async {
    await schema.runMigrations(0, 10);

    await db.execute(
        'INSERT INTO targets (target_id, canonical_id, target_proto) VALUES (?, ?, ?)',
        <Object>[1, 'foo', _createDummyQueryTargetWithLimboFreeVersion(1)]);

    // Make sure that we don't drop the lastLimboFreeSnapshotVersion if we are already on schema version 10.
    await schema.runMigrations(10, 10);

    final List<proto.Target> targets = await _readTargets(db);
    expect(targets.single.hasLastLimboFreeSnapshotVersion(), isTrue);
  });

  test('existingDocumentsRemainReadableAfterReadTimeMigration', () async {
    // Initialize the schema to the state prior to the read time migration, with a document in the cache.
    await schema.runMigrations(0, 9);
    await db.execute('PRAGMA user_version = 9');
    await db.execute(
        'INSERT INTO remote_documents (path, contents) VALUES (?, ?)', <Object>[
      EncodedPath.encode(path('coll/existing')),
      _createDummyDocument('coll/existing')
    ]);
    db.close();

    // Opening the persistence runs migration 10.
    final SQLitePersistence persistence = await createSQLitePersistence(name);
    try {
      await persistence.runTransaction('add docs', () async {
        for (final MapEntry<String, int> entry in <String, int>{
          'coll/old': 1,
          'coll/current': 2,
          'coll/new': 3
        }.entries) {
          final Document document = doc(entry.key, 1, map(<dynamic>['a', 1]));
          await persistence.remoteDocumentCache
              .add(document, version(entry.value));
        }
      });

      // Queries with SnapshotVersion.none return all results, regardless of whether the read time has been set.
      ImmutableSortedMap<DocumentKey, Document> results = await persistence
          .remoteDocumentCache
          .getAllDocumentsMatchingQuery(query('coll'), IndexOffset.none);
      expect(
          results
              .map((MapEntry<DocumentKey, Document> e) => e.key.path.toString())
              .toSet(),
          <String>{'coll/existing', 'coll/old', 'coll/current', 'coll/new'});

      // Queries that filter by read time only return documents that were written after the migration.
      results = await persistence.remoteDocumentCache
          .getAllDocumentsMatchingQuery(
              query('coll'), IndexOffset.createSuccessor(version(2), -1));
      expect(
          results
              .map((MapEntry<DocumentKey, Document> e) => e.key.path.toString())
              .toList(),
          <String>['coll/new']);
    } finally {
      await persistence.shutdown();
    }
    db = await DatabaseMock.create(name)
      ..renamePath = false;
  });

  test('localStoreServesExistingDataAfterReadTimeMigration', () async {
    // A version 9 database with a cached document, a target that matched it and a pending write.
    await schema.runMigrations(0, 9);
    await db.execute('PRAGMA user_version = 9');
    await db.execute(
        'INSERT INTO remote_documents (path, contents) VALUES (?, ?)', <Object>[
      EncodedPath.encode(path('coll/a')),
      _serializer
          .encodeMaybeDocument(
              doc('coll/a', 5, map(<dynamic>['matches', true])))
          .writeToBuffer()
    ]);
    final QueryData queryData = QueryData(
      query('coll').filter(filter('matches', '==', true)).toTarget(),
      2,
      1,
      QueryPurpose.listen,
      version(5),
      resumeToken(5),
    );
    await db.execute(
        'INSERT INTO targets (target_id, canonical_id, snapshot_version_seconds, snapshot_version_nanos, resume_token, '
        'last_listen_sequence_number, target_proto) VALUES (?, ?, ?, ?, ?, ?, ?)',
        <Object>[
          2,
          queryData.target.canonicalId,
          0,
          5000,
          resumeToken(5)!,
          1,
          _serializer.encodeQueryData(queryData).writeToBuffer()
        ]);
    await db.execute(
        'INSERT INTO target_documents (target_id, path, sequence_number) VALUES (?, ?, ?)',
        <Object>[2, EncodedPath.encode(path('coll/a')), 1]);
    await db.execute(
        'UPDATE target_globals SET highest_target_id = 2, highest_listen_sequence_number = 1, target_count = 1');
    db.close();

    final SQLitePersistence persistence = await createSQLitePersistence(name);
    try {
      final LocalStore localStore =
          LocalStore(persistence, User.unauthenticated);
      await localStore.start();

      final Query q = query('coll').filter(filter('matches', '==', true));
      final QueryData allocated = await localStore.allocateTarget(q.toTarget());
      expect(allocated.targetId, 2);
      expect(allocated.lastLimboFreeSnapshotVersion, SnapshotVersion.none);

      final QueryResult result = await localStore.executeQuery(q, true);
      expect(result.remoteKeys.toList(), <DocumentKey>[key('coll/a')]);
      expect(
          result.documents
              .map((MapEntry<DocumentKey, Document> e) => e.key)
              .toList(),
          <DocumentKey>[key('coll/a')]);

      final MaybeDocument? read = await localStore.readDocument(key('coll/a'));
      expect(read, doc('coll/a', 5, map(<dynamic>['matches', true])));
    } finally {
      await persistence.shutdown();
    }
    db = await DatabaseMock.create(name)
      ..renamePath = false;
  });
}
