part of 'indexeddb_persistence_web.dart';

/// The cache of remote documents on `remoteDocumentsV14` and `remoteDocumentGlobal`
/// (`indexeddb_remote_document_cache.ts`).
///
/// A row is keyed by `[prefixPath, collectionGroup, readTime, documentId]`: replacing a document removes its row
/// under the old read time first (found through `documentKeyIndex`). The size of the cache in `remoteDocumentGlobal`
/// is kept as the JS SDK keeps it (the length of the document's JSON), for its garbage collection.
class IndexedDbRemoteDocumentCache implements RemoteDocumentCache {
  IndexedDbRemoteDocumentCache._(this._persistence);

  final WebIndexedDbPersistence _persistence;

  IndexManager? _indexManager;

  @override
  set indexManager(IndexManager indexManager) => _indexManager = indexManager;

  _IdbTransaction get _transaction => _persistence._current;

  IndexedDbSerializer get _serializer => _persistence.serializer;

  web.IDBIndex _keyIndex(_IdbTransaction transaction) => transaction
      .store(DbStores.remoteDocuments)
      .index(DbStores.remoteDocumentsDocumentKeyIndex);

  /// `dbDocumentSize`: the length of the JSON of the document part of [row].
  static int _documentSize(JSAny? row) {
    if (row == null) {
      return 0;
    }
    final JSObject object = row as JSObject;
    for (final String field in const <String>[
      'document',
      'unknownDocument',
      'noDocument',
    ]) {
      final JSAny? value = object.getProperty(field.toJS);
      if (value != null && !value.isUndefined) {
        return idbJsonLength(value);
      }
    }
    return 0;
  }

  /// Deletes the rows of [key] (one, unless something else wrote the store) and returns their size.
  Future<int> _deleteRows(_IdbTransaction transaction, DocumentKey key) async {
    int size = 0;
    await transaction.forEach(
      'delete the cached document $key',
      () => _keyIndex(
        transaction,
      ).openCursor(web.IDBKeyRange.only(idbKey(dbRemoteDocumentKey(key)))),
      (web.IDBCursor cursor) {
        size += _documentSize((cursor as web.IDBCursorWithValue).value);
        cursor.delete();
        return true;
      },
    );
    return size;
  }

  Future<void> _updateByteSize(_IdbTransaction transaction, int delta) async {
    if (delta == 0) {
      return;
    }
    final Object? metadata = await transaction.read(
      'get the document cache metadata',
      () => transaction
          .store(DbStores.remoteDocumentGlobal)
          .get(DbStores.remoteDocumentGlobalKey.toJS),
    );
    hardAssert(metadata is Map, 'Missing document cache metadata');
    final int byteSize = ((metadata! as Map)['byteSize']! as num).toInt();
    await transaction.request(
      'put the document cache metadata',
      () => transaction
          .store(DbStores.remoteDocumentGlobal)
          .put(
            idbToJs(<String, Object?>{'byteSize': byteSize + delta}),
            DbStores.remoteDocumentGlobalKey.toJS,
          ),
    );
  }

  @override
  Future<void> add(MaybeDocument document, SnapshotVersion readTime) async {
    hardAssert(
      readTime != SnapshotVersion.none,
      'Cannot add document to the RemoteDocumentCache with a read time of zero',
    );
    final _IdbTransaction transaction = _transaction;
    final int previousSize = await _deleteRows(transaction, document.key);
    final JSAny? row = idbToJs(
      _serializer.toDbRemoteDocument(document, readTime),
    );
    await transaction.request(
      'put the cached document ${document.key}',
      () => transaction.store(DbStores.remoteDocuments).put(row),
    );
    await _updateByteSize(transaction, _documentSize(row) - previousSize);
    await (_indexManager ?? _persistence.indexManager)
        .addToCollectionParentIndex(document.key.path.popLast());
  }

  @override
  Future<void> remove(DocumentKey documentKey) async {
    final _IdbTransaction transaction = _transaction;
    final int size = await _deleteRows(transaction, documentKey);
    await _updateByteSize(transaction, -size);
  }

  @override
  Future<void> removeAll(Iterable<DocumentKey> documentKeys) async {
    for (final DocumentKey key in documentKeys) {
      await remove(key);
    }
  }

  /// The document of [row], or null for no row and for a sentinel removal (`maybeDecodeDocument`).
  ReadDocument? _decode(Object? row) {
    if (row is! Map) {
      return null;
    }
    final ReadDocument read = _serializer.fromDbRemoteDocument(
      row.cast<String, Object?>(),
    );
    return IndexedDbSerializer.isSentinelRemoval(read.document) ? null : read;
  }

  @override
  Future<MaybeDocument?> get(DocumentKey documentKey) async {
    final _IdbTransaction transaction = _transaction;
    final Object? row = await transaction.read(
      'get the cached document $documentKey',
      () => _keyIndex(
        transaction,
      ).get(web.IDBKeyRange.only(idbKey(dbRemoteDocumentKey(documentKey)))),
    );
    return _decode(row)?.document;
  }

  @override
  Future<Map<DocumentKey, MaybeDocument?>> getAll(
    Iterable<DocumentKey> documentKeys,
  ) async {
    final _IdbTransaction transaction = _transaction;
    final List<DocumentKey> keys = documentKeys.toList();
    // All requests are made at once; IndexedDB answers them in order.
    final List<Object?> rows = await Future.wait(<Future<Object?>>[
      for (final DocumentKey key in keys)
        transaction.read(
          'get the cached document $key',
          () => _keyIndex(
            transaction,
          ).get(web.IDBKeyRange.only(idbKey(dbRemoteDocumentKey(key)))),
        ),
    ]);
    return <DocumentKey, MaybeDocument?>{
      for (int i = 0; i < keys.length; i++) keys[i]: _decode(rows[i])?.document,
    };
  }

  @override
  Future<Map<DocumentKey, ReadDocument>> getAllForCollectionGroup(
    String collectionGroup,
    IndexOffset offset,
    int limit,
  ) async {
    // Only the index backfiller calls this, and this slice has no field indexes; kept as the JS SDK has it.
    final _IdbTransaction transaction = _transaction;
    List<Object?> groupKey(SnapshotVersion readTime, List<String> path) =>
        <Object?>[
          collectionGroup,
          dbTimestampKey(readTime),
          path.isEmpty ? <String>[] : path.sublist(0, path.length - 2),
          path.isEmpty ? '' : path.last,
        ];
    final Map<DocumentKey, ReadDocument> result = <DocumentKey, ReadDocument>{};
    await transaction.forEach(
      'scan the collection group $collectionGroup',
      () => transaction
          .store(DbStores.remoteDocuments)
          .index(DbStores.remoteDocumentsCollectionGroupIndex)
          .openCursor(
            web.IDBKeyRange.bound(
              idbKey(
                groupKey(offset.readTime, offset.documentKey.path.segments),
              ),
              idbKey(<Object>[
                collectionGroup,
                <Object>[jsMaxSafeInteger, jsMaxSafeInteger],
                <Object>[],
                '',
              ]),
              true,
            ),
          ),
      (web.IDBCursor cursor) {
        final ReadDocument? read = _decode(
          idbToDart((cursor as web.IDBCursorWithValue).value),
        );
        if (read != null) {
          result[read.document.key] = read;
        }
        return result.length < limit;
      },
    );
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
    final _IdbTransaction transaction = _transaction;
    // The documents of one collection are contiguous in the store, ordered by read time and then id: the range
    // starts after the offset (exclusive) and ends after the latest read time.
    final ResourcePath collection = query.path;
    final List<String> prefix = collection.popLast().segments;
    final String collectionGroup = collection.getLastSegment();
    final List<String> offsetPath = offset.documentKey.path.segments;
    final List<Object?> rows =
        (await transaction.read(
              'scan the collection $collection',
              () => transaction
                  .store(DbStores.remoteDocuments)
                  .getAll(
                    web.IDBKeyRange.bound(
                      idbKey(<Object>[
                        prefix,
                        collectionGroup,
                        dbTimestampKey(offset.readTime),
                        if (offsetPath.isEmpty) '' else offsetPath.last,
                      ]),
                      idbKey(<Object>[
                        prefix,
                        collectionGroup,
                        <Object>[jsMaxSafeInteger, jsMaxSafeInteger],
                        '',
                      ]),
                      true,
                    ),
                  ),
            ))!
            as List<Object?>;
    context?.incrementDocumentReadCount(rows.length);
    ImmutableSortedMap<DocumentKey, Document> result =
        DocumentCollections.emptyDocumentMap();
    for (final Object? row in rows) {
      final MaybeDocument? document = _decode(row)?.document;
      if (document is Document &&
          (mutatedKeys.contains(document.key) || query.matches(document))) {
        result = result.insert(document.key, document);
      }
    }
    return result;
  }
}
