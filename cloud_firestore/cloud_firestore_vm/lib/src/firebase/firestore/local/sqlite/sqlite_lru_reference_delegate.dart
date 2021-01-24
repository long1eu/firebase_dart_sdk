// File created by
// Lung Razvan <long1eu>
// on 21/09/2018

part of sqlite_persistence;

class SQLiteLruReferenceDelegate implements ReferenceDelegate, LruDelegate {
  SQLiteLruReferenceDelegate(this.persistence, LruGarbageCollectorParams params)
      : _currentSequenceNumber = ListenSequence.invalid {
    garbageCollector = LruGarbageCollector(this, params);
  }

  /// The batch size for orphaned document GC in [removeOrphanedDocuments].
  ///
  /// This addresses https://github.com/firebase/firebase-android-sdk/issues/706, where a customer
  /// reported that LRU GC hit a CursorWindow size limit during orphaned document removal.
  static const int _kRemoveOrphanedDocumentsBatchSize = 100;

  final SQLitePersistence persistence;
  ListenSequence listenSequence;
  int _currentSequenceNumber;

  @override
  ReferenceSet inMemoryPins;

  @override
  LruGarbageCollector garbageCollector;

  void start(int highestSequenceNumber) {
    listenSequence = ListenSequence(highestSequenceNumber);
  }

  @override
  void onTransactionStarted() {
    hardAssert(
      _currentSequenceNumber == ListenSequence.invalid,
      'Starting a transaction without committing the previous one',
    );
    _currentSequenceNumber = listenSequence.next;
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
    hardAssert(_currentSequenceNumber != ListenSequence.invalid,
        'Attempting to get a sequence number outside of a transaction');
    return _currentSequenceNumber;
  }

  @override
  Future<int> getSequenceNumberCount() async {
    final int targetCount = persistence.targetCache.targetCount;
    final Map<String, dynamic> data = (await persistence.query(
      // @formatter:off
            '''
              SELECT COUNT(*) as count
              FROM (SELECT sequence_number
                    FROM target_documents
                    GROUP BY path
                    HAVING COUNT(*) = 1
                       AND target_id = 0);'''
            // @formatter:on
            ))
        .first;
    return targetCount + data['count'];
  }

  @override
  Future<void> forEachTarget(Consumer<TargetData> consumer) async {
    await persistence.targetCache.forEachTarget(consumer);
  }

  @override
  Future<void> forEachOrphanedDocumentSequenceNumber(Consumer<int> consumer) async {
    final List<Map<String, dynamic>> result = await persistence.query(
      // @formatter:off
        '''
         SELECT sequence_number
         FROM target_documents
         GROUP BY path
         HAVING COUNT(*) = 1
          AND target_id = 0;
        '''
        // @formatter:on
        );

    for (Map<String, dynamic> row in result) {
      consumer(row['sequence_number']);
    }
  }

  @override
  Future<void> addReference(DocumentKey key) async {
    await _writeSentinel(key);
  }

  @override
  Future<void> removeReference(DocumentKey key) async {
    await _writeSentinel(key);
  }

  @override
  Future<int> removeTargets(int upperBound, Set<int> activeTargetIds) {
    return persistence.targetCache.removeQueries(upperBound, activeTargetIds);
  }

  @override
  Future<void> removeMutationReference(DocumentKey key) async {
    await _writeSentinel(key);
  }

  /// Returns true if any mutation queue contains the given document.
  Future<bool> _mutationQueuesContainKey(DocumentKey key) async {
    return (await persistence.query(
      // @formatter:off
        '''
          SELECT 1
          FROM document_mutations
          WHERE path = ?;
        ''',
        // @formatter:on
        <String>[EncodedPath.encode(key.path)])).isNotEmpty;
  }

  /// Returns true if anything would prevent this document from being garbage collected, given that the document in
  /// question is not present in any targets and has a sequence number less than or equal to the upper bound for the
  /// collection run.
  Future<bool> _isPinned(DocumentKey key) async {
    if (inMemoryPins.containsKey(key)) {
      return true;
    }

    return _mutationQueuesContainKey(key);
  }

  Future<void> _removeSentinel(DocumentKey key) async {
    await persistence.execute(
      // @formatter:off
        '''
          DELETE
          FROM target_documents
          WHERE path = ?
             AND target_id = 0;
        ''',
        // @formatter:on
        <String>[EncodedPath.encode(key.path)]);
  }

  @override
  Future<int> removeOrphanedDocuments(int upperBound) async {
    int count = 0;
    final List<Map<String, dynamic>> result = await persistence.query(
      // @formatter:off
        '''
          SELECT path
          FROM target_documents
          GROUP BY path
          HAVING count(*) = 1
             AND target_id = 0
             AND sequence_number <= ?;
        ''',
        // @formatter:on
        <int>[upperBound]);

    for (Map<String, dynamic> row in result) {
      final ResourcePath path = EncodedPath.decodeResourcePath(row['path']);
      final DocumentKey key = DocumentKey.fromPath(path);
      if (!await _isPinned(key)) {
        count++;
        await persistence.remoteDocumentCache.remove(key);
        await _removeSentinel(key);
      }
    }

    bool resultsRemaining = true;
    while (resultsRemaining) {
      int rowsProcessed = 0;
      final List<Map<String, dynamic>> rows = await persistence.query(
        // @formatter:off
          '''
          SELECT path
          FROM target_documents
          GROUP BY path
          HAVING count(*) = 1
             AND target_id = 0
             AND sequence_number <= ?
             LIMIT ?;
        ''',
        // @formatter:on
        <int>[upperBound, _kRemoveOrphanedDocumentsBatchSize],
      );

      for (Map<String, dynamic> row in rows) {
        final ResourcePath path = EncodedPath.decodeResourcePath(row['path']);
        final DocumentKey key = DocumentKey.fromPath(path);
        if (!await _isPinned(key)) {
          count++;
          await persistence.remoteDocumentCache.remove(key);
          await _removeSentinel(key);
        }
        rowsProcessed++;
      }

      resultsRemaining = rowsProcessed == _kRemoveOrphanedDocumentsBatchSize;
    }

    return count;
  }

  @override
  Future<void> removeTarget(TargetData targetData) async {
    final TargetData updated = targetData.copyWith(sequenceNumber: currentSequenceNumber);
    await persistence.targetCache.updateTargetData(updated);
  }

  @override
  Future<void> updateLimboDocument(DocumentKey key) async {
    await _writeSentinel(key);
  }

  Future<void> _writeSentinel(DocumentKey key) async {
    final String path = EncodedPath.encode(key.path);
    await persistence.execute(
      // @formatter:off
        '''
          INSERT
          OR REPLACE INTO target_documents (target_id, path, sequence_number)
          VALUES (0, ?, ?);
        ''',
        // @formatter:on
        <dynamic>[path, currentSequenceNumber]);
  }

  @override
  Future<int> get byteSize => persistence.byteSize;
}
