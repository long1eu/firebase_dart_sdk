part of 'indexeddb_persistence_web.dart';

/// The cache of targets on `targets`, `targetDocuments` and `targetGlobal` (`indexeddb_target_cache.ts`).
///
/// PORTING NOTE: the JS SDK reads `targetGlobal` in every transaction that needs it, because other tabs change it.
/// Here one tab has the database, so the metadata is kept in memory as in the Android SDK (read at start, and again
/// after a transaction rolled back).
class IndexedDbQueryCache implements QueryCache {
  IndexedDbQueryCache._(this._persistence);

  final WebIndexedDbPersistence _persistence;

  @override
  int highestTargetId = 0;

  int _highestListenSequenceNumber = 0;

  @override
  SnapshotVersion lastRemoteSnapshotVersion = SnapshotVersion.none;

  @override
  int targetCount = 0;

  @override
  int get highestListenSequenceNumber => _highestListenSequenceNumber;

  _IdbTransaction get _transaction => _persistence._current;

  IndexedDbSerializer get _serializer => _persistence.serializer;

  /// The row of `targetGlobal` (`DbTargetGlobal`).
  static Map<String, Object?> _metadataRow(
    int highestTargetId,
    int highestListenSequenceNumber,
    SnapshotVersion lastRemoteSnapshotVersion,
    int targetCount,
  ) => <String, Object?>{
    'highestTargetId': highestTargetId,
    'highestListenSequenceNumber': highestListenSequenceNumber,
    'lastRemoteSnapshotVersion': toDbTimestamp(lastRemoteSnapshotVersion),
    'targetCount': targetCount,
  };

  /// Reads the metadata, inside a transaction.
  Future<void> _load() async {
    final _IdbTransaction transaction = _transaction;
    final Object? row = await transaction.read(
      'get the target metadata',
      () => transaction
          .store(DbStores.targetGlobal)
          .get(DbStores.targetGlobalKey.toJS),
    );
    hardAssert(row is Map, 'Missing target metadata row.');
    final Map<Object?, Object?> metadata = row! as Map<Object?, Object?>;
    int number(String field) => (metadata[field] as num?)?.toInt() ?? 0;
    highestTargetId = number('highestTargetId');
    _highestListenSequenceNumber = number('highestListenSequenceNumber');
    final Object? version = metadata['lastRemoteSnapshotVersion'];
    lastRemoteSnapshotVersion = version is Map
        ? fromDbTimestamp(version)
        : SnapshotVersion.none;
    targetCount = number('targetCount');
  }

  Future<void> _writeMetadata() async {
    final _IdbTransaction transaction = _transaction;
    await transaction.request(
      'put the target metadata',
      () => transaction
          .store(DbStores.targetGlobal)
          .put(
            idbToJs(
              _metadataRow(
                highestTargetId,
                _highestListenSequenceNumber,
                lastRemoteSnapshotVersion,
                targetCount,
              ),
            ),
            DbStores.targetGlobalKey.toJS,
          ),
    );
  }

  @override
  Future<void> forEachTarget(Consumer<QueryData> consumer) async {
    final _IdbTransaction transaction = _transaction;
    final List<Object?> rows =
        (await transaction.read(
              'get all targets',
              () => transaction.store(DbStores.targets).getAll(),
            ))!
            as List<Object?>;
    for (final Object? row in rows) {
      final QueryData? data = _decode(row);
      if (data != null) {
        consumer(data);
      }
    }
  }

  /// The target of [row], or null for one this SDK can not read (a pipeline target of the JS SDK).
  QueryData? _decode(Object? row) {
    if (row is! Map) {
      return null;
    }
    try {
      return _serializer.fromDbTarget(row.cast<String, Object?>());
    } on FormatException catch (e) {
      Log.d(
        WebIndexedDbPersistence.tag,
        'Skipping target ${row['targetId']}: ${e.message}',
      );
      return null;
    }
  }

  @override
  Future<void> setLastRemoteSnapshotVersion(SnapshotVersion snapshotVersion) =>
      _persistence._write(
        'Set the last remote snapshot version',
        () => _setLastRemoteSnapshotVersion(snapshotVersion),
      );

  Future<void> _setLastRemoteSnapshotVersion(
    SnapshotVersion snapshotVersion,
  ) async {
    lastRemoteSnapshotVersion = snapshotVersion;
    await _writeMetadata();
  }

  Future<void> _saveQueryData(QueryData queryData) async {
    final _IdbTransaction transaction = _transaction;
    final JSAny? row = idbToJs(_serializer.toDbTarget(queryData));
    await transaction.request(
      'put target ${queryData.targetId}',
      () => transaction.store(DbStores.targets).put(row),
    );
  }

  bool _updateMetadata(QueryData queryData) {
    bool updated = false;
    if (queryData.targetId > highestTargetId) {
      highestTargetId = queryData.targetId;
      updated = true;
    }
    if (queryData.sequenceNumber > _highestListenSequenceNumber) {
      _highestListenSequenceNumber = queryData.sequenceNumber;
      updated = true;
    }
    return updated;
  }

  @override
  Future<void> addQueryData(QueryData queryData) =>
      _persistence._write('Add a target', () => _addQueryData(queryData));

  Future<void> _addQueryData(QueryData queryData) async {
    await _saveQueryData(queryData);
    _updateMetadata(queryData);
    targetCount++;
    await _writeMetadata();
  }

  @override
  Future<void> updateQueryData(QueryData queryData) =>
      _persistence._write('Update a target', () => _updateQueryData(queryData));

  Future<void> _updateQueryData(QueryData queryData) async {
    await _saveQueryData(queryData);
    if (_updateMetadata(queryData)) {
      await _writeMetadata();
    }
  }

  @override
  Future<void> removeQueryData(QueryData queryData) =>
      _persistence._write('Remove a target', () => _removeQueryData(queryData));

  Future<void> _removeQueryData(QueryData queryData) async {
    final _IdbTransaction transaction = _transaction;
    final int targetId = queryData.targetId;
    await removeMatchingKeysForTargetId(targetId);
    await transaction.request(
      'delete target $targetId',
      () => transaction.store(DbStores.targets).delete(targetId.toJS),
    );
    hardAssert(targetCount > 0, 'Removing from an empty target cache');
    targetCount--;
    await _writeMetadata();
  }

  /// Removes the targets with a sequence number up to [upperBound] that are not in [activeTargetIds], with their
  /// documents in `targetDocuments` (`removeTargets` of `indexeddb_target_cache.ts`). The rows are read as they are,
  /// not decoded: a target this SDK can not read (a pipeline target of the JS SDK) is collected too.
  Future<int> removeTargets(int upperBound, Set<int> activeTargetIds) async {
    final _IdbTransaction transaction = _transaction;
    final List<int> removed = <int>[];
    await transaction.forEach(
      'find the targets to collect',
      () => transaction.store(DbStores.targets).openCursor(),
      (web.IDBCursor cursor) {
        final JSObject row =
            (cursor as web.IDBCursorWithValue).value! as JSObject;
        final JSAny? id = row.getProperty('targetId'.toJS);
        final JSAny? sequenceNumber = row.getProperty(
          'lastListenSequenceNumber'.toJS,
        );
        if (id.isA<JSNumber>() &&
            sequenceNumber.isA<JSNumber>() &&
            (sequenceNumber! as JSNumber).toDartDouble <= upperBound) {
          final int targetId = (id! as JSNumber).toDartInt;
          if (!activeTargetIds.contains(targetId)) {
            removed.add(targetId);
          }
        }
        return true;
      },
    );
    for (final int targetId in removed) {
      await removeMatchingKeysForTargetId(targetId);
      await transaction.request(
        'delete target $targetId',
        () => transaction.store(DbStores.targets).delete(targetId.toJS),
      );
    }
    if (removed.isNotEmpty) {
      hardAssert(
        targetCount >= removed.length,
        'Removing from an empty target cache',
      );
      targetCount -= removed.length;
      await _writeMetadata();
    }
    return removed.length;
  }

  @override
  Future<QueryData?> getQueryData(Target target) async {
    final _IdbTransaction transaction = _transaction;
    // The canonical id is not unique: compare the targets.
    final String canonicalId = target.canonicalId;
    final List<Object?> rows =
        (await transaction.read(
              'get the targets of a query',
              () => transaction
                  .store(DbStores.targets)
                  .index(DbStores.targetsQueryIndex)
                  .getAll(
                    web.IDBKeyRange.bound(
                      idbKey(<Object>[canonicalId, double.negativeInfinity]),
                      idbKey(<Object>[canonicalId, double.infinity]),
                    ),
                  ),
            ))!
            as List<Object?>;
    for (final Object? row in rows) {
      final QueryData? found = _decode(row);
      if (found != null && found.target == target) {
        return found;
      }
    }
    return null;
  }

  /// The keys of the rows of [targetId] in `targetDocuments`: `[targetId]` to `[targetId + 1]`.
  JSAny _targetRange(int targetId) => web.IDBKeyRange.bound(
    idbKey(<Object>[targetId]),
    idbKey(<Object>[targetId + 1]),
    false,
    true,
  );

  @override
  Future<void> addMatchingKeys(
    ImmutableSortedSet<DocumentKey> keys,
    int targetId,
  ) => _persistence._write(
    'Add matching keys',
    () => _addMatchingKeys(keys, targetId),
  );

  Future<void> _addMatchingKeys(
    ImmutableSortedSet<DocumentKey> keys,
    int targetId,
  ) async {
    final _IdbTransaction transaction = _transaction;
    final ReferenceDelegate delegate = _persistence.referenceDelegate;
    for (final DocumentKey key in keys) {
      final JSAny? row = idbToJs(<String, Object?>{
        'targetId': targetId,
        'path': encodeJsResourcePath(key.path),
      });
      await transaction.request(
        'put a document of target $targetId',
        () => transaction.store(DbStores.targetDocuments).put(row),
      );
      await delegate.addReference(key);
    }
  }

  @override
  Future<void> removeMatchingKeys(
    ImmutableSortedSet<DocumentKey> keys,
    int targetId,
  ) => _persistence._write(
    'Remove matching keys',
    () => _removeMatchingKeys(keys, targetId),
  );

  Future<void> _removeMatchingKeys(
    ImmutableSortedSet<DocumentKey> keys,
    int targetId,
  ) async {
    final _IdbTransaction transaction = _transaction;
    final ReferenceDelegate delegate = _persistence.referenceDelegate;
    for (final DocumentKey key in keys) {
      await transaction.request(
        'delete a document of target $targetId',
        () => transaction
            .store(DbStores.targetDocuments)
            .delete(idbKey(<Object>[targetId, encodeJsResourcePath(key.path)])),
      );
      await delegate.removeReference(key);
    }
  }

  @override
  Future<void> removeMatchingKeysForTargetId(int targetId) =>
      _persistence._write(
        'Remove the matching keys of a target',
        () => _removeMatchingKeysForTargetId(targetId),
      );

  Future<void> _removeMatchingKeysForTargetId(int targetId) async {
    final _IdbTransaction transaction = _transaction;
    await transaction.request(
      'delete the documents of target $targetId',
      () => transaction
          .store(DbStores.targetDocuments)
          .delete(_targetRange(targetId)),
    );
  }

  @override
  Future<ImmutableSortedSet<DocumentKey>> getMatchingKeysForTargetId(
    int targetId,
  ) async {
    final _IdbTransaction transaction = _transaction;
    final List<Object?> keys =
        (await transaction.read(
              'get the documents of target $targetId',
              () => transaction
                  .store(DbStores.targetDocuments)
                  .getAllKeys(_targetRange(targetId)),
            ))!
            as List<Object?>;
    return ImmutableSortedSet<DocumentKey>(<DocumentKey>[
      for (final Object? key in keys)
        DocumentKey.fromPath(
          decodeJsResourcePath((key! as List<Object?>)[1]! as String),
        ),
    ], DocumentKey.comparator);
  }

  @override
  Future<bool> containsKey(DocumentKey key) async {
    final _IdbTransaction transaction = _transaction;
    final String path = encodeJsResourcePath(key.path);
    // The primary keys `[targetId, path]` of the document's rows; the sentinel row of target 0 does not count.
    final List<Object?> keys =
        (await transaction.read(
              'find the targets of a document',
              () => transaction
                  .store(DbStores.targetDocuments)
                  .index(DbStores.targetDocumentsDocumentIndex)
                  .getAllKeys(
                    web.IDBKeyRange.bound(
                      idbKey(<Object>[path]),
                      idbKey(<Object>[immediateSuccessorOf(path)]),
                      false,
                      true,
                    ),
                  ),
            ))!
            as List<Object?>;
    return keys.any(
      (Object? key) => ((key! as List<Object?>)[0]! as num).toInt() != 0,
    );
  }
}
