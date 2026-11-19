part of 'cache_store_persistence.dart';

/// The mutation queue of one user: `mut` by batch id, `docMut` by document, `mutQueue` for the stream token.
class _KvMutationQueue implements MutationQueue {
  _KvMutationQueue(this._db, this._uid);

  final CacheStorePersistence _db;
  final String _uid;

  bool _started = false;

  /// The id of the next batch: batch ids are unique across the users of the cache.
  int _nextBatchId = 0;

  Uint8List _lastStreamToken = Uint8List(0);

  Uint8List get _queueKey => _key(_Table.mutQueue).string(_uid).bytes;

  Uint8List get _batchesPrefix => _key(_Table.mut).string(_uid).bytes;

  Uint8List _batchKey(int batchId) =>
      _key(_Table.mut).string(_uid).integer(batchId).bytes;

  Uint8List _docMutPrefix(DocumentKey key) =>
      _key(_Table.docMut).string(_uid).documentKey(key).bytes;

  @override
  Future<void> start() async {
    _started = true;
    await _load();
    if (await _db._tx.get(_queueKey) == null) {
      // An entry for every queue, so that the next batch id is found across all users.
      await _writeQueueMetadata();
    }
  }

  /// Reads the next batch id and the stream token.
  Future<void> _load() async {
    if (!_started) {
      return;
    }
    // Batch ids start at 1, as in the other caches.
    int highest = 0;
    for (final String uid in await _db._queueUids()) {
      final Uint8List prefix = _key(_Table.mut).string(uid).bytes;
      final List<CacheStoreEntry> last = await _db._tx.scan(
        prefix,
        prefixEnd(prefix),
        reverse: true,
        limit: 1,
      );
      if (last.isNotEmpty) {
        final int batchId =
            (KvKeyReader(last.single.key)
                  ..string()
                  ..string())
                .integer();
        if (batchId > highest) {
          highest = batchId;
        }
      }
    }
    _nextBatchId = highest + 1;
    _lastStreamToken = await _db._tx.get(_queueKey) ?? Uint8List(0);
  }

  Future<void> _writeQueueMetadata() =>
      _db._tx.put(_queueKey, _lastStreamToken);

  @override
  Future<bool> isEmpty() async => !await _db._hasPrefix(_batchesPrefix);

  @override
  Future<int> getMutationBatchCount() async =>
      (await _db._scanAll(_batchesPrefix)).length;

  @override
  Future<int> getHighestUnacknowledgedBatchId({
    bool skipOtherClients = false,
  }) async {
    final List<CacheStoreEntry> last = await _db._tx.scan(
      _batchesPrefix,
      prefixEnd(_batchesPrefix),
      reverse: true,
      limit: 1,
    );
    if (last.isEmpty) {
      return MutationBatch.unknown;
    }
    return (KvKeyReader(last.single.key)
          ..string()
          ..string())
        .integer();
  }

  @override
  Future<void> acknowledgeBatch(
    MutationBatch batch,
    Uint8List streamToken,
  ) async {
    _lastStreamToken = streamToken;
    await _writeQueueMetadata();
  }

  @override
  Uint8List get lastStreamToken => _lastStreamToken;

  @override
  Future<void> setLastStreamToken(Uint8List streamToken) async {
    _lastStreamToken = streamToken;
    await _writeQueueMetadata();
  }

  @override
  Future<MutationBatch> addMutationBatch(
    Timestamp localWriteTime,
    List<Mutation> baseMutations,
    List<Mutation> mutations,
  ) async {
    final int batchId = _nextBatchId++;
    final MutationBatch batch = MutationBatch(
      batchId: batchId,
      localWriteTime: localWriteTime,
      baseMutations: baseMutations,
      mutations: mutations,
    );
    await _db._tx.put(
      _batchKey(batchId),
      _db.serializer.encodeMutationBatch(batch).writeToBuffer(),
    );
    final Set<DocumentKey> keys = <DocumentKey>{};
    for (final Mutation mutation in mutations) {
      if (!keys.add(mutation.key)) {
        continue;
      }
      await _db._tx.put(
        _key(
          _Table.docMut,
        ).string(_uid).documentKey(mutation.key).integer(batchId).bytes,
        _empty,
      );
      await _db.indexManager.addToCollectionParentIndex(
        mutation.key.path.popLast(),
      );
    }
    _db._statsCollector.recordRowsWritten(
      MutationQueue.statsTag,
      mutations.length,
    );
    return batch;
  }

  @override
  Future<MutationBatch?> lookupMutationBatch(int batchId) async {
    _db._statsCollector.recordRowsRead(MutationQueue.statsTag, 1);
    final Uint8List? value = await _db._tx.get(_batchKey(batchId));
    return value == null ? null : _decode(value);
  }

  @override
  Future<MutationBatch?> getNextMutationBatchAfterBatchId(
    int batchId, {
    bool skipOtherClients = false,
  }) async {
    _db._statsCollector.recordRowsRead(MutationQueue.statsTag, 1);
    final List<CacheStoreEntry> next = await _db._tx.scan(
      _batchKey(batchId + 1),
      prefixEnd(_batchesPrefix),
      limit: 1,
    );
    return next.isEmpty ? null : _decode(next.single.value);
  }

  @override
  Future<List<MutationBatch>> getAllMutationBatches() async {
    final List<CacheStoreEntry> entries = await _db._scanAll(_batchesPrefix);
    _db._statsCollector.recordRowsRead(MutationQueue.statsTag, entries.length);
    return <MutationBatch>[
      for (final CacheStoreEntry entry in entries) _decode(entry.value),
    ];
  }

  /// The batch ids of the `docMut` entries starting with [prefix].
  Future<Set<int>> _batchIdsUnder(Uint8List prefix) async {
    final Set<int> batchIds = <int>{};
    for (final CacheStoreEntry entry in await _db._scanAll(prefix)) {
      final KvKeyReader reader = KvKeyReader(entry.key)
        ..string()
        ..string()
        ..documentKey();
      batchIds.add(reader.integer());
    }
    return batchIds;
  }

  Future<List<MutationBatch>> _lookupAll(Iterable<int> batchIds) async {
    final List<int> sorted = batchIds.toList()..sort();
    final List<MutationBatch> result = <MutationBatch>[];
    for (final int batchId in sorted) {
      final Uint8List? value = await _db._tx.get(_batchKey(batchId));
      hardAssert(
        value != null,
        'Dangling document-mutation reference found: missing batch $batchId',
      );
      result.add(_decode(value!));
    }
    _db._statsCollector.recordRowsRead(MutationQueue.statsTag, result.length);
    return result;
  }

  @override
  Future<List<MutationBatch>> getAllMutationBatchesAffectingDocumentKey(
    DocumentKey documentKey,
  ) async => _lookupAll(await _batchIdsUnder(_docMutPrefix(documentKey)));

  @override
  Future<MutationBatch?> getNewestMutationBatchAffectingDocumentKey(
    DocumentKey documentKey, {
    int? beforeBatchId,
  }) async {
    final Uint8List prefix = _docMutPrefix(documentKey);
    final List<CacheStoreEntry> newest = await _db._tx.scan(
      prefix,
      beforeBatchId == null
          ? prefixEnd(prefix)
          : _key(_Table.docMut)
                .string(_uid)
                .documentKey(documentKey)
                .integer(beforeBatchId)
                .bytes,
      reverse: true,
      limit: 1,
    );
    if (newest.isEmpty) {
      return null;
    }
    final int batchId =
        (KvKeyReader(newest.single.key)
              ..string()
              ..string()
              ..documentKey())
            .integer();
    return lookupMutationBatch(batchId);
  }

  @override
  Future<List<MutationBatch>> getAllMutationBatchesAffectingDocumentKeys(
    Iterable<DocumentKey> documentKeys,
  ) async {
    final Set<int> batchIds = <int>{};
    for (final DocumentKey key in documentKeys) {
      batchIds.addAll(await _batchIdsUnder(_docMutPrefix(key)));
    }
    return _lookupAll(batchIds);
  }

  @override
  Future<List<MutationBatch>> getAllMutationBatchesAffectingQuery(
    Query query,
  ) async {
    hardAssert(
      !query.isCollectionGroupQuery,
      'CollectionGroup queries should be handled in LocalDocumentsView',
    );
    // The documents of the collection, not those of its subcollections: their keys share the collection's path.
    return _lookupAll(
      await _batchIdsUnder(
        _key(_Table.docMut).string(_uid).path(query.path).bytes,
      ),
    );
  }

  @override
  Future<void> replaceMutationBatch(MutationBatch batch) async {
    await _db._tx.put(
      _batchKey(batch.batchId),
      _db.serializer.encodeMutationBatch(batch).writeToBuffer(),
    );
    _db._statsCollector.recordRowsWritten(
      MutationQueue.statsTag,
      batch.mutations.length,
    );
  }

  @override
  Future<void> removeMutationBatch(MutationBatch batch) async {
    final Uint8List batchKey = _batchKey(batch.batchId);
    hardAssertLazy(
      await _db._tx.get(batchKey) != null,
      () => 'Mutation batch ($_uid, ${batch.batchId}) did not exist',
    );
    await _db._tx.delete(batchKey);
    for (final Mutation mutation in batch.mutations) {
      final DocumentKey key = mutation.key;
      await _db._tx.delete(
        _key(
          _Table.docMut,
        ).string(_uid).documentKey(key).integer(batch.batchId).bytes,
      );
      await _db.referenceDelegate.removeMutationReference(key);
    }
    _db._statsCollector.recordRowsDeleted(
      MutationQueue.statsTag,
      batch.mutations.length,
    );
  }

  @override
  Future<void> performConsistencyCheck() async {
    if (!await isEmpty()) {
      return;
    }
    final List<CacheStoreEntry> dangling = await _db._scanAll(
      _key(_Table.docMut).string(_uid).bytes,
    );
    hardAssertLazy(
      dangling.isEmpty,
      () =>
          'Document leak -- detected dangling mutation references when queue '
          'is empty. Dangling keys: ${dangling.map((CacheStoreEntry entry) => (KvKeyReader(entry.key)
            ..string()
            ..string()).documentKey()).toList()}',
    );
  }

  MutationBatch _decode(Uint8List bytes) => _db.serializer.decodeMutationBatch(
    parseStoredProto('MutationBatch', () => proto.WriteBatch.fromBuffer(bytes)),
  );
}
