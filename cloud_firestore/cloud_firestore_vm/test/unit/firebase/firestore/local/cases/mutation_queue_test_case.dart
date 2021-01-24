// File created by
// Lung Razvan <long1eu>
// on 01/10/2018

import 'dart:async';
import 'dart:typed_data';

import 'package:_firebase_database_collection_vm/_firebase_database_collection_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistence/mutation_queue.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistence/persistence.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/reference_set.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/set_mutation.dart';
import 'package:cloud_firestore_vm/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../../../util/test_util.dart';

class MutationQueueTestCase {
  MutationQueueTestCase(this._persistence);

  final Persistence _persistence;
  MutationQueue _mutationQueue;

  Future<void> setUp() async {
    _persistence.referenceDelegate.inMemoryPins = ReferenceSet();
    _mutationQueue = _persistence.getMutationQueue(User.unauthenticated);
    await _mutationQueue.start();
  }

  Future<void> tearDown() => _persistence.shutdown();

  @testMethod
  Future<void> testCountBatches() async {
    await _expectCount(count: 0, isEmpty: true);

    final MutationBatch batch1 = await _addMutationBatch();
    await _expectCount(count: 1, isEmpty: false);

    final MutationBatch batch2 = await _addMutationBatch();
    await _expectCount(count: 2, isEmpty: false);

    await _removeMutationBatches(<MutationBatch>[batch1]);
    await _expectCount(count: 1, isEmpty: false);

    await _removeMutationBatches(<MutationBatch>[batch2]);
    await _expectCount(count: 0, isEmpty: true);
    expect(await _mutationQueue.isEmpty(), isTrue);
  }

  @testMethod
  Future<void> testAcknowledgeThenRemove() async {
    final MutationBatch batch1 = await _addMutationBatch();

    await _persistence.runTransaction('testAcknowledgeThenRemove', () async {
      await _mutationQueue.acknowledgeBatch(batch1, Uint8List(0));
      await _mutationQueue.removeMutationBatch(batch1);
    });

    await _expectCount(count: 0, isEmpty: true);
  }

  @testMethod
  Future<void> testLookupMutationBatch() async {
    // Searching on an empty queue should not find a non-existent batch
    MutationBatch notFound = await _mutationQueue.lookupMutationBatch(42);
    expect(notFound, isNull);

    final List<MutationBatch> batches = await _createBatches(10);
    final List<MutationBatch> removed = await _removeFirstBatches(3, batches);

    // After removing, a batch should not be found
    for (MutationBatch batch in removed) {
      notFound = await _mutationQueue.lookupMutationBatch(batch.batchId);
      expect(notFound, isNull);
    }

    // Remaining entries should still be found
    for (MutationBatch batch in batches) {
      final MutationBatch found =
          await _mutationQueue.lookupMutationBatch(batch.batchId);
      expect(found, isNotNull);
      expect(found.batchId, batch.batchId);
    }

    // Even on a nonempty queue searching should not find a non-existent batch
    notFound = await _mutationQueue.lookupMutationBatch(42);
    expect(notFound, isNull);
  }

  @testMethod
  Future<void> testNextMutationBatchAfterBatchId() async {
    final List<MutationBatch> batches = await _createBatches(10);
    final List<MutationBatch> removed = await _removeFirstBatches(3, batches);

    for (int i = 0; i < batches.length - 1; i++) {
      final MutationBatch current = batches[i];
      final MutationBatch next = batches[i + 1];
      final MutationBatch found = await _mutationQueue
          .getNextMutationBatchAfterBatchId(current.batchId);
      expect(found, isNotNull);
      expect(found.batchId, next.batchId);
    }

    for (int i = 0; i < removed.length; i++) {
      final MutationBatch current = removed[i];
      final MutationBatch next = batches[0];
      final MutationBatch found = await _mutationQueue
          .getNextMutationBatchAfterBatchId(current.batchId);
      expect(found, isNotNull);
      expect(found.batchId, next.batchId);
    }

    final MutationBatch first = batches[0];
    final MutationBatch found = await _mutationQueue
        .getNextMutationBatchAfterBatchId(first.batchId - 42);
    expect(found, isNotNull);
    expect(found.batchId, first.batchId);

    final MutationBatch last = batches[batches.length - 1];
    final MutationBatch notFound =
        await _mutationQueue.getNextMutationBatchAfterBatchId(last.batchId);
    expect(notFound, isNull);
  }

  @testMethod
  Future<void> testAllMutationBatchesAffectingDocumentKey() async {
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
    await _persistence.runTransaction('New mutation batch', () async {
      for (Mutation mutation in mutations) {
        batches.add(await _mutationQueue.addMutationBatch(
            Timestamp.now(), <Mutation>[], <Mutation>[mutation]));
      }
    });

    final List<MutationBatch> expected = <MutationBatch>[
      batches[1],
      batches[2]
    ];
    final List<MutationBatch> matches = await _mutationQueue
        .getAllMutationBatchesAffectingDocumentKey(key('foo/bar'));

    expect(matches, expected);
  }

  @testMethod
  Future<void> testAllMutationBatchesAffectingDocumentKeys() async {
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
    await _persistence.runTransaction('New mutation batch', () async {
      for (Mutation mutation in mutations) {
        batches.add(await _mutationQueue.addMutationBatch(
            Timestamp.now(), <Mutation>[], <Mutation>[mutation]));
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
        await _mutationQueue.getAllMutationBatchesAffectingDocumentKeys(keys);

    expect(matches, expected);
  }

  // timeout: const Timeout(Duration(minutes: 2))
  @testMethod
  Future<void>
      testAllMutationBatchesAffectingDocumentLotsOfDocumentKeys() async {
    final List<Mutation> mutations = <Mutation>[];
    // Make sure to force SQLite implementation to split the large query into several smaller ones.
    const int lotsOfMutations = 10000;
    for (int i = 0; i < lotsOfMutations; i++) {
      mutations.add(setMutation('foo/$i', map(<dynamic>['a', 1])));
    }
    final List<MutationBatch> batches = <MutationBatch>[];
    await _persistence.runTransaction('New mutation batch', () async {
      for (Mutation mutation in mutations) {
        batches.add(await _mutationQueue.addMutationBatch(
            Timestamp.now(), <Mutation>[], <Mutation>[mutation]));
      }
    });

    // To make it easier validating the large resulting set, use a simple criteria to evaluate -- query all keys with an
    // even number in them and make sure the corresponding batches make it into the results.
    ImmutableSortedSet<DocumentKey> evenKeys = DocumentKey.emptyKeySet;
    final List<MutationBatch> expected = <MutationBatch>[];
    for (int i = 2; i < lotsOfMutations; i += 2) {
      evenKeys = evenKeys.insert(key('foo/$i'));
      expected.add(batches[i]);
    }

    final List<MutationBatch> matches = await _mutationQueue
        .getAllMutationBatchesAffectingDocumentKeys(evenKeys);
    expect(matches, containsAllInOrder(expected));
    expect(matches.length, expected.length);
  }

  @testMethod
  Future<void> testAllMutationBatchesAffectingQuery() async {
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
    await _persistence.runTransaction('New mutation batch', () async {
      for (Mutation mutation in mutations) {
        batches.add(await _mutationQueue.addMutationBatch(
            Timestamp.now(), <Mutation>[], <Mutation>[mutation]));
      }
    });

    final List<MutationBatch> expected = <MutationBatch>[
      batches[1],
      batches[2],
      batches[4]
    ];

    final Query query = Query(path('foo'));
    final List<MutationBatch> matches =
        await _mutationQueue.getAllMutationBatchesAffectingQuery(query);

    expect(matches, expected);
  }

  @testMethod
  Future<void> testAllMutationBatchesAffectingQueryWithCompoundBatches() async {
    final Map<String, Object> value = map(<dynamic>['a', 1]);

    // Store all the mutations.
    final List<MutationBatch> batches = <MutationBatch>[];
    await _persistence.runTransaction('New mutation batch', () async {
      batches
        ..add(await _mutationQueue.addMutationBatch(
            Timestamp.now(), <Mutation>[], <SetMutation>[
          setMutation('foo/bar', value),
          setMutation('foo/bar/baz/quux', value)
        ]))
        ..add(await _mutationQueue.addMutationBatch(
            Timestamp.now(), <Mutation>[], <SetMutation>[
          setMutation('foo/bar', value),
          setMutation('foo/baz', value)
        ]));
    });

    final List<MutationBatch> expected = <MutationBatch>[
      batches[0],
      batches[1]
    ];

    final Query query = Query(path('foo'));
    final List<MutationBatch> matches =
        await _mutationQueue.getAllMutationBatchesAffectingQuery(query);

    expect(matches, expected);
  }

  @testMethod
  Future<void> testRemoveMutationBatches() async {
    final List<MutationBatch> batches = await _createBatches(10);

    await _removeMutationBatches(<MutationBatch>[batches.removeAt(0)]);
    await _expectCount(count: 9, isEmpty: false);

    List<MutationBatch> found;

    found = await _mutationQueue.getAllMutationBatches();
    expect(found, batches);
    expect(found.length, 9);

    await _removeMutationBatches(
        <MutationBatch>[batches[0], batches[1], batches[2]]);
    batches //
      ..remove(batches[0])
      ..remove(batches[0])
      ..remove(batches[0]);

    expect(await _batchCount(), 6);

    found = await _mutationQueue.getAllMutationBatches();
    expect(found, batches);
    expect(found.length, 6);

    await _removeMutationBatches(<MutationBatch>[batches.removeAt(0)]);
    expect(await _batchCount(), 5);

    found = await _mutationQueue.getAllMutationBatches();
    expect(found, batches);
    expect(found.length, 5);

    await _removeMutationBatches(<MutationBatch>[batches.removeAt(0)]);
    expect(await _batchCount(), 4);

    await _removeMutationBatches(<MutationBatch>[batches.removeAt(0)]);
    expect(await _batchCount(), 3);

    found = await _mutationQueue.getAllMutationBatches();
    expect(found, batches);
    expect(found.length, 3);

    await _removeMutationBatches(batches);
    found = await _mutationQueue.getAllMutationBatches();
    expect(found, isEmpty);
    expect(found.length, 0);
    await _expectCount(count: 0, isEmpty: true);
  }

  @testMethod
  Future<void> testStreamToken() async {
    final Uint8List streamToken1 = resumeToken('token1');
    final Uint8List streamToken2 = resumeToken('token2');

    await _persistence.runTransaction('initial stream token',
        () => _mutationQueue.setLastStreamToken(streamToken1));

    final MutationBatch batch1 = await _addMutationBatch();
    await _addMutationBatch();

    expect(_mutationQueue.lastStreamToken, streamToken1);

    await _persistence.runTransaction('acknowledgeBatchId',
        () => _mutationQueue.acknowledgeBatch(batch1, streamToken2));

    expect(_mutationQueue.lastStreamToken, streamToken2);
  }

  /// Creates a new [MutationBatch] with the given key, the next batch ID and a set of dummy mutations.
  Future<MutationBatch> _addMutationBatch([String key = 'foo/bar']) {
    final SetMutation mutation = setMutation(key, map(<dynamic>['a', 1]));

    return _persistence.runTransactionAndReturn(
        'New mutation batch',
        () => _mutationQueue.addMutationBatch(
            Timestamp.now(), <Mutation>[], <SetMutation>[mutation]));
  }

  /// Creates a list of batches containing [number] dummy [MutationBatches]. Each has a different batchId.
  Future<List<MutationBatch>> _createBatches(int number) async {
    final List<MutationBatch> batches = <MutationBatch>[];
    for (int i = 0; i < number; i++) {
      batches.add(await _addMutationBatch());
    }
    return batches;
  }

  /// Calls [_removeMutationBatches] on the mutation queue in a new transaction and commits.
  Future<void> _removeMutationBatches(List<MutationBatch> batches) async {
    await _persistence.runTransaction('Remove mutation batches', () async {
      for (MutationBatch batch in batches) {
        await _mutationQueue.removeMutationBatch(batch);
      }
    });
  }

  /// Returns the number of mutation batches in the mutation queue.
  Future<int> _batchCount() {
    return _persistence.runTransactionAndReturn('batchCount',
        () async => (await _mutationQueue.getAllMutationBatches()).length);
  }

  /// Removes the first n from the given [batches] and returns them.
  ///
  /// [n] The number of batches to remove
  /// [batches] the list to mutate, removing entries from it.
  ///
  /// Returns a new list containing all the entries that were removed from [batches].
  Future<List<MutationBatch>> _removeFirstBatches(
      int n, List<MutationBatch> batches) async {
    final List<MutationBatch> removed = <MutationBatch>[];
    for (int i = 0; i < n; i++) {
      final MutationBatch batch = batches[0];
      await _removeMutationBatches(<MutationBatch>[batch]);
      batches.removeAt(0);
      removed.add(batch);
    }
    return removed;
  }

  Future<void> _expectCount({int count, bool isEmpty}) async {
    await _persistence.runTransaction('expectCount', () async {
      final bool empty = await _mutationQueue.isEmpty();
      expect(empty, isEmpty);
    });

    final int batch = await _batchCount();
    expect(batch, count);
  }
}
