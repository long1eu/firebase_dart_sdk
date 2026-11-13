// File created by
// Lung Razvan <long1eu>
// on 21/09/2018

part of 'memory_persistence.dart';

/// In-memory cache of remote documents.
class MemoryRemoteDocumentCache implements RemoteDocumentCache {
  MemoryRemoteDocumentCache(MemoryPersistence persistence, this._statsCollector)
    : documents = DocumentCollections.emptyMaybeDocumentMap(),
      _persistence = persistence;

  /// Underlying cache of documents.
  ImmutableSortedMap<DocumentKey, MaybeDocument> documents;

  /// The read time of every document in [documents].
  final Map<DocumentKey, SnapshotVersion> _readTimes =
      <DocumentKey, SnapshotVersion>{};

  final MemoryPersistence _persistence;
  final StatsCollector _statsCollector;

  IndexManager? _indexManager;

  @override
  set indexManager(IndexManager indexManager) => _indexManager = indexManager;

  @override
  Future<void> add(MaybeDocument document, SnapshotVersion readTime) async {
    hardAssert(
      readTime != SnapshotVersion.none,
      'Cannot add document to the RemoteDocumentCache with a read time of zero',
    );
    documents = documents.insert(document.key, document);
    _readTimes[document.key] = readTime;
    await (_indexManager ?? _persistence.indexManager)
        .addToCollectionParentIndex(document.key.path.popLast());
  }

  @override
  Future<void> remove(DocumentKey key) async {
    _statsCollector.recordRowsDeleted(RemoteDocumentCache.statsTag, 1);
    documents = documents.remove(key);
    _readTimes.remove(key);
  }

  @override
  Future<void> removeAll(Iterable<DocumentKey> documentKeys) async {
    for (DocumentKey key in documentKeys) {
      await remove(key);
    }
  }

  @override
  Future<MaybeDocument?> get(DocumentKey key) async {
    _statsCollector.recordRowsRead(RemoteDocumentCache.statsTag, 1);
    return documents[key];
  }

  @override
  Future<Map<DocumentKey, MaybeDocument?>> getAll(
    Iterable<DocumentKey> documentKeys,
  ) async {
    final List<MapEntry<DocumentKey, MaybeDocument?>> entries =
        await Future.wait(
          documentKeys.map(
            (DocumentKey key) async =>
                MapEntry<DocumentKey, MaybeDocument?>(key, await get(key)),
          ),
        );

    _statsCollector.recordRowsRead(
      RemoteDocumentCache.statsTag,
      entries.length,
    );
    return Map<DocumentKey, MaybeDocument?>.fromEntries(entries);
  }

  @override
  Future<Map<DocumentKey, ReadDocument>> getAllForCollectionGroup(
    String collectionGroup,
    IndexOffset offset,
    int limit,
  ) {
    // This method should only be called from the IndexBackfiller if SQLite is enabled.
    throw UnsupportedError(
      'getAllForCollectionGroup(String, IndexOffset, int) is not supported.',
    );
  }

  @override
  Future<ImmutableSortedMap<DocumentKey, Document>>
  getAllDocumentsMatchingQuery(
    Query query,
    IndexOffset offset, {
    Set<DocumentKey> mutatedKeys = const <DocumentKey>{},
    QueryContext? context,
  }) async {
    hardAssert(
      !query.isCollectionGroupQuery,
      'CollectionGroup queries should be handled in LocalDocumentsView',
    );
    ImmutableSortedMap<DocumentKey, Document> result =
        DocumentCollections.emptyDocumentMap();

    // Documents are ordered by key, so we can use a prefix scan to narrow down the documents we need to match the query
    // against.
    final ResourcePath queryPath = query.path;
    final DocumentKey prefix = DocumentKey.fromPath(
      queryPath.appendSegment(''),
    );
    final Iterator<MapEntry<DocumentKey, MaybeDocument>> iterator = documents
        .iteratorFrom(prefix);
    int rowsRead = 0;
    while (iterator.moveNext()) {
      final MapEntry<DocumentKey, MaybeDocument> entry = iterator.current;
      rowsRead++;
      final DocumentKey key = entry.key;
      if (!queryPath.isPrefixOf(key.path)) {
        break;
      }

      if (key.path.length > queryPath.length + 1) {
        // Exclude entries from subcollections.
        continue;
      }

      final MaybeDocument maybeDoc = entry.value;
      if (maybeDoc is! Document) {
        continue;
      }

      if (offset != IndexOffset.none &&
          IndexOffset(
                _readTimes[entry.key]!,
                entry.key,
                FieldIndex.initialLargestBatchId,
              ).compareTo(offset) <=
              0) {
        continue;
      }

      final Document doc = maybeDoc;
      if (mutatedKeys.contains(doc.key) || query.matches(doc)) {
        result = result.insert(doc.key, doc);
      }
    }

    _statsCollector.recordRowsRead(RemoteDocumentCache.statsTag, rowsRead);
    return result;
  }

  /// Returns an estimate of the number of bytes used to store the given document key in memory. This is only an
  /// estimate and includes the size of the segments of the path, but not any object overhead or path separators.
  static int _getKeySize(DocumentKey key) {
    final ResourcePath path = key.path;
    int count = 0;
    for (int i = 0; i < path.length; i++) {
      // Strings in dart are utf-16, each character is two bytes in memory
      count += path.segments[i].length * 2;
    }
    return count;
  }

  int getByteSize(LocalSerializer serializer) {
    int count = 0;
    for (MapEntry<DocumentKey, MaybeDocument> entry in documents) {
      count += _getKeySize(entry.key);
      count += serializer
          .encodeMaybeDocument(entry.value)
          .writeToBuffer()
          .length;
    }
    return count;
  }
}
