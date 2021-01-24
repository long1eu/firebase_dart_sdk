// File created by
// Lung Razvan <long1eu>
// on 21/09/2018

part of sqlite_persistence;

/// Cached Queries backed by SQLite.
class SQLiteTargetCache implements TargetCache {
  SQLiteTargetCache(this._db, this._localSerializer);

  final SQLitePersistence _db;
  final LocalSerializer _localSerializer;

  int _lastListenSequenceNumber;

  @override
  int highestTargetId;

  @override
  SnapshotVersion lastRemoteSnapshotVersion = SnapshotVersion.none;

  @override
  int targetCount;

  Future<void> start() async {
    // Store exactly one row in the table. If the row exists at all, it's the global metadata.
    final List<Map<String, dynamic>> result = await _db.query(
      // @formatter:off
        '''
          SELECT highest_target_id,
                 highest_listen_sequence_number,
                 last_remote_snapshot_version_seconds,
                 last_remote_snapshot_version_nanos,
                 target_count
          FROM target_globals
          LIMIT 1;
        '''
        // @formatter:on
        );
    hardAssert(result.isNotEmpty, 'Missing target_globals entry');

    final Map<String, dynamic> row = result.first;

    highestTargetId = row['highest_target_id'];
    _lastListenSequenceNumber = row['highest_listen_sequence_number'];
    lastRemoteSnapshotVersion = SnapshotVersion(Timestamp(
      row['last_remote_snapshot_version_seconds'],
      row['last_remote_snapshot_version_nanos'],
    ));
    targetCount = row['target_count'];
  }

  @override
  int get highestListenSequenceNumber => _lastListenSequenceNumber;

  @override
  Future<void> forEachTarget(Consumer<TargetData> consumer) async {
    final List<Map<String, dynamic>> result = await _db.query(
      // @formatter:off
        '''
          SELECT target_proto
          FROM targets;
        '''
        // @formatter:on
        );

    for (Map<String, dynamic> row in result) {
      final Uint8List targetProto = row['target_proto'];
      final TargetData targetData = _decodeTargetData(targetProto);
      consumer(targetData);
    }
  }

  @override
  Future<void> setLastRemoteSnapshotVersion(SnapshotVersion snapshotVersion) async {
    lastRemoteSnapshotVersion = snapshotVersion;
    await _writeMetadata();
  }

  Future<void> _saveTargetData(TargetData targetData) async {
    final int targetId = targetData.targetId;
    final String canonicalId = targetData.target.canonicalId;
    final Timestamp version = targetData.snapshotVersion.timestamp;

    final proto.Target targetProto = _localSerializer.encodeTargetData(targetData);

    await _db.execute(
      // @formatter:off
        '''
          INSERT
          OR REPLACE INTO targets (target_id,
                                   canonical_id,
                                   snapshot_version_seconds,
                                   snapshot_version_nanos,
                                   resume_token,
                                   last_listen_sequence_number,
                                   target_proto)
          VALUES (?, ?, ?, ?, ?, ?, ?);        
        ''',
        // @formatter:on
        <dynamic>[
          targetId,
          canonicalId,
          version.seconds,
          version.nanoseconds,
          targetData.resumeToken,
          targetData.sequenceNumber,
          targetProto.writeToBuffer()
        ]);
  }

  bool _updateMetadata(TargetData targetData) {
    bool wasUpdated = false;

    if (targetData.targetId > highestTargetId) {
      highestTargetId = targetData.targetId;
      wasUpdated = true;
    }

    if (targetData.sequenceNumber > _lastListenSequenceNumber) {
      _lastListenSequenceNumber = targetData.sequenceNumber;
      wasUpdated = true;
    }

    return wasUpdated;
  }

  @override
  Future<void> addTargetData(TargetData targetData) async {
    await _saveTargetData(targetData);
    // PORTING NOTE: The query_targets index is maintained by SQLite.
    _updateMetadata(targetData);
    targetCount++;
    await _writeMetadata();
  }

  @override
  Future<void> updateTargetData(TargetData targetData) async {
    await _saveTargetData(targetData);

    if (_updateMetadata(targetData)) {
      await _writeMetadata();
    }
  }

  Future<void> _writeMetadata() async {
    await _db.execute(
      // @formatter:off
        '''
          UPDATE target_globals
          SET highest_target_id                    = ?,
              highest_listen_sequence_number       = ?,
              last_remote_snapshot_version_seconds = ?,
              last_remote_snapshot_version_nanos   = ?,
              target_count                         = ?;                  
        '''
        // @formatter:on
        ,
        <dynamic>[
          highestTargetId,
          _lastListenSequenceNumber,
          lastRemoteSnapshotVersion.timestamp.seconds,
          lastRemoteSnapshotVersion.timestamp.nanoseconds,
          targetCount,
        ]);
  }

  Future<void> _removeTarget(int targetId) async {
    await _removeMatchingKeysForTargetId(targetId);
    await _db.execute(
      // @formatter:off
        '''
          DELETE
          FROM targets
          WHERE target_id = ?;
        ''',
        // @formatter:on
        <int>[targetId]);
    targetCount--;
  }

  @override
  Future<void> removeTargetData(TargetData targetData) async {
    final int targetId = targetData.targetId;
    await _removeTarget(targetId);
    await _writeMetadata();
  }

  /// Drops any targets with sequence number less than or equal to the upper bound, excepting those present in
  /// [activeTargetIds]. Document associations for the removed targets are also removed. Returns the number of targets
  /// removed.
  Future<int> removeQueries(int upperBound, Set<int> activeTargetIds) async {
    int count = 0;
    // SQLite has a max sql statement size, so there is technically a possibility that including a an IN clause in this
    // query to filter [activeTargetIds] could overflow. Rather than deal with that, we filter out live targets from the
    // result set.

    final List<Map<String, dynamic>> result = await _db.query(
      // @formatter:off
        '''
          SELECT target_id
          FROM targets
          WHERE last_listen_sequence_number <= ?;
        ''',
        // @formatter:on
        <int>[upperBound]);

    for (Map<String, dynamic> row in result) {
      final int targetId = row['target_id'];
      if (!activeTargetIds.contains(targetId)) {
        await _removeTarget(targetId);
        count++;
      }
    }

    await _writeMetadata();
    return count;
  }

  @override
  Future<TargetData> getTargetData(Target target) async {
    // Querying the targets table by canonical_id may yield more than one result because canonical_id values are not
    // required to be unique per target. This query depends on the query_targets index to be efficient.
    final String canonicalId = target.canonicalId;

    final List<Map<String, dynamic>> result = await _db.query(
      // @formatter:off
        '''
          SELECT target_proto
          FROM targets
          WHERE canonical_id = ?;
        ''',
        // @formatter:on
        <String>[canonicalId]);

    TargetData data;
    for (Map<String, dynamic> row in result) {
      // TODO(long1eu): break out early if found.
      final TargetData found = _decodeTargetData(row['target_proto']);

      // After finding a potential match, check that the query is actually equal to the requested query.
      if (target == found.target) {
        data = found;
      }
    }

    return data;
  }

  TargetData _decodeTargetData(List<int> bytes) {
    return _localSerializer.decodeTargetData(proto.Target.fromBuffer(bytes));
  }

  // Matching key tracking

  @override
  Future<void> addMatchingKeys(ImmutableSortedSet<DocumentKey> keys, int targetId) async {
    // PORTING NOTE: The reverse index (document_targets) is maintained by SQLite.
    //
    // When updates come in we treat those as added keys, which means these inserts won't necessarily be unique between
    // invocations. This INSERT statement uses the IGNORE conflict resolution strategy to avoid failing on any attempts
    // to add duplicate entries. This works because there's no additional information in the row. If we want to track
    // additional data this will probably need to become INSERT OR REPLACE instead.
    const String statement =
    // @formatter:off
        '''
          INSERT
          OR IGNORE INTO target_documents (target_id, path)
          VALUES (?, ?);
        '''
        // @formatter:on
        ;

    final ReferenceDelegate delegate = _db.referenceDelegate;
    for (DocumentKey key in keys) {
      final String path = EncodedPath.encode(key.path);
      await _db.execute(statement, <dynamic>[targetId, path]);
      await delegate.addReference(key);
    }
  }

  @override
  Future<void> removeMatchingKeys(ImmutableSortedSet<DocumentKey> keys, int targetId) async {
    // PORTING NOTE: The reverse index (document_targets) is maintained by SQLite.
    const String statement =
    // @formatter:off
        '''
          DELETE
          FROM target_documents
          WHERE target_id = ?
            AND path = ?;
        ''';
    // @formatter:on

    final ReferenceDelegate delegate = _db.referenceDelegate;
    for (DocumentKey key in keys) {
      final String path = EncodedPath.encode(key.path);
      await _db.execute(statement, <dynamic>[targetId, path]);
      await delegate.removeReference(key);
    }
  }

  Future<void> _removeMatchingKeysForTargetId(int targetId) async {
    await _db.execute(
      // @formatter:off
        '''
          DELETE
          FROM target_documents
          WHERE target_id = ?;
        ''',
        // @formatter:on
        <int>[targetId]);
  }

  @override
  Future<ImmutableSortedSet<DocumentKey>> getMatchingKeysForTargetId(int targetId) async {
    ImmutableSortedSet<DocumentKey> keys = DocumentKey.emptyKeySet;

    final List<Map<String, dynamic>> result = await _db.query(
      // @formatter:off
        '''
          SELECT path
          FROM target_documents
          WHERE target_id = ?;
        ''',
        // @formatter:on
        <int>[targetId]);

    for (Map<String, dynamic> row in result) {
      final String path = row['path'];
      final DocumentKey key = DocumentKey.fromPath(EncodedPath.decodeResourcePath(path));
      keys = keys.insert(key);
    }

    return keys;
  }

  @override
  Future<bool> containsKey(DocumentKey key) async {
    final String path = EncodedPath.encode(key.path);

    final List<Map<String, dynamic>> result = await _db.query(
      // @formatter:off
        '''
          SELECT target_id
          FROM target_documents
          WHERE path = ?
          AND target_id != 0
          LIMIT 1;
        ''',
        // @formatter:on
        <String>[path]);

    return result.isNotEmpty;
  }
}
