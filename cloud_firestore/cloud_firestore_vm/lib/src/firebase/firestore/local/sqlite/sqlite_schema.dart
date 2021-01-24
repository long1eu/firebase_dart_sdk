// File created by
// Lung Razvan <long1eu>
// on 21/09/2018

part of sqlite_persistence;

/// Migrates schemas from version 0 (empty) to whatever the current version is.
///
/// Migrations are numbered for the version of the database they apply to. The [version] constant in this class should
/// be one more than the highest numbered migration.
///
/// NOTE: Once we ship code with a migration in it the code for that migration should never be changed again. Further
/// changes can be made to the schema by adding a new migration method, bumping the [version], and adding a call to the
/// migration method from [runMigrations].
class SQLiteSchema {
  const SQLiteSchema(this.db, this.serializer);

  /// The version of the schema. Increase this by one for each migration added to [runMigrations] below.
  static const int version = 11;

  // Remove this constant and increment version to enable indexing support
  static const int indexingSupportVersion = version + 1;

  final Database db;
  final LocalSerializer serializer;

  /// Runs the migration methods defined in this class, starting at the given version.
  Future<void> runMigrations([int fromVersion = 0, int toVersion = version]) async {
    // New migrations should be added at the end of the series of `if` statements and should follow the pattern. Make
    // sure to increment `VERSION` and to read the comment below about requirements for new migrations.

    if (fromVersion < 1 && toVersion >= 1) {
      await _createV1MutationQueue();
      await _createV1TargetCache();
      await _createV1RemoteDocumentCache();
    }

    // Migration 2 to populate the target_globals table no longer needed since migration 3 unconditionally clears it.

    if (fromVersion < 3 && toVersion >= 3) {
      // Brand new clients don't need to drop and recreate--only clients that have potentially corrupt data.
      if (fromVersion != 0) {
        await _dropV1TargetCache();
        await _createV1TargetCache();
      }
    }

    if (fromVersion < 4 && toVersion >= 4) {
      await _ensureTargetGlobal();
      await _addTargetCount();
    }

    if (fromVersion < 5 && toVersion >= 5) {
      await _addSequenceNumber();
    }

    if (fromVersion < 6 && toVersion >= 6) {
      await _removeAcknowledgedMutations();
    }

    if (fromVersion < 7 && toVersion >= 7) {
      await _ensureSequenceNumbers();
    }

    if (fromVersion < 8 && toVersion >= 8) {
      await _createV8CollectionParentsIndex();
    }

    if (fromVersion < 9 && toVersion >= 9) {
      if (!await _hasReadTime()) {
        await _addReadTime();
      } else {
        // Index-free queries rely on the fact that documents updated after a query's last limbo
        // free snapshot version are persisted with their read-time. If a customer upgrades to
        // schema version 9, downgrades and then upgrades again, some queries may have a last limbo
        // free snapshot version despite the fact that not all updated document have an associated
        // read time.
        await _dropLastLimboFreeSnapshotVersion();
      }
    }

    if (fromVersion == 9 && toVersion >= 10) {
      // Firestore v21.10 contained a regression that led us to disable an assert that is required
      // to ensure data integrity. While the schema did not change between version 9 and 10, we use
      // the schema bump to version 10 to clear any affected data.
      await _dropLastLimboFreeSnapshotVersion();
    }

    if (fromVersion < 11 && toVersion >= 11) {
      // Schema version 11 changed the format of canonical IDs in the target cache.
      await _rewriteCanonicalIds();
    }

    // Adding a new migration? READ THIS FIRST!
    //
    // Be aware that the SDK version may be downgraded then re-upgraded. This means that running your new migration must
    // not prevent older versions of the SDK from functioning. Additionally, your migration must be able to run multiple
    // times. In practice, this means a few things:
    //  * Do not delete tables or columns. Older versions may be reading and writing them.
    //  * Guard schema additions. Check if tables or columns exist before adding them.
    //  * Data migrations should *probably* always run. Older versions of the SDK will not have maintained invariants
    //  from later versions, so migrations that update values cannot assume that existing values have been properly
    //  maintained. Calculate them again, if applicable.

    if (fromVersion < indexingSupportVersion && toVersion >= indexingSupportVersion) {
      if (Persistence.indexingSupportEnabled) {
        await _createLocalDocumentsCollectionIndex();
      }
    }
  }

  /// Used to assert that a set of tables either all exist or not. The supplied function is run if none of the tables
  /// exist. Use this method to create a set of tables at once.
  ///
  /// If some but not all of the tables exist, an exception will be thrown.
  Future<void> _ifTablesDontExist(List<String> tables, Future<void> Function() fn) async {
    bool tablesFound = false;
    final String allTables = '[${tables.join(', ')}]';
    for (int i = 0; i < tables.length; i++) {
      final String table = tables[i];
      final bool tableFound = await _tableExists(table);
      if (i == 0) {
        tablesFound = tableFound;
      } else if (tableFound != tablesFound) {
        final StringBuffer msg = StringBuffer('Expected all of $allTables to either exist or not, but ');
        if (tablesFound) {
          msg.write('${tables[0]} exists and $table does not');
        } else {
          msg.write('${tables[0]} does not exist and $table does');
        }
        throw StateError(msg.toString());
      }
    }
    if (!tablesFound) {
      return fn();
    } else {
      Log.d('SQLiteSchema', 'Skipping migration because all of $allTables already exist');
    }
  }

  Future<void> _createV1MutationQueue() async {
    return _ifTablesDontExist(<String>['mutation_queues', 'mutations', 'document_mutations'], () async {
      // A table naming all the mutation queues in the system.
      await db.query(
        // @formatter:off
          '''
          CREATE TABLE mutation_queues (
            uid                        TEXT PRIMARY KEY,
            last_acknowledged_batch_id INTEGER,
            last_stream_token          BLOB
          );
        '''
          // @formatter:on
          );

      // All the mutation batches in the system, partitioned by user.
      await db.query(
        // @formatter:off
          '''
          CREATE TABLE mutations (
            uid       TEXT,
            batch_id  INTEGER,
            mutations BLOB,
            PRIMARY KEY (uid, batch_id)
          );
        '''
          // @formatter:on
          );

      // A manually maintained index of all the mutation batches that affect a given document key. The rows in this
      // table are references based on the contents of mutations.mutations.
      await db.query(
        // @formatter:off
          '''
          CREATE TABLE document_mutations (
            uid      TEXT,
            path     TEXT,
            batch_id INTEGER,
            PRIMARY KEY (uid, path, batch_id)
          );
        '''
          // @formatter:on
          );
    });
  }

  /// Note: as of this migration, [last_acknowledged_batch_id] is no longer used by the code.
  Future<void> _removeAcknowledgedMutations() async {
    final List<Map<String, dynamic>> data =
        await db.query('SELECT uid, last_acknowledged_batch_id FROM mutation_queues');

    for (Map<String, dynamic> row in data) {
      final String uid = row['uid'];
      final int lastAcknowledgedBatchId = row['last_acknowledged_batch_id'];

      final List<Map<String, dynamic>> rows = await db.query(
          'SELECT batch_id FROM mutations WHERE uid = ? AND batch_id <= ?', <dynamic>[uid, lastAcknowledgedBatchId]);

      for (Map<String, dynamic> row in rows) {
        await _removeMutationBatch(uid, row['batch_id']);
      }
    }
  }

  Future<void> _removeMutationBatch(String uid, int batchId) async {
    final int deleted =
        await db.delete('DELETE FROM mutations WHERE uid = ? AND batch_id = ?', <dynamic>[uid, batchId]);
    hardAssert(deleted != 0, 'Mutation batch ($uid, $batchId) did not exist');

    // Delete all index entries for this batch
    return db.delete('DELETE FROM document_mutations WHERE uid = ? AND batch_id = ?', <dynamic>[uid, batchId]);
  }

  Future<void> _createV1TargetCache() async {
    return _ifTablesDontExist(<String>['targets', 'target_globals', 'target_documents'], () async {
      // A cache of targets and associated metadata
      await db.query(
        // @formatter:off
          '''
          CREATE TABLE targets (
            target_id                   INTEGER PRIMARY KEY,
            canonical_id                TEXT,
            snapshot_version_seconds    INTEGER,
            snapshot_version_nanos      INTEGER,
            resume_token                BLOB,
            last_listen_sequence_number INTEGER,
            target_proto                BLOB
          );
        '''
          // @formatter:on
          );

      await db.query(
        // @formatter:off
          '''
          CREATE INDEX query_targets
            ON targets (canonical_id, target_id);
        '''
          // @formatter:on
          );

      // Global state tracked across all queries, tracked separately
      await db.query(
        // @formatter:off
          '''
          CREATE TABLE target_globals (
            highest_target_id                    INTEGER,
            highest_listen_sequence_number       INTEGER,
            last_remote_snapshot_version_seconds INTEGER,
            last_remote_snapshot_version_nanos   INTEGER
          );
        '''
          // @formatter:on
          );

      // A Mapping table between targets, document paths
      await db.query(
        // @formatter:off
          '''
          CREATE TABLE target_documents (
            target_id       INTEGER,
            path            TEXT,
            PRIMARY KEY (target_id, path)
          );
        '''
          // @formatter:on
          );

      // The document_targets reverse mapping table is just an index on target_documents.
      await db.query(
        // @formatter:off
          '''
          CREATE INDEX document_targets
            ON target_documents (path, target_id);
        '''
          // @formatter:on
          );
    });
  }

  Future<void> _dropV1TargetCache() async {
    // This might be overkill, but if any future migration drops these, it's possible we could try dropping tables that
    // don't exist.
    if (await _tableExists('targets')) {
      await db.execute('DROP TABLE targets');
    }
    if (await _tableExists('target_globals')) {
      await db.execute('DROP TABLE target_globals');
    }
    if (await _tableExists('target_documents')) {
      await db.execute('DROP TABLE target_documents');
    }
  }

  Future<void> _createV1RemoteDocumentCache() async {
    return _ifTablesDontExist(<String>['remote_documents'], () async {
      // A cache of documents obtained from the server.
      await db.query(
        // @formatter:off
          '''
          CREATE TABLE remote_documents (
            path     TEXT PRIMARY KEY,
            contents BLOB
          );
        '''
          // @formatter:on
          );
    });
  }

  // TODO(indexing): Put the schema version in this method name.
  Future<void> _createLocalDocumentsCollectionIndex() async {
    // field_value_type determines type of field_value fields.
    // field_value_1 is first component
    // field_value_2 is the second component; required for timestamps, GeoPoints
    return _ifTablesDontExist(<String>['collection_index'], () async {
      // A per-user, per-collection index for cached documents indexed by a single field's name and value.
      await db.query(
        // @formatter:off
          '''
          CREATE TABLE collection_index (
            uid              TEXT,
            collection_path  TEXT,
            field_path       TEXT,
            field_value_type INTEGER,
            field_value_1,
            field_value_2,
            document_id      TEXT,
            PRIMARY KEY (uid, collection_path, field_path, field_value_type, field_value_1, field_value_2, document_id)
          );
        '''
          // @formatter:on
          );
    });
  }

  Future<void> _ensureTargetGlobal() async {
    final bool targetGlobalExists = await _rowNumber('target_globals') == 1;

    if (!targetGlobalExists) {
      await db.execute(
        // @formatter:off
          '''
          INSERT INTO target_globals
          (highest_target_id, highest_listen_sequence_number, last_remote_snapshot_version_seconds,
           last_remote_snapshot_version_nanos)
          VALUES (?, ?, ?, ?)
          ''',
          // @formatter:on
          <int>[0, 0, 0, 0]);
    }
  }

  Future<void> _addTargetCount() async {
    if (!(await _tableContainsColumn('target_globals', 'target_count'))) {
      await db.execute('ALTER TABLE target_globals ADD COLUMN target_count INTEGER');
    }
    // Even if the column already existed, rerun the data migration to make sure it's correct.
    final int count = await _rowNumber('targets');
    return db.execute(
      // @formatter:off
        '''
          UPDATE target_globals
          SET target_count=?
        ''',
        // @formatter:on
        <int>[count]);
  }

  Future<void> _addSequenceNumber() async {
    if (!(await _tableContainsColumn('target_documents', 'sequence_number'))) {
      return db.execute('ALTER TABLE target_documents ADD COLUMN sequence_number INTEGER');
    }
  }

  Future<bool> _hasReadTime() async {
    final bool hasReadTimeSeconds = await _tableContainsColumn('remote_documents', 'read_time_seconds');
    final bool hasReadTimeNanos = await _tableContainsColumn('remote_documents', 'read_time_nanos');

    hardAssert(
      hasReadTimeSeconds == hasReadTimeNanos,
      'Table contained just one of read_time_seconds or read_time_nanos',
    );

    return hasReadTimeSeconds && hasReadTimeNanos;
  }

  Future<void> _addReadTime() async {
    await db.execute('ALTER TABLE remote_documents ADD COLUMN read_time_seconds INTEGER');
    await db.execute('ALTER TABLE remote_documents ADD COLUMN read_time_nanos INTEGER');
  }

  Future<void> _dropLastLimboFreeSnapshotVersion() async {
    final List<Map<String, dynamic>> rows = await db.query('SELECT target_id, target_proto FROM targets');

    for (Map<String, dynamic> row in rows) {
      final int targetId = row['target_id'];
      final Uint8List targetProtoBytes = Uint8List.fromList(row['target_proto']);

      final proto.Target targetProto = proto.Target.fromBuffer(targetProtoBytes) //
        ..clearLastLimboFreeSnapshotVersion();

      await db.execute(
        'UPDATE targets SET target_proto = ? WHERE target_id = ?',
        <dynamic>[targetProto.writeToBuffer(), targetId],
      );
    }
  }

  /// Ensures that each entry in the remote document cache has a corresponding sentinel row. Any
  /// entries that lack a sentinel row are given one with the sequence number set to the highest
  /// recorded sequence number from the target metadata.
  Future<void> _ensureSequenceNumbers() async {
    // Get the current highest sequence number
    final List<Map<String, dynamic>> sequenceNumberQuery = await db.query(
      // @formatter:off
        '''
          SELECT highest_listen_sequence_number
          FROM target_globals
          LIMIT 1;
        '''
        // @formatter:on
        );
    final int sequenceNumber = sequenceNumberQuery.first['highest_listen_sequence_number'];
    assert(sequenceNumber != null, 'Missing highest sequence number');

    final List<Map<String, dynamic>> untaggedDocumentsQuery = await db.query(
      // @formatter:off
        '''
          SELECT RD.path
          FROM remote_documents AS RD
          WHERE NOT EXISTS(
                  SELECT TD.path
                  FROM target_documents AS TD
                  WHERE RD.path = TD.path
                    AND TD.target_id = 0);
        '''
        // @formatter:on
        );

    for (Map<String, dynamic> row in untaggedDocumentsQuery) {
      await db.execute(
        // @formatter:off
        '''
          INSERT INTO target_documents (target_id,
                                        path,
                                        sequence_number)
          VALUES (0, ?, ?);
        ''',
        // @formatter:on
        <dynamic>[row.values.first, sequenceNumber],
      );
    }
  }

  Future<void> _createV8CollectionParentsIndex() async {
    await _ifTablesDontExist(
      <String>['collection_parents'],
      () async {
        // A table storing associations between a Collection ID (e.g.
        // 'messages') to a parent path (e.g. '/chats/123') that contains it as
        // a (sub)collection. This is used to efficiently find all collections
        // to query when performing a Collection Group query. Note that the
        // parent path will be an empty path in the case of root-level
        // collections.
        await db.execute(
          // @formatter:off
            '''
              CREATE TABLE collection_parents(
                  collection_id TEXT,
                  parent        TEXT,
                  PRIMARY KEY (collection_id, parent)
              );
            '''
            // @formatter:on
            );
      },
    );

    // Helper to add an index entry if we haven't already written it.
    final MemoryCollectionParentIndex cache = MemoryCollectionParentIndex();

    Future<void> addEntry(ResourcePath collectionPath) async {
      if (cache.add(collectionPath)) {
        final String collectionId = collectionPath.getLastSegment();
        final ResourcePath parentPath = collectionPath.popLast();

        await db.execute(
          // @formatter:off
          '''
            INSERT OR REPLACE INTO collection_parents (collection_id,
                                                       parent)
            VALUES (?, ?);
          ''',
          // @formatter:on
          <dynamic>[collectionId, EncodedPath.encode(parentPath)],
        );
      }
    }

    // Index existing remote documents.
    final List<Map<String, dynamic>> remoteDocumentsQuery = await db.query(
      // @formatter:off
        '''
          SELECT path
          FROM remote_documents;
        '''
        // @formatter:on
        );

    for (Map<String, dynamic> row in remoteDocumentsQuery) {
      final ResourcePath path = EncodedPath.decodeResourcePath(row['path']);
      await addEntry(path.popLast());
    }

    // Index existing mutations.
    final List<Map<String, dynamic>> documentMutationsQuery = await db.query(
      // @formatter:off
        '''
          SELECT path
          FROM document_mutations;
        '''
        // @formatter:on
        );

    for (Map<String, dynamic> row in documentMutationsQuery) {
      final ResourcePath path = EncodedPath.decodeResourcePath(row['path']);
      await addEntry(path.popLast());
    }
  }

  Future<void> _rewriteCanonicalIds() async {
    final List<Map<String, dynamic>> rows = await db.query('SELECT target_id, target_proto FROM targets');
    for (final Map<String, dynamic> row in rows) {
      final int targetId = row['target_id'];
      final Uint8List targetProtoBytes = Uint8List.fromList(row['target_proto']);

      final proto.Target targetProto = proto.Target.fromBuffer(targetProtoBytes);
      final TargetData targetData = serializer.decodeTargetData(targetProto);
      final String updatedCanonicalId = targetData.target.canonicalId;
      await db
          .execute('UPDATE targets SET canonical_id  = ? WHERE target_id = ?', <dynamic>[updatedCanonicalId, targetId]);
    }
  }

  Future<bool> _tableContainsColumn(String table, String column) async {
    final List<String> columns = await getTableColumns(table);
    return columns.contains(column);
  }

  @visibleForTesting
  Future<List<String>> getTableColumns(String table) async {
    final List<Map<String, dynamic>> data = await db.query('PRAGMA table_info($table);');
    return data.map<String>((Map<String, dynamic> row) => row['name']).toList();
  }

  Future<bool> _tableExists(String table) async {
    final List<Map<String, dynamic>> data =
        await db.query('SELECT 1=1 FROM sqlite_master WHERE tbl_name = ?', <String>[table]);
    return data.isNotEmpty;
  }

  Future<int> _rowNumber(String tableName) async {
    return (await db.query('SELECT Count(*) as count FROM $tableName;')).first['count'];
  }
}
