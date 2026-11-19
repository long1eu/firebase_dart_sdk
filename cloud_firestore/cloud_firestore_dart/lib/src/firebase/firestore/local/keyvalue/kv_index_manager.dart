part of 'cache_store_persistence.dart';

/// The collection parent index (`collParent`), for collection group queries.
///
/// The key-value cache has no persistent cache indexes (field indexes) yet: the client reports it as a cache without
/// them (`persistentCacheIndexManager` is null and `setIndexConfiguration` throws), and the methods that would create
/// one throw an [UnsupportedError] rather than ignore it. Queries run on the documents of the collection, as with
/// the memory cache.
class _KvIndexManager implements IndexManager {
  _KvIndexManager(this._db);

  final CacheStorePersistence _db;

  /// The parents added in this session, so that a document write does not write its parent again.
  final Set<ResourcePath> _knownParents = <ResourcePath>{};

  static UnsupportedError _unsupported() => UnsupportedError(
    'The key-value cache (keyValueCacheSettings) has no persistent cache indexes yet.',
  );

  @override
  Future<void> addToCollectionParentIndex(ResourcePath collectionPath) async {
    hardAssert(collectionPath.length.isOdd, 'Expected a collection path.');
    if (_knownParents.contains(collectionPath)) {
      return;
    }
    await _db._tx.put(
      _key(_Table.collParent)
          .string(collectionPath.getLastSegment())
          .path(collectionPath.popLast())
          .bytes,
      _empty,
    );
    // Only remembered once the transaction committed: a rolled back one did not write it.
    final ResourcePath path = collectionPath;
    _pendingParents.add(path);
  }

  /// The parents written by the running transaction.
  final Set<ResourcePath> _pendingParents = <ResourcePath>{};

  void _onCommitted() {
    _knownParents.addAll(_pendingParents);
    _pendingParents.clear();
  }

  void _onRolledBack() => _pendingParents.clear();

  @override
  Future<List<ResourcePath>> getCollectionParents(String collectionId) async {
    final Uint8List prefix = _key(_Table.collParent).string(collectionId).bytes;
    return <ResourcePath>[
      for (final CacheStoreEntry entry in await _db._scanAll(prefix))
        (KvKeyReader(entry.key)
              ..string()
              ..string())
            .path(),
    ];
  }

  @override
  Future<void> start() async {}

  @override
  Future<void> addFieldIndex(FieldIndex index) async => throw _unsupported();

  @override
  Future<void> deleteFieldIndex(FieldIndex index) async => throw _unsupported();

  /// Nothing to delete: there are none.
  @override
  Future<void> deleteAllFieldIndexes() async {}

  @override
  Future<void> createTargetIndexes(Target target) async => throw _unsupported();

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
  List<FieldIndex> getFieldIndexes([String? collectionGroup]) =>
      const <FieldIndex>[];

  @override
  IndexOffset getMinOffsetForTarget(Target target) => IndexOffset.none;

  @override
  IndexOffset getMinOffset(String collectionGroup) => IndexOffset.none;

  @override
  IndexType getIndexType(Target target) => IndexType.none;

  @override
  Future<void> updateIndexEntries(
    Map<DocumentKey, MaybeDocument?> documents,
  ) async {}
}
