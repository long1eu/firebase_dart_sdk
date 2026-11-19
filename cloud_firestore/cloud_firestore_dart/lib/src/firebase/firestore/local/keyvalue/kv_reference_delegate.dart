part of 'cache_store_persistence.dart';

/// The LRU reference delegate: the sequence number of a document that no target holds is kept in its `docTarget`
/// entry of target id 0 (the sentinel), as the SQLite and LevelDB persistences of the official SDKs do.
class _KvReferenceDelegate implements ReferenceDelegate, LruDelegate {
  _KvReferenceDelegate(this._db, LruGarbageCollectorParams params) {
    garbageCollector = LruGarbageCollector(this, params);
  }

  final CacheStorePersistence _db;
  late ListenSequence _listenSequence;
  int _currentSequenceNumber = ListenSequence.invalid;

  @override
  late ReferenceSet inMemoryPins;

  @override
  late final LruGarbageCollector garbageCollector;

  void start(int highestSequenceNumber) {
    _listenSequence = ListenSequence(highestSequenceNumber);
  }

  @override
  void onTransactionStarted() {
    hardAssert(
      _currentSequenceNumber == ListenSequence.invalid,
      'Starting a transaction without committing the previous one',
    );
    _currentSequenceNumber = _listenSequence.next;
  }

  @override
  void onTransactionRolledBack() {
    _currentSequenceNumber = ListenSequence.invalid;
  }

  @override
  Future<void> onTransactionCommitted() async {
    hardAssert(
      _currentSequenceNumber != ListenSequence.invalid,
      'Committing a transaction without having started one',
    );
    _currentSequenceNumber = ListenSequence.invalid;
  }

  @override
  int get currentSequenceNumber {
    hardAssert(
      _currentSequenceNumber != ListenSequence.invalid,
      'Attempting to get a sequence number outside of a transaction',
    );
    return _currentSequenceNumber;
  }

  Uint8List _sentinelKey(DocumentKey key) =>
      _key(_Table.docTarget).documentKey(key).integer(0).bytes;

  Future<void> _writeSentinel(DocumentKey key) => _db._tx.put(
    _sentinelKey(key),
    KvKeyWriter().integer(currentSequenceNumber).bytes,
  );

  @override
  Future<void> addReference(DocumentKey key) => _writeSentinel(key);

  @override
  Future<void> removeReference(DocumentKey key) => _writeSentinel(key);

  @override
  Future<void> removeMutationReference(DocumentKey key) => _writeSentinel(key);

  @override
  Future<void> updateLimboDocument(DocumentKey key) => _writeSentinel(key);

  @override
  Future<void> removeTarget(QueryData queryData) async {
    await _db.queryCache.updateQueryData(
      queryData.copyWith(
        snapshotVersion: queryData.snapshotVersion,
        resumeToken: queryData.resumeToken,
        sequenceNumber: currentSequenceNumber,
      ),
    );
  }

  /// Calls [onOrphan] with each document that only has a sentinel (no target holds it) and its sequence number, in
  /// key order. `docTarget` is ordered by document and then target id, so the sentinel (id 0) of a document comes
  /// first among its entries.
  Future<void> _forEachOrphan(
    FutureOr<void> Function(DocumentKey key, int sequenceNumber) onOrphan,
  ) async {
    DocumentKey? candidate;
    int candidateSequenceNumber = 0;
    final List<(DocumentKey, int)> orphans = <(DocumentKey, int)>[];
    await _db._scanPrefix(_key(_Table.docTarget).bytes, (
      List<CacheStoreEntry> page,
    ) {
      for (final CacheStoreEntry entry in page) {
        final KvKeyReader reader = KvKeyReader(entry.key)..string();
        final DocumentKey key = reader.documentKey();
        final int targetId = reader.integer();
        if (candidate != null && candidate != key) {
          orphans.add((candidate!, candidateSequenceNumber));
          candidate = null;
        }
        if (targetId == 0) {
          candidate = key;
          candidateSequenceNumber = KvKeyReader(entry.value).integer();
        } else if (candidate == key) {
          candidate = null;
        }
      }
      return true;
    });
    if (candidate != null) {
      orphans.add((candidate!, candidateSequenceNumber));
    }
    for (final (DocumentKey key, int sequenceNumber) in orphans) {
      await onOrphan(key, sequenceNumber);
    }
  }

  @override
  Future<int> getSequenceNumberCount() async {
    int orphans = 0;
    await _forEachOrphan((_, _) => orphans++);
    return _db.queryCache.targetCount + orphans;
  }

  @override
  Future<void> forEachTarget(Consumer<QueryData> consumer) =>
      _db.queryCache.forEachTarget(consumer);

  @override
  Future<void> forEachOrphanedDocumentSequenceNumber(Consumer<int> consumer) =>
      _forEachOrphan((_, int sequenceNumber) => consumer(sequenceNumber));

  @override
  Future<int> removeTargets(int upperBound, Set<int> activeTargetIds) =>
      _db.queryCache._removeQueries(upperBound, activeTargetIds);

  @override
  Future<int> removeOrphanedDocuments(int upperBound) async {
    final List<DocumentKey> removed = <DocumentKey>[];
    await _forEachOrphan((DocumentKey key, int sequenceNumber) async {
      if (sequenceNumber > upperBound ||
          inMemoryPins.containsKey(key) ||
          await _db._mutationQueuesContainKey(key)) {
        return;
      }
      removed.add(key);
      await _db._tx.delete(_sentinelKey(key));
    });
    await _db.remoteDocumentCache.removeAll(removed);
    return removed.length;
  }

  @override
  Future<int> get byteSize async => _db.remoteDocumentCache.byteSize;
}
