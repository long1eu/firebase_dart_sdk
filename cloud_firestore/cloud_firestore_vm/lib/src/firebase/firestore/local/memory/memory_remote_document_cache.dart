// File created by
// Lung Razvan <long1eu>
// on 21/09/2018

part of memory_persistence;

/// In-memory cache of remote documents.
class MemoryRemoteDocumentCache implements RemoteDocumentCache {
  MemoryRemoteDocumentCache(MemoryPersistence persistence, this._statsCollector)
      : documents = DocumentCollections.emptyMaybeDocumentMap(),
        _persistence = persistence;

  /// Underlying cache of documents.
  ImmutableSortedMap<DocumentKey, MaybeDocument> documents;

  final MemoryPersistence _persistence;
  final StatsCollector _statsCollector;

  @override
  Future<void> add(MaybeDocument document) async {
    documents = documents.insert(document.key, document);
    await _persistence.indexManager
        .addToCollectionParentIndex(document.key.path.popLast());
  }

  @override
  Future<void> remove(DocumentKey key) async {
    _statsCollector.recordRowsDeleted(RemoteDocumentCache.statsTag, 1);
    documents = documents.remove(key);
  }

  @override
  Future<MaybeDocument> get(DocumentKey key) async {
    _statsCollector.recordRowsRead(RemoteDocumentCache.statsTag, 1);
    return documents[key];
  }

  @override
  Future<Map<DocumentKey, MaybeDocument>> getAll(
      Iterable<DocumentKey> documentKeys) async {
    final List<MapEntry<DocumentKey, MaybeDocument>> entries =
        await Future.wait(documentKeys.map((DocumentKey key) async =>
            MapEntry<DocumentKey, MaybeDocument>(key, await get(key))));

    _statsCollector.recordRowsRead(
        RemoteDocumentCache.statsTag, entries.length);
    return Map<DocumentKey, MaybeDocument>.fromEntries(entries);
  }

  @override
  Future<ImmutableSortedMap<DocumentKey, Document>>
      getAllDocumentsMatchingQuery(Query query) async {
    hardAssert(!query.isCollectionGroupQuery,
        'CollectionGroup queries should be handled in LocalDocumentsView');
    ImmutableSortedMap<DocumentKey, Document> result =
        DocumentCollections.emptyDocumentMap();

    // Documents are ordered by key, so we can use a prefix scan to narrow down the documents we need to match the query
    // against.
    final ResourcePath queryPath = query.path;
    final DocumentKey prefix =
        DocumentKey.fromPath(queryPath.appendSegment(''));
    final Iterator<MapEntry<DocumentKey, MaybeDocument>> iterator =
        documents.iteratorFrom(prefix);
    int rowsRead = 0;
    while (iterator.moveNext()) {
      final MapEntry<DocumentKey, MaybeDocument> entry = iterator.current;
      rowsRead++;
      final DocumentKey key = entry.key;
      if (!queryPath.isPrefixOf(key.path)) {
        break;
      }

      final MaybeDocument maybeDoc = entry.value;
      if (!(maybeDoc is Document)) {
        continue;
      }

      final Document doc = maybeDoc;
      if (query.matches(doc)) {
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
      count +=
          serializer.encodeMaybeDocument(entry.value).writeToBuffer().length;
    }
    return count;
  }
}
