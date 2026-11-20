part of 'indexeddb_persistence_web.dart';

/// The mutation queue of one user on the stores `mutations`, `documentMutations` and `mutationQueues`
/// (`indexeddb_mutation_queue.ts`).
///
/// The batch ids come from the key generator of `mutations` (auto-increment), so they are unique across users and
/// never reused, as in the JS SDK.
class IndexedDbMutationQueue implements MutationQueue {
  IndexedDbMutationQueue._(this._persistence, User user)
    : _userId = user.uid ?? '';

  final WebIndexedDbPersistence _persistence;

  /// The user id of the rows: empty for the signed-out user.
  final String _userId;

  Uint8List _lastStreamToken = Uint8List(0);

  _IdbTransaction get _transaction => _persistence._current;

  IndexedDbSerializer get _serializer => _persistence.serializer;

  /// Every row of this user in the index `userMutationsIndex` (`[userId, batchId]`).
  JSAny get _userRange => web.IDBKeyRange.bound(
    idbKey(<Object>[_userId, double.negativeInfinity]),
    idbKey(<Object>[_userId, double.infinity]),
  );

  web.IDBIndex _userIndex(_IdbTransaction transaction) =>
      transaction.store(DbStores.mutations).index(DbStores.mutationsUserIndex);

  /// Writes the row of a new queue: in a transaction of its own when it is called outside of one, as SQLite would
  /// (the local store starts the queue in a transaction, the tests of the mutation queue do not).
  @override
  Future<void> start() =>
      _persistence._write('Start the mutation queue of "$_userId"', () async {
        final _IdbTransaction transaction = _transaction;
        final Object? row = await transaction.read(
          'get the mutation queue of "$_userId"',
          () => transaction.store(DbStores.mutationQueues).get(_userId.toJS),
        );
        if (row is Map && row['lastStreamToken'] is String) {
          _lastStreamToken = base64.decode(row['lastStreamToken']! as String);
        } else if (row == null) {
          await _writeMetadata(MutationBatch.unknown);
        }
      });

  /// The row of this user in `mutationQueues`.
  ///
  /// NOT IN THE OFFICIAL SDKS: the JS SDK no longer writes these rows (it keeps the stream token in memory), but still
  /// reads their keys to learn which users have pending writes (`mutationQueuesContainKey`, for its garbage
  /// collection). This SDK keeps the stream token here, as the Android SDK does in its SQLite table, in the shape the
  /// JS SDK's `DbMutationQueue` row has (the token in base64).
  Future<void> _writeMetadata(int lastAcknowledgedBatchId) async {
    final _IdbTransaction transaction = _transaction;
    await transaction.request(
      'put the mutation queue of "$_userId"',
      () => transaction
          .store(DbStores.mutationQueues)
          .put(
            idbToJs(<String, Object?>{
              'userId': _userId,
              'lastAcknowledgedBatchId': lastAcknowledgedBatchId,
              'lastStreamToken': base64.encode(_lastStreamToken),
            }),
          ),
    );
  }

  @override
  Future<bool> isEmpty() async {
    final _IdbTransaction transaction = _transaction;
    final JSAny? key = await transaction.request(
      'find a batch of "$_userId"',
      () => _userIndex(transaction).getKey(_userRange),
    );
    return key.isUndefinedOrNull;
  }

  @override
  Future<int> getMutationBatchCount() async {
    final _IdbTransaction transaction = _transaction;
    final JSAny? count = await transaction.request(
      'count the batches of "$_userId"',
      () => _userIndex(transaction).count(_userRange),
    );
    return (count! as JSNumber).toDartInt;
  }

  @override
  Future<int> getHighestUnacknowledgedBatchId({
    bool skipOtherClients = false,
  }) async {
    final _IdbTransaction transaction = _transaction;
    int batchId = MutationBatch.unknown;
    // PORTING NOTE: the JS SDK opens this cursor on `upperBound([userId, Infinity])`, which reaches the batches of
    // other users when this one has none; the range here holds this user's batches only.
    await transaction.forEach(
      'find the last batch of "$_userId"',
      () => _userIndex(transaction).openKeyCursor(_userRange, 'prev'),
      (web.IDBCursor cursor) {
        batchId = (idbToDart(cursor.primaryKey)! as num).toInt();
        return false;
      },
    );
    return batchId;
  }

  @override
  Future<void> acknowledgeBatch(MutationBatch batch, Uint8List streamToken) =>
      _persistence._write(
        'Acknowledge a batch',
        () => _acknowledgeBatch(batch, streamToken),
      );

  Future<void> _acknowledgeBatch(
    MutationBatch batch,
    Uint8List streamToken,
  ) async {
    _lastStreamToken = streamToken;
    await _writeMetadata(batch.batchId);
  }

  @override
  Uint8List get lastStreamToken => _lastStreamToken;

  @override
  Future<void> setLastStreamToken(Uint8List streamToken) => _persistence._write(
    'Set the last stream token',
    () => _setLastStreamToken(streamToken),
  );

  Future<void> _setLastStreamToken(Uint8List streamToken) async {
    _lastStreamToken = streamToken;
    final _IdbTransaction transaction = _transaction;
    final Object? row = await transaction.read(
      'get the mutation queue of "$_userId"',
      () => transaction.store(DbStores.mutationQueues).get(_userId.toJS),
    );
    final Object? acknowledged = row is Map
        ? row['lastAcknowledgedBatchId']
        : null;
    await _writeMetadata(
      acknowledged is num ? acknowledged.toInt() : MutationBatch.unknown,
    );
  }

  @override
  Future<MutationBatch> addMutationBatch(
    Timestamp localWriteTime,
    List<Mutation> baseMutations,
    List<Mutation> mutations,
  ) => _persistence._write(
    'Add a mutation batch',
    () => _addMutationBatch(localWriteTime, baseMutations, mutations),
  );

  Future<MutationBatch> _addMutationBatch(
    Timestamp localWriteTime,
    List<Mutation> baseMutations,
    List<Mutation> mutations,
  ) async {
    hardAssert(mutations.isNotEmpty, 'Mutation batches should not be empty');
    final _IdbTransaction transaction = _transaction;
    // As the JS SDK: an empty row first to take the next key of the generator, then the batch under that key (Chrome
    // and Firefox did not index rows with a generated key in a compound index correctly, crbug.com/701972).
    final JSAny? key = await transaction.request(
      'allocate a batch id',
      () => transaction.store(DbStores.mutations).add(JSObject()),
    );
    final int batchId = (key! as JSNumber).toDartInt;
    final MutationBatch batch = MutationBatch(
      batchId: batchId,
      localWriteTime: localWriteTime,
      baseMutations: baseMutations,
      mutations: mutations,
    );
    final JSAny? row = idbToJs(_serializer.toDbMutationBatch(_userId, batch));
    final Set<ResourcePath> collectionParents = <ResourcePath>{};
    final List<Future<Object?>> writes = <Future<Object?>>[
      transaction.request(
        'put batch $batchId',
        () => transaction.store(DbStores.mutations).put(row),
      ),
    ];
    for (final Mutation mutation in mutations) {
      collectionParents.add(mutation.key.path.popLast());
      final JSAny indexKey = idbKey(<Object>[
        _userId,
        encodeJsResourcePath(mutation.key.path),
        batchId,
      ]);
      writes.add(
        transaction.request(
          'put a document mutation of batch $batchId',
          () => transaction
              .store(DbStores.documentMutations)
              .put(JSObject(), indexKey),
        ),
      );
    }
    await Future.wait(writes);
    _persistence._statsCollector.recordRowsWritten(
      MutationQueue.statsTag,
      mutations.length,
    );
    for (final ResourcePath parent in collectionParents) {
      await _persistence.indexManager.addToCollectionParentIndex(parent);
    }
    return batch;
  }

  MutationBatch? _decode(Object? row, int batchId) {
    if (row is! Map) {
      return null;
    }
    _persistence._statsCollector.recordRowsRead(MutationQueue.statsTag, 1);
    hardAssertLazy(
      row['userId'] == _userId,
      () =>
          'Unexpected user "${row['userId']}" for mutation batch $batchId (expected "$_userId")',
    );
    return _serializer.fromDbMutationBatch(row.cast<String, Object?>());
  }

  @override
  Future<MutationBatch?> lookupMutationBatch(int batchId) async {
    final _IdbTransaction transaction = _transaction;
    final Object? row = await transaction.read(
      'get batch $batchId',
      () => transaction.store(DbStores.mutations).get(batchId.toJS),
    );
    return _decode(row, batchId);
  }

  @override
  Future<MutationBatch?> getNextMutationBatchAfterBatchId(
    int batchId, {
    bool skipOtherClients = false,
  }) async {
    final _IdbTransaction transaction = _transaction;
    final List<Object?> rows =
        (await transaction.read(
              'get the batch of "$_userId" after $batchId',
              () => _userIndex(transaction).getAll(
                web.IDBKeyRange.bound(
                  idbKey(<Object>[_userId, batchId + 1]),
                  idbKey(<Object>[_userId, double.infinity]),
                ),
                1,
              ),
            ))!
            as List<Object?>;
    return rows.isEmpty
        ? null
        : _decode(
            rows.first,
            ((rows.first! as Map)['batchId']! as num).toInt(),
          );
  }

  @override
  Future<List<MutationBatch>> getAllMutationBatches() async {
    final _IdbTransaction transaction = _transaction;
    final List<Object?> rows =
        (await transaction.read(
              'get the batches of "$_userId"',
              () => _userIndex(transaction).getAll(_userRange),
            ))!
            as List<Object?>;
    return <MutationBatch>[
      for (final Object? row in rows)
        _decode(row, ((row! as Map)['batchId']! as num).toInt())!,
    ];
  }

  /// The ids of the batches with a row in `documentMutations` for [path] (in order).
  Future<List<int>> _batchIdsFor(
    _IdbTransaction transaction,
    ResourcePath path,
  ) async {
    final String encoded = encodeJsResourcePath(path);
    final List<int> batchIds = <int>[];
    await transaction.forEach(
      'find the batches of a document',
      () => transaction
          .store(DbStores.documentMutations)
          .openKeyCursor(
            web.IDBKeyRange.lowerBound(idbKey(<Object>[_userId, encoded])),
          ),
      (web.IDBCursor cursor) {
        final List<Object?> key = idbToDart(cursor.key)! as List<Object?>;
        // The rows of one document are contiguous and come before those of its subcollections.
        if (key[0] != _userId || key[1] != encoded) {
          return false;
        }
        batchIds.add((key[2]! as num).toInt());
        return true;
      },
    );
    return batchIds;
  }

  Future<List<MutationBatch>> _lookupMutationBatches(
    _IdbTransaction transaction,
    Iterable<int> batchIds,
  ) async {
    final List<int> sorted = batchIds.toSet().toList()..sort();
    final List<Object?> rows = await Future.wait(<Future<Object?>>[
      for (final int batchId in sorted)
        transaction.read(
          'get batch $batchId',
          () => transaction.store(DbStores.mutations).get(batchId.toJS),
        ),
    ]);
    final List<MutationBatch> result = <MutationBatch>[];
    for (int i = 0; i < sorted.length; i++) {
      final MutationBatch? batch = _decode(rows[i], sorted[i]);
      hardAssertLazy(
        batch != null,
        () =>
            'Dangling document-mutation reference found, which points to batch ${sorted[i]}',
      );
      result.add(batch!);
    }
    return result;
  }

  @override
  Future<List<MutationBatch>> getAllMutationBatchesAffectingDocumentKey(
    DocumentKey documentKey,
  ) async {
    final _IdbTransaction transaction = _transaction;
    return _lookupMutationBatches(
      transaction,
      await _batchIdsFor(transaction, documentKey.path),
    );
  }

  @override
  Future<MutationBatch?> getNewestMutationBatchAffectingDocumentKey(
    DocumentKey documentKey, {
    int? beforeBatchId,
  }) async {
    final _IdbTransaction transaction = _transaction;
    final String encoded = encodeJsResourcePath(documentKey.path);
    // A backwards key cursor over the rows `[userId, path, batchId]` of the document, below [beforeBatchId].
    int? batchId;
    await transaction.forEach(
      'find the newest batch of a document',
      () => transaction
          .store(DbStores.documentMutations)
          .openKeyCursor(
            web.IDBKeyRange.bound(
              idbKey(<Object>[_userId, encoded, double.negativeInfinity]),
              idbKey(<Object>[
                _userId,
                encoded,
                beforeBatchId ?? double.infinity,
              ]),
              false,
              true,
            ),
            'prev',
          ),
      (web.IDBCursor cursor) {
        final List<Object?> key = idbToDart(cursor.key)! as List<Object?>;
        batchId = (key[2]! as num).toInt();
        return false;
      },
    );
    final int? found = batchId;
    if (found == null) {
      return null;
    }
    return (await _lookupMutationBatches(transaction, <int>[found])).single;
  }

  @override
  Future<List<MutationBatch>> getAllMutationBatchesAffectingDocumentKeys(
    Iterable<DocumentKey> documentKeys,
  ) async {
    final _IdbTransaction transaction = _transaction;
    final List<List<int>> ids = await Future.wait(<Future<List<int>>>[
      for (final DocumentKey key in documentKeys)
        _batchIdsFor(transaction, key.path),
    ]);
    return _lookupMutationBatches(transaction, ids.expand((List<int> i) => i));
  }

  @override
  Future<List<MutationBatch>> getAllMutationBatchesAffectingQuery(
    Query query,
  ) async {
    hardAssert(
      !query.isCollectionGroupQuery,
      'CollectionGroup queries should be handled in LocalDocumentsView',
    );
    final _IdbTransaction transaction = _transaction;
    final ResourcePath queryPath = query.path;
    final int immediateChildrenLength = queryPath.length + 1;
    final Set<int> batchIds = <int>{};
    await transaction.forEach(
      'find the batches of a collection',
      () => transaction
          .store(DbStores.documentMutations)
          .openKeyCursor(
            web.IDBKeyRange.lowerBound(
              idbKey(<Object>[_userId, encodeJsResourcePath(queryPath)]),
            ),
          ),
      (web.IDBCursor cursor) {
        final List<Object?> key = idbToDart(cursor.key)! as List<Object?>;
        if (key[0] != _userId) {
          return false;
        }
        final ResourcePath path = decodeJsResourcePath(key[1]! as String);
        if (!queryPath.isPrefixOf(path)) {
          return false;
        }
        // Rows of documents in subcollections can not match.
        if (path.length == immediateChildrenLength) {
          batchIds.add((key[2]! as num).toInt());
        }
        return true;
      },
    );
    return _lookupMutationBatches(transaction, batchIds);
  }

  /// The row of the batch is rewritten under the same key; the rows of `documentMutations` stay, since [batch] changes
  /// the same documents.
  @override
  Future<void> replaceMutationBatch(MutationBatch batch) => _persistence._write(
    'Replace a mutation batch',
    () => _replaceMutationBatch(batch),
  );

  Future<void> _replaceMutationBatch(MutationBatch batch) async {
    final _IdbTransaction transaction = _transaction;
    final JSAny? row = idbToJs(_serializer.toDbMutationBatch(_userId, batch));
    await transaction.request(
      'replace batch ${batch.batchId}',
      () => transaction.store(DbStores.mutations).put(row),
    );
  }

  @override
  Future<void> removeMutationBatch(MutationBatch batch) => _persistence._write(
    'Remove a mutation batch',
    () => _removeMutationBatch(batch),
  );

  Future<void> _removeMutationBatch(MutationBatch batch) async {
    final _IdbTransaction transaction = _transaction;
    final int batchId = batch.batchId;
    int deleted = 0;
    await transaction.forEach(
      'delete batch $batchId',
      () => transaction
          .store(DbStores.mutations)
          .openCursor(web.IDBKeyRange.only(batchId.toJS)),
      (web.IDBCursor cursor) {
        deleted++;
        cursor.delete();
        return true;
      },
    );
    hardAssert(
      deleted == 1,
      'Dangling document-mutation reference found: missing batch $batchId',
    );
    _persistence._statsCollector.recordRowsDeleted(
      MutationQueue.statsTag,
      batch.mutations.length,
    );
    await Future.wait(<Future<Object?>>[
      for (final Mutation mutation in batch.mutations)
        transaction.request(
          'delete a document mutation of batch $batchId',
          () => transaction
              .store(DbStores.documentMutations)
              .delete(
                idbKey(<Object>[
                  _userId,
                  encodeJsResourcePath(mutation.key.path),
                  batchId,
                ]),
              ),
        ),
    ]);
    for (final Mutation mutation in batch.mutations) {
      await _persistence.referenceDelegate.removeMutationReference(
        mutation.key,
      );
    }
  }

  @override
  Future<void> performConsistencyCheck() async {
    if (!await isEmpty()) {
      return;
    }
    final _IdbTransaction transaction = _transaction;
    final List<ResourcePath> dangling = <ResourcePath>[];
    await transaction.forEach(
      'find dangling document mutations',
      () => transaction
          .store(DbStores.documentMutations)
          .openKeyCursor(web.IDBKeyRange.lowerBound(idbKey(<Object>[_userId]))),
      (web.IDBCursor cursor) {
        final List<Object?> key = idbToDart(cursor.key)! as List<Object?>;
        if (key[0] != _userId) {
          return false;
        }
        dangling.add(decodeJsResourcePath(key[1]! as String));
        return true;
      },
    );
    hardAssertLazy(
      dangling.isEmpty,
      () =>
          'Document leak -- detected dangling mutation references when queue is empty. Dangling keys: $dangling',
    );
  }
}
