// File created by
// Lung Razvan <long1eu>
// on 01/10/2018

import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_database_collection/firebase_database_collection.dart';
import 'package:firebase_firestore/src/firebase/firestore/auth/user.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/mutation_queue.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/sqlite_persistence.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/set_mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/write_stream.dart';
import 'package:firebase_firestore/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import 'cases/mutation_queue_test_case.dart';
import 'persistence_test_helpers.dart';

void main() {
  MutationQueueTestCase testCase;
  MutationQueue mutationQueue;

  setUp(() async {
    print('setUp');
    final SQLitePersistence persistence =
        await PersistenceTestHelpers.openSQLitePersistence(
            'firebase/firestore/local/sqlite_mutation_queue_${PersistenceTestHelpers.nextSQLiteDatabaseName()}.db');

    testCase = MutationQueueTestCase(persistence);
    await testCase.setUp();

    mutationQueue = testCase.mutationQueue;
    print('setUpDone');
  });

  tearDown(() => Future<void>.delayed(
      const Duration(milliseconds: 250), () => testCase.tearDown()));

  test('testCountBatches', () async {
    await testCase.expectCount(count: 0, isEmpty: true);

    final MutationBatch batch1 = await testCase.addMutationBatch();
    await testCase.expectCount(count: 1, isEmpty: false);

    final MutationBatch batch2 = await testCase.addMutationBatch();
    await testCase.expectCount(count: 2, isEmpty: false);

    await testCase.removeMutationBatches(<MutationBatch>[batch2]);
    await testCase.expectCount(count: 1, isEmpty: false);

    await testCase.removeMutationBatches(<MutationBatch>[batch1]);
    await testCase.expectCount(count: 0, isEmpty: true);
  });

  test('testAcknowledgeBatchId', () async {
    // Initial state of an empty queue
    expect(mutationQueue.highestAcknowledgedBatchId, MutationBatch.unknown);

    // Adding mutation batches should not change the highest acked batchId.
    final MutationBatch batch1 = await testCase.addMutationBatch();
    final MutationBatch batch2 = await testCase.addMutationBatch();
    final MutationBatch batch3 = await testCase.addMutationBatch();
    expect(batch1.batchId, greaterThan(MutationBatch.unknown));
    expect(batch2.batchId, greaterThan(batch1.batchId));
    expect(batch3.batchId, greaterThan(batch2.batchId));

    expect(mutationQueue.highestAcknowledgedBatchId, MutationBatch.unknown);

    await testCase.acknowledgeBatch(batch1);
    expect(mutationQueue.highestAcknowledgedBatchId, batch1.batchId);

    await testCase.acknowledgeBatch(batch2);
    expect(mutationQueue.highestAcknowledgedBatchId, batch2.batchId);

    await testCase.removeMutationBatches(<MutationBatch>[batch1]);
    expect(mutationQueue.highestAcknowledgedBatchId, batch2.batchId);

    await testCase.removeMutationBatches(<MutationBatch>[batch2]);
    expect(mutationQueue.highestAcknowledgedBatchId, batch2.batchId);

    // Batch 3 never acknowledged.
    await testCase.removeMutationBatches(<MutationBatch>[batch3]);
    expect(mutationQueue.highestAcknowledgedBatchId, batch2.batchId);
  });

  test('testAcknowledgeThenRemove', () async {
    final MutationBatch batch1 = await testCase.addMutationBatch();

    await testCase.persistence.runTransaction('testAcknowledgeThenRemove',
        () async {
      await mutationQueue.acknowledgeBatch(
          batch1, WriteStream.emptyStreamToken);
      await mutationQueue.removeMutationBatches(<MutationBatch>[batch1]);
    });

    await testCase.expectCount(count: 0, isEmpty: true);
    expect(mutationQueue.highestAcknowledgedBatchId, batch1.batchId);
  });

  test('testHighestAcknowledgedBatchIdNeverExceedsNextBatchId', () async {
    final MutationBatch batch1 = await testCase.addMutationBatch();
    final MutationBatch batch2 = await testCase.addMutationBatch();
    await testCase.acknowledgeBatch(batch1);
    await testCase.acknowledgeBatch(batch2);
    expect(mutationQueue.highestAcknowledgedBatchId, batch2.batchId);

    await testCase.removeMutationBatches(<MutationBatch>[batch1, batch2]);
    expect(mutationQueue.highestAcknowledgedBatchId, batch2.batchId);

    // Restart the queue so that nextBatchId will be reset.
    mutationQueue = testCase.persistence.getMutationQueue(User.unauthenticated);
    testCase.mutationQueue = mutationQueue;
    await mutationQueue.start();

    await testCase.persistence
        .runTransaction('Start mutationQueue', () => mutationQueue.start());

    // Verify that on restart with an empty queue, nextBatchId falls to a lower value.
    expect(mutationQueue.nextBatchId, lessThan(batch2.batchId));

    // As a result highestAcknowledgedBatchId must also reset lower.
    expect(mutationQueue.highestAcknowledgedBatchId, MutationBatch.unknown);

    // The mutation queue will reset the next batchId after all mutations are
    // removed so adding another mutation will cause a collision.
    final MutationBatch newBatch = await testCase.addMutationBatch();
    expect(newBatch.batchId, batch1.batchId);

    // Restart the queue with one unacknowledged batch in it.
    await testCase.persistence
        .runTransaction('Start mutationQueue', () => mutationQueue.start());

    expect(mutationQueue.nextBatchId, newBatch.batchId + 1);

    // highestAcknowledgedBatchId must still be MutationBatch.unknown.
    expect(mutationQueue.highestAcknowledgedBatchId, MutationBatch.unknown);
  });

  test('testLookupMutationBatch', () async {
    // Searching on an empty queue should not find a non-existent batch
    MutationBatch notFound = await mutationQueue.lookupMutationBatch(42);
    expect(notFound, isNull);

    final List<MutationBatch> batches = await testCase.createBatches(10);
    final List<MutationBatch> removed =
        await testCase.makeHoles(<int>[2, 6, 7], batches);

    // After removing, a batch should not be found
    for (MutationBatch batch in removed) {
      notFound = await mutationQueue.lookupMutationBatch(batch.batchId);
      expect(notFound, isNull);
    }

    // Remaining entries should still be found
    for (MutationBatch batch in batches) {
      final MutationBatch found =
          await mutationQueue.lookupMutationBatch(batch.batchId);
      expect(found, isNotNull);
      expect(found.batchId, batch.batchId);
    }

    // Even on a nonempty queue searching should not find a non-existent batch
    notFound = await mutationQueue.lookupMutationBatch(42);
    expect(notFound, isNull);
  });

  test('testNextMutationBatchAfterBatchId', () async {
    final List<MutationBatch> batches = await testCase.createBatches(10);

    // This is an array of successors assuming the removals below will happen:
    final List<MutationBatch> afters = <MutationBatch>[
      batches[3],
      batches[8],
      batches[8]
    ];
    final List<MutationBatch> removed =
        await testCase.makeHoles(<int>[2, 6, 7], batches);

    for (int i = 0; i < batches.length - 1; i++) {
      final MutationBatch current = batches[i];
      final MutationBatch next = batches[i + 1];
      final MutationBatch found =
          await mutationQueue.getNextMutationBatchAfterBatchId(current.batchId);
      expect(found, isNotNull);
      expect(found.batchId, next.batchId);
    }

    for (int i = 0; i < removed.length; i++) {
      final MutationBatch current = removed[i];
      final MutationBatch next = afters[i];
      final MutationBatch found =
          await mutationQueue.getNextMutationBatchAfterBatchId(current.batchId);
      expect(found, isNotNull);
      expect(found.batchId, next.batchId);
    }

    final MutationBatch first = batches[0];
    final MutationBatch found = await mutationQueue
        .getNextMutationBatchAfterBatchId(first.batchId - 42);
    expect(found, isNotNull);
    expect(found.batchId, first.batchId);

    final MutationBatch last = batches[batches.length - 1];
    final MutationBatch notFound =
        await mutationQueue.getNextMutationBatchAfterBatchId(last.batchId);
    expect(notFound, isNull);
  });

  test('testNextMutationBatchAfterBatchIdSkipsAcknowledgedBatches', () async {
    final List<MutationBatch> batches = await testCase.createBatches(3);

    MutationBatch result = await mutationQueue
        .getNextMutationBatchAfterBatchId(MutationBatch.unknown);
    expect(result, batches[0]);

    await testCase.acknowledgeBatch(batches[0]);
    result = await mutationQueue
        .getNextMutationBatchAfterBatchId(MutationBatch.unknown);
    expect(result, batches[1]);

    result = await mutationQueue
        .getNextMutationBatchAfterBatchId(batches[0].batchId);
    expect(result, batches[1]);

    result = await mutationQueue
        .getNextMutationBatchAfterBatchId(batches[1].batchId);
    expect(result, batches[2]);
  });

  test('testAllMutationBatchesThroughBatchID', () async {
    final List<MutationBatch> batches = await testCase.createBatches(10);
    await testCase.makeHoles(<int>[2, 6, 7], batches);

    List<MutationBatch> found;
    List<MutationBatch> expected;

    found = await mutationQueue
        .getAllMutationBatchesThroughBatchId(batches[0].batchId - 1);
    expect(found, isEmpty);

    for (int i = 0; i < batches.length; i++) {
      found = await mutationQueue
          .getAllMutationBatchesThroughBatchId(batches[i].batchId);
      expected = batches.sublist(0, i + 1);
      expect(found, expected);
    }
  });

  test('testAllMutationBatchesAffectingDocumentKey', () async {
    final List<Mutation> mutations = <Mutation>[
      setMutation('fob/bar', map(<dynamic>['a', 1])),
      setMutation('foo/bar', map(<dynamic>['a', 1])),
      patchMutation('foo/bar', map(<dynamic>['b', 1])),
      setMutation('foo/bar/suffix/key', map(<dynamic>['a', 1])),
      setMutation('foo/baz', map(<dynamic>['a', 1])),
      setMutation('food/bar', map(<dynamic>['a', 1]))
    ];

    // Store all the mutations.
    final List<MutationBatch> batches = <MutationBatch>[];
    await testCase.persistence.runTransaction('New mutation batch', () async {
      for (Mutation mutation in mutations) {
        batches.add(await mutationQueue
            .addMutationBatch(Timestamp.now(), <Mutation>[mutation]));
      }
    });

    final List<MutationBatch> expected = <MutationBatch>[
      batches[1],
      batches[2]
    ];
    final List<MutationBatch> matches = await mutationQueue
        .getAllMutationBatchesAffectingDocumentKey(key('foo/bar'));

    expect(matches, expected);
  });

  test('testAllMutationBatchesAffectingDocumentKeys', () async {
    final List<Mutation> mutations = <Mutation>[
      setMutation('fob/bar', map(<dynamic>['a', 1])),
      setMutation('foo/bar', map(<dynamic>['a', 1])),
      patchMutation('foo/bar', map(<dynamic>['b', 1])),
      setMutation('foo/bar/suffix/key', map(<dynamic>['a', 1])),
      setMutation('foo/baz', map(<dynamic>['a', 1])),
      setMutation('food/bar', map(<dynamic>['a', 1]))
    ];

    // Store all the mutations.
    final List<MutationBatch> batches = <MutationBatch>[];
    await testCase.persistence.runTransaction('New mutation batch', () async {
      for (Mutation mutation in mutations) {
        batches.add(await mutationQueue
            .addMutationBatch(Timestamp.now(), <Mutation>[mutation]));
      }
    });

    final ImmutableSortedSet<DocumentKey> keys =
        DocumentKey.emptyKeySet.insert(key('foo/bar')).insert(key('foo/baz'));

    final List<MutationBatch> expected = <MutationBatch>[
      batches[1],
      batches[2],
      batches[4]
    ];
    final List<MutationBatch> matches =
        await mutationQueue.getAllMutationBatchesAffectingDocumentKeys(keys);

    expect(matches, expected);
  });

  // PORTING NOTE: this test only applies to Android, because it's the only p
  // latform where the implementation of
  // getAllMutationBatchesAffectingDocumentKeys might split the input into
  // several queries.
  test('testAllMutationBatchesAffectingDocumentLotsOfDocumentKeys', () async {
    final List<Mutation> mutations = <Mutation>[];
    // Make sure to force SQLite implementation to split the large query into
    // several smaller ones.
    const int lotsOfMutations = 10000;
    for (int i = 0; i < lotsOfMutations; i++) {
      mutations.add(setMutation('foo/$i', map(<dynamic>['a', 1])));
    }
    final List<MutationBatch> batches = <MutationBatch>[];
    await testCase.persistence.runTransaction('New mutation batch', () async {
      for (Mutation mutation in mutations) {
        batches.add(await mutationQueue
            .addMutationBatch(Timestamp.now(), <Mutation>[mutation]));
      }
    });

    // To make it easier validating the large resulting set, use a simple
    // criteria to evaluate -- query all keys with an even number in them and
    // make sure the corresponding batches make it into the results.
    ImmutableSortedSet<DocumentKey> evenKeys = DocumentKey.emptyKeySet;
    final List<MutationBatch> expected = <MutationBatch>[];
    for (int i = 2; i < lotsOfMutations; i += 2) {
      evenKeys = evenKeys.insert(key('foo/$i'));
      expected.add(batches[i]);
    }

    final List<MutationBatch> matches = await mutationQueue
        .getAllMutationBatchesAffectingDocumentKeys(evenKeys);
    expect(matches, containsAllInOrder(expected));
    expect(matches.length, expected.length);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('testAllMutationBatchesAffectingQuery', () async {
    final List<Mutation> mutations = <Mutation>[
      setMutation('fob/bar', map(<dynamic>['a', 1])),
      setMutation('foo/bar', map(<dynamic>['a', 1])),
      patchMutation('foo/bar', map(<dynamic>['b', 1])),
      setMutation('foo/bar/suffix/key', map(<dynamic>['a', 1])),
      setMutation('foo/baz', map(<dynamic>['a', 1])),
      setMutation('food/bar', map(<dynamic>['a', 1]))
    ];

    // Store all the mutations.
    final List<MutationBatch> batches = <MutationBatch>[];
    await testCase.persistence.runTransaction('New mutation batch', () async {
      for (Mutation mutation in mutations) {
        batches.add(await mutationQueue
            .addMutationBatch(Timestamp.now(), <Mutation>[mutation]));
      }
    });

    final List<MutationBatch> expected = <MutationBatch>[
      batches[1],
      batches[2],
      batches[4]
    ];

    final Query query = Query.atPath(path('foo'));
    final List<MutationBatch> matches =
        await mutationQueue.getAllMutationBatchesAffectingQuery(query);

    expect(matches, expected);
  });

  test('testAllMutationBatchesAffectingQuery_withCompoundBatches', () async {
    final Map<String, Object> value = map(<dynamic>['a', 1]);

    // Store all the mutations.
    final List<MutationBatch> batches = <MutationBatch>[];
    await testCase.persistence.runTransaction('New mutation batch', () async {
      batches.add(await mutationQueue.addMutationBatch(
          Timestamp.now(), <SetMutation>[
        setMutation('foo/bar', value),
        setMutation('foo/bar/baz/quux', value)
      ]));
      batches.add(await mutationQueue.addMutationBatch(
          Timestamp.now(), <SetMutation>[
        setMutation('foo/bar', value),
        setMutation('foo/baz', value)
      ]));
    });

    final List<MutationBatch> expected = <MutationBatch>[
      batches[0],
      batches[1]
    ];

    final Query query = Query.atPath(path('foo'));
    final List<MutationBatch> matches =
        await mutationQueue.getAllMutationBatchesAffectingQuery(query);

    expect(matches, expected);
  });

  test('testRemoveMutationBatches', () async {
    final List<MutationBatch> batches = await testCase.createBatches(10);
    final MutationBatch last = batches[batches.length - 1];

    await testCase.removeMutationBatches(<MutationBatch>[batches.removeAt(0)]);
    expect(await testCase.batchCount(), 9);

    List<MutationBatch> found;

    found =
        await mutationQueue.getAllMutationBatchesThroughBatchId(last.batchId);
    expect(found, batches);
    expect(found.length, 9);

    await testCase.removeMutationBatches(
        <MutationBatch>[batches[0], batches[1], batches[2]]);
    batches.remove(batches[0]);
    batches.remove(batches[0]);
    batches.remove(batches[0]);
    expect(await testCase.batchCount(), 6);

    found =
        await mutationQueue.getAllMutationBatchesThroughBatchId(last.batchId);
    expect(found, batches);
    expect(found.length, 6);

    await testCase.removeMutationBatches(
        <MutationBatch>[batches.removeAt(batches.length - 1)]);
    expect(await testCase.batchCount(), 5);

    found =
        await mutationQueue.getAllMutationBatchesThroughBatchId(last.batchId);
    expect(found, batches);
    expect(found.length, 5);

    await testCase.removeMutationBatches(<MutationBatch>[batches.removeAt(3)]);
    expect(await testCase.batchCount(), 4);

    await testCase.removeMutationBatches(<MutationBatch>[batches.removeAt(1)]);
    expect(await testCase.batchCount(), 3);

    found =
        await mutationQueue.getAllMutationBatchesThroughBatchId(last.batchId);
    expect(found, batches);
    expect(found.length, 3);

    await testCase.removeMutationBatches(batches);
    found =
        await mutationQueue.getAllMutationBatchesThroughBatchId(last.batchId);
    expect(found, isEmpty);
    expect(found.length, 0);
    await testCase.expectCount(count: 0, isEmpty: true);
  });

  test('testStreamToken', () async {
    final Uint8List streamToken1 = streamToken('token1');
    final Uint8List streamToken2 = streamToken('token2');

    await testCase.persistence.runTransaction('initial stream token',
        () => mutationQueue.setLastStreamToken(streamToken1));

    final MutationBatch batch1 = await testCase.addMutationBatch();
    await testCase.addMutationBatch();

    expect(mutationQueue.lastStreamToken, streamToken1);

    await testCase.persistence.runTransaction('acknowledgeBatchId',
        () => mutationQueue.acknowledgeBatch(batch1, streamToken2));

    expect(mutationQueue.highestAcknowledgedBatchId, batch1.batchId);
    expect(mutationQueue.lastStreamToken, streamToken2);
  });
}
