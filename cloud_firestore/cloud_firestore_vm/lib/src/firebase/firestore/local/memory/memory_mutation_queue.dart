// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

part of memory_persistence;

class MemoryMutationQueue implements MutationQueue {
  MemoryMutationQueue(this.persistence, this._statsCollector)
      : _queue = <MutationBatch>[],
        _batchesByDocumentKey = ImmutableSortedSet<DocumentReference>(
            <DocumentReference>[], DocumentReference.byKey),
        _nextBatchId = 1,
        lastStreamToken = Uint8List(0);

  /// A FIFO queue of all mutations to apply to the backend. Mutations are added to the end of the queue as they're
  /// written, and removed from the front of the queue as the mutations become visible or are rejected.
  ///
  /// When successfully applied, mutations must be acknowledged by the write stream and made visible on the watch
  /// stream. It's possible for the watch stream to fall behind in which case the batches at the head of the queue will
  /// be acknowledged but held until the watch stream sees the changes.
  ///
  /// If a batch is rejected while there are held write acknowledgements at the head of the queue the rejected batch is
  /// converted to a tombstone: its mutations are removed but the batch remains in the queue. This maintains a simple
  /// consecutive ordering of batches in the queue.
  ///
  /// Once the held write acknowledgements become visible they are removed from the head of the queue along with any
  /// tombstones that follow.
  final List<MutationBatch> _queue;

  /// An ordered mapping between documents and the mutation batch ids.
  ImmutableSortedSet<DocumentReference> _batchesByDocumentKey;

  /// The next value to use when assigning sequential ids to each mutation batch.
  int _nextBatchId;

  /// The last received stream token from the server, used to acknowledge which responses the client has processed.
  /// Stream tokens are opaque checkpoint markers whose only real value is their inclusion in the next request.
  @override
  Uint8List lastStreamToken;

  final MemoryPersistence persistence;
  final StatsCollector _statsCollector;

  // MutationQueue implementation

  @override
  Future<void> start() async {
    // Note: The queue may be shutdown / started multiple times, since we maintain the queue for the duration of the app
    // session in case a user logs out / back in. To behave like the SQLite-backed [MutationQueue] (and accommodate
    // tests that expect as much), we reset [nextBatchId] if the queue is empty.
    final bool queueIsEmpty = await isEmpty();
    if (queueIsEmpty) {
      _nextBatchId = 1;
    }
  }

  @override
  Future<bool> isEmpty() async {
    // If the queue has any entries at all, the first entry must not be a tombstone (otherwise it would have been
    // removed already).
    return _queue.isEmpty;
  }

  @override
  Future<void> acknowledgeBatch(
      MutationBatch batch, Uint8List streamToken) async {
    final int batchId = batch.batchId;
    final int batchIndex = _indexOfExistingBatchId(batchId, 'acknowledged');
    hardAssert(batchIndex == 0,
        'Can only acknowledge the first batch in the mutation queue');

    // Verify that the batch in the queue is the one to be acknowledged.
    final MutationBatch check = _queue[batchIndex];
    hardAssert(batchId == check.batchId,
        'Queue ordering failure: expected batch $batchId, got batch ${check.batchId}');

    lastStreamToken = checkNotNull(streamToken);
  }

  @override
  Future<void> setLastStreamToken(Uint8List streamToken) async {
    lastStreamToken = checkNotNull(streamToken);
  }

  @override
  Future<MutationBatch> addMutationBatch(
    Timestamp localWriteTime,
    List<Mutation> baseMutations,
    List<Mutation> mutations,
  ) async {
    hardAssert(mutations.isNotEmpty, 'Mutation batches should not be empty');

    final int batchId = _nextBatchId;
    _nextBatchId += 1;

    final int size = _queue.length;
    if (size > 0) {
      final MutationBatch prior = _queue[size - 1];
      hardAssert(prior.batchId < batchId,
          'Mutation batchIds must be monotonically increasing order');
    }

    final MutationBatch batch = MutationBatch(
      batchId: batchId,
      localWriteTime: localWriteTime,
      baseMutations: baseMutations,
      mutations: mutations,
    );
    _queue.add(batch);

    // Track references by document key and index collection parents.
    for (Mutation mutation in mutations) {
      _batchesByDocumentKey = _batchesByDocumentKey
          .insert(DocumentReference(mutation.key, batchId));

      await persistence.indexManager
          .addToCollectionParentIndex(mutation.key.path.popLast());
    }

    _statsCollector.recordRowsWritten(MutationQueue.statsTag, 1);
    return batch;
  }

  @override
  Future<MutationBatch> lookupMutationBatch(int batchId) async {
    _statsCollector.recordRowsRead(MutationQueue.statsTag, 1);
    final int index = _indexOfBatchId(batchId);
    if (index < 0 || index >= _queue.length) {
      return null;
    }

    final MutationBatch batch = _queue[index];
    hardAssert(batch.batchId == batchId, 'If found batch must match');
    return batch;
  }

  @override
  Future<MutationBatch> getNextMutationBatchAfterBatchId(int batchId) async {
    final int nextBatchId = batchId + 1;

    // The requested batchId may still be out of range so normalize it to the start of the queue.
    final int rawIndex = _indexOfBatchId(nextBatchId);
    final int index = rawIndex < 0 ? 0 : rawIndex;
    return _queue.length > index ? _queue[index] : null;
  }

  @override
  Future<List<MutationBatch>> getAllMutationBatches() async {
    return List<MutationBatch>.unmodifiable(_queue);
  }

  @override
  Future<List<MutationBatch>> getAllMutationBatchesAffectingDocumentKey(
      DocumentKey documentKey) async {
    final DocumentReference start = DocumentReference(documentKey, 0);

    final List<MutationBatch> result = <MutationBatch>[];
    final Iterator<DocumentReference> iterator =
        _batchesByDocumentKey.iteratorFrom(start);
    while (iterator.moveNext()) {
      final DocumentReference reference = iterator.current;
      if (documentKey != reference.key) {
        break;
      }

      final MutationBatch batch = await lookupMutationBatch(reference.id);
      hardAssert(
          batch != null, 'Batches in the index must exist in the main table');
      result.add(batch);
    }

    _statsCollector.recordRowsRead(MutationQueue.statsTag, result.length);
    return result;
  }

  @override
  Future<List<MutationBatch>> getAllMutationBatchesAffectingDocumentKeys(
      Iterable<DocumentKey> documentKeys) async {
    ImmutableSortedSet<int> uniqueBatchIDs =
        ImmutableSortedSet<int>(<int>[], standardComparator<num>());

    for (DocumentKey key in documentKeys) {
      final DocumentReference start = DocumentReference(key, 0);
      final Iterator<DocumentReference> batchesIterator =
          _batchesByDocumentKey.iteratorFrom(start);
      while (batchesIterator.moveNext()) {
        final DocumentReference reference = batchesIterator.current;
        if (key != reference.key) {
          break;
        }
        uniqueBatchIDs = uniqueBatchIDs.insert(reference.id);
      }
    }

    return _lookupMutationBatches(uniqueBatchIDs);
  }

  @override
  Future<List<MutationBatch>> getAllMutationBatchesAffectingQuery(
      Query query) async {
    hardAssert(!query.isCollectionGroupQuery,
        'CollectionGroup queries should be handled in LocalDocumentsView');

    // Use the query path as a prefix for testing if a document matches the query.
    final ResourcePath prefix = query.path;
    final int immediateChildrenPathLength = prefix.length + 1;

    // Construct a document reference for actually scanning the index. Unlike the prefix, the document key in this
    // reference must have an even number of segments. The empty segment can be used as a suffix of the query path
    // because it precedes all other segments in an ordered traversal.
    ResourcePath startPath = prefix;
    if (!DocumentKey.isDocumentKey(startPath)) {
      startPath = startPath.appendSegment('');
    }
    final DocumentReference start =
        DocumentReference(DocumentKey.fromPath(startPath), 0);

    // Find unique [batchId]s referenced by all documents potentially matching the query.
    ImmutableSortedSet<int> uniqueBatchIDs =
        ImmutableSortedSet<int>(<int>[], standardComparator<num>());

    final Iterator<DocumentReference> iterator =
        _batchesByDocumentKey.iteratorFrom(start);
    while (iterator.moveNext()) {
      final DocumentReference reference = iterator.current;
      final ResourcePath rowKeyPath = reference.key.path;
      if (!prefix.isPrefixOf(rowKeyPath)) {
        break;
      }

      // Rows with document keys more than one segment longer than the query path can't be matches.
      // For example, a query on 'rooms' can't match the document /rooms/abc/messages/xyx.
      // TODO(long1eu): we'll need a different scanner when we implement ancestor queries.
      if (rowKeyPath.length == immediateChildrenPathLength) {
        uniqueBatchIDs = uniqueBatchIDs.insert(reference.id);
      }
    }

    return _lookupMutationBatches(uniqueBatchIDs);
  }

  Future<List<MutationBatch>> _lookupMutationBatches(
      ImmutableSortedSet<int> batchIds) async {
    // Construct an array of matching batches, sorted by batchId to ensure that multiple mutations affecting the same
    // document key are applied in order.
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
  Future<void> removeMutationBatch(MutationBatch batch) async {
    // Find the position of the first batch for removal. This need not be the first entry in the queue.
    final int batchIndex = _indexOfExistingBatchId(batch.batchId, 'removed');
    hardAssert(batchIndex == 0,
        'Can only remove the first entry of the mutation queue');

    _queue.removeAt(0);

    // Remove entries from the index too.
    ImmutableSortedSet<DocumentReference> references = _batchesByDocumentKey;
    for (Mutation mutation in batch.mutations) {
      final DocumentKey key = mutation.key;
      await persistence.referenceDelegate.removeMutationReference(key);

      final DocumentReference reference = DocumentReference(key, batch.batchId);
      references = references.remove(reference);
    }

    _batchesByDocumentKey = references;
  }

  @override
  Future<void> performConsistencyCheck() async {
    if (_queue.isEmpty) {
      hardAssert(_batchesByDocumentKey.isEmpty,
          'Document leak -- detected dangling mutation references when queue is empty.');
    }
  }

  bool containsKey(DocumentKey key) {
    // Create a reference with a zero ID as the start position to find any document reference with this key.
    final DocumentReference reference = DocumentReference(key, 0);

    final Iterator<DocumentReference> iterator =
        _batchesByDocumentKey.iteratorFrom(reference);
    if (!iterator.moveNext()) {
      return false;
    }

    final DocumentKey firstKey = iterator.current.key;
    return firstKey == key;
  }

  // Helpers

  /// Finds the index of the given batchId in the mutation queue. This operation
  /// is O(1).
  ///
  /// Returns the computed index of the batch with the given [batchId], based on
  /// the state of the queue. Note this index can be negative if the requested
  /// [batchId] has already been removed from the queue or past the end of the
  /// queue if the [batchId] is larger than the last added batch.
  int _indexOfBatchId(int batchId) {
    if (_queue.isEmpty) {
      // As an index this is past the end of the queue
      return 0;
    }

    // Examine the front of the queue to figure out the difference between the
    // [batchId] and indexes in the array. Note that since the queue is ordered
    // by [batchId], if the first batch has a larger [batchId] then the
    // requested [batchId] doesn't exist in the queue.
    final MutationBatch firstBatch = _queue[0];
    final int firstBatchId = firstBatch.batchId;
    return batchId - firstBatchId;
  }

  /// Finds the index of the given [batchId] in the mutation queue and asserts
  /// that the resulting index is within the bounds of the queue. The [batchId]
  /// to search for [action] is description of what the caller is doing, phrased
  /// in passive form (e.g. 'acknowledged' in a routine that acknowledges
  /// batches).
  int _indexOfExistingBatchId(int batchId, String action) {
    final int index = _indexOfBatchId(batchId);
    hardAssert(index >= 0 && index < _queue.length,
        'Batches must exist to be $action');
    return index;
  }

  int getByteSize(LocalSerializer serializer) {
    int count = 0;
    for (MutationBatch batch in _queue) {
      count += serializer.encodeMutationBatch(batch).writeToBuffer().length;
    }
    return count;
  }
}
