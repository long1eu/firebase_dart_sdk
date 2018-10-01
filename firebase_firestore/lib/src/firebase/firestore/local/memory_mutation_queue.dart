// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:firebase_database_collection/firebase_database_collection.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/document_reference.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/memory_persistence.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/mutation_queue.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/resource_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/write_stream.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';
import 'package:firebase_firestore/src/firebase/timestamp.dart';

class MemoryMutationQueue implements MutationQueue {
  /// A FIFO queue of all mutations to apply to the backend. Mutations are added
  /// to the end of the queue as they're written, and removed from the front of
  /// the queue as the mutations become visible or are rejected.
  ///
  /// * When successfully applied, mutations must be acknowledged by the write
  /// stream and made visible on the watch stream. It's possible for the watch
  /// stream to fall behind in which case the batches at the head of the queue
  /// will be acknowledged but held until the watch stream sees the changes.
  ///
  /// * If a batch is rejected while there are held write acknowledgements at
  /// the head of the queue the rejected batch is converted to a tombstone: its
  /// mutations are removed but the batch remains in the queue. This maintains
  /// a simple consecutive ordering of batches in the queue.
  ///
  /// * Once the held write acknowledgements become visible they are removed
  /// from the head of the queue along with any tombstones that follow.
  final List<MutationBatch> queue;

  /// An ordered mapping between documents and the mutation batch ids.
  ImmutableSortedSet<DocumentReference> batchesByDocumentKey;

  /// The next value to use when assigning sequential ids to each mutation
  /// batch.
  @override
  int nextBatchId;

  /// The highest acknowledged mutation in the queue.
  @override
  int highestAcknowledgedBatchId;

  /// The last received stream token from the server, used to acknowledge which
  /// responses the client has processed. Stream tokens are opaque checkpoint
  /// markers whose only real value is their inclusion in the next request.
  @override
  Uint8List lastStreamToken;

  final MemoryPersistence persistence;

  MemoryMutationQueue(this.persistence)
      : queue = <MutationBatch>[],
        batchesByDocumentKey = ImmutableSortedSet<DocumentReference>(
            <DocumentReference>[], DocumentReference.byKey),
        nextBatchId = 1,
        highestAcknowledgedBatchId = MutationBatch.unknown,
        lastStreamToken = WriteStream.emptyStreamToken;

  // MutationQueue implementation

  @override
  Future<void> start() async {
    // Note: The queue may be shutdown / started multiple times, since we
    // maintain the queue for the duration of the app session in case a user
    // logs out / back in. To behave like the SQLite-backed [MutationQueue]
    // (and accommodate tests that expect as much), we reset [nextBatchId] and
    // [highestAcknowledgedBatchId] if the queue is empty.
    if (await isEmpty()) {
      nextBatchId = 1;
      highestAcknowledgedBatchId = MutationBatch.unknown;
    }
    Assert.hardAssert(highestAcknowledgedBatchId < nextBatchId,
        'highestAcknowledgedBatchId must be less than the nextBatchId');
  }

  @override
  Future<bool> isEmpty() async {
    // If the queue has any entries at all, the first entry must not be a
    // tombstone (otherwise it would have been removed already).
    return queue.isEmpty;
  }

  @override
  Future<void> acknowledgeBatch(
      MutationBatch batch, Uint8List streamToken) async {
    final int batchId = batch.batchId;
    Assert.hardAssert(batchId > highestAcknowledgedBatchId,
        'Mutation batchIds must be acknowledged in order');

    final int batchIndex = indexOfExistingBatchId(batchId, 'acknowledged');

    // Verify that the batch in the queue is the one to be acknowledged.
    final MutationBatch check = queue[batchIndex];
    Assert.hardAssert(batchId == check.batchId,
        'Queue ordering failure: expected batch $batchId, got batch ${check.batchId}');
    Assert.hardAssert(
        !check.isTombstone, 'Can\'t acknowledge a previously removed batch');

    highestAcknowledgedBatchId = batchId;
    lastStreamToken = Assert.checkNotNull(streamToken);
  }

  @override
  Future<void> setLastStreamToken(Uint8List streamToken) async {
    lastStreamToken = Assert.checkNotNull(streamToken);
  }

  @override
  Future<MutationBatch> addMutationBatch(
      Timestamp localWriteTime, List<Mutation> mutations) async {
    Assert.hardAssert(
        mutations.isNotEmpty, 'Mutation batches should not be empty');

    final int batchId = nextBatchId;
    nextBatchId += 1;

    final int size = queue.length;
    if (size > 0) {
      final MutationBatch prior = queue[size - 1];
      Assert.hardAssert(prior.batchId < batchId,
          'Mutation batchIds must be monotonically increasing order');
    }

    final MutationBatch batch =
        MutationBatch(batchId, localWriteTime, mutations);
    queue.add(batch);

    // Track references by document key.
    for (Mutation mutation in mutations) {
      batchesByDocumentKey =
          batchesByDocumentKey.insert(DocumentReference(mutation.key, batchId));
    }

    return batch;
  }

  @override
  Future<MutationBatch> lookupMutationBatch(int batchId) async {
    final int index = indexOfBatchId(batchId);
    if (index < 0 || index >= queue.length) {
      return null;
    }

    final MutationBatch batch = queue[index];
    Assert.hardAssert(batch.batchId == batchId, 'If found batch must match');
    return batch.isTombstone ? null : batch;
  }

  @override
  Future<MutationBatch> getNextMutationBatchAfterBatchId(int batchId) async {
    final int size = queue.length;

    // All batches with [batchId] <= [highestAcknowledgedBatchId] have been
    // acknowledged so the first unacknowledged batch after batchId will have a
    // [batchId] larger than both of these values.
    final int nextBatchId = max(batchId, highestAcknowledgedBatchId) + 1;

    // The requested batchId may still be out of range so normalize it to the
    // start of the queue.
    final int rawIndex = indexOfBatchId(nextBatchId);
    int index = rawIndex < 0 ? 0 : rawIndex;

    // Finally return the first non-tombstone batch.
    for (; index < size; index++) {
      final MutationBatch batch = queue[index];
      if (!batch.isTombstone) {
        return batch;
      }
    }

    return null;
  }

  @override
  Future<List<MutationBatch>> getAllMutationBatches() async {
    return getAllLiveMutationBatchesBeforeIndex(queue.length);
  }

  @override
  Future<List<MutationBatch>> getAllMutationBatchesThroughBatchId(
      int batchId) async {
    final int count = queue.length;

    int endIndex = indexOfBatchId(batchId);
    if (endIndex < 0) {
      endIndex = 0;
    } else if (endIndex >= count) {
      endIndex = count;
    } else {
      // The endIndex is in the queue so increment to pull everything in the
      // queue including it.
      endIndex += 1;
    }

    return getAllLiveMutationBatchesBeforeIndex(endIndex);
  }

  @override
  Future<List<MutationBatch>> getAllMutationBatchesAffectingDocumentKey(
      DocumentKey documentKey) async {
    final DocumentReference start = DocumentReference(documentKey, 0);

    final List<MutationBatch> result = <MutationBatch>[];
    final Iterator<DocumentReference> iterator =
        batchesByDocumentKey.iteratorFrom(start);
    while (iterator.moveNext()) {
      final DocumentReference reference = iterator.current;
      if (documentKey != reference.key) {
        break;
      }

      final MutationBatch batch = await lookupMutationBatch(reference.id);
      Assert.hardAssert(
          batch != null, 'Batches in the index must exist in the main table');
      result.add(batch);
    }

    return result;
  }

  @override
  Future<List<MutationBatch>> getAllMutationBatchesAffectingDocumentKeys(
      Iterable<DocumentKey> documentKeys) async {
    ImmutableSortedSet<int> uniqueBatchIDs = ImmutableSortedSet<int>();

    for (DocumentKey key in documentKeys) {
      final DocumentReference start = DocumentReference(key, 0);
      final Iterator<DocumentReference> batchesIterator =
          batchesByDocumentKey.iteratorFrom(start);
      while (batchesIterator.moveNext()) {
        final DocumentReference reference = batchesIterator.current;
        if (key != reference.key) {
          break;
        }
        uniqueBatchIDs = uniqueBatchIDs.insert(reference.id);
      }
    }

    return lookupMutationBatches(uniqueBatchIDs);
  }

  @override
  Future<List<MutationBatch>> getAllMutationBatchesAffectingQuery(
      Query query) async {
    // Use the query path as a prefix for testing if a document matches the
    // query.
    final ResourcePath prefix = query.path;
    final int immediateChildrenPathLength = prefix.length + 1;

    // Construct a document reference for actually scanning the index. Unlike
    // the prefix, the document key in this reference must have an even number
    // of segments. The empty segment can be used as a suffix of the query path
    // because it precedes all other segments in an ordered traversal.
    ResourcePath startPath = prefix;
    if (!DocumentKey.isDocumentKey(startPath)) {
      startPath = startPath.appendSegment('');
    }
    final DocumentReference start =
        DocumentReference(DocumentKey.fromPath(startPath), 0);

    // Find unique [batchId]s referenced by all documents potentially matching the
    // query.
    ImmutableSortedSet<int> uniqueBatchIDs = ImmutableSortedSet<int>();

    final Iterator<DocumentReference> iterator =
        batchesByDocumentKey.iteratorFrom(start);
    while (iterator.moveNext()) {
      final DocumentReference reference = iterator.current;
      final ResourcePath rowKeyPath = reference.key.path;
      if (!prefix.isPrefixOf(rowKeyPath)) {
        break;
      }

      // Rows with document keys more than one segment longer than the query
      // path can't be matches. For example, a query on 'rooms' can't match the
      // document /rooms/abc/messages/xyx.
      // TODO: we'll need a different scanner when we implement ancestor queries.
      if (rowKeyPath.length == immediateChildrenPathLength) {
        uniqueBatchIDs = uniqueBatchIDs.insert(reference.id);
      }
    }

    return lookupMutationBatches(uniqueBatchIDs);
  }

  Future<List<MutationBatch>> lookupMutationBatches(
      ImmutableSortedSet<int> batchIds) async {
    // Construct an array of matching batches, sorted by batchId to ensure that
    // multiple mutations affecting the same document key are applied in order.
    final List<MutationBatch> result = <MutationBatch>[];
    for (int batchId in batchIds) {
      final MutationBatch batch = await lookupMutationBatch(batchId);
      if (batch != null) {
        result.add(batch);
      }
    }

    return result;
  }

  @override
  Future<void> removeMutationBatches(List<MutationBatch> batches) async {
    final int batchCount = batches.length;
    Assert.hardAssert(
        batchCount > 0, 'Should not remove mutations when none exist.');

    final int firstBatchId = batches[0].batchId;

    final int queueCount = queue.length;

    // Find the position of the first batch for removal. This need not be the
    // first entry in the queue.
    final int startIndex = indexOfExistingBatchId(firstBatchId, 'removed');
    Assert.hardAssert(queue[startIndex].batchId == firstBatchId,
        'Removed batches must exist in the queue');

    // Check that removed batches are contiguous (while excluding tombstones).
    int batchIndex = 1;
    int queueIndex = startIndex + 1;
    while (batchIndex < batchCount && queueIndex < queueCount) {
      final MutationBatch batch = queue[queueIndex];
      if (batch.isTombstone) {
        queueIndex++;
        continue;
      }

      Assert.hardAssert(batch.batchId == batches[batchIndex].batchId,
          'Removed batches must be contiguous in the queue');
      batchIndex++;
      queueIndex++;
    }

    // Only actually remove batches if removing at the front of the queue.
    // Previously rejected batches may have left tombstones in the queue, so
    // expand the removal range to include any tombstones.
    if (startIndex == 0) {
      for (; queueIndex < queueCount; queueIndex++) {
        final MutationBatch batch = queue[queueIndex];
        if (!batch.isTombstone) {
          break;
        }
      }

      queue.sublist(startIndex, queueIndex).clear();
    } else {
      // Mark tombstones
      for (int i = startIndex; i < queueIndex; i++) {
        queue[i] = queue[i].toTombstone();
      }
    }

    // Remove entries from the index too.
    ImmutableSortedSet<DocumentReference> references = batchesByDocumentKey;
    for (MutationBatch batch in batches) {
      final int batchId = batch.batchId;
      for (Mutation mutation in batch.mutations) {
        final DocumentKey key = mutation.key;
        persistence.referenceDelegate.removeMutationReference(key);

        final DocumentReference reference = DocumentReference(key, batchId);
        references = references.remove(reference);
      }
    }
    batchesByDocumentKey = references;
  }

  @override
  Future<void> performConsistencyCheck() async {
    if (queue.isEmpty) {
      Assert.hardAssert(batchesByDocumentKey.isEmpty,
          'Document leak -- detected dangling mutation references when queue is empty.');
    }
  }

  bool containsKey(DocumentKey key) {
    // Create a reference with a zero ID as the start position to find any
    // document reference with this key.
    final DocumentReference reference = DocumentReference(key, 0);

    final Iterator<DocumentReference> iterator =
        batchesByDocumentKey.iteratorFrom(reference);
    if (!iterator.moveNext()) {
      return false;
    }

    final DocumentKey firstKey = iterator.current.key;
    return firstKey == key;
  }

  // Helpers

  /// A private helper that collects all the mutation batches in the queue up to
  /// but not including the given [endIndex]. All tombstones in the queue are
  /// excluded.
  List<MutationBatch> getAllLiveMutationBatchesBeforeIndex(int endIndex) {
    final List<MutationBatch> result = <MutationBatch>[];

    for (int i = 0; i < endIndex; i++) {
      final MutationBatch batch = queue[i];

      if (!batch.isTombstone) {
        result.add(batch);
      }
    }
    return result.toList(growable: false);
  }

  /// Finds the index of the given batchId in the mutation queue.
  /// This operation is O(1).
  ///
  /// Returns the computed index of the batch with the given [batchId], based on
  /// the state of the queue. Note this index can be negative if the requested
  /// [batchId] has already been removed from the queue or past the end of the
  /// queue if the [batchId] is larger than the last added batch.
  int indexOfBatchId(int batchId) {
    if (queue.isEmpty) {
      // As an index this is past the end of the queue
      return 0;
    }

    // Examine the front of the queue to figure out the difference between the
    // [batchId] and indexes in the array. Note that since the queue is ordered
    // by [batchId], if the first batch has a larger [batchId] then the
    // requested [batchId] doesn't exist in the queue.
    final MutationBatch firstBatch = queue[0];
    final int firstBatchId = firstBatch.batchId;
    return batchId - firstBatchId;
  }

  /// Finds the index of the given [batchId] in the mutation queue and asserts
  /// that the resulting index is within the bounds of the queue. The [batchId]
  /// to search for [action] is description of what the caller is doing, phrased
  /// in passive form (e.g. 'acknowledged' in a routine that acknowledges
  /// batches).
  int indexOfExistingBatchId(int batchId, String action) {
    final int index = indexOfBatchId(batchId);
    Assert.hardAssert(
        index >= 0 && index < queue.length, 'Batches must exist to be $action');
    return index;
  }
}
