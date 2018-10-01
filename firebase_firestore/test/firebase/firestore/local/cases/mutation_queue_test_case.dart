// File created by
// Lung Razvan <long1eu>
// on 01/10/2018

import 'dart:async';

import 'package:firebase_firestore/src/firebase/firestore/auth/user.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/mutation_queue.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/persistence.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/set_mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/write_stream.dart';
import 'package:firebase_firestore/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

class MutationQueueTestCase {
  final Persistence persistence;
  MutationQueue mutationQueue;

  MutationQueueTestCase(this.persistence);

  Future<void> setUp() async {
    mutationQueue = persistence.getMutationQueue(User.unauthenticated);
    await mutationQueue.start();
  }

  Future<void> tearDown() => persistence.shutdown();

  /// Creates a new [MutationBatch] with the given key, the next batch ID and a
  /// set of dummy mutations.
  Future<MutationBatch> addMutationBatch([String key = 'foo/bar']) {
    final SetMutation mutation = setMutation(key, map(<dynamic>['a', 1]));

    return persistence.runTransactionAndReturn(
        'New mutation batch',
        () => mutationQueue
            .addMutationBatch(Timestamp.now(), <SetMutation>[mutation]));
  }

  /// Creates a list of batches containing [number] dummy [MutationBatches].
  /// Each has a different batchId.
  Future<List<MutationBatch>> createBatches(int number) async {
    final List<MutationBatch> batches = List<MutationBatch>(number);
    for (int i = 0; i < number; i++) {
      batches[i] = await addMutationBatch();
    }
    return batches;
  }

  Future<void> acknowledgeBatch(MutationBatch batch) async {
    await persistence.runTransaction(
        'Ack batchId',
        () => mutationQueue.acknowledgeBatch(
            batch, WriteStream.emptyStreamToken));
  }

  /// Calls [removeMutationBatches] on the mutation queue in a new transaction
  /// and commits.
  Future<void> removeMutationBatches(List<MutationBatch> batches) async {
    await persistence.runTransaction('Remove mutation batches',
        () => mutationQueue.removeMutationBatches(batches));
  }

  /// Returns the number of mutation batches in the mutation queue.
  Future<int> batchCount() {
    return persistence.runTransactionAndReturn('batchCount',
        () async => (await mutationQueue.getAllMutationBatches()).length);
  }

  /// Removes entries from the given [batches] and returns them.
  ///
  /// [holes] is an list of indexes in the batches list; in increasing order.
  /// Indexes are relative to the original state of the batches list, not any
  /// intermediate state that might occur.
  /// [batches] the list to mutate, removing entries from it.
  ///
  /// Returns a new list containing all the entries that were removed from
  /// [batches].
  Future<List<MutationBatch>> makeHoles(
      List<int> holes, List<MutationBatch> batches) async {
    final List<MutationBatch> removed = <MutationBatch>[];
    for (int i = 0; i < holes.length; i++) {
      final int index = holes[i] - i;
      final MutationBatch batch = batches[index];
      await removeMutationBatches(<MutationBatch>[batch]);

      batches.removeAt(index);
      removed.add(batch);
    }
    return removed;
  }

  Future<void> expectCount({int count, bool isEmpty}) async {
    final int batch = await batchCount();
    expect(batch, count);

    await persistence.runTransaction('expectCount', () async {
      final bool empty = await mutationQueue.isEmpty();
      expect(empty, isEmpty);
    });
  }
}

// ignore: always_specify_types
const setMutation = TestUtil.setMutation;
// ignore: always_specify_types
const patchMutation = TestUtil.patchMutation;
// ignore: always_specify_types
const map = TestUtil.map;
// ignore: always_specify_types
const key = TestUtil.key;
