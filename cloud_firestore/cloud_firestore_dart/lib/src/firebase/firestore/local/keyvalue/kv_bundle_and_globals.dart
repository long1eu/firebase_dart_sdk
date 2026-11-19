part of 'cache_store_persistence.dart';

/// The loaded bundles (`bundle`) and named queries (`namedQuery`).
class _KvBundleCache implements BundleCache {
  _KvBundleCache(this._db);

  final CacheStorePersistence _db;

  @override
  Future<BundleMetadata?> getBundleMetadata(String bundleId) async {
    final Uint8List? value = await _db._tx.get(
      _key(_Table.bundle).string(bundleId).bytes,
    );
    if (value == null) {
      return null;
    }
    final KvKeyReader reader = KvKeyReader(value);
    final int schemaVersion = reader.integer();
    final SnapshotVersion createTime = _readVersion(reader);
    final int totalDocuments = reader.integer();
    final int totalBytes = reader.integer();
    return BundleMetadata(
      bundleId,
      schemaVersion,
      createTime,
      totalDocuments,
      totalBytes,
    );
  }

  @override
  Future<void> saveBundleMetadata(BundleMetadata metadata) => _db._tx.put(
    _key(_Table.bundle).string(metadata.bundleId).bytes,
    _writeVersion(
      KvKeyWriter().integer(metadata.schemaVersion),
      metadata.createTime,
    ).integer(metadata.totalDocuments).integer(metadata.totalBytes).bytes,
  );

  @override
  Future<NamedQuery?> getNamedQuery(String queryName) async {
    final Uint8List? value = await _db._tx.get(
      _key(_Table.namedQuery).string(queryName).bytes,
    );
    if (value == null) {
      return null;
    }
    final KvKeyReader reader = KvKeyReader(value);
    final SnapshotVersion readTime = _readVersion(reader);
    final Uint8List bytes = reader.rest();
    final BundledQuery bundledQuery = _db.serializer.decodeBundledQuery(
      parseStoredProto(
        'NamedQuery',
        () => proto.BundledQuery.fromBuffer(bytes),
      ),
    );
    return NamedQuery(queryName, bundledQuery, readTime);
  }

  @override
  Future<void> saveNamedQuery(NamedQuery query) => _db._tx.put(
    _key(_Table.namedQuery).string(query.name).bytes,
    _writeVersion(KvKeyWriter(), query.readTime)
        .raw(
          _db.serializer.encodeBundledQuery(query.bundledQuery).writeToBuffer(),
        )
        .bytes,
  );
}

/// The values that cut across components (`global`): the session token and the queued-writes merge marks.
class _KvGlobalsCache implements GlobalsCache {
  _KvGlobalsCache(this._db);

  final CacheStorePersistence _db;

  static const String _sessionToken = 'sessionToken';
  static const String _mergeMarkPrefix = 'queuedWritesMergeMark/';

  Uint8List _valueKey(String name) =>
      _key(_Table.global).string('value/$name').bytes;

  @override
  Future<Uint8List> getSessionToken() async =>
      await getValue(_sessionToken) ?? Uint8List(0);

  @override
  Future<void> setSessionToken(Uint8List value) =>
      setValue(_sessionToken, value);

  @override
  Future<Uint8List?> getValue(String name) => _db._tx.get(_valueKey(name));

  @override
  Future<void> setValue(String name, Uint8List? value) => value == null
      ? _db._tx.delete(_valueKey(name))
      : _db._tx.put(_valueKey(name), value);

  @override
  Future<QueuedWritesMergeMark?> getQueuedWritesMergeMark(String uid) async {
    final Uint8List? value = await getValue('$_mergeMarkPrefix$uid');
    if (value == null) {
      return null;
    }
    final KvKeyReader reader = KvKeyReader(value);
    final int batchId = reader.integer();
    final int seconds = reader.integer();
    final int nanos = reader.integer();
    return QueuedWritesMergeMark(batchId, Timestamp(seconds, nanos));
  }

  @override
  Future<void> setQueuedWritesMergeMark(
    String uid,
    QueuedWritesMergeMark mark,
  ) => setValue(
    '$_mergeMarkPrefix$uid',
    KvKeyWriter()
        .integer(mark.batchId)
        .integer(mark.localWriteTime.seconds)
        .integer(mark.localWriteTime.nanoseconds)
        .bytes,
  );
}
