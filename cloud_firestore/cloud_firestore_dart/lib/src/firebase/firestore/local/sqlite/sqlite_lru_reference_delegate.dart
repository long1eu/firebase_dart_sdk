// File created by
// Lung Razvan <long1eu>
// on 21/09/2018

part of 'sqlite_persistence.dart';

class SQLiteLruReferenceDelegate implements ReferenceDelegate, LruDelegate {
  SQLiteLruReferenceDelegate(this.persistence, LruGarbageCollectorParams params)
    : _currentSequenceNumber = ListenSequence.invalid {
    garbageCollector = LruGarbageCollector(this, params);
  }

  /// The batch size for orphaned document GC in [removeOrphanedDocuments].
  ///
  /// Upstream (`REMOVE_ORPHANED_DOCUMENTS_BATCH_SIZE`) added it for https://github.com/firebase/firebase-android-sdk/issues/706,
  /// where LRU GC hit a CursorWindow size limit during orphaned document removal. Here it bounds the rows a single
  /// query returns: the database adapter reads every row of a query into memory.
  @visibleForTesting
  static const int removeOrphanedDocumentsBatchSize = 100;

  /// The number of rows [forEachOrphanedDocumentSequenceNumber] reads per query.
  ///
  /// PORTING NOTE: upstream walks a cursor over all orphaned documents (and JS an IndexedDB cursor); the database
  /// adapter of the port has no cursor, so the documents are read in pages by path.
  @visibleForTesting
  static const int orphanedSequenceNumbersPageSize = 1000;

  final SQLitePersistence persistence;
  late ListenSequence listenSequence;
  int _currentSequenceNumber;

  @override
  late ReferenceSet inMemoryPins;

  @override
  late LruGarbageCollector garbageCollector;

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

  @override
  Future<int> getSequenceNumberCount() async {
    final int targetCount = persistence.queryCache.targetCount;
    final Map<String, dynamic> data = (await persistence.query(
      // @formatter:off
      '''
              SELECT COUNT(*) as count
              FROM (SELECT sequence_number
                    FROM target_documents
                    GROUP BY path
                    HAVING COUNT(*) = 1
                       AND target_id = 0);''',
      // @formatter:on
    )).first;
    return targetCount + (data['count'] as int);
  }

  @override
  Future<void> forEachTarget(Consumer<QueryData> consumer) async {
    await persistence.queryCache.forEachTarget(consumer);
  }

  @override
  Future<void> forEachOrphanedDocumentSequenceNumber(
    Consumer<int> consumer,
  ) async {
    String startPath = EncodedPath.encode(ResourcePath.empty);
    while (true) {
      final List<Map<String, dynamic>> rows = await persistence.query(
        // @formatter:off
        '''
           SELECT path, sequence_number
           FROM target_documents
           WHERE path > ?
           GROUP BY path
           HAVING COUNT(*) = 1
              AND target_id = 0
           ORDER BY path
           LIMIT ?;
          ''',
        // @formatter:on
        <Object>[startPath, orphanedSequenceNumbersPageSize],
      );

      for (Map<String, dynamic> row in rows) {
        consumer(row['sequence_number']);
      }
      if (rows.length < orphanedSequenceNumbersPageSize) {
        return;
      }
      startPath = rows.last['path'];
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
    return persistence.queryCache.removeQueries(upperBound, activeTargetIds);
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
      <String>[EncodedPath.encode(key.path)],
    )).isNotEmpty;
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
      <String>[EncodedPath.encode(key.path)],
    );
  }

  @override
  Future<int> removeOrphanedDocuments(int upperBound) async {
    int count = 0;
    String startPath = EncodedPath.encode(ResourcePath.empty);
    bool resultsRemaining = true;
    while (resultsRemaining) {
      // PORTING NOTE: upstream has `path > ?` in the HAVING clause. In WHERE, older SQLite versions (which do not move
      // the term themselves) also start every batch at [startPath] instead of at the first document; ORDER BY makes
      // the order the paging relies on explicit.
      final List<Map<String, dynamic>> rows = await persistence.query(
        // @formatter:off
        '''
            SELECT path
            FROM target_documents
            WHERE path > ?
            GROUP BY path
            HAVING COUNT(*) = 1
               AND target_id = 0
               AND sequence_number <= ?
            ORDER BY path
            LIMIT ?;
          ''',
        // @formatter:on
        <Object>[startPath, upperBound, removeOrphanedDocumentsBatchSize],
      );

      final List<DocumentKey> docsToRemove = <DocumentKey>[];
      for (Map<String, dynamic> row in rows) {
        final String encodedPath = row['path'];
        final ResourcePath path = EncodedPath.decodeResourcePath(encodedPath);
        final DocumentKey key = DocumentKey.fromPath(path);
        if (!await _isPinned(key)) {
          count++;
          docsToRemove.add(key);
          await _removeSentinel(key);
        }

        // Set startPath so the next batch (if necessary) picks up where this one left off.
        startPath = encodedPath;
      }

      // PORTING NOTE: upstream collects the keys of all batches and removes the documents once at the end; removing
      // them per batch is equivalent (the remote documents are not part of the query above) and keeps the memory
      // bounded by the batch size.
      await persistence.remoteDocumentCache.removeAll(docsToRemove);
      resultsRemaining = rows.length == removeOrphanedDocumentsBatchSize;
    }

    return count;
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
      <dynamic>[path, currentSequenceNumber],
    );
  }

  @override
  Future<int> get byteSize => persistence.byteSize;
}
