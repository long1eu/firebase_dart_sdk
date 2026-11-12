// File created by
// Lung Razvan <long1eu>
// on 21/09/2018

part of 'sqlite_persistence.dart';

/// Migrates schemas from version 0 (empty) to whatever the current version is.
///
/// Migrations are numbered for the version of the database they apply to. The [version] constant in this class should
/// be one more than the highest numbered migration.
///
/// NOTE: Once we ship code with a migration in it the code for that migration should never be changed again. Further
/// changes can be made to the schema by adding a new migration method, bumping the [version], and adding a call to the
/// migration method from [runMigrations].
class SQLiteSchema {
  const SQLiteSchema(this.db);

  /// The version of the schema. Increase this by one for each migration added to [runMigrations] below.
  static const int version = 13;

  /// The batch size for data migrations on a large table. This is chosen to balance the memory usage of the rows read
  /// with the number of round trips.
  static const int migrationBatchSize = 100;

  final Database db;

  /// Runs the migration methods defined in this class, starting at the given version.
  Future<void> runMigrations(
      [int fromVersion = 0, int toVersion = version]) async {
    // New migrations should be added at the end of the series of `if` statements and should follow the pattern. Make
    // sure to increment `VERSION` and to read the comment below about requirements for new migrations.

    if (fromVersion < 1 && toVersion >= 1) {
      await _createV1MutationQueue();
      await _createV1QueryCache();
      await _createV1RemoteDocumentCache();
    }

    // Migration 2 to populate the target_globals table no longer needed since migration 3 unconditionally clears it.

    if (fromVersion < 3 && toVersion >= 3) {
      // Brand new clients don't need to drop and recreate--only clients that have potentially corrupt data.
      if (fromVersion != 0) {
        await _dropV1QueryCache();
        await _createV1QueryCache();
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

    // Migration 9 corresponds to migration 12 of the Android SDK (`createBundleCache`, added by the bundles feature in
    // 22.1.0): the port is at its own numbering, so the Android migrations 9 to 11 (overlay, indexing, canonical id
    // rewrite) are not part of it.
    if (fromVersion < 9 && toVersion >= 9) {
      await _createV9BundleCache();
    }

    // Migration 10 corresponds to migrations 9 and 10 of the Android SDK (read time on remote documents for index-free
    // queries, 47def6d / a744cb7 / d8ff6a5).
    if (fromVersion < 10 && toVersion >= 10) {
      if (!(await _hasReadTime())) {
        await _addReadTime();
      } else {
        // Index-free queries rely on the fact that documents updated after a query's last limbo free snapshot version
        // are persisted with their read time. If a client upgrades to schema version 10, downgrades and then upgrades
        // again, some queries may have a last limbo free snapshot version despite the fact that not all updated
        // documents have an associated read time.
        await _dropLastLimboFreeSnapshotVersion();
      }
    }

    // Migration 11 corresponds to migration 14 of the Android SDK (document overlays, final table shape of 1b8e6dd).
    // The overlays themselves are built from the mutation queue by the [SQLiteOverlayMigrationManager] the next time
    // the local store starts.
    if (fromVersion < 11 && toVersion >= 11) {
      await _createOverlays();
      await _createDataMigrationTable();
      await _addPendingDataMigration(Persistence.dataMigrationBuildOverlays);
    }

    // Migration 12 corresponds to migrations 13 and 15 of the Android SDK: the number of segments of the path of each
    // remote document (to scan a collection without its subcollections in SQL), and a read time of zero for the
    // documents that were written before read times existed, so that scans ordered by read time (the index backfill)
    // return them first instead of never.
    if (fromVersion < 12 && toVersion >= 12) {
      await _addPathLength();
      await _ensurePathLength();
      await _ensureReadTime();
    }

    // Migration 13 corresponds to migration 16 of the Android SDK (client-side field indexes).
    if (fromVersion < 13 && toVersion >= 13) {
      await _createFieldIndex();
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
  }

  /// Used to assert that a set of tables either all exist or not. The supplied function is run if none of the tables
  /// exist. Use this method to create a set of tables at once.
  ///
  /// If some but not all of the tables exist, an exception will be thrown.
  Future<void> _ifTablesDontExist(
      List<String> tables, Future<void> Function() fn) async {
    bool tablesFound = false;
    final String allTables = '[${tables.join(', ')}]';
    for (int i = 0; i < tables.length; i++) {
      final String table = tables[i];
      final bool tableFound = await _tableExists(table);
      if (i == 0) {
        tablesFound = tableFound;
      } else if (tableFound != tablesFound) {
        final StringBuffer msg = StringBuffer(
            'Expected all of $allTables to either exist or not, but ');
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
      Log.d('SQLiteSchema',
          'Skipping migration because all of $allTables already exist');
    }
  }

  Future<void> _createV1MutationQueue() async {
    return _ifTablesDontExist(
        <String>['mutation_queues', 'mutations', 'document_mutations'],
        () async {
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
    final List<Map<String, dynamic>> data = await db
        .query('SELECT uid, last_acknowledged_batch_id FROM mutation_queues');

    for (Map<String, dynamic> row in data) {
      final String uid = row['uid'];
      final int lastAcknowledgedBatchId =
          (row['last_acknowledged_batch_id'] as int?) ?? 0;

      final List<Map<String, dynamic>> rows = await db.query(
          'SELECT batch_id FROM mutations WHERE uid = ? AND batch_id <= ?',
          <dynamic>[uid, lastAcknowledgedBatchId]);

      for (Map<String, dynamic> row in rows) {
        await _removeMutationBatch(uid, row['batch_id']);
      }
    }
  }

  Future<void> _removeMutationBatch(String uid, int batchId) async {
    final int deleted = await db.delete(
        'DELETE FROM mutations WHERE uid = ? AND batch_id = ?',
        <dynamic>[uid, batchId]);
    hardAssertLazy(
        deleted != 0, () => 'Mutation batch ($uid, $batchId) did not exist');

    // Delete all index entries for this batch
    await db.delete(
        'DELETE FROM document_mutations WHERE uid = ? AND batch_id = ?',
        <dynamic>[uid, batchId]);
  }

  Future<void> _createV1QueryCache() async {
    return _ifTablesDontExist(
        <String>['targets', 'target_globals', 'target_documents'], () async {
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

  Future<void> _dropV1QueryCache() async {
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
      await db.execute(
          'ALTER TABLE target_globals ADD COLUMN target_count INTEGER');
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
      return db.execute(
          'ALTER TABLE target_documents ADD COLUMN sequence_number INTEGER');
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
    final int sequenceNumber =
        sequenceNumberQuery.first['highest_listen_sequence_number'];

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

  /// Creates the tables that hold the metadata of the bundles loaded by the client and the named queries they contain.
  Future<void> _createV9BundleCache() async {
    await _ifTablesDontExist(<String>['bundles', 'named_queries'], () async {
      await db.execute(
          // @formatter:off
          '''
            CREATE TABLE bundles (
              bundle_id           TEXT PRIMARY KEY,
              create_time_seconds INTEGER,
              create_time_nanos   INTEGER,
              schema_version      INTEGER,
              total_documents     INTEGER,
              total_bytes         INTEGER
            );
          '''
          // @formatter:on
          );

      await db.execute(
          // @formatter:off
          '''
            CREATE TABLE named_queries (
              name                TEXT PRIMARY KEY,
              read_time_seconds   INTEGER,
              read_time_nanos     INTEGER,
              bundled_query_proto BLOB
            );
          '''
          // @formatter:on
          );
    });
  }

  Future<void> _createOverlays() async {
    await _ifTablesDontExist(<String>['document_overlays'], () async {
      await db.execute(
          // @formatter:off
          '''
            CREATE TABLE document_overlays (
              uid               TEXT,
              collection_path   TEXT,
              document_id       TEXT,
              collection_group  TEXT,
              largest_batch_id  INTEGER,
              overlay_mutation  BLOB,
              PRIMARY KEY (uid, collection_path, document_id)
            );
          '''
          // @formatter:on
          );
      await db.execute(
          'CREATE INDEX batch_id_overlay ON document_overlays (uid, largest_batch_id)');
      await db.execute(
          'CREATE INDEX collection_group_overlay ON document_overlays (uid, collection_group)');
    });
  }

  Future<void> _createDataMigrationTable() async {
    await _ifTablesDontExist(<String>['data_migrations'], () async {
      await db.execute(
          'CREATE TABLE data_migrations (migration_name TEXT, PRIMARY KEY (migration_name))');
    });
  }

  Future<void> _addPendingDataMigration(String migration) async {
    await db.execute(
        'INSERT OR IGNORE INTO data_migrations (migration_name) VALUES (?)',
        <Object>[migration]);
  }

  Future<void> _addPathLength() async {
    if (!(await _tableContainsColumn('remote_documents', 'path_length'))) {
      // The "path_length" column store the number of segments in the path.
      await db.execute(
          'ALTER TABLE remote_documents ADD COLUMN path_length INTEGER');
    }
  }

  /// Populates the remote_document's path_length column.
  Future<void> _ensurePathLength() async {
    while (true) {
      final List<Map<String, dynamic>> rows = await db.query(
          'SELECT path FROM remote_documents WHERE path_length IS NULL LIMIT ?',
          <Object>[migrationBatchSize]);
      if (rows.isEmpty) {
        break;
      }

      for (final Map<String, dynamic> row in rows) {
        final String encodedPath = row['path'];
        final ResourcePath decodedPath =
            EncodedPath.decodeResourcePath(encodedPath);
        await db.execute(
            'UPDATE remote_documents SET path_length = ? WHERE path = ?',
            <Object>[decodedPath.length, encodedPath]);
      }
    }
  }

  /// Initialize the remote_document's read_time column with 0 values if they are not set.
  Future<void> _ensureReadTime() async {
    await db.execute(
        'UPDATE remote_documents SET read_time_seconds = 0, read_time_nanos = 0 WHERE read_time_seconds IS NULL');
  }

  /// Creates the tables of the field indexes.
  ///
  /// The `index_configuration` table holds the configuration for all indices. Entries in this table apply for all
  /// users. It is not possible to only enable indices for a subset of users.
  ///
  /// The `index_state` table holds backfill information on each index that stores when it was last updated.
  ///
  /// The `index_entries` table holds the index values themselves. An index value is created for every field
  /// combination that matches a configured index.
  Future<void> _createFieldIndex() async {
    await _ifTablesDontExist(
        <String>['index_configuration', 'index_state', 'index_entries'],
        () async {
      // Global configuration for all existing field indexes
      await db.execute(
          // @formatter:off
          '''
            CREATE TABLE index_configuration (
              index_id         INTEGER,
              collection_group TEXT,
              index_proto      BLOB, -- V1 Admin index proto
              PRIMARY KEY (index_id)
            );
          '''
          // @formatter:on
          );

      // Per index per user state to track the backfill state for each index
      await db.execute(
          // @formatter:off
          '''
            CREATE TABLE index_state (
              index_id          INTEGER,
              uid               TEXT,
              sequence_number   INTEGER, -- Specifies the order of updates
              read_time_seconds INTEGER, -- Read time of last processed document
              read_time_nanos   INTEGER,
              document_key      TEXT,    -- Key of the last processed document
              largest_batch_id  INTEGER, -- Largest mutation batch id that was processed
              PRIMARY KEY (index_id, uid)
            );
          '''
          // @formatter:on
          );

      // The index entry table stores the encoded entries for all fields.
      // The table only has a single primary index. `array_value` should be set for all queries.
      await db.execute(
          // @formatter:off
          '''
            CREATE TABLE index_entries (
              index_id          INTEGER, -- The index_id of the field index creating this entry
              uid               TEXT,
              array_value       BLOB,    -- index values for ArrayContains/ArrayContainsAny
              directional_value BLOB,    -- index values for equality and inequalities
              document_key      TEXT,
              PRIMARY KEY (index_id, uid, array_value, directional_value, document_key)
            );
          '''
          // @formatter:on
          );

      await db.execute(
          'CREATE INDEX read_time ON remote_documents(read_time_seconds, read_time_nanos)');
    });
  }

  Future<bool> _hasReadTime() async {
    final bool hasReadTimeSeconds =
        await _tableContainsColumn('remote_documents', 'read_time_seconds');
    final bool hasReadTimeNanos =
        await _tableContainsColumn('remote_documents', 'read_time_nanos');

    hardAssert(hasReadTimeSeconds == hasReadTimeNanos,
        'Table contained just one of read_time_seconds or read_time_nanos');

    return hasReadTimeSeconds && hasReadTimeNanos;
  }

  Future<void> _addReadTime() async {
    await db.execute(
        'ALTER TABLE remote_documents ADD COLUMN read_time_seconds INTEGER');
    await db.execute(
        'ALTER TABLE remote_documents ADD COLUMN read_time_nanos INTEGER');
  }

  Future<void> _dropLastLimboFreeSnapshotVersion() async {
    final List<Map<String, dynamic>> rows =
        await db.query('SELECT target_id, target_proto FROM targets');
    for (Map<String, dynamic> row in rows) {
      final int targetId = row['target_id'];
      final Uint8List targetProtoBytes = row['target_proto'];
      final proto.Target targetProto;
      try {
        targetProto = proto.Target.fromBuffer(targetProtoBytes);
      } on InvalidProtocolBufferException catch (_) {
        throw fail('Failed to decode Query data for target $targetId');
      }
      targetProto.clearLastLimboFreeSnapshotVersion();
      await db.execute('UPDATE targets SET target_proto = ? WHERE target_id = ?',
          <Object>[targetProto.writeToBuffer(), targetId]);
    }
  }

  Future<bool> _tableContainsColumn(String table, String column) async {
    final List<String> columns = await getTableColumns(table);
    return columns.contains(column);
  }

  @visibleForTesting
  Future<List<String>> getTableColumns(String table) async {
    final List<Map<String, dynamic>> data =
        await db.query('PRAGMA table_info($table);');
    return data.map<String>((Map<String, dynamic> row) => row['name']).toList();
  }

  Future<bool> _tableExists(String table) async {
    final List<Map<String, dynamic>> data = await db.query(
        'SELECT 1=1 FROM sqlite_master WHERE tbl_name = ?', <String>[table]);
    return data.isNotEmpty;
  }

  Future<int> _rowNumber(String tableName) async {
    return (await db.query('SELECT Count(*) as count FROM $tableName;'))
        .first['count'];
  }
}
