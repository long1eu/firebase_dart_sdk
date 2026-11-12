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

// End to end upgrade paths of the read time (schema 10) and overlay (schema 11) migrations:
//   * a schema 9 database with pending mutations of several users (sets, merges, updates, deletes, transforms): after
//     the upgrade the local view is the one the pre-overlay engine computed (the mutation queue replayed on the
//     remote documents);
//   * a database with a downgrade-then-upgrade history, during which the schema 9 SDK changed the cache;
//   * interrupted migrations (between or inside the schema steps, and during the overlay data migration).
//
// The schema 9 database is written with SQL, the way the schema 9 SDK stored its data.

import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/field_value.dart'
    as firestore;
import 'package:cloud_firestore_dart/src/firebase/firestore/local/encoded_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_view_changes.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_overlay_migration_manager.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/patch_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_event.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/target_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/user_data_converter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/database.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:test/test.dart';

import '../../../../util/test_util.dart';
import 'mock/database_mock.dart';
import 'persistence_test_helpers.dart';

const String _name = 'firebase/firestore/local/overlay_upgrade_path_test.db';
final DatabaseId _databaseId = DatabaseId.forProject('projectId');
final LocalSerializer _serializer =
    LocalSerializer(RemoteSerializer(_databaseId));
final UserDataConverter _converter = UserDataConverter(_databaseId);

const User _alice = User('alice');
const User _bob = User('bob');
const List<User> _users = <User>[User.unauthenticated, _alice, _bob];

Mutation _update(String path, Map<String, Object?> data) => _converter
    .parseUpdateData(data)
    .toMutation(key(path), Precondition(exists: true));

Mutation _set(String path, Map<String, Object?> data) =>
    _converter.parseSetData(data).toMutation(key(path), Precondition.none);

Mutation _merge(String path, Map<String, Object?> data) => _converter
    .parseMergeData(data, null)
    .toMutation(key(path), Precondition.none);

/// The local view of [key] as the pre-overlay engine computed it: the batches of the mutation queue replayed, in
/// order, on the remote document.
MaybeDocument? _replay(
    DocumentKey key, MaybeDocument? remote, List<MutationBatch> batches) {
  MaybeDocument? document = remote;
  for (final MutationBatch batch in batches) {
    document = batch.applyToLocalView(key, document);
  }
  return document;
}

/// The content of a cache as the schema 9 SDK wrote it: remote documents and the mutation queues of the users.
class _LegacyData {
  final Map<DocumentKey, MaybeDocument> remoteDocuments =
      <DocumentKey, MaybeDocument>{};
  final Map<User, List<MutationBatch>> queues = <User, List<MutationBatch>>{};
  int _nextBatchId = 1;

  void remote(MaybeDocument document) {
    remoteDocuments[document.key] = document;
  }

  /// Adds a batch the way the pre-overlay `LocalStore.writeLocally` did, including the base mutations of
  /// non-idempotent transforms.
  MutationBatch write(User user, List<Mutation> mutations) {
    final List<MutationBatch> queue =
        queues.putIfAbsent(user, () => <MutationBatch>[]);
    final List<Mutation> baseMutations = <Mutation>[];
    for (final Mutation mutation in mutations) {
      final ObjectValue? baseValue = mutation.extractTransformBaseValue(
          _replay(mutation.key, remoteDocuments[mutation.key], queue));
      if (baseValue != null) {
        baseMutations.add(PatchMutation(mutation.key, baseValue,
            baseValue.fieldMask, Precondition(exists: true)));
      }
    }
    final MutationBatch batch = MutationBatch(
      batchId: _nextBatchId++,
      localWriteTime: Timestamp(1700000000 + _nextBatchId, 0),
      baseMutations: baseMutations,
      mutations: mutations,
    );
    queue.add(batch);
    return batch;
  }

  Set<DocumentKey> get allKeys => <DocumentKey>{
        ...remoteDocuments.keys,
        for (final List<MutationBatch> queue in queues.values)
          for (final MutationBatch batch in queue) ...batch.keys,
      };

  MaybeDocument? expectedView(User user, DocumentKey key) => _replay(
      key, remoteDocuments[key], queues[user] ?? const <MutationBatch>[]);

  /// Writes the data into [db] with the statements of the schema 9 SDK (no read time, no overlays).
  Future<void> writeTo(Database db) async {
    for (final MaybeDocument document in remoteDocuments.values) {
      await writeRemoteDocument(db, document);
    }
    for (final MapEntry<User, List<MutationBatch>> entry in queues.entries) {
      final String uid = entry.key.uid ?? '';
      await db.execute(
          'INSERT OR REPLACE INTO mutation_queues (uid, last_acknowledged_batch_id, last_stream_token) VALUES (?, ?, ?)',
          <Object>[uid, -1, Uint8List(0)]);
      for (final MutationBatch batch in entry.value) {
        await writeBatch(db, uid, batch);
      }
    }
  }

  static Future<void> writeRemoteDocument(
      Database db, MaybeDocument document) async {
    final String path = EncodedPath.encode(document.key.path);
    await db.execute(
        'INSERT OR REPLACE INTO remote_documents (path, contents) VALUES (?, ?)',
        <Object>[
          path,
          _serializer.encodeMaybeDocument(document).writeToBuffer()
        ]);
    await db.execute(
        'INSERT OR REPLACE INTO target_documents (target_id, path, sequence_number) VALUES (0, ?, 1)',
        <Object>[path]);
    await db.execute(
        'INSERT OR REPLACE INTO collection_parents (collection_id, parent) VALUES (?, ?)',
        <Object>[
          document.key.path.popLast().getLastSegment(),
          EncodedPath.encode(document.key.path.popLast().popLast())
        ]);
  }

  static Future<void> writeBatch(
      Database db, String uid, MutationBatch batch) async {
    await db.execute(
        'INSERT INTO mutations (uid, batch_id, mutations) VALUES (?, ?, ?)',
        <Object>[
          uid,
          batch.batchId,
          _serializer.encodeMutationBatch(batch).writeToBuffer()
        ]);
    for (final DocumentKey key in batch.keys) {
      await db.execute(
          'INSERT INTO document_mutations (uid, path, batch_id) VALUES (?, ?, ?)',
          <Object>[uid, EncodedPath.encode(key.path), batch.batchId]);
    }
  }

  static Future<void> removeBatch(Database db, String uid, int batchId) async {
    await db.execute('DELETE FROM mutations WHERE uid = ? AND batch_id = ?',
        <Object>[uid, batchId]);
    await db.execute(
        'DELETE FROM document_mutations WHERE uid = ? AND batch_id = ?',
        <Object>[uid, batchId]);
  }
}

/// Pending writes of three users that cover every kind of mutation and overlay.
_LegacyData _legacyData() {
  final _LegacyData data = _LegacyData()
    ..remote(doc('rooms/set', 3, map(<dynamic>['a', 1, 'b', 2])))
    ..remote(doc(
        'rooms/update',
        4,
        map(<dynamic>[
          'a',
          1,
          'nested',
          map(<dynamic>['x', 1, 'y', 2])
        ])))
    ..remote(doc('rooms/delete', 5, map(<dynamic>['a', 1])))
    ..remote(doc(
        'rooms/counter',
        6,
        map(<dynamic>[
          'count',
          5,
          'tags',
          <String>['a']
        ])))
    ..remote(doc('rooms/untouched', 7, map(<dynamic>['a', 1])))
    ..remote(deletedDoc('rooms/deletedRemotely', 8))
    ..remote(doc('rooms/set/messages/m1', 9, map(<dynamic>['text', 'hi'])));

  // Unauthenticated user.
  data
    ..write(User.unauthenticated, <Mutation>[
      _set('rooms/set', map(<dynamic>['c', 3])),
    ])
    ..write(User.unauthenticated, <Mutation>[
      _update('rooms/update', <String, Object?>{
        'a': 2,
        'nested.x': firestore.FieldValue.delete(),
      }),
      _update('rooms/missing', <String, Object?>{'never': 'applied'}),
    ])
    ..write(User.unauthenticated, <Mutation>[deleteMutation('rooms/delete')])
    ..write(User.unauthenticated, <Mutation>[
      _update('rooms/counter', <String, Object?>{
        'count': firestore.FieldValue.increment(2),
        'tags': firestore.FieldValue.arrayUnion(<Object?>['b']),
        'updated': firestore.FieldValue.serverTimestamp(),
      }),
    ])
    ..write(User.unauthenticated, <Mutation>[
      _update('rooms/counter',
          <String, Object?>{'count': firestore.FieldValue.increment(10)}),
      _merge('rooms/new', <String, Object?>{
        'created': firestore.FieldValue.serverTimestamp(),
        'n': 1,
      }),
      _merge('rooms/deletedRemotely', <String, Object?>{'back': true}),
      _update('rooms/set/messages/m1', <String, Object?>{'text': 'edited'}),
    ]);

  // Alice: several batches on the same documents, delete then recreate.
  data
    ..write(_alice, <Mutation>[deleteMutation('rooms/set')])
    ..write(_alice, <Mutation>[
      _merge('rooms/set', <String, Object?>{'again': true}),
      _update('rooms/update', <String, Object?>{'nested.z': 3}),
    ])
    ..write(_alice, <Mutation>[
      _update('rooms/update', <String, Object?>{
        'nested.z': firestore.FieldValue.delete(),
        'a': firestore.FieldValue.increment(1.5),
      }),
      _set('rooms/aliceOnly', <String, Object?>{
        'list': firestore.FieldValue.arrayUnion(<Object?>[1, 2]),
      }),
      _merge('rooms/untouched', <String, Object?>{}),
    ])
    ..write(_alice, <Mutation>[
      _set('rooms/aliceOnly', map(<dynamic>['replaced', true])),
      deleteMutation('rooms/counter'),
    ]);

  // Bob: writes that do not apply, and a delete of a document that is not cached.
  data
    ..write(_bob, <Mutation>[
      _update('rooms/deletedRemotely', <String, Object?>{'no': 'effect'}),
      deleteMutation('rooms/unknown'),
    ])
    ..write(_bob, <Mutation>[
      _update('rooms/delete', <String, Object?>{
        'a': firestore.FieldValue.arrayRemove(<Object?>[1]),
        'stamp': firestore.FieldValue.serverTimestamp(),
      }),
    ]);
  return data;
}

/// Makes every statement fail once [shouldFail] returns true for one, as if the process was gone.
class _DyingDatabase extends Database {
  _DyingDatabase(this._delegate, this._shouldFail);

  final DatabaseMock _delegate;
  final bool Function(String statement) _shouldFail;
  bool dead = false;

  void _check(String statement) {
    if (dead || _shouldFail(statement)) {
      dead = true;
      throw StateError('The process died at: $statement');
    }
  }

  @override
  String get path => _delegate.path;

  @override
  Future<void> execute(String statement, [List<Object?>? arguments]) {
    _check(statement);
    return _delegate.execute(statement, arguments);
  }

  @override
  Future<List<Map<String, dynamic>>> query(String statement,
      [List<Object?>? arguments]) {
    _check(statement);
    return _delegate.query(statement, arguments);
  }

  @override
  Future<int> delete(String statement, [List<Object?>? arguments]) {
    _check(statement);
    return _delegate.delete(statement, arguments);
  }

  /// Closes the connection without commit or rollback, as the operating system does for a killed process.
  @override
  void close() => _delegate.close();
}

void main() {
  SQLitePersistence? persistence;

  Future<DatabaseMock> openRaw() async {
    return await DatabaseMock.create(_name)
      ..renamePath = false;
  }

  /// Creates a schema 9 database that holds [data].
  Future<void> createLegacyDatabase(_LegacyData data) async {
    final DatabaseMock db = await openRaw();
    await SQLiteSchema(db).runMigrations(0, 9);
    await db.execute('PRAGMA user_version = 9');
    await data.writeTo(db);
    db.close();
  }

  Future<SQLitePersistence> open() async {
    final SQLitePersistence opened = await createSQLitePersistence(_name);
    (opened.database as DatabaseMock).renamePath = false;
    return persistence = opened;
  }

  /// Opens the database through a connection that dies at the first statement [shouldFail] accepts.
  Future<SQLitePersistence> createDying(
      bool Function(String statement) shouldFail) {
    return SQLitePersistence.create(
      _name,
      _databaseId,
      _serializer,
      (String path,
          {int? version,
          OnConfigure? onConfigure,
          OnCreate? onCreate,
          OnVersionChange? onUpgrade,
          OnVersionChange? onDowngrade,
          OnOpen? onOpen}) async {
        // The file holds a schema 9 database; open it as such and run the upgrade through the dying connection.
        final DatabaseMock mock = await DatabaseMock.create(_name,
            version: 9, onConfigure: onConfigure);
        mock.renamePath = false;
        final _DyingDatabase dying = _DyingDatabase(mock, shouldFail);
        try {
          await onUpgrade!(dying, 9, version!);
          await mock.execute('PRAGMA user_version = $version');
        } catch (_) {
          // The version is not stored: the next open runs the migrations again.
          mock.close();
          rethrow;
        }
        await onOpen?.call(dying);
        return dying;
      },
      const LruGarbageCollectorParams(),
    );
  }

  /// Checks that every user sees the view the pre-overlay engine computed for [data], by key and by query.
  Future<void> expectLegacyView(
      SQLitePersistence opened, _LegacyData data) async {
    final LocalStore store = LocalStore(opened, User.unauthenticated);
    await store.start();
    expect(
        await (opened.overlayMigrationManager as SQLiteOverlayMigrationManager)
            .hasPendingOverlayMigration(),
        isFalse);

    for (final User user in _users) {
      await store.handleUserChange(user);
      final Map<DocumentKey, Document> expectedRooms =
          <DocumentKey, Document>{};
      for (final DocumentKey documentKey in data.allKeys) {
        final MaybeDocument? expected = data.expectedView(user, documentKey);
        expect(await store.readDocument(documentKey), expected,
            reason: 'user ${user.uid}, document $documentKey');
        if (expected is Document && documentKey.path.length == 2) {
          expectedRooms[documentKey] = expected;
        }
      }

      for (final bool usePreviousResults in <bool>[true, false]) {
        final ImmutableSortedMap<DocumentKey, Document> rooms =
            (await store.executeQuery(query('rooms'), usePreviousResults))
                .documents;
        expect(<DocumentKey, Document>{
          for (final MapEntry<DocumentKey, Document> entry in rooms)
            entry.key: entry.value
        }, expectedRooms, reason: 'user ${user.uid}, query rooms');
      }

      // The mutation queue itself is untouched.
      final List<int> batchIds = <int>[];
      int last = -1;
      while (true) {
        final MutationBatch? batch = await store.getNextMutationBatch(last);
        if (batch == null) {
          break;
        }
        batchIds.add(last = batch.batchId);
      }
      expect(
          batchIds,
          (data.queues[user] ?? const <MutationBatch>[])
              .map((MutationBatch batch) => batch.batchId)
              .toList());
    }
  }

  setUp(() => DatabaseMock.deleteDatabaseFiles(_name));

  tearDown(() async {
    if (persistence != null && persistence!.started) {
      await persistence!.shutdown();
    }
    persistence = null;
    DatabaseMock.deleteDatabaseFiles(_name);
  });

  test('the fixture covers documents that exist, are deleted and are missing',
      () {
    // Guards the fixture: the expected views must contain every kind of result.
    final _LegacyData data = _legacyData();
    final List<MaybeDocument?> views = <MaybeDocument?>[
      for (final User user in _users)
        for (final DocumentKey documentKey in data.allKeys)
          data.expectedView(user, documentKey),
    ];
    expect(
        views.whereType<Document>().where((Document d) => d.hasLocalMutations),
        isNotEmpty);
    expect(
        views.whereType<Document>().where((Document d) => !d.hasLocalMutations),
        isNotEmpty);
    expect(views.where((MaybeDocument? d) => d != null && d is! Document),
        isNotEmpty);
    expect(views.where((MaybeDocument? d) => d == null), isNotEmpty);
    expect(
        views.whereType<Document>().any((Document d) => d.data.internalValue
            .any((MapEntry<String, FieldValue> e) =>
                e.value is ServerTimestampValue)),
        isTrue);
  });

  test(
      'schema 9 database with pending mutations of several users keeps its local view',
      () async {
    final _LegacyData data = _legacyData();
    await createLegacyDatabase(data);

    await expectLegacyView(await open(), data);

    // A second start does not run the data migration again and serves the same view.
    await persistence!.shutdown();
    await expectLegacyView(await open(), data);
  });

  test(
      'downgrade to schema 9 and upgrade again: no stale limbo free version, no stale overlay',
      () async {
    // 1. The current SDK syncs a query and has two pending writes.
    SQLitePersistence opened = await open();
    LocalStore store = LocalStore(opened, User.unauthenticated);
    await store.start();
    final Query matching = query('rooms').filter(filter('matches', '==', true));
    QueryData target = await store.allocateTarget(matching.toTarget());
    final Document synced =
        doc('rooms/synced', 10, map(<dynamic>['matches', true]));
    await store.applyRemoteEvent(RemoteEvent(
      documentUpdates: <DocumentKey, MaybeDocument>{
        synced.key: synced,
        key('rooms/other'):
            doc('rooms/other', 10, map(<dynamic>['matches', false])),
      },
      resolvedLimboDocuments: const <DocumentKey>{},
      snapshotVersion: version(10),
      targetChanges: <int, TargetChange>{
        target.targetId: TargetChange(
          resumeToken: resumeToken(10)!,
          current: true,
          addedDocuments: keySet(<DocumentKey>[synced.key]),
          modifiedDocuments: DocumentKey.emptyKeySet,
          removedDocuments: DocumentKey.emptyKeySet,
        ),
      },
    ));
    await store.notifyLocalViewChanges(<LocalViewChanges>[
      LocalViewChanges(target.targetId, /* fromCache= */ false,
          DocumentKey.emptyKeySet, DocumentKey.emptyKeySet),
    ]);
    await store.releaseTarget(target.targetId);
    final MutationBatch acknowledgedLater = MutationBatch(
        batchId: (await store.writeLocally(<Mutation>[
          _set('rooms/ackedByOldSdk',
              map(<dynamic>['matches', true, 'v', 'local']))
        ]))
            .batchId,
        localWriteTime: Timestamp.now(),
        baseMutations: const <Mutation>[],
        mutations: <Mutation>[
          _set('rooms/ackedByOldSdk',
              map(<dynamic>['matches', true, 'v', 'local']))
        ]);
    await store.writeLocally(<Mutation>[
      _update('rooms/synced', <String, Object?>{'edited': true})
    ]);

    final DatabaseMock rawBefore = opened.database as DatabaseMock;
    final proto.Target persisted = proto.Target.fromBuffer((await rawBefore
            .query('SELECT target_proto FROM targets WHERE target_id = ?',
                <Object>[target.targetId]))
        .first['target_proto'] as List<int>);
    expect(persisted.hasLastLimboFreeSnapshotVersion(), isTrue,
        reason: 'precondition: the limbo free version was persisted');
    expect(
        await rawBefore.query('SELECT * FROM document_overlays'), hasLength(2));
    await opened.shutdown();

    // 2. The schema 9 SDK runs on the database: it stores a document without read time that now matches the query,
    //    acknowledges the first write (the batch goes, the document is written to the cache) and adds a write.
    DatabaseMock raw = await openRaw();
    await raw.execute('PRAGMA user_version = 9');
    final Document changedByOldSdk =
        doc('rooms/other', 20, map(<dynamic>['matches', true]));
    await _LegacyData.writeRemoteDocument(raw, changedByOldSdk);
    final Document acked = doc('rooms/ackedByOldSdk', 21,
        map(<dynamic>['matches', true, 'v', 'server']));
    await _LegacyData.writeRemoteDocument(raw, acked);
    await _LegacyData.removeBatch(raw, '', acknowledgedLater.batchId);
    final MutationBatch addedByOldSdk = MutationBatch(
        batchId: 100,
        localWriteTime: Timestamp(1700000100, 0),
        baseMutations: const <Mutation>[],
        mutations: <Mutation>[
          _merge('rooms/addedByOldSdk', map(<dynamic>['matches', true]))
        ]);
    await _LegacyData.writeBatch(raw, '', addedByOldSdk);
    raw.close();

    // 3. The current SDK opens the database again.
    opened = await open();
    store = LocalStore(opened, User.unauthenticated);
    await store.start();
    target = await store.allocateTarget(matching.toTarget());
    expect(target.lastLimboFreeSnapshotVersion, SnapshotVersion.none,
        reason:
            'documents written by the old SDK have no read time, previous results cannot be trusted');

    final ImmutableSortedMap<DocumentKey, Document> result =
        (await store.executeQuery(matching, /* usePreviousResults= */ true))
            .documents;
    expect(<DocumentKey, Document>{
      for (final MapEntry<DocumentKey, Document> entry in result)
        entry.key: entry.value
    }, <DocumentKey, Document>{
      // Synced before, with the pending update that survived the downgrade.
      synced.key: doc(
          'rooms/synced',
          0,
          map(<dynamic>['matches', true, 'edited', true]),
          DocumentState.localMutations),
      // Written by the old SDK without read time.
      changedByOldSdk.key: changedByOldSdk,
      // Acknowledged by the old SDK: the overlay of the write must be gone, the server version shows.
      acked.key: acked,
      // Written by the old SDK: has an overlay now.
      key('rooms/addedByOldSdk'): doc('rooms/addedByOldSdk', 0,
          map(<dynamic>['matches', true]), DocumentState.localMutations),
    });
    expect(await store.readDocument(acked.key), acked);

    raw = opened.database as DatabaseMock;
    final List<Map<String, dynamic>> overlays = await raw.query(
        'SELECT document_id, largest_batch_id FROM document_overlays ORDER BY document_id');
    expect(
        overlays.map((Map<String, dynamic> row) => row['document_id']).toList(),
        <String>['addedByOldSdk', 'synced']);
  });

  group('interrupted migration', () {
    test('between the two read time columns of schema 10', () async {
      final _LegacyData data = _legacyData();
      await createLegacyDatabase(data);
      final DatabaseMock raw = await openRaw();
      await raw.execute(
          'ALTER TABLE remote_documents ADD COLUMN read_time_seconds INTEGER');
      raw.close();

      await expectLegacyView(await open(), data);
      expect(
          await SQLiteSchema(persistence!.database)
              .getTableColumns('remote_documents'),
          containsAll(<String>['read_time_seconds', 'read_time_nanos']));
    });

    test('after schema 10, before the version was stored', () async {
      final _LegacyData data = _legacyData();
      await createLegacyDatabase(data);
      final DatabaseMock raw = await openRaw();
      await SQLiteSchema(raw).runMigrations(9, 10);
      raw.close();

      await expectLegacyView(await open(), data);
    });

    test('between schema 10 and 11', () async {
      final _LegacyData data = _legacyData();
      await createLegacyDatabase(data);
      final DatabaseMock raw = await openRaw();
      await SQLiteSchema(raw).runMigrations(9, 10);
      await raw.execute('PRAGMA user_version = 10');
      raw.close();

      await expectLegacyView(await open(), data);
    });

    test('inside schema 11, after the overlay table was created', () async {
      final _LegacyData data = _legacyData();
      await createLegacyDatabase(data);
      final DatabaseMock raw = await openRaw();
      await SQLiteSchema(raw).runMigrations(9, 10);
      // The first statement of migration 11; the indexes, the data migration table and its entry are missing.
      await raw.execute('''
        CREATE TABLE document_overlays (
          uid TEXT, collection_path TEXT, document_id TEXT, collection_group TEXT,
          largest_batch_id INTEGER, overlay_mutation BLOB,
          PRIMARY KEY (uid, collection_path, document_id))''');
      raw.close();

      await expectLegacyView(await open(), data);
      final List<
          Map<String,
              dynamic>> indexes = await persistence!.database.query(
          "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'document_overlays'");
      expect(
          indexes.map((Map<String, dynamic> row) => row['name']),
          containsAll(
              <String>['batch_id_overlay', 'collection_group_overlay']));
    });

    test('process dies while the overlays are built', () async {
      final _LegacyData data = _legacyData();
      await createLegacyDatabase(data);

      // The connection dies at the fifth overlay the data migration writes.
      int overlayWrites = 0;
      final SQLitePersistence dying = await createDying((String statement) =>
          statement.contains('INTO document_overlays') && ++overlayWrites == 5);
      await dying.start();
      await expectLater(
          LocalStore(dying, User.unauthenticated).start(), throwsStateError);
      expect(overlayWrites, 5);
      await dying.shutdown();

      // Nothing of the half built overlays is visible and the migration is still pending.
      final DatabaseMock raw = await openRaw();
      expect(await raw.query('SELECT * FROM document_overlays'), isEmpty);
      expect(await raw.query('SELECT * FROM data_migrations'), hasLength(1));
      raw.close();

      await expectLegacyView(await open(), data);
    });

    test('process dies during the schema migration', () async {
      final _LegacyData data = _legacyData();
      await createLegacyDatabase(data);

      // The connection dies when migration 11 creates the first index (after the table).
      final SQLitePersistence dying = await createDying(
          (String statement) => statement.contains('CREATE INDEX'));
      await expectLater(dying.start(), throwsStateError);

      await expectLegacyView(await open(), data);
    });
  });
}
