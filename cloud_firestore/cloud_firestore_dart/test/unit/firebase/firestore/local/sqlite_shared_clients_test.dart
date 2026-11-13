// Two clients on one SQLite file: the isolate before a hot restart and the one after it, a background isolate, a
// second process. There is no coordination between them yet (no primary lease), but they must not damage the cache:
// ids are unique, the metadata rows are not overwritten with what a client remembered, the schema is migrated once,
// and a client fails clearly when the schema changes under it.
//
// The first group runs two persistences in this isolate, interleaved step by step. The second group runs real
// concurrent writers in several isolates.

@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_write_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/database.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:test/test.dart';

import '../../../../util/sqlite3_database.dart';
import '../../../../util/test_util.dart';

const String fixturePath =
    'test/res/legacy/cloud_firestore_vm_0.0.7_schema8.db';

/// The project of the documents in the fixture.
const String projectId = 'legacy-project';

int _counter = 0;

/// A database name (below `build/test`) that no other test uses.
String newName(String label) =>
    'firebase/firestore/local/shared_clients_${label}_$pid'
    '_${DateTime.now().microsecondsSinceEpoch}_${_counter++}.db';

/// The schema version stored in the file [name].
int storedVersion(String name) {
  final sql.Database raw = sql.sqlite3.open(
    DatabaseMock.pathForName(name).path,
  );
  try {
    return raw.userVersion;
  } finally {
    raw.dispose();
  }
}

/// Called by [opener] between reading the stored version and running the callbacks.
typedef BeforeCallbacks = Future<void> Function();

/// An opener on the file [name] that follows the `OpenDatabase` contract and keeps the file when it is closed.
OpenDatabase opener(String name, {BeforeCallbacks? beforeCallbacks}) {
  return (
    String path, {
    int? version,
    OnConfigure? onConfigure,
    OnCreate? onCreate,
    OnVersionChange? onUpgrade,
    OnVersionChange? onDowngrade,
    OnOpen? onOpen,
  }) async {
    if (beforeCallbacks == null) {
      final DatabaseMock db = await DatabaseMock.create(
        name,
        version: version,
        onConfigure: onConfigure,
        onCreate: onCreate,
        onUpgrade: onUpgrade,
        onDowngrade: onDowngrade,
        onOpen: onOpen,
      );
      return db..renamePath = false;
    }

    // The same steps as [DatabaseMock.create], with a pause after the version was read.
    final int stored = storedVersion(name);
    final DatabaseMock db = await DatabaseMock.create(name, version: stored)
      ..renamePath = false;
    await onConfigure?.call(db);
    await beforeCallbacks();
    if (stored < version!) {
      await onUpgrade?.call(db, stored, version);
      db.database.userVersion = version;
    }
    await onOpen?.call(db);
    return db;
  };
}

Future<SQLitePersistence> openPersistence(
  String name, {
  BeforeCallbacks? beforeCallbacks,
}) async {
  final DatabaseId databaseId = DatabaseId.forProject(projectId);
  final SQLitePersistence persistence = await SQLitePersistence.create(
    name,
    databaseId,
    LocalSerializer(RemoteSerializer(databaseId)),
    opener(name, beforeCallbacks: beforeCallbacks),
    const LruGarbageCollectorParams(),
  );
  await persistence.start();
  return persistence;
}

/// One client: a persistence and the local store on it.
class Client {
  Client(this.persistence, this.store);

  final SQLitePersistence persistence;
  final LocalStore store;

  static Future<Client> open(String name, {User? user}) async {
    final SQLitePersistence persistence = await openPersistence(name);
    final LocalStore store = LocalStore(
      persistence,
      user ?? User.unauthenticated,
    );
    await store.start();
    return Client(persistence, store);
  }

  Future<QueryData> listen(String collection) {
    return store.allocateTarget(query(collection).toTarget());
  }

  Future<int> write(String path) async {
    final LocalWriteResult result = await store.writeLocally(<Mutation>[
      setMutation(path, map<Object?>(<Object?>['v', 1])),
    ]);
    return result.batchId;
  }

  Future<Map<String, dynamic>> targetGlobals() async {
    return (await persistence.query('SELECT * FROM target_globals')).single;
  }
}

FieldIndex indexOn(String collectionGroup, String field) {
  return FieldIndex(FieldIndex.unknownId, collectionGroup, <IndexSegment>[
    IndexSegment(FieldPath.fromSingleSegment(field), SegmentKind.ascending),
  ], FieldIndex.initialState);
}

/// What a writer isolate did.
class WriterResult {
  WriterResult(this.targetIds, this.batchIds, this.sequenceNumbers);

  final List<int> targetIds;
  final List<int> batchIds;
  final List<int> sequenceNumbers;
}

/// Makes writer isolates start every round together: a writer asks with [arrive] and waits until all [parties] have
/// arrived at the same round. A writer can then not run ahead of the others, so the ids of every round of every
/// writer come from a database that the others changed since the writer's previous round.
class RoundBarrier {
  RoundBarrier(this.parties) {
    _port.listen((Object? message) {
      final List<Object?> arrival = message! as List<Object?>;
      final int round = arrival[0]! as int;
      final List<SendPort> waiting = _waiting.putIfAbsent(
        round,
        () => <SendPort>[],
      )..add(arrival[1]! as SendPort);
      if (waiting.length == parties) {
        _waiting.remove(round);
        for (final SendPort writer in waiting) {
          writer.send(null);
        }
      }
    });
  }

  final int parties;
  final ReceivePort _port = ReceivePort();
  final Map<int, List<SendPort>> _waiting = <int, List<SendPort>>{};

  /// Passed to the writer isolates.
  SendPort get sendPort => _port.sendPort;

  void close() => _port.close();

  /// Called in a writer isolate: completes when every writer has arrived at [round].
  static Future<void> arrive(SendPort barrier, int round) async {
    final ReceivePort reply = ReceivePort();
    barrier.send(<Object?>[round, reply.sendPort]);
    await reply.first;
  }
}

/// Opens the cache [name] in a new isolate and allocates [rounds] targets of its own, one shared target per round,
/// and writes [rounds] batches. With [openAt] the cache is opened at that moment. With [barrier] (a
/// [RoundBarrier.sendPort]) every round starts when all writers have arrived at it.
Future<WriterResult> runWriter(
  String name,
  int writer,
  int rounds, {
  DateTime? openAt,
  SendPort? barrier,
}) {
  return Isolate.run(() async {
    Future<void> until(DateTime? time) async {
      if (time != null) {
        final Duration wait = time.difference(DateTime.now());
        if (!wait.isNegative) {
          await Future<void>.delayed(wait);
        }
      }
    }

    await until(openAt);
    final Client client = await Client.open(name);
    final List<int> targetIds = <int>[];
    final List<int> batchIds = <int>[];
    final List<int> sequenceNumbers = <int>[];
    for (int i = 0; i < rounds; i++) {
      if (barrier != null) {
        await RoundBarrier.arrive(barrier, i);
      }
      final QueryData own = await client.listen('writer$writer-$i');
      targetIds.add(own.targetId);
      sequenceNumbers.add(own.sequenceNumber);
      await client.listen('shared-$i');
      batchIds.add(await client.write('writes/writer$writer-$i'));
      if (barrier == null) {
        // Let the other isolates in. A connection that waits for the lock sleeps between its attempts (SQLite's
        // busy handler), so a writer that takes the lock again at once keeps the others out.
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
    }
    await client.persistence.shutdown();
    return WriterResult(targetIds, batchIds, sequenceNumbers);
  });
}

void main() {
  late String name;

  setUp(() {
    name = newName('db');
    addTearDown(() => DatabaseMock.deleteDatabaseFiles(name));
  });

  Future<Client> open({User? user}) async {
    final Client client = await Client.open(name, user: user);
    addTearDown(() async {
      if (client.persistence.started) {
        await client.persistence.shutdown();
      }
    });
    return client;
  }

  group('two clients in one isolate', () {
    test(
      'allocate different target ids, and the same id for the same target',
      () async {
        final Client a = await open();
        final Client b = await open();

        final List<int> ids = <int>[
          (await a.listen('a1')).targetId,
          (await b.listen('b1')).targetId,
          (await a.listen('a2')).targetId,
          (await b.listen('b2')).targetId,
          (await b.listen('b3')).targetId,
          (await a.listen('a3')).targetId,
        ];
        expect(ids.toSet(), hasLength(6), reason: '$ids');
        expect(ids, <int>[2, 4, 6, 8, 10, 12]);

        // A target that the other client allocated is found, not allocated again.
        expect((await b.listen('a1')).targetId, ids[0]);
        expect((await a.listen('b3')).targetId, ids[4]);

        for (final Client client in <Client>[a, b]) {
          final Map<String, dynamic> globals = await client.targetGlobals();
          expect(globals['highest_target_id'], 12);
          expect(globals['target_count'], 6);
          // What a client keeps in memory is brought up to date when its next transaction starts.
          await client.persistence.runTransaction('nothing', () async {});
          expect(client.persistence.queryCache.targetCount, 6);
          expect(client.persistence.queryCache.highestTargetId, 12);
          expect(
            (await client.persistence.query(
              'SELECT COUNT(*) AS c FROM targets',
            )).single['c'],
            6,
          );
        }
      },
    );

    test('listen sequence numbers keep growing across the clients', () async {
      final Client a = await open();
      final Client b = await open();

      final List<int> sequenceNumbers = <int>[];
      for (int i = 0; i < 4; i++) {
        sequenceNumbers
          ..add((await a.listen('a$i')).sequenceNumber)
          ..add((await b.listen('b$i')).sequenceNumber);
      }
      for (int i = 1; i < sequenceNumbers.length; i++) {
        expect(
          sequenceNumbers[i],
          greaterThan(sequenceNumbers[i - 1]),
          reason: '$sequenceNumbers',
        );
      }
      expect(
        (await a.targetGlobals())['highest_listen_sequence_number'],
        sequenceNumbers.last,
      );
    });

    test('assign different batch ids, also for different users', () async {
      final Client a = await open();
      final Client b = await open();
      final Client c = await open(user: User('alice'));

      final List<int> ids = <int>[
        await a.write('docs/a1'),
        await b.write('docs/b1'),
        await c.write('docs/c1'),
        await a.write('docs/a2'),
        await c.write('docs/c2'),
        await b.write('docs/b2'),
      ];
      expect(ids.toSet(), hasLength(6), reason: '$ids');
      for (int i = 1; i < ids.length; i++) {
        expect(ids[i], greaterThan(ids[i - 1]), reason: '$ids');
      }
      expect(
        (await a.persistence.query(
          'SELECT batch_id FROM mutations ORDER BY batch_id',
        )).map((Map<String, dynamic> row) => row['batch_id']).toList(),
        ids,
      );
    });

    test('do not overwrite the snapshot version or the stream token '
        'with what they remembered', () async {
      final Client a = await open();
      final Client b = await open();

      final SnapshotVersion version = SnapshotVersion(Timestamp(1000, 0));
      await a.persistence.runTransaction('set version', () async {
        await a.persistence.queryCache.setLastRemoteSnapshotVersion(version);
      });
      final Uint8List token = Uint8List.fromList(<int>[1, 2, 3]);
      await a.store.setLastStreamToken(token);

      // B started before both changes. Its next writes of the two metadata rows must carry them.
      await b.listen('b1');
      await b.write('docs/b1');
      expect(b.store.getLastRemoteSnapshotVersion(), version);
      expect(b.store.lastStreamToken, token);

      final Map<String, dynamic> globals = await a.targetGlobals();
      expect(globals['last_remote_snapshot_version_seconds'], 1000);
      expect(
        (await a.persistence.query(
          "SELECT last_stream_token FROM mutation_queues WHERE uid = ''",
        )).single['last_stream_token'],
        token,
      );
    });

    test(
      'see the field indexes of each other and give them different ids',
      () async {
        final Client a = await open();
        final Client b = await open();

        await a.store.configureFieldIndexes(<FieldIndex>[
          indexOn('rooms', 'a'),
        ]);
        expect(a.store.getFieldIndexes(), hasLength(1));

        // B learns about the index with its next transaction, and adds one.
        await b.store.configureFieldIndexes(<FieldIndex>[
          indexOn('rooms', 'a'),
          indexOn('rooms', 'b'),
        ]);
        expect(b.store.getFieldIndexes(), hasLength(2));

        await a.listen('anything');
        final List<FieldIndex> seenByA = a.store.getFieldIndexes();
        expect(seenByA, hasLength(2));
        expect(
          seenByA.map((FieldIndex index) => index.indexId).toSet(),
          hasLength(2),
        );
        expect(
          (await a.persistence.query(
            'SELECT COUNT(*) AS c FROM index_configuration',
          )).single['c'],
          2,
        );

        // And when the other client removes them.
        await b.store.deleteAllFieldIndexes();
        await a.listen('anything else');
        expect(a.store.getFieldIndexes(), isEmpty);
      },
    );

    test(
      'read their state again only after a commit of the other client',
      () async {
        final Client a = await open();
        final Client b = await open();
        final int seenByA = a.persistence.foreignCommitsSeen;

        await a.listen('a1');
        await a.write('docs/a1');
        await a.listen('a1');
        expect(a.persistence.foreignCommitsSeen, seenByA);

        await b.write('docs/b1');
        await a.listen('a2');
        await a.listen('a3');
        expect(a.persistence.foreignCommitsSeen, seenByA + 1);
      },
    );

    test(
      'a client fails clearly when the schema version changes under it',
      () async {
        final Client a = await open();
        await a.listen('a1');

        final sql.Database raw = sql.sqlite3.open(
          DatabaseMock.pathForName(name).path,
        );
        addTearDown(raw.dispose);
        raw.userVersion = SQLiteSchema.version + 1;

        Matcher skew(int version) => throwsA(
          isA<FirestoreError>()
              .having(
                (FirestoreError e) => e.code,
                'code',
                FirestoreErrorCode.failedPrecondition,
              )
              .having(
                (FirestoreError e) => e.message,
                'message',
                allOf(
                  contains('different version of the SDK'),
                  contains('is now $version,'),
                ),
              ),
        );
        await expectLater(a.listen('a2'), skew(SQLiteSchema.version + 1));
        // It stays failed, and nothing was written.
        await expectLater(a.write('docs/a'), skew(SQLiteSchema.version + 1));
        expect(raw.select('SELECT * FROM targets'), hasLength(1));
        expect(raw.select('SELECT * FROM mutations'), isEmpty);

        // The same for a version that was lowered by an older SDK.
        raw.userVersion = SQLiteSchema.version - 1;
        await expectLater(a.listen('a3'), skew(SQLiteSchema.version - 1));

        // Back at the version of this client it works again.
        raw.userVersion = SQLiteSchema.version;
        expect((await a.listen('a4')).targetId, 4);
      },
    );

    test('a cache of a newer schema version still opens (downgrade)', () async {
      final Client a = await open();
      await a.listen('a1');
      await a.persistence.shutdown();

      final sql.Database raw = sql.sqlite3.open(
        DatabaseMock.pathForName(name).path,
      );
      raw
        ..userVersion = SQLiteSchema.version + 1
        ..dispose();

      final Client again = await open();
      expect((await again.listen('a1')).targetId, 2);
      expect((await again.listen('a2')).targetId, 4);
    });

    test('a migration that another client finished in the meantime '
        'is not run again', () async {
      File(fixturePath).copySync(
        (DatabaseMock.pathForName(
          name,
        )..parent.createSync(recursive: true)).path,
      );

      // The slow client read schema 8 and is about to be told to upgrade from it, when a second client opens the
      // file and migrates it.
      late SQLitePersistence fast;
      final SQLitePersistence slow = await openPersistence(
        name,
        beforeCallbacks: () async {
          // Under another persistence key: `start()` of two persistences with the same name wait for each other.
          expect(storedVersion(name), 8);
          fast = await SQLitePersistence.create(
            '$name-fast',
            DatabaseId.forProject(projectId),
            LocalSerializer(RemoteSerializer(DatabaseId.forProject(projectId))),
            opener(name),
            const LruGarbageCollectorParams(),
          );
          await fast.start();
          expect(
            (await fast.query('PRAGMA user_version')).single.values.single,
            SQLiteSchema.version,
          );
        },
      );
      addTearDown(() async {
        await slow.shutdown();
        await fast.shutdown();
      });

      for (final SQLitePersistence persistence in <SQLitePersistence>[
        slow,
        fast,
      ]) {
        expect(
          (await persistence.query('PRAGMA user_version')).single.values.single,
          SQLiteSchema.version,
        );
        expect(
          (await persistence.query(
            'PRAGMA integrity_check',
          )).single.values.single,
          'ok',
        );
      }
      // The overlay data migration that schema 11 registers is pending exactly once.
      expect(
        await slow.query('SELECT migration_name FROM data_migrations'),
        hasLength(1),
      );
      final LocalStore store = LocalStore(slow, User.unauthenticated);
      await store.start();
      expect(await slow.query('SELECT * FROM data_migrations'), isEmpty);
    });
  });

  // example/sqlite_database_web.dart does this, so that the setup and the version it leads to are one transaction.
  test('an opener may run the setup inside a transaction of its own', () async {
    File(fixturePath).copySync(
      (DatabaseMock.pathForName(name)..parent.createSync(recursive: true)).path,
    );
    final DatabaseId databaseId = DatabaseId.forProject(projectId);
    final SQLitePersistence persistence = await SQLitePersistence.create(
      name,
      databaseId,
      LocalSerializer(RemoteSerializer(databaseId)),
      (
        String path, {
        int? version,
        OnConfigure? onConfigure,
        OnCreate? onCreate,
        OnVersionChange? onUpgrade,
        OnVersionChange? onDowngrade,
        OnOpen? onOpen,
      }) async {
        final int stored = storedVersion(name);
        final DatabaseMock db = await DatabaseMock.create(name, version: stored)
          ..renamePath = false;
        await onConfigure?.call(db);
        db.database.execute('BEGIN IMMEDIATE');
        await onUpgrade?.call(db, stored, version!);
        db.database.userVersion = version!;
        expect(db.database.autocommit, isFalse);
        db.database.execute('COMMIT');
        await onOpen?.call(db);
        return db;
      },
      const LruGarbageCollectorParams(),
    );
    await persistence.start();
    addTearDown(persistence.shutdown);

    expect(storedVersion(name), SQLiteSchema.version);
    final LocalStore store = LocalStore(persistence, User.unauthenticated);
    await store.start();
    expect(
      (await store.allocateTarget(query('rooms').toTarget())).targetId,
      greaterThan(0),
    );
  });

  group('clients in several isolates', () {
    test('write at the same time without sharing an id', () async {
      const int writers = 4;
      const int rounds = 40;

      // Create the file first: the writers then race on targets and batches, not on the setup.
      final Client first = await open();
      await first.persistence.shutdown();

      // Every round starts in all writers together, whatever the scheduler does: in each round every writer
      // allocates and writes with ids it remembered from before the other writers' last round.
      final RoundBarrier barrier = RoundBarrier(writers);
      addTearDown(barrier.close);
      final List<WriterResult> results =
          await Future.wait(<Future<WriterResult>>[
            for (int writer = 0; writer < writers; writer++)
              runWriter(name, writer, rounds, barrier: barrier.sendPort),
          ]);

      final List<int> targetIds = <int>[
        for (final WriterResult result in results) ...result.targetIds,
      ];
      final List<int> batchIds = <int>[
        for (final WriterResult result in results) ...result.batchIds,
      ];
      final List<int> sequenceNumbers = <int>[
        for (final WriterResult result in results) ...result.sequenceNumbers,
      ];
      expect(targetIds.toSet(), hasLength(writers * rounds));
      expect(batchIds.toSet(), hasLength(writers * rounds));
      expect(sequenceNumbers.toSet(), hasLength(writers * rounds));

      final Client check = await open();
      // The own targets of every writer, and one per round that all of them asked for.
      const int targets = writers * rounds + rounds;
      expect(
        (await check.persistence.query(
          'SELECT COUNT(*) AS c FROM targets',
        )).single['c'],
        targets,
      );
      expect(
        (await check.persistence.query(
          'SELECT COUNT(DISTINCT canonical_id) AS c FROM targets',
        )).single['c'],
        targets,
      );
      final Map<String, dynamic> globals = await check.targetGlobals();
      expect(globals['target_count'], targets);
      expect(globals['highest_target_id'], targets * 2);
      expect(
        (await check.persistence.query(
          'SELECT COUNT(*) AS c FROM mutations',
        )).single['c'],
        writers * rounds,
      );
      expect(
        (await check.persistence.query(
          'PRAGMA integrity_check',
        )).single.values.single,
        'ok',
      );
      // The barrier made the writers interleave: the batches of a round all come after those of the round before,
      // so no writer got a contiguous block of ids.
      for (int round = 1; round < rounds; round++) {
        final Iterable<int> before = results.map(
          (WriterResult result) => result.batchIds[round - 1],
        );
        final Iterable<int> now = results.map(
          (WriterResult result) => result.batchIds[round],
        );
        expect(
          now.reduce(min),
          greaterThan(before.reduce(max)),
          reason: 'round $round: ${results.map((r) => r.batchIds)}',
        );
      }
      for (final WriterResult result in results) {
        expect(
          result.batchIds.last - result.batchIds.first,
          greaterThan(rounds),
          reason: 'the writers ran one after the other: ${result.batchIds}',
        );
      }
    });

    test('open a new cache at the same time', () async {
      final List<WriterResult> results =
          await Future.wait(<Future<WriterResult>>[
            for (int writer = 0; writer < 4; writer++)
              runWriter(
                name,
                writer,
                3,
                openAt: DateTime.now().add(const Duration(seconds: 1)),
              ),
          ]);
      expect(<int>{
        for (final WriterResult result in results) ...result.targetIds,
      }, hasLength(12));

      final Client check = await open();
      expect(
        (await check.persistence.query(
          'PRAGMA user_version',
        )).single.values.single,
        SQLiteSchema.version,
      );
      expect((await check.targetGlobals())['target_count'], 15);
    });

    test('migrate an old cache at the same time', () async {
      File(fixturePath).copySync(
        (DatabaseMock.pathForName(
          name,
        )..parent.createSync(recursive: true)).path,
      );
      final sql.Database before = sql.sqlite3.open(
        DatabaseMock.pathForName(name).path,
      );
      expect(before.userVersion, 8);
      final int documents =
          before
                  .select('SELECT COUNT(*) AS c FROM remote_documents')
                  .single['c']
              as int;
      final int batches =
          before.select('SELECT COUNT(*) AS c FROM mutations').single['c']
              as int;
      final int targets =
          before.select('SELECT COUNT(*) AS c FROM targets').single['c'] as int;
      before.dispose();
      expect(documents, greaterThan(0));
      expect(batches, greaterThan(0));

      const int writers = 4;
      const int rounds = 3;
      await Future.wait(<Future<WriterResult>>[
        for (int writer = 0; writer < writers; writer++)
          runWriter(
            name,
            writer,
            rounds,
            openAt: DateTime.now().add(const Duration(seconds: 1)),
          ),
      ]);

      final Client check = await open();
      Future<int> count(String table) async =>
          (await check.persistence.query(
                'SELECT COUNT(*) AS c FROM $table',
              )).single['c']
              as int;
      expect(
        (await check.persistence.query(
          'PRAGMA user_version',
        )).single.values.single,
        SQLiteSchema.version,
      );
      expect(
        (await check.persistence.query(
          'PRAGMA integrity_check',
        )).single.values.single,
        'ok',
      );
      expect(await count('remote_documents'), documents);
      expect(await count('mutations'), batches + writers * rounds);
      expect(await count('targets'), targets + writers * rounds + rounds);
      expect(await count('data_migrations'), 0);
      // One overlay per document with a pending write: the legacy ones were built once, not once per client.
      expect(
        await count('document_overlays'),
        (await check.persistence.query(
          'SELECT COUNT(DISTINCT path) AS c FROM document_mutations',
        )).single['c'],
      );
    });
  });
}
