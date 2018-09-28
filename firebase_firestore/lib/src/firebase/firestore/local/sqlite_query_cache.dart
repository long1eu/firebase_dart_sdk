// File created by
// Lung Razvan <long1eu>
// on 21/09/2018

import 'dart:async';

import 'package:firebase_database_collection/firebase_database_collection.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/encoded_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/local_serializer.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_cache.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_data.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/reference_delegate.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/sqlite_persistence.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/snapshot_version.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/database_impl.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/types.dart';
import 'package:firebase_firestore/src/firebase/timestamp.dart';
import 'package:firebase_firestore/src/proto/firestore/local/target.pb.dart'
    as proto;

/// Cached Queries backed by SQLite.
class SQLiteQueryCache implements QueryCache {
  final SQLitePersistence db;
  final LocalSerializer localSerializer;

  int lastListenSequenceNumber;

  @override
  int highestTargetId;

  @override
  SnapshotVersion lastRemoteSnapshotVersion = SnapshotVersion.none;

  @override
  int targetCount;

  SQLiteQueryCache(this.db, this.localSerializer);

  Future<void> start(DatabaseExecutor tx) async {
    // Store exactly one row in the table. If the row exists at all, it's the
    // global metadata.
    final List<Map<String, dynamic>> result = await db.query(tx,
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
    final Map<String, dynamic> row = result.first;

    highestTargetId = row['highest_target_id'] as int;
    lastListenSequenceNumber = row['highest_listen_sequence_number'] as int;
    lastRemoteSnapshotVersion = SnapshotVersion(Timestamp(
      row['last_remote_snapshot_version_seconds'] as int,
      row['last_remote_snapshot_version_nanos'] as int,
    ));
    targetCount = row['targetCount'] as int;

    Assert.hardAssert(result.length == 1, 'Missing target_globals entry');
  }

  @override
  int get highestListenSequenceNumber => lastListenSequenceNumber;

  @override
  Future<void> forEachTarget(
      DatabaseExecutor tx, Consumer<QueryData> consumer) async {
    final List<Map<String, dynamic>> result = await db.query(tx,
        // @formatter:off
        '''
          SELECT target_proto
          FROM targets;
        '''
        // @formatter:on
        );

    for (Map<String, dynamic> row in result) {
      final List<int> blob = row['target_proto'];
      consumer(_decodeQueryData(blob));
    }
  }

  @override
  Future<void> setLastRemoteSnapshotVersion(
      DatabaseExecutor tx, SnapshotVersion snapshotVersion) async {
    lastRemoteSnapshotVersion = snapshotVersion;
    await _writeMetadata(tx);
  }

  Future<void> _saveQueryData(DatabaseExecutor tx, QueryData queryData) async {
    final int targetId = queryData.targetId;
    final String canonicalId = queryData.query.canonicalId;
    final Timestamp version = queryData.snapshotVersion.timestamp;

    final proto.Target targetProto = localSerializer.encodeQueryData(queryData);

    await db.execute(tx,
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
          queryData.resumeToken,
          queryData.sequenceNumber,
          targetProto.writeToBuffer()
        ]);
  }

  bool _updateMetadata(QueryData queryData) {
    bool wasUpdated = false;

    if (queryData.targetId > highestTargetId) {
      highestTargetId = queryData.targetId;
      wasUpdated = true;
    }

    if (queryData.sequenceNumber > lastListenSequenceNumber) {
      lastListenSequenceNumber = queryData.sequenceNumber;
      wasUpdated = true;
    }

    return wasUpdated;
  }

  @override
  Future<void> addQueryData(DatabaseExecutor tx, QueryData queryData) async {
    await _saveQueryData(tx, queryData);
    // PORTING NOTE: The query_targets index is maintained by SQLite.
    _updateMetadata(queryData);
    targetCount++;
    await _writeMetadata(tx);
  }

  @override
  Future<void> updateQueryData(DatabaseExecutor tx, QueryData queryData) async {
    await _saveQueryData(tx, queryData);

    if (_updateMetadata(queryData)) {
      await _writeMetadata(tx);
    }
  }

  Future<void> _writeMetadata(DatabaseExecutor tx) async {
    await db.execute(
        tx,
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
          lastListenSequenceNumber,
          lastRemoteSnapshotVersion.timestamp.seconds,
          lastRemoteSnapshotVersion.timestamp.nanoseconds,
          targetCount,
        ]);
  }

  Future<void> _removeTarget(DatabaseExecutor tx, int targetId) async {
    await _removeMatchingKeysForTargetId(tx, targetId);
    await db.execute(tx,
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
  Future<void> removeQueryData(DatabaseExecutor tx, QueryData queryData) async {
    final int targetId = queryData.targetId;
    await _removeTarget(tx, targetId);
    await _writeMetadata(tx);
  }

  /// Drops any targets with sequence number less than or equal to the upper
  /// bound, excepting those present in [activeTargetIds]. Document associations
  /// for the removed targets are also removed. Returns the number of targets
  /// removed.
  Future<int> removeQueries(
      DatabaseExecutor tx, int upperBound, Set<int> activeTargetIds) async {
    int count = 0;
    // SQLite has a max sql statement size, so there is technically a
    // possibility that including a an IN clause in this query to filter
    // [activeTargetIds] could overflow. Rather than deal with that, we filter
    // out live targets from the result set.

    final List<Map<String, dynamic>> result = await db.query(
      tx,
      // @formatter:off
      '''
          SELECT target_id
          FROM targets
          WHERE last_listen_sequence_number <= ?;
        ''',
      // @formatter:on
    );

    for (Map<String, dynamic> row in result) {
      final int targetId = row['target_id'];
      if (!activeTargetIds.contains(targetId)) {
        await _removeTarget(tx, targetId);
        count++;
      }
    }

    await _writeMetadata(tx);
    return count;
  }

  @override
  Future<QueryData> getQueryData(DatabaseExecutor tx, Query query) async {
    // Querying the targets table by canonical_id may yield more than one result
    // because canonical_id values are not required to be unique per target.
    // This query depends on the query_targets index to be efficient.
    final String canonicalId = query.canonicalId;

    final List<Map<String, dynamic>> result = await db.query(tx,
        // @formatter:off
        '''
          SELECT target_proto
          FROM targets
          WHERE canonical_id = ?;
        ''',
        // @formatter:on
        <String>[canonicalId]);

    QueryData data;
    for (Map<String, dynamic> row in result) {
      // TODO: break out early if found.
      final QueryData found =
          _decodeQueryData(row['target_proto'] as List<int>);

      // After finding a potential match, check that the query is actually equal
      // to the requested query.
      if (query == found.query) {
        data = found;
      }
    }

    return data;
  }

  QueryData _decodeQueryData(List<int> bytes) {
    return localSerializer.decodeQueryData(proto.Target.fromBuffer(bytes));
  }

  // Matching key tracking

  @override
  Future<void> addMatchingKeys(DatabaseExecutor tx,
      ImmutableSortedSet<DocumentKey> keys, int targetId) async {
    // PORTING NOTE: The reverse index (document_targets) is maintained by
    // SQLite.
    //
    // When updates come in we treat those as added keys, which means these
    // inserts won't necessarily be unique between invocations. This INSERT
    // statement uses the IGNORE conflict resolution strategy to avoid failing
    // on any attempts to add duplicate entries. This works because there's no
    // additional information in the row. If we want to track additional data
    // this will probably need to become INSERT OR REPLACE instead.
    const String statement =
        // @formatter:off
        '''
          INSERT
          OR IGNORE INTO target_documents (target_id, path)
          VALUES (?, ?);
        '''
        // @formatter:on
        ;

    final ReferenceDelegate delegate = db.referenceDelegate;
    for (DocumentKey key in keys) {
      final String path = EncodedPath.encode(key.path);
      await db.execute(tx, statement, <dynamic>[targetId, path]);
      await delegate.addReference(tx, key);
    }
  }

  @override
  Future<void> removeMatchingKeys(DatabaseExecutor tx,
      ImmutableSortedSet<DocumentKey> keys, int targetId) async {
    // PORTING NOTE: The reverse index (document_targets) is maintained by SQLite.
    const String statement =
        // @formatter:off
        '''
          DELETE
          FROM target_documents
          WHERE target_id = ?
            AND path = ?;
        '''
        // @formatter:on
        ;

    final ReferenceDelegate delegate = db.referenceDelegate;
    for (DocumentKey key in keys) {
      final String path = EncodedPath.encode(key.path);
      await db.execute(tx, statement, <dynamic>[targetId, path]);
      await delegate.removeReference(tx, key);
    }
  }

  Future<void> _removeMatchingKeysForTargetId(
      DatabaseExecutor tx, int targetId) async {
    await db.execute(tx,
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
  Future<ImmutableSortedSet<DocumentKey>> getMatchingKeysForTargetId(
      DatabaseExecutor tx, int targetId) async {
    ImmutableSortedSet<DocumentKey> keys = DocumentKey.emptyKeySet;

    final List<Map<String, dynamic>> result = await db.query(tx,
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
      final DocumentKey key =
          DocumentKey.fromPath(EncodedPath.decodeResourcePath(path));
      keys = keys.insert(key);
    }

    return keys;
  }

  @override
  Future<bool> containsKey(DatabaseExecutor tx, DocumentKey key) async {
    final String path = EncodedPath.encode(key.path);

    final List<Map<String, dynamic>> result = await db.query(tx,
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
