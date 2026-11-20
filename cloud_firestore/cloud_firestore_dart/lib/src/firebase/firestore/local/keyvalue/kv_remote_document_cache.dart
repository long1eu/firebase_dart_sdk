part of 'cache_store_persistence.dart';

/// The document types of the `doc` table, so that a scan skips deleted documents without decoding them.
const int _noDocument = 1;
const int _foundDocument = 2;
const int _unknownDocument = 3;

/// The remote documents: `doc` by key, `docRead` by collection and read time. The byte size of the values of `doc` is
/// kept in `global/docBytes`, the size the LRU garbage collector compares with the threshold.
class _KvRemoteDocumentCache implements RemoteDocumentCache {
  _KvRemoteDocumentCache(this._db);

  final CacheStorePersistence _db;

  IndexManager? _indexManager;

  int _byteSize = 0;

  static final Uint8List _byteSizeKey = _key(
    _Table.global,
  ).string('docBytes').bytes;

  @override
  set indexManager(IndexManager indexManager) => _indexManager = indexManager;

  int get byteSize => _byteSize;

  Future<void> _loadByteSize() async {
    final Uint8List? value = await _db._tx.get(_byteSizeKey);
    _byteSize = value == null ? 0 : KvKeyReader(value).integer();
  }

  Future<void> _addToByteSize(int delta) async {
    if (delta == 0) {
      return;
    }
    _byteSize += delta;
    await _db._tx.put(_byteSizeKey, KvKeyWriter().integer(_byteSize).bytes);
  }

  Uint8List _docKey(DocumentKey key) => _key(_Table.doc).documentKey(key).bytes;

  Uint8List _readKey(DocumentKey key, SnapshotVersion readTime) {
    final ResourcePath path = key.path;
    return _writeVersion(
      _key(_Table.docRead).path(path.popLast()),
      readTime,
    ).string(path.getLastSegment()).bytes;
  }

  @override
  Future<void> add(
    MaybeDocument maybeDocument,
    SnapshotVersion readTime,
  ) async {
    hardAssert(
      readTime != SnapshotVersion.none,
      'Cannot add document to the RemoteDocumentCache with a read time of zero',
    );
    final DocumentKey key = maybeDocument.key;
    final Uint8List docKey = _docKey(key);
    final Uint8List? previous = await _db._tx.get(docKey);
    if (previous != null) {
      await _db._tx.delete(_readKey(key, _readVersion(KvKeyReader(previous))));
    }

    final int type = switch (maybeDocument) {
      NoDocument() => _noDocument,
      Document() => _foundDocument,
      UnknownDocument() => _unknownDocument,
      _ => throw fail('Unknown document type ${maybeDocument.runtimeType}'),
    };
    final Uint8List value = _writeVersion(KvKeyWriter(), readTime)
        .integer(type)
        .raw(_db.serializer.encodeMaybeDocument(maybeDocument).writeToBuffer())
        .bytes;
    _db._statsCollector.recordRowsWritten(RemoteDocumentCache.statsTag, 1);
    await _db._tx.put(docKey, value);
    await _db._tx.put(_readKey(key, readTime), _empty);
    await _addToByteSize(value.length - (previous?.length ?? 0));

    await (_indexManager ?? _db.indexManager).addToCollectionParentIndex(
      key.path.popLast(),
    );
  }

  @override
  Future<void> remove(DocumentKey documentKey) =>
      removeAll(<DocumentKey>[documentKey]);

  @override
  Future<void> removeAll(Iterable<DocumentKey> documentKeys) async {
    final Map<DocumentKey, MaybeDocument?> deleted =
        <DocumentKey, MaybeDocument?>{};
    int removedBytes = 0;
    for (final DocumentKey key in documentKeys) {
      deleted[key] = null;
      final Uint8List docKey = _docKey(key);
      final Uint8List? previous = await _db._tx.get(docKey);
      if (previous == null) {
        continue;
      }
      _db._statsCollector.recordRowsDeleted(RemoteDocumentCache.statsTag, 1);
      await _db._tx.delete(docKey);
      await _db._tx.delete(_readKey(key, _readVersion(KvKeyReader(previous))));
      removedBytes += previous.length;
    }
    await _addToByteSize(-removedBytes);
    if (deleted.isNotEmpty) {
      // A removed document has no index entries.
      await _indexManager?.updateIndexEntries(deleted);
    }
  }

  @override
  Future<MaybeDocument?> get(DocumentKey documentKey) async {
    _db._statsCollector.recordRowsRead(RemoteDocumentCache.statsTag, 1);
    final Uint8List? value = await _db._tx.get(_docKey(documentKey));
    return value == null ? null : _decode(value).document;
  }

  @override
  Future<Map<DocumentKey, MaybeDocument?>> getAll(
    Iterable<DocumentKey> documentKeys,
  ) async {
    final Map<DocumentKey, MaybeDocument?> results =
        <DocumentKey, MaybeDocument?>{};
    int read = 0;
    for (final DocumentKey key in documentKeys) {
      final Uint8List? value = await _db._tx.get(_docKey(key));
      if (value != null) {
        read++;
      }
      results[key] = value == null ? null : _decode(value).document;
    }
    _db._statsCollector.recordRowsRead(RemoteDocumentCache.statsTag, read);
    return results;
  }

  @override
  Future<Map<DocumentKey, ReadDocument>> getAllForCollectionGroup(
    String collectionGroup,
    IndexOffset offset,
    int limit,
  ) async {
    final List<ResourcePath> parents = await _db.indexManager
        .getCollectionParents(collectionGroup);
    final List<MapEntry<DocumentKey, ReadDocument>> found =
        <MapEntry<DocumentKey, ReadDocument>>[];
    for (final ResourcePath parent in parents) {
      found.addAll(
        await _readSince(parent.appendSegment(collectionGroup), offset, limit),
      );
    }
    found.sort(_byReadTimeAndKey);
    final Map<DocumentKey, ReadDocument> result = <DocumentKey, ReadDocument>{
      for (final MapEntry<DocumentKey, ReadDocument> entry in found.take(limit))
        entry.key: entry.value,
    };
    _db._statsCollector.recordRowsRead(
      RemoteDocumentCache.statsTag,
      result.length,
    );
    return result;
  }

  static int _byReadTimeAndKey(
    MapEntry<DocumentKey, ReadDocument> a,
    MapEntry<DocumentKey, ReadDocument> b,
  ) {
    final int byTime = a.value.readTime.compareTo(b.value.readTime);
    return byTime != 0 ? byTime : a.key.compareTo(b.key);
  }

  /// The documents of [collection] read after [offset] (after its read time, or at that read time with a larger key),
  /// in the order of read time and key, at most [limit] of them when given.
  Future<List<MapEntry<DocumentKey, ReadDocument>>> _readSince(
    ResourcePath collection,
    IndexOffset offset, [
    int? limit,
  ]) async {
    final Uint8List prefix = _key(_Table.docRead).path(collection).bytes;
    final Uint8List from = _writeVersion(
      _key(_Table.docRead).path(collection),
      offset.readTime,
    ).bytes;
    final List<MapEntry<DocumentKey, ReadDocument>> result =
        <MapEntry<DocumentKey, ReadDocument>>[];
    await _db._scanPrefix(prefix, from: from, (
      List<CacheStoreEntry> page,
    ) async {
      for (final CacheStoreEntry entry in page) {
        final KvKeyReader reader = KvKeyReader(entry.key)
          ..string()
          ..path();
        final SnapshotVersion readTime = _readVersion(reader);
        final DocumentKey key = DocumentKey.fromPath(
          collection.appendSegment(reader.string()),
        );
        if (readTime == offset.readTime &&
            key.compareTo(offset.documentKey) <= 0) {
          continue;
        }
        final Uint8List? value = await _db._tx.get(_docKey(key));
        if (value == null) {
          continue;
        }
        result.add(
          MapEntry<DocumentKey, ReadDocument>(key, (
            document: _decode(value).document,
            readTime: readTime,
          )),
        );
        if (limit != null && result.length >= limit) {
          return false;
        }
      }
      return true;
    });
    return result;
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
    final Map<DocumentKey, Document> results = <DocumentKey, Document>{};
    int read = 0;

    void consider(MaybeDocument document) {
      if (document is Document &&
          (mutatedKeys.contains(document.key) || query.matches(document))) {
        results[document.key] = document;
      }
    }

    if (offset != IndexOffset.none) {
      // Only the documents read after the offset, through `docRead`.
      for (final MapEntry<DocumentKey, ReadDocument> entry in await _readSince(
        query.path,
        offset,
      )) {
        read++;
        consider(entry.value.document);
      }
    } else {
      final Uint8List prefix = _key(_Table.doc).path(query.path).bytes;
      await _db._scanPrefix(prefix, (List<CacheStoreEntry> page) {
        for (final CacheStoreEntry entry in page) {
          final KvKeyReader reader = KvKeyReader(entry.value);
          _readVersion(reader);
          // Deleted and unknown documents are skipped by their type, not decoded: not counted as read (as the SQLite
          // cache, whose query filters them out).
          if (reader.integer() != _foundDocument) {
            continue;
          }
          read++;
          consider(_decodeDocument(reader.rest()));
        }
        return true;
      });
    }

    _db._statsCollector.recordRowsRead(RemoteDocumentCache.statsTag, read);
    context?.incrementDocumentReadCount(read);
    return ImmutableSortedMap<DocumentKey, Document>.fromMap(
      results,
      DocumentKey.comparator,
    );
  }

  ({MaybeDocument document, SnapshotVersion readTime}) _decode(
    Uint8List value,
  ) {
    final KvKeyReader reader = KvKeyReader(value);
    final SnapshotVersion readTime = _readVersion(reader);
    reader.integer();
    return (document: _decodeDocument(reader.rest()), readTime: readTime);
  }

  MaybeDocument _decodeDocument(Uint8List bytes) =>
      _db.serializer.decodeMaybeDocument(
        parseStoredProto(
          'MaybeDocument',
          () => proto.MaybeDocument.fromBuffer(bytes),
        ),
      );
}
