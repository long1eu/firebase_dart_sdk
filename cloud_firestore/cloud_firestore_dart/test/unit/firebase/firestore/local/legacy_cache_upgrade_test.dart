// A cache written by the last version published as cloud_firestore_vm (0.0.7,
// schema 8) opens with the current code, is migrated to the current schema
// and keeps its data: cached documents, targets, the mutation queue with a
// pending batch that has legacy transform writes, and the collection parents.
//
// The schema-8 database is test/res/legacy/cloud_firestore_vm_0.0.7_schema8.db.
// legacy/schema8_fixture.dart documents how it was produced and builds it;
// regenerate the file with
//
//     UPDATE_GOLDEN=1 dart test test/unit/firebase/firestore/local/legacy_cache_upgrade_test.dart
//
// Nothing here names the current schema version: the tests go up to
// `SQLiteSchema.version`, so a new migration is covered when it is added.

import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/delete_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/patch_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/set_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/no_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/database.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:rxdart/subjects.dart';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:test/test.dart';

import '../../../../util/sqlite3_library.dart';
import '../../../../util/test_util.dart';
import '../remote/mock_datastore.dart';
import '../remote/remote_store_test.dart' show MockRemoteStoreCallback;
import 'legacy/schema8_fixture.dart';
import 'mock/database_mock.dart';

const String fixturePath =
    'test/res/legacy/cloud_firestore_vm_0.0.7_schema8.db';

/// Every row of every table of the database at [path], for comparing two
/// database files by content (the bytes of a SQLite file depend on the SQLite
/// version that wrote it).
Map<String, List<String>> dump(String path) {
  final sql.Database db = nativeSqlite3.open(path, mode: sql.OpenMode.readOnly);
  try {
    final Map<String, List<String>> result = <String, List<String>>{
      'user_version': <String>['${db.userVersion}'],
      'schema': <String>[
        for (final sql.Row row in db.select(
            'SELECT type, name, sql FROM sqlite_master ORDER BY type, name'))
          '${row['type']} ${row['name']}: '
              '${'${row['sql']}'.replaceAll(RegExp(r'\s+'), ' ')}',
      ],
    };
    for (final sql.Row table in db.select(
        "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name")) {
      final String name = table['name'] as String;
      result[name] = <String>[
        for (final sql.Row row in db.select('SELECT * FROM $name'))
          row.values.toString(),
      ]..sort();
    }
    return result;
  } finally {
    db.dispose();
  }
}

/// Writes a fresh schema-8 database to [file].
Future<void> generate(File file) async {
  if (file.existsSync()) {
    file.deleteSync();
  }
  file.parent.createSync(recursive: true);
  final sql.Database raw = nativeSqlite3.open(file.path);
  try {
    await buildSchema8Database(_RawDatabase(raw, file.path));
    raw.userVersion = legacySchemaVersion;
  } finally {
    raw.dispose();
  }
}

class _RawDatabase implements Database {
  _RawDatabase(this._db, this.path);

  final sql.Database _db;

  @override
  final String path;

  @override
  Future<void> execute(String statement, [List<Object?>? arguments]) async =>
      _db.execute(statement, arguments ?? const <Object?>[]);

  @override
  Future<List<Map<String, dynamic>>> query(String statement,
          [List<Object?>? arguments]) async =>
      _db
          .select(statement, arguments ?? const <Object?>[])
          .map(Map<String, dynamic>.of)
          .toList();

  @override
  Future<int> delete(String statement, [List<Object?>? arguments]) async {
    _db.execute(statement, arguments ?? const <Object?>[]);
    return _db.updatedRows;
  }

  @override
  void close() => _db.dispose();
}

int _counter = 0;

/// The file each persistence of [openCopy] works on.
final Map<SQLitePersistence, File> _files = <SQLitePersistence, File>{};

/// Opens a copy of the database file [source] with the current
/// [SQLitePersistence], through an opener that follows the `OpenDatabase`
/// contract (so the migrations run in `onUpgrade`).
Future<SQLitePersistence> openCopy(File source, String label) async {
  final String name = 'firebase/firestore/local/legacy_${label}_'
      '${DateTime.now().microsecondsSinceEpoch}_${_counter++}.db';
  DatabaseMock.deleteDatabaseFiles(name);
  final File copy = DatabaseMock.pathForName(name)
    ..parent.createSync(recursive: true);
  source.copySync(copy.path);

  final DatabaseId databaseId = DatabaseId.forProject(legacyProjectId);
  final SQLitePersistence persistence = await SQLitePersistence.create(
    'legacy',
    databaseId,
    LocalSerializer(RemoteSerializer(databaseId)),
    (String path,
        {int? version,
        OnConfigure? onConfigure,
        OnCreate? onCreate,
        OnVersionChange? onUpgrade,
        OnVersionChange? onDowngrade,
        OnOpen? onOpen}) async {
      final DatabaseMock db = await DatabaseMock.create(name,
          version: version,
          onConfigure: onConfigure,
          onCreate: onCreate,
          onUpgrade: onUpgrade,
          onDowngrade: onDowngrade,
          onOpen: onOpen);
      return db..renamePath = false;
    },
    const LruGarbageCollectorParams(),
  );
  await persistence.start();
  _files[persistence] = copy;
  addTearDown(() async {
    _files.remove(persistence);
    if (persistence.started) {
      await persistence.shutdown();
    }
    DatabaseMock.deleteDatabaseFiles(name);
  });
  return persistence;
}

Future<int> userVersion(SQLitePersistence persistence) async {
  final List<Map<String, dynamic>> rows =
      await persistence.query('PRAGMA user_version');
  return rows.single.values.single as int;
}

/// Acknowledges written batches in the local store, like the sync engine.
class _AcknowledgingCallback extends MockRemoteStoreCallback {
  _AcknowledgingCallback(this.localStore);

  final LocalStore localStore;
  final List<int> acknowledged = <int>[];

  @override
  Future<void> handleSuccessfulWrite(
      MutationBatchResult successfulWrite) async {
    await localStore.acknowledgeBatch(successfulWrite);
    acknowledged.add(successfulWrite.batch.batchId);
  }
}

Map<String, Object?> data(MaybeDocument? document) =>
    (document! as Document).data.value;

void main() {
  final File fixture = File(fixturePath);

  test('the committed schema 8 database is what the builder produces',
      () async {
    if (Platform.environment['UPDATE_GOLDEN'] == '1') {
      await generate(fixture);
      return;
    }
    expect(fixture.existsSync(), isTrue,
        reason: 'Missing $fixturePath. Run with UPDATE_GOLDEN=1.');

    final File fresh = DatabaseMock.pathForName(
        'firebase/firestore/local/legacy_fresh_schema8.db');
    await generate(fresh);
    addTearDown(fresh.deleteSync);

    expect(dump(fixture.path), dump(fresh.path));
    expect(dump(fixture.path)['user_version'], <String>['8']);
  });

  test('the current code creates the same schema 8 tables', () async {
    // The builder copies the DDL of 0.0.7; the migrations of the current code
    // up to version 8 must still produce exactly those tables and columns.
    final File current = DatabaseMock.pathForName(
        'firebase/firestore/local/legacy_current_schema8.db');
    if (current.existsSync()) {
      current.deleteSync();
    }
    current.parent.createSync(recursive: true);
    final sql.Database raw = nativeSqlite3.open(current.path);
    await SQLiteSchema(_RawDatabase(raw, current.path))
        .runMigrations(0, legacySchemaVersion);
    raw.dispose();
    addTearDown(current.deleteSync);

    Map<String, Set<String>> columns(String path) {
      final sql.Database db =
          nativeSqlite3.open(path, mode: sql.OpenMode.readOnly);
      try {
        return <String, Set<String>>{
          for (final sql.Row table in db.select(
              "SELECT name FROM sqlite_master WHERE type IN ('table', 'index') "
              "AND name NOT LIKE 'sqlite_%'"))
            table['name'] as String: <String>{
              for (final sql.Row column
                  in db.select('PRAGMA table_info(${table['name']})'))
                '${column['name']} ${column['type']} pk=${column['pk']}',
            },
        };
      } finally {
        db.dispose();
      }
    }

    expect(columns(fixture.path), columns(current.path));
  });

  group('a cache written by cloud_firestore_vm 0.0.7', () {
    late SQLitePersistence persistence;
    late LocalStore localStore;

    setUp(() async {
      persistence = await openCopy(fixture, 'upgrade');
      localStore = LocalStore(persistence, User.unauthenticated);
      await localStore.start();
    });

    test('is migrated to the current schema version', () async {
      expect(SQLiteSchema.version, greaterThan(legacySchemaVersion));
      expect(await userVersion(persistence), SQLiteSchema.version);
    });

    test('keeps its remote documents', () async {
      // readDocument applies the pending batch; the remote document cache has
      // what the backend sent.
      Future<MaybeDocument?> remote(String path) =>
          persistence.runTransactionAndReturn<MaybeDocument?>('read remote',
              () => persistence.remoteDocumentCache.get(key(path)));

      expect(data(await remote('rooms/eros')),
          <String, Object?>{'name': 'Eros', 'members': 3});
      expect(data(await remote('rooms/hades')),
          <String, Object?>{'name': 'Hades', 'members': 10});
      expect(data(await remote('rooms/eros/messages/1')),
          <String, Object?>{'text': 'hi'});
      expect((await remote('rooms/eros'))!.version.timestamp,
          Timestamp(1586000100, 0));
      expect(await remote('rooms/gone'), isA<NoDocument>());
      expect(await remote('rooms/missing'), isNull);
    });

    test('keeps the pending batch, with the transform writes folded in',
        () async {
      final MutationBatch? batch = await localStore.getNextMutationBatch(-1);
      expect(batch, isNotNull);
      expect(batch!.batchId, legacyBatchId);
      expect(batch.localWriteTime, Timestamp(1586000400, 5000));
      expect(await localStore.getNextMutationBatch(legacyBatchId), isNull);
      expect(localStore.lastStreamToken, legacyStreamToken);

      // set + transform, patch + transform, delete: five writes in 0.0.7,
      // three mutations now.
      expect(batch.mutations.map((Mutation m) => m.runtimeType),
          <Type>[SetMutation, PatchMutation, DeleteMutation]);
      expect(batch.mutations.map((Mutation m) => m.key.path.toString()),
          legacyMutatedPaths);

      final SetMutation set = batch.mutations[0] as SetMutation;
      expect(set.value.value, <String, Object?>{'name': 'Eros II'});
      expect(set.fieldTransforms.single.fieldPath, field('updatedAt'));

      final PatchMutation patch = batch.mutations[1] as PatchMutation;
      expect(patch.mask.mask, isEmpty);
      expect(patch.fieldTransforms.single.fieldPath, field('members'));

      expect(batch.baseMutations.single, isA<PatchMutation>());
    });

    test('shows the documents with the pending batch applied', () async {
      final Map<String, Object?> eros =
          data(await localStore.readDocument(key('rooms/eros')));
      expect(eros['name'], 'Eros II');
      expect(eros.containsKey('members'), isFalse);
      // The local estimate of the server timestamp is the local write time.
      expect(eros.containsKey('updatedAt'), isTrue);

      expect(data(await localStore.readDocument(key('rooms/hades'))),
          <String, Object?>{'name': 'Hades', 'members': 11});
      expect(
          await localStore.readDocument(key('rooms/gone')), isA<NoDocument>());
    });

    test('answers queries from the cache', () async {
      // With and without the results of previous executions (the old targets
      // have none of the data newer versions keep for that), the answer has
      // to be the same.
      Future<List<String>> ids(Query q) async {
        final List<List<String>> results = <List<String>>[];
        for (final bool usePreviousResults in <bool>[true, false]) {
          final ImmutableSortedMap<DocumentKey, Document> docs =
              (await localStore.executeQuery(q, usePreviousResults)).documents;
          results.add(<String>[
            for (final MapEntry<DocumentKey, Document> entry in docs)
              entry.key.path.toString(),
          ]);
        }
        expect(results[0], results[1]);
        return results[0];
      }

      expect(await ids(query('rooms')), <String>['rooms/eros', 'rooms/hades']);
      expect(await ids(query('rooms').filter(filter('members', '>', 5))),
          <String>['rooms/hades']);
      expect(await ids(query('rooms/eros/messages')),
          <String>['rooms/eros/messages/1']);
      // Collection group queries need the collection parents index, for a
      // subcollection and for a root collection (whose parent is the empty
      // path).
      expect(await ids(Query(path(''), collectionGroup: 'messages')),
          <String>['rooms/eros/messages/1']);
      expect(await ids(Query(path(''), collectionGroup: 'rooms')),
          <String>['rooms/eros', 'rooms/hades']);
    });

    test('reuses its targets: their canonical ids are migrated', () async {
      final Map<int, Query> queries = <int, Query>{
        2: query('rooms'),
        4: query('rooms')
            .filter(filter('members', '>', 5))
            .orderBy(orderBy('members', 'desc'))
            .limitToFirst(10),
        6: query('rooms/eros'),
        8: Query(path(''), collectionGroup: 'messages'),
      };

      for (final LegacyTarget legacy in legacyTargets) {
        final Query q = queries[legacy.targetId]!;
        // 0.0.7 stored ids in another format (filters with spaces, order bys
        // without a separator). Schema migration 19 computed the ids of the
        // stored targets again...
        if (legacy.targetId == 4) {
          expect(
            legacy.canonicalId,
            'rooms|f:members > 5|ob:membersdesc__name__desc|l:10',
          );
          expect(
            q.toTarget().canonicalId,
            'rooms|f:members>5|ob:membersdesc,__name__desc|l:10',
          );
        }

        // ...so listening to the query again finds the stored target, with
        // its id and resume token, instead of allocating a new one.
        final QueryData queryData =
            await localStore.allocateTarget(q.toTarget());
        expect(queryData.targetId, legacy.targetId);
        expect(queryData.resumeToken,
            Uint8List.fromList('resume-${legacy.targetId}'.codeUnits));
        expect(queryData.snapshotVersion.timestamp, Timestamp(1586000300, 0));
        expect(queryData.target, q.toTarget());

        final ImmutableSortedSet<DocumentKey> keys =
            await localStore.getRemoteDocumentKeys(legacy.targetId);
        expect(keys.map((DocumentKey k) => k.path.toString()).toSet(),
            legacy.documents.toSet());
      }

      // A new query gets an id after the highest one of the old cache.
      final QueryData fresh =
          await localStore.allocateTarget(query('other').toTarget());
      expect(fresh.targetId, greaterThan(legacyTargets.last.targetId));
      expect(localStore.getLastRemoteSnapshotVersion().timestamp,
          Timestamp(legacyLastRemoteSnapshotSeconds, 0));
    });

    test('sends the pending batch to the backend and applies the ack',
        () async {
      final TaskScheduler scheduler = TaskScheduler('');
      final MockDatastore datastore = MockDatastore(scheduler);
      final BehaviorSubject<bool> onNetworkConnected =
          BehaviorSubject<bool>.seeded(true);
      final _AcknowledgingCallback callback =
          _AcknowledgingCallback(localStore);
      final RemoteStore remoteStore = RemoteStore(
          callback, localStore, datastore, onNetworkConnected, scheduler);
      await remoteStore.start();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // One write request with the three mutations of the batch.
      expect(datastore.writesSent, 1);
      final List<Mutation> sent = datastore.waitForWriteSend();
      expect(sent.map((Mutation m) => m.runtimeType),
          <Type>[SetMutation, PatchMutation, DeleteMutation]);
      expect(sent[0].fieldTransforms, hasLength(1));
      expect(sent[1].fieldTransforms, hasLength(1));

      // The backend acknowledges: one result per mutation, with the transform
      // results.
      final Timestamp serverTime = Timestamp(1700000000, 0);
      await datastore.ackWrite(version(1700000000000000), <MutationResult>[
        MutationResult(version(1700000000000000),
            <FieldValue>[TimestampValue.valueOf(serverTime)]),
        MutationResult(
            version(1700000000000000), <FieldValue>[IntegerValue.valueOf(11)]),
        MutationResult(version(1700000000000000)),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(callback.acknowledged, <int>[legacyBatchId]);
      expect(await localStore.getNextMutationBatch(-1), isNull);
      expect(await persistence.query('SELECT batch_id FROM document_mutations'),
          isEmpty);

      // The acknowledged values are in the cache until the watch stream
      // delivers the documents.
      final Map<String, Object?> eros =
          data(await localStore.readDocument(key('rooms/eros')));
      expect(eros['name'], 'Eros II');
      expect(eros['updatedAt'], serverTime);
      expect(data(await localStore.readDocument(key('rooms/hades')))['members'],
          11);

      await remoteStore.shutdown();
      await onNetworkConnected.close();
    });

    test('can be closed and opened again', () async {
      await localStore
          .writeLocally(<Mutation>[setMutation('rooms/new', map())]);
      await persistence.shutdown();

      // Open the migrated file once more: no migration left to run.
      final SQLitePersistence again =
          await openCopy(_files[persistence]!, 'reopen');
      expect(await userVersion(again), SQLiteSchema.version);
      final LocalStore store = LocalStore(again, User.unauthenticated);
      await store.start();
      expect(data(await store.readDocument(key('rooms/hades')))['members'], 11);
      expect(await store.readDocument(key('rooms/new')), isA<Document>());
      expect((await store.getNextMutationBatch(legacyBatchId))!.batchId,
          legacyBatchId + 1);
    });
  });

  group('a cache at an intermediate schema version', () {
    // A database as the current code creates it at version `from`, with the
    // rows of the schema 8 fixture that fit the tables of that version, is
    // opened and migrated to the current version. Versions above 8 never
    // shipped in a release before 0.1.0, but a development build may have
    // left such a file.
    for (int from = 1; from < SQLiteSchema.version; from++) {
      test('migrates from version $from to ${SQLiteSchema.version}', () async {
        final File source = DatabaseMock.pathForName(
            'firebase/firestore/local/legacy_intermediate_$from.db');
        if (source.existsSync()) {
          source.deleteSync();
        }
        source.parent.createSync(recursive: true);
        final sql.Database raw = nativeSqlite3.open(source.path);
        final _RawDatabase db = _RawDatabase(raw, source.path);
        await SQLiteSchema(db).runMigrations(0, from);

        // Rows every version has: a remote document and a pending batch.
        await db.execute(
            'INSERT INTO remote_documents (path, contents) VALUES (?, ?)',
            <Object?>[
              legacyEncodePath('rooms/hades'),
              legacyRemoteDocuments()['rooms/hades']!.writeToBuffer()
            ]);
        await db.execute(
            'INSERT INTO mutation_queues (uid, last_acknowledged_batch_id, last_stream_token) VALUES (?, ?, ?)',
            <Object?>[legacyUid, -1, legacyStreamToken]);
        await db.execute(
            'INSERT INTO mutations (uid, batch_id, mutations) VALUES (?, ?, ?)',
            <Object?>[
              legacyUid,
              legacyBatchId,
              legacyPendingBatch().writeToBuffer()
            ]);
        for (final String path in legacyMutatedPaths) {
          await db.execute(
              'INSERT INTO document_mutations (uid, path, batch_id) VALUES (?, ?, ?)',
              <Object?>[legacyUid, legacyEncodePath(path), legacyBatchId]);
        }
        // A target: migration 3 drops the query cache of versions 1 and 2
        // (as upstream), from version 3 on it has to survive.
        final LegacyTarget target = legacyTargets.first;
        await db.execute(
            'INSERT INTO targets (target_id, canonical_id, snapshot_version_seconds, snapshot_version_nanos, resume_token, last_listen_sequence_number, target_proto) VALUES (?, ?, ?, ?, ?, ?, ?)',
            <Object?>[
              target.targetId,
              target.canonicalId,
              1586000300,
              0,
              Uint8List.fromList('resume-${target.targetId}'.codeUnits),
              target.sequenceNumber,
              legacyTargetProtos()[target.targetId]!.writeToBuffer(),
            ]);
        if (from >= 4) {
          await db.execute(
              'UPDATE target_globals SET highest_target_id = ?, target_count = 1',
              <Object?>[target.targetId]);
        }
        if (from >= 8) {
          // From version 8 on the SDK maintains the index itself.
          await db.execute(
              'INSERT INTO collection_parents (collection_id, parent) VALUES (?, ?)',
              <Object?>['rooms', legacyEncodePath('')]);
        }
        raw
          ..userVersion = from
          ..dispose();
        addTearDown(source.deleteSync);

        final SQLitePersistence persistence =
            await openCopy(source, 'intermediate_$from');
        expect(await userVersion(persistence), SQLiteSchema.version);

        final LocalStore localStore =
            LocalStore(persistence, User.unauthenticated);
        await localStore.start();

        expect(data(await localStore.readDocument(key('rooms/hades'))),
            <String, Object?>{'name': 'Hades', 'members': 11});
        final MutationBatch? batch = await localStore.getNextMutationBatch(-1);
        expect(batch!.batchId, legacyBatchId);
        expect(batch.mutations, hasLength(3));

        final QueryData queryData =
            await localStore.allocateTarget(query('rooms').toTarget());
        if (from >= 3) {
          expect(queryData.targetId, target.targetId);
          expect(queryData.resumeToken, isNotEmpty);
        } else {
          expect(queryData.resumeToken, isEmpty);
        }

        // The collection parents index (version 8) is built from the rows
        // that were there: the cached document and the document the pending
        // set creates.
        final ImmutableSortedMap<DocumentKey, Document> group =
            (await localStore.executeQuery(
                    Query(path(''), collectionGroup: 'rooms'), true))
                .documents;
        expect(<String>[
          for (final MapEntry<DocumentKey, Document> entry in group)
            entry.key.path.toString(),
        ], <String>[
          'rooms/eros',
          'rooms/hades'
        ]);
      });
    }
  });
}
