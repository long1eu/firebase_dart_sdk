part of 'cache_store_persistence.dart';

/// The targets: `target` by id, `targetCanon` by canonical id, `targetDoc` and `docTarget` for the documents of a
/// target in both directions, and `targetGlobal` for the counters, which are also kept in memory.
class _KvQueryCache implements QueryCache {
  _KvQueryCache(this._db);

  final CacheStorePersistence _db;

  static final Uint8List _globalsKey = _key(_Table.targetGlobal).bytes;

  @override
  int highestTargetId = 0;

  @override
  int highestListenSequenceNumber = 0;

  @override
  SnapshotVersion lastRemoteSnapshotVersion = SnapshotVersion.none;

  @override
  int targetCount = 0;

  Future<void> _start() async {
    final Uint8List? value = await _db._tx.get(_globalsKey);
    if (value == null) {
      highestTargetId = 0;
      highestListenSequenceNumber = 0;
      lastRemoteSnapshotVersion = SnapshotVersion.none;
      targetCount = 0;
      await _writeMetadata();
      return;
    }
    final KvKeyReader reader = KvKeyReader(value);
    highestTargetId = reader.integer();
    highestListenSequenceNumber = reader.integer();
    lastRemoteSnapshotVersion = _readVersion(reader);
    targetCount = reader.integer();
  }

  Future<void> _writeMetadata() => _db._tx.put(
    _globalsKey,
    _writeVersion(
      KvKeyWriter()
          .integer(highestTargetId)
          .integer(highestListenSequenceNumber),
      lastRemoteSnapshotVersion,
    ).integer(targetCount).bytes,
  );

  Uint8List _targetKey(int targetId) =>
      _key(_Table.target).integer(targetId).bytes;

  Uint8List _canonicalKey(QueryData queryData) => _key(
    _Table.targetCanon,
  ).string(queryData.target.canonicalId).integer(queryData.targetId).bytes;

  @override
  Future<void> forEachTarget(Consumer<QueryData> consumer) async {
    for (final CacheStoreEntry entry in await _db._scanAll(
      _key(_Table.target).bytes,
    )) {
      consumer(_decode(entry.value));
    }
  }

  @override
  Future<void> setLastRemoteSnapshotVersion(
    SnapshotVersion snapshotVersion,
  ) async {
    lastRemoteSnapshotVersion = snapshotVersion;
    await _writeMetadata();
  }

  Future<void> _save(QueryData queryData) async {
    await _db._tx.put(
      _targetKey(queryData.targetId),
      _db.serializer.encodeQueryData(queryData).writeToBuffer(),
    );
    await _db._tx.put(_canonicalKey(queryData), _empty);
  }

  bool _updateMetadata(QueryData queryData) {
    bool updated = false;
    if (queryData.targetId > highestTargetId) {
      highestTargetId = queryData.targetId;
      updated = true;
    }
    if (queryData.sequenceNumber > highestListenSequenceNumber) {
      highestListenSequenceNumber = queryData.sequenceNumber;
      updated = true;
    }
    return updated;
  }

  @override
  Future<void> addQueryData(QueryData queryData) async {
    await _save(queryData);
    _updateMetadata(queryData);
    targetCount++;
    await _writeMetadata();
  }

  @override
  Future<void> updateQueryData(QueryData queryData) async {
    await _save(queryData);
    if (_updateMetadata(queryData)) {
      await _writeMetadata();
    }
  }

  Future<void> _removeTarget(QueryData queryData) async {
    await removeMatchingKeysForTargetId(queryData.targetId);
    await _db._tx.delete(_targetKey(queryData.targetId));
    await _db._tx.delete(_canonicalKey(queryData));
    targetCount--;
  }

  @override
  Future<void> removeQueryData(QueryData queryData) async {
    await _removeTarget(queryData);
    await _writeMetadata();
  }

  /// Removes the targets whose sequence number is at most [upperBound] and that are not in [activeTargetIds], with
  /// their documents. Returns how many were removed.
  Future<int> _removeQueries(int upperBound, Set<int> activeTargetIds) async {
    int count = 0;
    for (final CacheStoreEntry entry in await _db._scanAll(
      _key(_Table.target).bytes,
    )) {
      final QueryData queryData = _decode(entry.value);
      if (queryData.sequenceNumber <= upperBound &&
          !activeTargetIds.contains(queryData.targetId)) {
        await _removeTarget(queryData);
        count++;
      }
    }
    await _writeMetadata();
    return count;
  }

  @override
  Future<QueryData?> getQueryData(Target target) async {
    // Canonical ids are not unique: the targets that share one are compared.
    final Uint8List prefix = _key(
      _Table.targetCanon,
    ).string(target.canonicalId).bytes;
    for (final CacheStoreEntry entry in await _db._scanAll(prefix)) {
      final int targetId =
          (KvKeyReader(entry.key)
                ..string()
                ..string())
              .integer();
      final Uint8List? value = await _db._tx.get(_targetKey(targetId));
      if (value == null) {
        continue;
      }
      final QueryData found = _decode(value);
      if (found.target == target) {
        return found;
      }
    }
    return null;
  }

  Uint8List _targetDocKey(int targetId, DocumentKey key) =>
      _key(_Table.targetDoc).integer(targetId).documentKey(key).bytes;

  Uint8List _docTargetKey(DocumentKey key, int targetId) =>
      _key(_Table.docTarget).documentKey(key).integer(targetId).bytes;

  @override
  Future<void> addMatchingKeys(
    ImmutableSortedSet<DocumentKey> keys,
    int targetId,
  ) async {
    final ReferenceDelegate delegate = _db.referenceDelegate;
    for (final DocumentKey key in keys) {
      await _db._tx.put(_targetDocKey(targetId, key), _empty);
      await _db._tx.put(_docTargetKey(key, targetId), _empty);
      await delegate.addReference(key);
    }
  }

  @override
  Future<void> removeMatchingKeys(
    ImmutableSortedSet<DocumentKey> keys,
    int targetId,
  ) async {
    final ReferenceDelegate delegate = _db.referenceDelegate;
    for (final DocumentKey key in keys) {
      await _db._tx.delete(_targetDocKey(targetId, key));
      await _db._tx.delete(_docTargetKey(key, targetId));
      await delegate.removeReference(key);
    }
  }

  @override
  Future<void> removeMatchingKeysForTargetId(int targetId) async {
    final Uint8List prefix = _key(_Table.targetDoc).integer(targetId).bytes;
    for (final CacheStoreEntry entry in await _db._scanAll(prefix)) {
      final DocumentKey key =
          (KvKeyReader(entry.key)
                ..string()
                ..integer())
              .documentKey();
      await _db._tx.delete(entry.key);
      await _db._tx.delete(_docTargetKey(key, targetId));
    }
  }

  @override
  Future<ImmutableSortedSet<DocumentKey>> getMatchingKeysForTargetId(
    int targetId,
  ) async {
    final Uint8List prefix = _key(_Table.targetDoc).integer(targetId).bytes;
    return ImmutableSortedSet<DocumentKey>(<DocumentKey>[
      for (final CacheStoreEntry entry in await _db._scanAll(prefix))
        (KvKeyReader(entry.key)
              ..string()
              ..integer())
            .documentKey(),
    ], DocumentKey.comparator);
  }

  @override
  Future<bool> containsKey(DocumentKey key) async {
    // Target id 0 holds the sequence number of the LRU garbage collector, not a target.
    final Uint8List prefix = _key(_Table.docTarget).documentKey(key).bytes;
    final List<CacheStoreEntry> found = await _db._tx.scan(
      _docTargetKey(key, 1),
      prefixEnd(prefix),
      limit: 1,
    );
    return found.isNotEmpty;
  }

  QueryData _decode(Uint8List bytes) => _db.serializer.decodeQueryData(
    parseStoredProto('TargetData', () => proto.Target.fromBuffer(bytes)),
  );
}
