// File created by
// Lung Razvan <long1eu>
// on 21/09/2018

part of memory_persistence;

/// Provides LRU garbage collection functionality for [MemoryPersistence].
class MemoryLruReferenceDelegate implements ReferenceDelegate, LruDelegate {
  MemoryLruReferenceDelegate(
      this.persistence, LruGarbageCollectorParams params, this.serializer)
      : orphanedSequenceNumbers = <DocumentKey, int>{},
        listenSequence =
            ListenSequence(persistence.queryCache.highestListenSequenceNumber),
        _currentSequenceNumber = ListenSequence.invalid {
    garbageCollector = LruGarbageCollector(this, params);
  }

  final MemoryPersistence persistence;
  final LocalSerializer serializer;
  final Map<DocumentKey, int> orphanedSequenceNumbers;

  final ListenSequence listenSequence;
  int _currentSequenceNumber;

  @override
  ReferenceSet inMemoryPins;

  @override
  LruGarbageCollector garbageCollector;

  @override
  void onTransactionStarted() {
    hardAssert(_currentSequenceNumber == ListenSequence.invalid,
        'Starting a transaction without committing the previous one');
    _currentSequenceNumber = listenSequence.next;
  }

  @override
  Future<void> onTransactionCommitted() async {
    hardAssert(_currentSequenceNumber != ListenSequence.invalid,
        'Committing a transaction without having started one');
    _currentSequenceNumber = ListenSequence.invalid;
  }

  @override
  int get currentSequenceNumber {
    hardAssert(_currentSequenceNumber != ListenSequence.invalid,
        'Attempting to get a sequence number outside of a transaction');
    return _currentSequenceNumber;
  }

  @override
  Future<void> forEachTarget(Consumer<QueryData> consumer) async {
    await persistence.queryCache.forEachTarget(consumer);
  }

  @override
  Future<int> getSequenceNumberCount() async {
    final int targetCount = persistence.queryCache.targetCount;
    int orphanedCount = 0;
    await forEachOrphanedDocumentSequenceNumber(
        (int sequenceNumber) => orphanedCount++);
    return targetCount + orphanedCount;
  }

  @override
  Future<void> forEachOrphanedDocumentSequenceNumber(
      Consumer<int> consumer) async {
    for (MapEntry<DocumentKey, int> entry in orphanedSequenceNumbers.entries) {
      // Pass in the exact sequence number as the upper bound so we know it won't be pinned by being too recent.
      final bool isPinned = await _isPinned(entry.key, entry.value);
      if (!isPinned) {
        consumer(entry.value);
      }
    }
  }

  @override
  Future<int> removeTargets(int upperBound, Set<int> activeTargetIds) async {
    return persistence.queryCache.removeQueries(upperBound, activeTargetIds);
  }

  @override
  Future<int> removeOrphanedDocuments(int upperBound) async {
    int count = 0;
    final MemoryRemoteDocumentCache cache = persistence.remoteDocumentCache;
    for (MapEntry<DocumentKey, MaybeDocument> entry in cache.documents) {
      final DocumentKey key = entry.key;
      if (!(await _isPinned(key, upperBound))) {
        await cache.remove(key);
        orphanedSequenceNumbers.remove(key);
        count++;
      }
    }
    return count;
  }

  @override
  Future<void> removeMutationReference(DocumentKey key) async {
    orphanedSequenceNumbers[key] = currentSequenceNumber;
  }

  @override
  Future<void> removeTarget(QueryData queryData) async {
    final QueryData updated = queryData.copyWith(
      snapshotVersion: queryData.snapshotVersion,
      resumeToken: queryData.resumeToken,
      sequenceNumber: currentSequenceNumber,
    );
    await persistence.queryCache.updateQueryData(updated);
  }

  @override
  Future<void> addReference(DocumentKey key) async {
    orphanedSequenceNumbers[key] = currentSequenceNumber;
  }

  @override
  Future<void> removeReference(DocumentKey key) async {
    orphanedSequenceNumbers[key] = currentSequenceNumber;
  }

  @override
  Future<void> updateLimboDocument(DocumentKey key) async {
    orphanedSequenceNumbers[key] = currentSequenceNumber;
  }

  bool _mutationQueuesContainsKey(DocumentKey key) {
    for (MemoryMutationQueue mutationQueue in persistence.getMutationQueues()) {
      if (mutationQueue.containsKey(key)) {
        return true;
      }
    }
    return false;
  }

  /// Returns [true] if there is anything that would keep the given document alive or if the document's sequence number
  /// is greater than the provided upper bound.
  Future<bool> _isPinned(DocumentKey key, int upperBound) async {
    if (_mutationQueuesContainsKey(key)) {
      return true;
    }

    if (inMemoryPins.containsKey(key)) {
      return true;
    }

    if (await persistence.queryCache.containsKey(key)) {
      return true;
    }

    final int sequenceNumber = orphanedSequenceNumbers[key];
    return sequenceNumber != null && sequenceNumber > upperBound;
  }

  @override
  Future<int> get byteSize async {
    // Note that this method is only used for testing because this delegate is only used for testing. The algorithm here
    // (loop through everything, serialize it and count bytes) is inefficient and inexact, but won't run in production.
    int count = 0;
    count += persistence.queryCache.getByteSize(serializer);
    count += persistence.remoteDocumentCache.getByteSize(serializer);
    for (MemoryMutationQueue queue in persistence.getMutationQueues()) {
      count += queue.getByteSize(serializer);
    }
    return count;
  }
}
