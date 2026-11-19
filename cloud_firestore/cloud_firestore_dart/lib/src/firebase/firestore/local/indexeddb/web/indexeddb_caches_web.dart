part of 'indexeddb_persistence_web.dart';

/// The document overlays of one user on `documentOverlays` (`indexeddb_document_overlay_cache.ts`).
class IndexedDbDocumentOverlayCache implements DocumentOverlayCache {
  IndexedDbDocumentOverlayCache._(this._persistence, User user)
    : _userId = user.uid ?? '';

  final WebIndexedDbPersistence _persistence;
  final String _userId;

  _IdbTransaction get _transaction => _persistence._current;

  IndexedDbSerializer get _serializer => _persistence.serializer;

  /// `toDbDocumentOverlayKey`: `[userId, encoded collection path, document id]`.
  JSAny _key(DocumentKey key) => idbKey(<Object>[
    _userId,
    encodeJsResourcePath(key.path.popLast()),
    key.path.getLastSegment(),
  ]);

  Overlay? _decode(Object? row) => row is Map
      ? _serializer.fromDbDocumentOverlay(row.cast<String, Object?>())
      : null;

  @override
  Future<Overlay?> getOverlay(DocumentKey key) async {
    final _IdbTransaction transaction = _transaction;
    return _decode(
      await transaction.read(
        'get the overlay of $key',
        () => transaction.store(DbStores.documentOverlays).get(_key(key)),
      ),
    );
  }

  @override
  Future<Map<DocumentKey, Overlay>> getOverlays(
    Iterable<DocumentKey> keys,
  ) async {
    final _IdbTransaction transaction = _transaction;
    final List<DocumentKey> list = keys.toList();
    final List<Object?> rows = await Future.wait(<Future<Object?>>[
      for (final DocumentKey key in list)
        transaction.read(
          'get the overlay of $key',
          () => transaction.store(DbStores.documentOverlays).get(_key(key)),
        ),
    ]);
    final Map<DocumentKey, Overlay> result = <DocumentKey, Overlay>{};
    for (int i = 0; i < list.length; i++) {
      final Overlay? overlay = _decode(rows[i]);
      if (overlay != null) {
        result[list[i]] = overlay;
      }
    }
    return result;
  }

  @override
  Future<void> saveOverlays(
    int largestBatchId,
    Map<DocumentKey, Mutation> overlays,
  ) async {
    final _IdbTransaction transaction = _transaction;
    await Future.wait(<Future<Object?>>[
      for (final Mutation mutation in overlays.values)
        transaction.request(
          'put the overlay of ${mutation.key}',
          () => transaction
              .store(DbStores.documentOverlays)
              .put(
                idbToJs(
                  _serializer.toDbDocumentOverlay(
                    _userId,
                    Overlay(largestBatchId, mutation),
                  ),
                ),
              ),
        ),
    ]);
  }

  @override
  Future<void> removeOverlaysForBatchId(int batchId) async {
    final _IdbTransaction transaction = _transaction;
    // PORTING NOTE: the JS SDK gets the keys of the batch and deletes per collection through
    // `collectionPathOverlayIndex`; this interface gives the batch id only, so the rows of the user are scanned.
    await transaction.forEach(
      'delete the overlays of batch $batchId',
      () => transaction
          .store(DbStores.documentOverlays)
          .openCursor(
            web.IDBKeyRange.bound(
              idbKey(<Object>[_userId]),
              idbKey(<Object>[immediateSuccessorOf(_userId)]),
              false,
              true,
            ),
          ),
      (web.IDBCursor cursor) {
        final Object? largestBatchId =
            ((cursor as web.IDBCursorWithValue).value! as JSObject)
                .getProperty('largestBatchId'.toJS)
                .dartify();
        if (largestBatchId is num && largestBatchId.toInt() == batchId) {
          cursor.delete();
        }
        return true;
      },
    );
  }

  @override
  Future<void> removeOverlays(Iterable<DocumentKey> keys) async {
    final _IdbTransaction transaction = _transaction;
    await Future.wait(<Future<Object?>>[
      for (final DocumentKey key in keys)
        transaction.request(
          'delete the overlay of $key',
          () => transaction.store(DbStores.documentOverlays).delete(_key(key)),
        ),
    ]);
  }

  @override
  Future<Map<DocumentKey, Overlay>> getOverlaysForCollection(
    ResourcePath collection,
    int sinceBatchId,
  ) async {
    final _IdbTransaction transaction = _transaction;
    final String collectionPath = encodeJsResourcePath(collection);
    final List<Object?> rows =
        (await transaction.read(
              'get the overlays of $collection',
              () => transaction
                  .store(DbStores.documentOverlays)
                  .index(DbStores.documentOverlaysCollectionPathIndex)
                  .getAll(
                    web.IDBKeyRange.bound(
                      idbKey(<Object>[_userId, collectionPath, sinceBatchId]),
                      idbKey(<Object>[
                        _userId,
                        collectionPath,
                        double.infinity,
                      ]),
                      true,
                    ),
                  ),
            ))!
            as List<Object?>;
    final Map<DocumentKey, Overlay> result = <DocumentKey, Overlay>{};
    for (final Object? row in rows) {
      final Overlay overlay = _decode(row)!;
      result[overlay.key] = overlay;
    }
    return result;
  }

  @override
  Future<Map<DocumentKey, Overlay>> getOverlaysForCollectionGroup(
    String collectionGroup,
    int sinceBatchId,
    int count,
  ) async {
    final _IdbTransaction transaction = _transaction;
    final Map<DocumentKey, Overlay> result = <DocumentKey, Overlay>{};
    int? currentBatchId;
    await transaction.forEach(
      'get the overlays of the collection group $collectionGroup',
      () => transaction
          .store(DbStores.documentOverlays)
          .index(DbStores.documentOverlaysCollectionGroupIndex)
          .openCursor(
            web.IDBKeyRange.bound(
              idbKey(<Object>[_userId, collectionGroup, sinceBatchId]),
              idbKey(<Object>[_userId, collectionGroup, double.infinity]),
              true,
            ),
          ),
      (web.IDBCursor cursor) {
        final Overlay overlay = _decode(
          idbToDart((cursor as web.IDBCursorWithValue).value),
        )!;
        // All the overlays of a batch, even past [count].
        if (result.length < count || overlay.largestBatchId == currentBatchId) {
          result[overlay.key] = overlay;
          currentBatchId = overlay.largestBatchId;
          return true;
        }
        return false;
      },
    );
    return result;
  }
}

/// The global values on `globals` (`indexeddb_globals_cache.ts`): rows `{name, value}` with the value a `Uint8Array`.
class IndexedDbGlobalsCache implements GlobalsCache {
  IndexedDbGlobalsCache._(this._persistence);

  final WebIndexedDbPersistence _persistence;

  static const String _sessionToken = 'sessionToken';

  _IdbTransaction get _transaction => _persistence._current;

  @override
  Future<Uint8List> getSessionToken() async =>
      await getValue(_sessionToken) ?? Uint8List(0);

  @override
  Future<void> setSessionToken(Uint8List value) =>
      setValue(_sessionToken, value);

  /// The prefix of the rows of the [QueuedWritesMergeMark]s, followed by the user id.
  static const String _queuedWritesMergeMark = 'queuedWritesMergeMark/';

  /// NOT IN THE OFFICIAL SDKS: the mark is a row `{name, value}` with the value the UTF-8 bytes of
  /// `<batchId>,<seconds>,<nanoseconds>`, as the SQLite cache stores it. The JS SDK does not read it.
  @override
  Future<QueuedWritesMergeMark?> getQueuedWritesMergeMark(String uid) async {
    final Uint8List? value = await getValue('$_queuedWritesMergeMark$uid');
    if (value == null) {
      return null;
    }
    final List<int?> numbers = <int?>[
      for (final String part
          in utf8.decode(value, allowMalformed: true).split(','))
        int.tryParse(part),
    ];
    if (numbers.length != 3 ||
        numbers.contains(null) ||
        numbers[2]! < 0 ||
        numbers[2]! >= 1000000000) {
      return null;
    }
    return QueuedWritesMergeMark(
      numbers[0]!,
      Timestamp(numbers[1]!, numbers[2]!),
    );
  }

  @override
  Future<void> setQueuedWritesMergeMark(
    String uid,
    QueuedWritesMergeMark mark,
  ) {
    final Timestamp time = mark.localWriteTime;
    return setValue(
      '$_queuedWritesMergeMark$uid',
      Uint8List.fromList(
        utf8.encode('${mark.batchId},${time.seconds},${time.nanoseconds}'),
      ),
    );
  }

  /// NOT IN THE OFFICIAL SDKS: values other than the session token (the record of the JS SDK cache import) are rows of
  /// the same store, which the JS SDK does not read.
  @override
  Future<Uint8List?> getValue(String name) async {
    final _IdbTransaction transaction = _transaction;
    final JSAny? row = await transaction.request(
      'get the global "$name"',
      () => transaction.store(DbStores.globals).get(name.toJS),
    );
    if (row.isUndefinedOrNull) {
      return null;
    }
    final JSAny? value = (row as JSObject).getProperty('value'.toJS);
    if (value.isUndefinedOrNull || !value.isA<JSUint8Array>()) {
      return null;
    }
    return Uint8List.fromList((value as JSUint8Array).toDart);
  }

  @override
  Future<void> setValue(String name, Uint8List? value) async {
    final _IdbTransaction transaction = _transaction;
    if (value == null) {
      await transaction.request(
        'delete the global "$name"',
        () => transaction.store(DbStores.globals).delete(name.toJS),
      );
      return;
    }
    final JSObject row = JSObject()
      ..setProperty('name'.toJS, name.toJS)
      ..setProperty('value'.toJS, Uint8List.fromList(value).toJS);
    await transaction.request(
      'put the global "$name"',
      () => transaction.store(DbStores.globals).put(row),
    );
  }
}

/// The collection parent index on `collectionParents` (`addToCollectionParentIndex` and `getCollectionParents` of
/// `indexeddb_index_manager.ts`).
///
/// TODO(long1eu): client-side field indexes, the next slice (`indexConfiguration`, `indexState` and `indexEntries`).
/// Until then no target is served from an index, as with a memory cache: [getIndexType] is [IndexType.none] and the
/// configuration methods do nothing.
class IndexedDbIndexManager extends IndexManager {
  IndexedDbIndexManager._(this._persistence);

  final WebIndexedDbPersistence _persistence;

  /// The entries already written, so that each one is written once per client (`collectionParentsCache` of the JS
  /// SDK).
  final MemoryCollectionParentIndex _written = MemoryCollectionParentIndex();

  _IdbTransaction get _transaction => _persistence._current;

  @override
  Future<void> start() async {}

  @override
  Future<void> addToCollectionParentIndex(ResourcePath collectionPath) async {
    hardAssert(collectionPath.length % 2 == 1, 'Expected a collection path.');
    if (_written.contains(collectionPath)) {
      return;
    }
    final _IdbTransaction transaction = _transaction;
    final JSAny? row = idbToJs(<String, Object?>{
      'collectionId': collectionPath.getLastSegment(),
      'parent': encodeJsResourcePath(collectionPath.popLast()),
    });
    await transaction.request(
      'put the collection parent of $collectionPath',
      () => transaction.store(DbStores.collectionParents).put(row),
    );
    _written.add(collectionPath);
  }

  @override
  Future<List<ResourcePath>> getCollectionParents(String collectionId) async {
    final _IdbTransaction transaction = _transaction;
    final List<Object?> rows =
        (await transaction.read(
              'get the parents of $collectionId',
              () => transaction
                  .store(DbStores.collectionParents)
                  .getAll(
                    web.IDBKeyRange.bound(
                      idbKey(<Object>[collectionId, '']),
                      idbKey(<Object>[immediateSuccessorOf(collectionId), '']),
                      false,
                      true,
                    ),
                  ),
            ))!
            as List<Object?>;
    return <ResourcePath>[
      for (final Object? row in rows)
        if (row is Map && row['collectionId'] == collectionId)
          decodeJsResourcePath(row['parent']! as String),
    ];
  }

  @override
  Future<void> addFieldIndex(FieldIndex index) async {}

  @override
  Future<void> deleteFieldIndex(FieldIndex index) async {}

  @override
  Future<void> deleteAllFieldIndexes() async {}

  @override
  Future<void> createTargetIndexes(Target target) async {}

  @override
  List<FieldIndex> getFieldIndexes([String? collectionGroup]) =>
      const <FieldIndex>[];

  @override
  IndexOffset getMinOffsetForTarget(Target target) => IndexOffset.none;

  @override
  IndexOffset getMinOffset(String collectionGroup) => IndexOffset.none;

  @override
  IndexType getIndexType(Target target) => IndexType.none;

  @override
  Future<List<DocumentKey>?> getDocumentsMatchingTarget(Target target) async =>
      null;

  @override
  Future<bool> hasCurrentIndexEntries(Target target, Document document) async =>
      false;

  @override
  String? getNextCollectionGroupToUpdate() => null;

  @override
  Future<void> updateCollectionGroup(
    String collectionGroup,
    IndexOffset offset,
  ) async {}

  @override
  Future<void> updateIndexEntries(
    Map<DocumentKey, MaybeDocument?> documents,
  ) async {}
}

/// The reference delegate and LRU garbage collection of the JS SDK's IndexedDB persistence
/// (`IndexedDbLruDelegateImpl`): every document that gains or loses a reference gets a sentinel row in
/// `targetDocuments` (target 0) with the sequence number of the transaction, and a released target keeps its data with
/// a new sequence number. A document whose only row in `targetDocuments` is its sentinel is orphaned; the collector
/// removes the orphaned documents and the inactive targets with the lowest sequence numbers once the cache (the
/// `byteSize` of `remoteDocumentGlobal`, as the JS SDK counts it) is over the threshold.
class IndexedDbReferenceDelegate implements ReferenceDelegate, LruDelegate {
  IndexedDbReferenceDelegate._(
    this._persistence,
    LruGarbageCollectorParams params,
  ) {
    garbageCollector = LruGarbageCollector(this, params);
  }

  final WebIndexedDbPersistence _persistence;

  late ListenSequence _listenSequence;

  int _currentSequenceNumber = ListenSequence.invalid;

  @override
  ReferenceSet? inMemoryPins;

  @override
  late final LruGarbageCollector garbageCollector;

  void _start(int highestSequenceNumber) {
    _listenSequence = ListenSequence(highestSequenceNumber);
  }

  @override
  int get currentSequenceNumber {
    hardAssert(
      _currentSequenceNumber != ListenSequence.invalid,
      'Attempting to get a sequence number outside of a transaction',
    );
    return _currentSequenceNumber;
  }

  @override
  void onTransactionStarted() {
    _currentSequenceNumber = _listenSequence.next;
  }

  @override
  Future<void> onTransactionCommitted() async {
    _currentSequenceNumber = ListenSequence.invalid;
  }

  @override
  void onTransactionRolledBack() {
    _currentSequenceNumber = ListenSequence.invalid;
  }

  /// `sentinelKey`: `[0, encoded path]`.
  static JSAny _sentinelKey(String encodedPath) =>
      idbKey(<Object>[0, encodedPath]);

  Future<void> _writeSentinel(DocumentKey key) async {
    final _IdbTransaction transaction = _persistence._current;
    final JSAny? row = idbToJs(<String, Object?>{
      'targetId': 0,
      'path': encodeJsResourcePath(key.path),
      'sequenceNumber': currentSequenceNumber,
    });
    await transaction.request(
      'put the sentinel row of $key',
      () => transaction.store(DbStores.targetDocuments).put(row),
    );
  }

  @override
  Future<void> addReference(DocumentKey key) => _writeSentinel(key);

  @override
  Future<void> removeReference(DocumentKey key) => _writeSentinel(key);

  @override
  Future<void> removeMutationReference(DocumentKey key) => _writeSentinel(key);

  @override
  Future<void> updateLimboDocument(DocumentKey key) => _writeSentinel(key);

  @override
  Future<void> removeTarget(QueryData queryData) {
    return _persistence.queryCache.updateQueryData(
      queryData.copyWith(
        snapshotVersion: queryData.snapshotVersion,
        resumeToken: queryData.resumeToken,
        sequenceNumber: currentSequenceNumber,
      ),
    );
  }

  // LRU garbage collection

  @override
  Future<void> forEachTarget(Consumer<QueryData> consumer) =>
      _persistence.queryCache.forEachTarget(consumer);

  @override
  Future<int> getSequenceNumberCount() async {
    int orphaned = 0;
    await _forEachOrphanedDocument((String _, int _) => orphaned++);
    return _persistence.queryCache.targetCount + orphaned;
  }

  @override
  Future<void> forEachOrphanedDocumentSequenceNumber(Consumer<int> consumer) =>
      _forEachOrphanedDocument(
        (String _, int sequenceNumber) => consumer(sequenceNumber),
      );

  /// Calls [visit] with the encoded path and the sequence number of every orphaned document: a document whose only row
  /// in `targetDocuments` is its sentinel row (target 0). The rows are read through `documentTargetsIndex`
  /// (`[path, targetId]`), where the sentinel of a document comes first (`forEachOrphanedDocument`).
  Future<void> _forEachOrphanedDocument(
    void Function(String encodedPath, int sequenceNumber) visit,
  ) async {
    final _IdbTransaction transaction = _persistence._current;
    String? nextPath;
    int nextToReport = ListenSequence.invalid;
    await transaction.forEach(
      'find the orphaned documents',
      () => transaction
          .store(DbStores.targetDocuments)
          .index(DbStores.targetDocumentsDocumentIndex)
          .openCursor(),
      (web.IDBCursor cursor) {
        final JSObject row =
            (cursor as web.IDBCursorWithValue).value! as JSObject;
        final JSAny? targetId = row.getProperty('targetId'.toJS);
        if (targetId.isA<JSNumber>() &&
            (targetId! as JSNumber).toDartDouble == 0) {
          // A new document: the previous one had no target if it is still to report.
          if (nextToReport != ListenSequence.invalid) {
            visit(nextPath!, nextToReport);
          }
          final JSAny? sequenceNumber = row.getProperty('sequenceNumber'.toJS);
          // The JS SDK always writes it in a sentinel row; one without counts as the oldest.
          nextToReport = sequenceNumber.isA<JSNumber>()
              ? (sequenceNumber! as JSNumber).toDartDouble.toInt()
              : 0;
          nextPath = (row.getProperty('path'.toJS)! as JSString).toDart;
        } else {
          nextToReport = ListenSequence.invalid;
        }
        return true;
      },
    );
    if (nextToReport != ListenSequence.invalid) {
      visit(nextPath!, nextToReport);
    }
  }

  @override
  Future<int> removeTargets(int upperBound, Set<int> activeTargetIds) =>
      _persistence.queryCache.removeTargets(upperBound, activeTargetIds);

  /// The ids of the users that have a batch in `mutations`, read through `userMutationsIndex` with one step per user.
  ///
  /// PORTING NOTE: the JS SDK walks the keys of `mutationQueues` (`mutationQueuesContainKey`), but no longer writes
  /// rows there itself; the users are read from the batches instead, so that the pending writes of a user the JS SDK
  /// added are pinned too.
  Future<List<String>> _usersWithBatches(_IdbTransaction transaction) async {
    final List<String> users = <String>[];
    await transaction.walk(
      'find the users with pending writes',
      () => transaction
          .store(DbStores.mutations)
          .index(DbStores.mutationsUserIndex)
          .openKeyCursor(),
      (web.IDBCursor cursor) {
        final Object? key = idbToDart(cursor.key);
        if (key is! List || key.isEmpty || key.first is! String) {
          return true;
        }
        final String user = key.first! as String;
        users.add(user);
        return idbKey(<Object>[user, double.infinity]);
      },
    );
    return users;
  }

  /// Whether a pending write of any user changes the document at [encodedPath] (`mutationQueuesContainKey`).
  Future<bool> _mutationQueuesContain(
    _IdbTransaction transaction,
    List<String> users,
    String encodedPath,
  ) async {
    for (final String user in users) {
      final JSAny? key = await transaction.request(
        'find a pending write of a document',
        () => transaction
            .store(DbStores.documentMutations)
            .getKey(
              web.IDBKeyRange.bound(
                idbKey(<Object>[user, encodedPath]),
                idbKey(<Object>[user, encodedPath, double.infinity]),
              ),
            ),
      );
      if (!key.isUndefinedOrNull) {
        return true;
      }
    }
    return false;
  }

  @override
  Future<int> removeOrphanedDocuments(int upperBound) async {
    final _IdbTransaction transaction = _persistence._current;
    final List<String> candidates = <String>[];
    await _forEachOrphanedDocument((String path, int sequenceNumber) {
      if (sequenceNumber <= upperBound) {
        candidates.add(path);
      }
    });
    if (candidates.isEmpty) {
      return 0;
    }
    final List<String> users = await _usersWithBatches(transaction);
    final List<DocumentKey> removed = <DocumentKey>[];
    for (final String path in candidates) {
      final DocumentKey key = DocumentKey.fromPath(decodeJsResourcePath(path));
      if ((inMemoryPins?.containsKey(key) ?? false) ||
          await _mutationQueuesContain(transaction, users, path)) {
        continue;
      }
      removed.add(key);
      await transaction.request(
        'delete the sentinel row of $key',
        () => transaction
            .store(DbStores.targetDocuments)
            .delete(_sentinelKey(path)),
      );
    }
    await _persistence.remoteDocumentCache.removeAll(removed);
    return removed.length;
  }

  @override
  Future<int> get byteSize => _persistence.remoteDocumentCache.getSize();
}

/// Bundles and named queries are not stored yet.
///
/// TODO(long1eu): bundles and named queries, a later slice (`bundles` and `namedQueries`, `indexeddb_bundle_cache.ts`).
/// Until then nothing is found, and loading a bundle fails with an [UnimplementedError].
class IndexedDbBundleCache implements BundleCache {
  const IndexedDbBundleCache._();

  @override
  Future<BundleMetadata?> getBundleMetadata(String bundleId) async => null;

  @override
  Future<NamedQuery?> getNamedQuery(String queryName) async => null;

  @override
  Future<void> saveBundleMetadata(BundleMetadata metadata) {
    throw UnimplementedError(
      'Loading bundles is not supported by the IndexedDB cache (IndexedDbCacheSettings) yet.',
    );
  }

  @override
  Future<void> saveNamedQuery(NamedQuery query) {
    throw UnimplementedError(
      'Loading bundles is not supported by the IndexedDB cache (IndexedDbCacheSettings) yet.',
    );
  }
}
