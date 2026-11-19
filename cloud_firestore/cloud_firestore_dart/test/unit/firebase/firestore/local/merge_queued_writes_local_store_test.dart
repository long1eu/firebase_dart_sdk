// The merge of a queue that already exists (LocalStore.startMergingQueuedWrites) must give the queue that the merge at
// write time would have built from the same writes, and must not change any document the app sees. It runs a few
// batches at a time, and a restart or a new write in between must not change the result.

import 'dart:math';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart' show FieldValue;
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/user_data_converter.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';
import 'persistence_test_helpers.dart';

void main() {
  final UserDataConverter converter = UserDataConverter(
    DatabaseId.forProject('project'),
  );
  final List<DocumentKey> keys = <DocumentKey>[
    key('coll/a'),
    key('coll/b'),
    key('coll/c'),
  ];

  Mutation randomMutation(Random random, DocumentKey documentKey) {
    final Map<String, Object?> data = <String, Object?>{};
    for (int i = 1 + random.nextInt(3); i > 0; i--) {
      switch (random.nextInt(12)) {
        case 0:
          data['count'] = FieldValue.increment(1 + random.nextInt(5));
        case 1:
        case 2:
          data['time'] = FieldValue.serverTimestamp();
        case 3:
          data['f${random.nextInt(3)}'] = FieldValue.delete();
        case 4:
          data['n'] = <String, Object?>{'x': random.nextInt(100)};
        case 5:
          data['tags'] = FieldValue.arrayUnion(<Object?>[random.nextInt(5)]);
        case 6:
          data['count'] = random.nextInt(10);
        default:
          data['f${random.nextInt(3)}'] = random.nextInt(100);
      }
    }
    switch (random.nextInt(12)) {
      case 0:
        return deleteMutation(documentKey.path.canonicalString);
      case 1:
        data.removeWhere(
          (String _, Object? value) =>
              value is FieldValue && value == FieldValue.delete(),
        );
        return converter
            .parseSetData(data)
            .toMutation(documentKey, Precondition.none);
      case 2:
      case 3:
        return converter
            .parseMergeData(data, null)
            .toMutation(documentKey, Precondition.none);
      default:
        return converter
            .parseUpdateData(data)
            .toMutation(documentKey, Precondition(exists: true));
    }
  }

  // A pending server timestamp shows the time of its batch, which differs between two runs.
  final RegExp estimate = RegExp(
    r'\{__local_write_time__:.*?__type__:server_timestamp\}',
  );
  String withTimes(Object? value) =>
      value.toString().replaceAll(estimate, 'time');

  Future<List<String>> queueOf(Persistence persistence) async {
    final List<MutationBatch> batches = await persistence
        .runTransactionAndReturn(
          'read the queue',
          () => persistence
              .getMutationQueue(User.unauthenticated)
              .getAllMutationBatches(),
        );
    return <String>[
      for (final MutationBatch batch in batches)
        withTimes('${batch.mutations} with base ${batch.baseMutations}'),
    ];
  }

  Future<List<String>> documentsOf(LocalStore localStore) async => <String>[
    for (final DocumentKey documentKey in keys)
      switch (await localStore.readDocument(documentKey)) {
        final Document document => withTimes(document.data),
        final MaybeDocument? other => '${other.runtimeType}',
      },
  ];

  Future<LocalStore> open(
    Persistence persistence, {
    required bool merge,
  }) async {
    final LocalStore localStore = LocalStore(persistence, User.unauthenticated)
      ..mergeUnsentWrites = merge;
    await localStore.start();
    return localStore;
  }

  Future<void> seedRemote(LocalStore localStore) async {
    final int targetId = (await localStore.allocateTarget(
      query('coll').toTarget(),
    )).targetId;
    await localStore.applyRemoteEvent(
      updateRemoteEvent(
        doc(keys[0], 10, <String, Object?>{
          'f0': 1,
          'count': 7,
          'tags': <int>[1],
        }),
        <int>[targetId],
        <int>[],
      ),
    );
  }

  /// Returns the number of batches the merge removed.
  Future<int> run(Future<Persistence> Function() create, int seed) async {
    final Random random = Random(seed);
    final List<List<Mutation>> writes = <List<Mutation>>[
      for (int i = 20 + random.nextInt(120); i > 0; i--)
        <Mutation>[
          // Mostly one document, so that chains are long.
          randomMutation(
            random,
            keys[random.nextInt(10) < 6 ? 0 : 1 + random.nextInt(2)],
          ),
          if (random.nextInt(12) == 0)
            randomMutation(random, keys[random.nextInt(3)]),
        ],
    ];
    // The writes made before the setting was on, and the ones made while the merge runs or after it.
    final int before = writes.length - random.nextInt(10);

    // What the merge at write time builds.
    final Persistence expectedPersistence = await create();
    final Persistence persistence = await create();
    try {
      LocalStore expected = await open(expectedPersistence, merge: true);
      await seedRemote(expected);
      expect(await expected.startMergingQueuedWrites(), isFalse);
      for (final List<Mutation> write in writes) {
        await expected.writeLocally(write, mayMerge: true);
      }

      LocalStore localStore = await open(persistence, merge: false);
      await seedRemote(localStore);
      for (final List<Mutation> write in writes.take(before)) {
        await localStore.writeLocally(write, mayMerge: true);
      }
      final List<String> documentsBefore = await documentsOf(localStore);
      final int batchesBefore = (await queueOf(persistence)).length;
      expect(batchesBefore, before);

      // The next session has the setting on.
      localStore = await open(persistence, merge: true);
      final bool started = await localStore.startMergingQueuedWrites();
      expect(started, isTrue, reason: 'seed $seed');
      int next = before;
      int merged = 0;
      while (localStore.mergingQueuedWrites) {
        // Nothing is sent while the merge runs.
        expect(await localStore.getNextMutationBatch(-1), isNull);
        merged += (await localStore.mergeQueuedWrites(
          maxBatches: 1 + random.nextInt(9),
        )).length;
        if (next == before) {
          // The merge alone never changes what the app sees.
          expect(
            await documentsOf(localStore),
            documentsBefore,
            reason: 'seed $seed',
          );
        }
        switch (random.nextInt(8)) {
          case 0 when next < writes.length:
            await localStore.writeLocally(writes[next++], mayMerge: true);
          case 1:
            // A restart half way: the merge goes on from its mark.
            localStore = await open(persistence, merge: true);
            await localStore.startMergingQueuedWrites();
        }
      }
      while (next < writes.length) {
        await localStore.writeLocally(writes[next++], mayMerge: true);
      }

      expect(
        await queueOf(persistence),
        await queueOf(expectedPersistence),
        reason: 'seed $seed',
      );
      expect(
        await documentsOf(localStore),
        await documentsOf(expected),
        reason: 'seed $seed',
      );
      expect(await localStore.getNextMutationBatch(-1), isNotNull);

      // A queue that is merged is not merged again at the next start.
      localStore = await open(persistence, merge: true);
      expect(
        await localStore.startMergingQueuedWrites(),
        isFalse,
        reason: 'seed $seed',
      );
      expected = await open(expectedPersistence, merge: true);
      expect(await expected.startMergingQueuedWrites(), isFalse);
      return merged;
    } finally {
      await persistence.shutdown();
      await expectedPersistence.shutdown();
    }
  }

  for (final String cache in <String>['memory', 'sqlite']) {
    test(
      'the queue of an earlier session is merged as at write time, $cache cache',
      () async {
        int merged = 0;
        for (int seed = 0; seed < (cache == 'memory' ? 150 : 25); seed++) {
          merged += await run(
            cache == 'memory'
                ? createLRUMemoryPersistence
                : createSQLitePersistence,
            seed,
          );
        }
        expect(merged, greaterThan(cache == 'memory' ? 2000 : 300));
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );
  }

  test('nothing runs with the setting off', () async {
    final Persistence persistence = await createLRUMemoryPersistence();
    final LocalStore localStore = await open(persistence, merge: false);
    final Random random = Random(1);
    for (int i = 0; i < 20; i++) {
      await localStore.writeLocally(<Mutation>[
        randomMutation(random, keys[0]),
      ], mayMerge: true);
    }
    expect(await localStore.startMergingQueuedWrites(), isFalse);
    expect(localStore.mergingQueuedWrites, isFalse);
    expect(await localStore.mergeQueuedWrites(), isEmpty);
    expect((await queueOf(persistence)).length, 20);
    expect(await localStore.getNextMutationBatch(-1), isNotNull);
    await persistence.shutdown();
  });
}
