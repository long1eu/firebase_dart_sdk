// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Schema migration cases that the other sqlite_schema_*_test.dart files do not
// cover:
//  * the Android SQLiteSchemaTest cases createsOverlaysAndMigrationTable
//    (Android 14 = port 11) and createsGlobalsTable (Android 17 = port 16);
//  * migration 15 (client metadata), which has no upstream counterpart;
//  * the JS SDK's "can upgrade from version N to N+1" cases of
//    indexeddb_persistence.test.ts: after each step the schema has exactly the
//    expected tables, indexes and columns;
//  * a database written by the current SDK, opened again after an older SDK
//    lowered its version (Android keeps the data of a downgrade, see
//    SQLitePersistence.OpenHelper.onDowngrade): every migration suffix runs
//    again on real data and keeps it.

import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/set_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/database.dart';
import 'package:test/test.dart';

import '../../../../util/index_helpers.dart';
import '../../../../util/test_util.dart';
import 'mock/database_mock.dart';
import 'persistence_test_helpers.dart';

/// What each migration adds: `table:<name>`, `index:<name>` and
/// `column:<table>.<column>` entries. Migrations 2, 3, 6 and 7 only change
/// data.
const Map<int, List<String>> _additions = <int, List<String>>{
  1: <String>[
    'table:mutation_queues',
    'column:mutation_queues.uid',
    'column:mutation_queues.last_acknowledged_batch_id',
    'column:mutation_queues.last_stream_token',
    'table:mutations',
    'column:mutations.uid',
    'column:mutations.batch_id',
    'column:mutations.mutations',
    'table:document_mutations',
    'column:document_mutations.uid',
    'column:document_mutations.path',
    'column:document_mutations.batch_id',
    'table:targets',
    'column:targets.target_id',
    'column:targets.canonical_id',
    'column:targets.snapshot_version_seconds',
    'column:targets.snapshot_version_nanos',
    'column:targets.resume_token',
    'column:targets.last_listen_sequence_number',
    'column:targets.target_proto',
    'index:query_targets',
    'table:target_globals',
    'column:target_globals.highest_target_id',
    'column:target_globals.highest_listen_sequence_number',
    'column:target_globals.last_remote_snapshot_version_seconds',
    'column:target_globals.last_remote_snapshot_version_nanos',
    'table:target_documents',
    'column:target_documents.target_id',
    'column:target_documents.path',
    'index:document_targets',
    'table:remote_documents',
    'column:remote_documents.path',
    'column:remote_documents.contents',
  ],
  4: <String>['column:target_globals.target_count'],
  5: <String>['column:target_documents.sequence_number'],
  8: <String>[
    'table:collection_parents',
    'column:collection_parents.collection_id',
    'column:collection_parents.parent',
  ],
  9: <String>[
    'table:bundles',
    'column:bundles.bundle_id',
    'column:bundles.create_time_seconds',
    'column:bundles.create_time_nanos',
    'column:bundles.schema_version',
    'column:bundles.total_documents',
    'column:bundles.total_bytes',
    'table:named_queries',
    'column:named_queries.name',
    'column:named_queries.read_time_seconds',
    'column:named_queries.read_time_nanos',
    'column:named_queries.bundled_query_proto',
  ],
  10: <String>[
    'column:remote_documents.read_time_seconds',
    'column:remote_documents.read_time_nanos',
  ],
  11: <String>[
    'table:document_overlays',
    'column:document_overlays.uid',
    'column:document_overlays.collection_path',
    'column:document_overlays.document_id',
    'column:document_overlays.collection_group',
    'column:document_overlays.largest_batch_id',
    'column:document_overlays.overlay_mutation',
    'index:batch_id_overlay',
    'index:collection_group_overlay',
    'table:data_migrations',
    'column:data_migrations.migration_name',
  ],
  12: <String>['column:remote_documents.path_length'],
  13: <String>[
    'table:index_configuration',
    'column:index_configuration.index_id',
    'column:index_configuration.collection_group',
    'column:index_configuration.index_proto',
    'table:index_state',
    'column:index_state.index_id',
    'column:index_state.uid',
    'column:index_state.sequence_number',
    'column:index_state.read_time_seconds',
    'column:index_state.read_time_nanos',
    'column:index_state.document_key',
    'column:index_state.largest_batch_id',
    'table:index_entries',
    'column:index_entries.index_id',
    'column:index_entries.uid',
    'column:index_entries.array_value',
    'column:index_entries.directional_value',
    'column:index_entries.document_key',
    'index:read_time',
  ],
  14: <String>[
    'index:document_mutations_path',
    'index:index_entries_document_key',
  ],
  15: <String>[
    'table:clients',
    'column:clients.client_id',
    'column:clients.update_time_ms',
    'column:clients.network_enabled',
    'column:clients.in_foreground',
    'table:primary_client',
    'column:primary_client.id',
    'column:primary_client.owner_id',
    'column:primary_client.allow_synchronization',
    'column:primary_client.lease_timestamp_ms',
    'table:persistence_epoch',
    'column:persistence_epoch.id',
    'column:persistence_epoch.epoch',
  ],
  16: <String>['table:globals', 'column:globals.name', 'column:globals.value'],
  17: <String>['column:remote_documents.document_type'],
  18: <String>['column:mutations.client_id'],
};

Set<String> _expectedSchema(int version) => <String>{
  for (int v = 1; v <= version; v++) ...?_additions[v],
};

Future<Set<String>> _currentSchema(DatabaseMock db) async {
  final Set<String> schema = <String>{};
  final List<Map<String, dynamic>> objects = await db.query(
    "SELECT type, name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'",
  );
  for (final Map<String, dynamic> object in objects) {
    final String name = object['name'] as String;
    schema.add('${object['type']}:$name');
    if (object['type'] == 'table') {
      for (final Map<String, dynamic> column in await db.query(
        'PRAGMA table_info($name)',
      )) {
        schema.add('column:$name.${column['name']}');
      }
    }
  }
  return schema;
}

Future<bool> _tableExists(DatabaseMock db, String table) async {
  final List<Map<String, dynamic>> rows = await db.query(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
    <Object>[table],
  );
  return rows.isNotEmpty;
}

void main() {
  const String name =
      'firebase/firestore/local/sqlite_schema_migrations_test.db';
  late DatabaseMock db;
  late SQLiteSchema schema;

  setUp(() async {
    DatabaseMock.deleteDatabaseFiles(name);
    db = await DatabaseMock.create(name)
      ..renamePath = false;
    schema = SQLiteSchema(db);
  });

  tearDown(() {
    db.close();
    DatabaseMock.deleteDatabaseFiles(name);
  });

  test('createsOverlaysAndMigrationTable', () async {
    // 11 is the version that enables overlays (14 in the Android SDK).
    await schema.runMigrations(0, 11);
    expect(await _tableExists(db, 'document_overlays'), isTrue);
    expect(await _tableExists(db, 'data_migrations'), isTrue);

    final List<Map<String, dynamic>> rows = await db.query(
      'SELECT * FROM data_migrations',
    );
    expect(rows, isNotEmpty);
    expect(
      rows.first['migration_name'],
      Persistence.dataMigrationBuildOverlays,
    );
  });

  test('createsGlobalsTable', () async {
    // 16 in the port, 17 in the Android SDK.
    await schema.runMigrations(0, 16);
    expect(await _tableExists(db, 'globals'), isTrue);
  });

  test('createsClientMetadataTables', () async {
    await schema.runMigrations(0, 14);
    expect(await _tableExists(db, 'clients'), isFalse);

    await schema.runMigrations(14, 15);
    expect(await _tableExists(db, 'clients'), isTrue);
    expect(await _tableExists(db, 'primary_client'), isTrue);
    expect(
      await db.query('SELECT id, epoch FROM persistence_epoch'),
      <Map<String, Object?>>[
        <String, Object?>{'id': 0, 'epoch': 0},
      ],
    );

    await db.execute('UPDATE persistence_epoch SET epoch = 7');
    await db.execute(
      'INSERT INTO clients (client_id, update_time_ms, network_enabled, '
      'in_foreground) VALUES (?, ?, ?, ?)',
      <Object>['client', 1000, 1, 0],
    );
    await db.execute(
      'INSERT INTO primary_client (id, owner_id, allow_synchronization, '
      'lease_timestamp_ms) VALUES (?, ?, ?, ?)',
      <Object>[0, 'client', 1, 1000],
    );

    // A downgrade and upgrade runs the migration again: it keeps the rows and
    // the epoch.
    await schema.runMigrations(14, 15);
    expect(
      await db.query('SELECT id, epoch FROM persistence_epoch'),
      <Map<String, Object?>>[
        <String, Object?>{'id': 0, 'epoch': 7},
      ],
    );
    expect(await db.query('SELECT client_id FROM clients'), hasLength(1));
    expect(await db.query('SELECT owner_id FROM primary_client'), hasLength(1));
  });

  test('can install schema version 1', () async {
    await schema.runMigrations(0, 1);
    expect(await _currentSchema(db), _expectedSchema(1));
  });

  for (int version = 1; version < SQLiteSchema.version; version++) {
    test('can upgrade from version $version to ${version + 1}', () async {
      await schema.runMigrations(0, version);
      expect(await _currentSchema(db), _expectedSchema(version));

      await schema.runMigrations(version, version + 1);
      expect(await _currentSchema(db), _expectedSchema(version + 1));
    });
  }

  test('the expected schema covers every migration', () {
    expect(
      _additions.keys.reduce((int a, int b) => a > b ? a : b),
      SQLiteSchema.version,
    );
  });

  group('reopening after a downgrade', () {
    final Uint8List sessionToken = Uint8List.fromList(<int>[1, 2, 3]);
    final FieldIndex index = fieldIndex(
      'coll',
      fieldsAndKinds: <Object>['a', SegmentKind.ascending],
    );

    for (
      int downgradeVersion = 0;
      downgradeVersion < SQLiteSchema.version;
      downgradeVersion++
    ) {
      test(
        'keeps the data when migrating again from $downgradeVersion',
        () async {
          final String dbName =
              'firebase/firestore/local/sqlite_schema_downgrade_$downgradeVersion.db';
          DatabaseMock.deleteDatabaseFiles(dbName);
          try {
            SQLitePersistence persistence = await createSQLitePersistence(
              dbName,
            );
            LocalStore localStore = LocalStore(
              persistence,
              User.unauthenticated,
            );
            await localStore.start();
            await persistence.runTransaction('add document', () async {
              await persistence.remoteDocumentCache.add(
                doc('coll/remote', 5, map(<dynamic>['a', 1])),
                version(5),
              );
            });
            await localStore.writeLocally(<SetMutation>[
              setMutation('coll/local', <String, Object?>{'a': 2}),
            ]);
            final QueryData target = await localStore.allocateTarget(
              query('coll').toTarget(),
            );
            await localStore.configureFieldIndexes(<FieldIndex>[index]);
            await localStore.setSessionToken(sessionToken);
            (persistence.database as DatabaseMock).renamePath = false;
            await persistence.shutdown();

            // An older SDK opens the file: the opener stores its lower version
            // and keeps the data.
            final DatabaseMock raw = await DatabaseMock.create(dbName)
              ..renamePath = false;
            await raw.execute('PRAGMA user_version = $downgradeVersion');
            raw.close();

            persistence = await createSQLitePersistence(dbName);
            localStore = LocalStore(persistence, User.unauthenticated);
            await localStore.start();
            try {
              expect(
                await localStore.readDocument(key('coll/remote')),
                doc('coll/remote', 5, map(<dynamic>['a', 1])),
              );
              expect(
                await localStore.readDocument(key('coll/local')),
                doc(
                  'coll/local',
                  0,
                  map(<dynamic>['a', 2]),
                  DocumentState.localMutations,
                ),
              );
              expect(await localStore.getNextMutationBatch(-1), isNotNull);
              expect(
                localStore
                    .getFieldIndexes()
                    .map((FieldIndex i) => i.collectionGroup)
                    .toList(),
                <String>['coll'],
              );
              expect(await localStore.getSessionToken(), sessionToken);

              // The migrations that ran again did not duplicate any row, and
              // the overlays were built again from the mutation queue.
              final Database database = persistence.database;
              expect(
                await database.query(
                  'SELECT target_id, path FROM target_documents '
                  'GROUP BY target_id, path HAVING COUNT(*) > 1',
                ),
                isEmpty,
              );
              expect(
                await database.query(
                  "SELECT 1 FROM document_overlays WHERE document_id = 'local'",
                ),
                hasLength(1),
              );
              expect(
                await database.query('SELECT * FROM data_migrations'),
                isEmpty,
              );

              // Migration 3 drops the query cache of a version 1 or 2 file.
              final QueryData? cached = await persistence
                  .runTransactionAndReturn(
                    'read target',
                    () => persistence.queryCache.getQueryData(
                      query('coll').toTarget(),
                    ),
                  );
              if (downgradeVersion == 1 || downgradeVersion == 2) {
                expect(cached, isNull);
              } else {
                expect(cached?.targetId, target.targetId);
              }

              final List<Map<String, dynamic>> stored = await persistence
                  .database
                  .query('PRAGMA user_version');
              expect(stored.single.values.single, SQLiteSchema.version);
            } finally {
              await persistence.shutdown();
            }
          } finally {
            DatabaseMock.deleteDatabaseFiles(dbName);
          }
        },
      );
    }
  });
}
