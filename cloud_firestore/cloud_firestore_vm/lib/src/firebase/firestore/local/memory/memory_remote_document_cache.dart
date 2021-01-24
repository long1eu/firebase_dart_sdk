// File created by
// Lung Razvan <long1eu>
// on 21/09/2018

part of memory_persistence;

/// In-memory cache of remote documents.
class MemoryRemoteDocumentCache implements RemoteDocumentCache {
  MemoryRemoteDocumentCache(MemoryPersistence persistence)
      : _documents =
            ImmutableSortedMap<DocumentKey, MapEntry<MaybeDocument, SnapshotVersion>>.emptyMap(DocumentKey.comparator),
        _persistence = persistence;

  /// Underlying cache of documents.
  ImmutableSortedMap<DocumentKey, MapEntry<MaybeDocument, SnapshotVersion>> _documents;

  final MemoryPersistence _persistence;

  @override
  Future<void> add(MaybeDocument document, SnapshotVersion readTime) async {
    hardAssert(
      readTime != SnapshotVersion.none,
      'Cannot add document to the RemoteDocumentCache with a read time of zero',
    );
    _documents = _documents.insert(document.key, MapEntry<MaybeDocument, SnapshotVersion>(document, readTime));

    await _persistence.indexManager.addToCollectionParentIndex(document.key.path.popLast());
  }

  @override
  Future<void> remove(DocumentKey key) async {
    _documents = _documents.remove(key);
  }

  @override
  Future<MaybeDocument> get(DocumentKey key) async {
    final MapEntry<MaybeDocument, SnapshotVersion> entry = _documents[key];
    return entry != null ? entry.key : null;
  }

  @override
  Future<Map<DocumentKey, MaybeDocument>> getAll(Iterable<DocumentKey> documentKeys) async {
    final Map<DocumentKey, MaybeDocument> result = <DocumentKey, MaybeDocument>{};

    for (DocumentKey key in documentKeys) {
      // Make sure each key has a corresponding entry, which is null in case the document is not
      // found.
      result[key] = await get(key);
    }

    return result;
  }

  @override
  Future<ImmutableSortedMap<DocumentKey, Document>> getAllDocumentsMatchingQuery(
    Query query,
    SnapshotVersion sinceReadTime,
  ) async {
    hardAssert(!query.isCollectionGroupQuery, 'CollectionGroup queries should be handled in LocalDocumentsView');
    ImmutableSortedMap<DocumentKey, Document> result = DocumentCollections.emptyDocumentMap();

    // Documents are ordered by key, so we can use a prefix scan to narrow down the documents we need to match the query
    // against.
    final ResourcePath queryPath = query.path;
    final DocumentKey prefix = DocumentKey.fromPath(queryPath.appendSegment(''));
    final Iterator<MapEntry<DocumentKey, MapEntry<MaybeDocument, SnapshotVersion>>> iterator =
        _documents.iteratorFrom(prefix);

    while (iterator.moveNext()) {
      final MapEntry<DocumentKey, MapEntry<MaybeDocument, SnapshotVersion>> entry = iterator.current;

      final DocumentKey key = entry.key;
      if (!queryPath.isPrefixOf(key.path)) {
        break;
      }

      final MaybeDocument maybeDoc = entry.value.key;
      if (maybeDoc is! Document) {
        continue;
      }

      final SnapshotVersion readTime = entry.value.value;
      if (readTime.compareTo(sinceReadTime) <= 0) {
        continue;
      }

      final Document doc = maybeDoc;
      if (query.matches(doc)) {
        result = result.insert(doc.key, doc);
      }
    }

    return result;
  }

  Iterable<MaybeDocument> get documents {
    return _documents.map((MapEntry<DocumentKey, MapEntry<MaybeDocument, SnapshotVersion>> item) => item.value.key);
  }

  int getByteSize(LocalSerializer serializer) {
    int count = 0;
    for (MaybeDocument doc in documents) {
      count += serializer.encodeMaybeDocument(doc).writeToBuffer().lengthInBytes;
    }
    return count;
  }
}
