part of 'cache_store_persistence.dart';

/// The document overlays of one user: `overlay` by document, with three indexes without values: `overlayBatch` by
/// batch id (to remove the overlays of a batch), `overlayColl` by collection and batch id (the overlays of a
/// collection changed since a batch) and `overlayGroup` by collection group and batch id (for the index backfiller).
class _KvDocumentOverlayCache implements DocumentOverlayCache {
  _KvDocumentOverlayCache(this._db, this._uid);

  final CacheStorePersistence _db;
  final String _uid;

  Uint8List _overlayKey(DocumentKey key) =>
      _key(_Table.overlay).string(_uid).documentKey(key).bytes;

  Uint8List _batchKey(int batchId, DocumentKey key) => _key(
    _Table.overlayBatch,
  ).string(_uid).integer(batchId).documentKey(key).bytes;

  Uint8List _collectionKey(int batchId, DocumentKey key) =>
      _key(_Table.overlayColl)
          .string(_uid)
          .path(key.path.popLast())
          .integer(batchId)
          .string(key.path.getLastSegment())
          .bytes;

  Uint8List _groupKey(int batchId, DocumentKey key) => _key(_Table.overlayGroup)
      .string(_uid)
      .string(key.collectionGroup)
      .integer(batchId)
      .documentKey(key)
      .bytes;

  @override
  Future<Overlay?> getOverlay(DocumentKey key) async {
    final Uint8List? value = await _db._tx.get(_overlayKey(key));
    return value == null ? null : _decode(value);
  }

  @override
  Future<Map<DocumentKey, Overlay>> getOverlays(
    Iterable<DocumentKey> keys,
  ) async {
    final Map<DocumentKey, Overlay> result = <DocumentKey, Overlay>{};
    for (final DocumentKey key in keys) {
      final Overlay? overlay = await getOverlay(key);
      if (overlay != null) {
        result[key] = overlay;
      }
    }
    return result;
  }

  @override
  Future<void> saveOverlays(
    int largestBatchId,
    Map<DocumentKey, Mutation> overlays,
  ) async {
    for (final MapEntry<DocumentKey, Mutation> entry in overlays.entries) {
      final DocumentKey key = entry.key;
      final Overlay? previous = await getOverlay(key);
      if (previous != null) {
        await _removeIndexes(previous.largestBatchId, key);
      }
      await _db._tx.put(
        _overlayKey(key),
        KvKeyWriter()
            .integer(largestBatchId)
            .raw(
              _db.serializer.encodeOverlayMutation(entry.value).writeToBuffer(),
            )
            .bytes,
      );
      await _db._tx.put(_batchKey(largestBatchId, key), _empty);
      await _db._tx.put(_collectionKey(largestBatchId, key), _empty);
      await _db._tx.put(_groupKey(largestBatchId, key), _empty);
    }
  }

  Future<void> _removeIndexes(int batchId, DocumentKey key) async {
    await _db._tx.delete(_batchKey(batchId, key));
    await _db._tx.delete(_collectionKey(batchId, key));
    await _db._tx.delete(_groupKey(batchId, key));
  }

  @override
  Future<void> removeOverlaysForBatchId(int batchId) async {
    final Uint8List prefix = _key(
      _Table.overlayBatch,
    ).string(_uid).integer(batchId).bytes;
    for (final CacheStoreEntry entry in await _db._scanAll(prefix)) {
      final DocumentKey key =
          (KvKeyReader(entry.key)
                ..string()
                ..string()
                ..integer())
              .documentKey();
      await _db._tx.delete(_overlayKey(key));
      await _removeIndexes(batchId, key);
    }
  }

  @override
  Future<void> removeOverlays(Iterable<DocumentKey> keys) async {
    for (final DocumentKey key in keys) {
      final Overlay? previous = await getOverlay(key);
      if (previous != null) {
        await _db._tx.delete(_overlayKey(key));
        await _removeIndexes(previous.largestBatchId, key);
      }
    }
  }

  @override
  Future<Map<DocumentKey, Overlay>> getOverlaysForCollection(
    ResourcePath collection,
    int sinceBatchId,
  ) async {
    // A range of `overlayColl`: the overlays of the collection whose batch id is larger than [sinceBatchId].
    final Uint8List prefix = _key(
      _Table.overlayColl,
    ).string(_uid).path(collection).bytes;
    final Uint8List from = _key(
      _Table.overlayColl,
    ).string(_uid).path(collection).integer(sinceBatchId + 1).bytes;
    final Map<DocumentKey, Overlay> result = <DocumentKey, Overlay>{};
    await _db._scanPrefix(prefix, from: from, (
      List<CacheStoreEntry> page,
    ) async {
      for (final CacheStoreEntry entry in page) {
        final KvKeyReader reader = KvKeyReader(entry.key)
          ..string()
          ..string()
          ..path()
          ..integer();
        final DocumentKey key = DocumentKey.fromPath(
          collection.appendSegment(reader.string()),
        );
        result[key] = (await getOverlay(key))!;
      }
      return true;
    });
    return result;
  }

  @override
  Future<CollectionOverlays> getOverlaysForCollectionQuery(
    Query query,
    Timestamp now,
  ) async {
    return CollectionOverlays.split(
      await getOverlaysForCollection(query.path, -1),
      query,
      now,
    );
  }

  @override
  Future<Map<DocumentKey, Overlay>> getOverlaysForCollectionGroup(
    String collectionGroup,
    int sinceBatchId,
    int count,
  ) async {
    // The overlays of the group by batch id, from the batch after [sinceBatchId], whole batches until [count] is
    // reached (a batch is never cut).
    final Uint8List prefix = _key(
      _Table.overlayGroup,
    ).string(_uid).string(collectionGroup).bytes;
    final Uint8List from = _key(
      _Table.overlayGroup,
    ).string(_uid).string(collectionGroup).integer(sinceBatchId + 1).bytes;
    final Map<DocumentKey, Overlay> result = <DocumentKey, Overlay>{};
    int? lastBatchId;
    await _db._scanPrefix(prefix, from: from, (
      List<CacheStoreEntry> page,
    ) async {
      for (final CacheStoreEntry entry in page) {
        final KvKeyReader reader = KvKeyReader(entry.key)
          ..string()
          ..string()
          ..string();
        final int batchId = reader.integer();
        if (result.length >= count && batchId != lastBatchId) {
          return false;
        }
        lastBatchId = batchId;
        final DocumentKey key = reader.documentKey();
        result[key] = (await getOverlay(key))!;
      }
      return true;
    });
    return result;
  }

  Overlay _decode(Uint8List value) {
    final KvKeyReader reader = KvKeyReader(value);
    final int largestBatchId = reader.integer();
    final Uint8List bytes = reader.rest();
    return Overlay(
      largestBatchId,
      _db.serializer.decodeOverlayMutation(
        parseStoredProto('Overlay', () => proto.Write.fromBuffer(bytes)),
      ),
    );
  }
}
