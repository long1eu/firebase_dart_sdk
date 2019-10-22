// File created by
// Lung Razvan <long1eu>
// on 21/09/2018

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:firebase_firestore/src/firebase/firestore/auth/user.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/encoded_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/local_serializer.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/mutation_queue.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/sqlite_persistence.dart' as sq;
import 'package:firebase_firestore/src/firebase/firestore/local/sqlite_persistence.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/resource_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/write_stream.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';
import 'package:firebase_firestore/src/firebase/timestamp.dart';
import 'package:firebase_firestore/src/proto/google/firebase/firestore/proto/mutation.pb.dart'
    as proto;
import 'package:protobuf/protobuf.dart';

/// A mutation queue for a specific user, backed by SQLite.
class SQLiteMutationQueue implements MutationQueue {
  /// Creates a mutation queue for the given user, in the SQLite database wrapped by the persistence interface.
  SQLiteMutationQueue(this.db, this.serializer, User user)
      : uid = user.isAuthenticated ? user.uid : '',
        _lastStreamToken = WriteStream.emptyStreamToken;

  final sq.SQLitePersistence db;
  final LocalSerializer serializer;

  /// The normalized uid (e.g. null => '') used in the uid column.
  final String uid;

  /// Next value to use when assigning sequential IDs to each mutation batch.
  ///
  /// NOTE: There can only be one [SQLiteMutationQueue] for a given db at a time, hence it is safe
  /// to track [_nextBatchId] as an instance-level property. Should we ever relax this constraint
  /// we'll need to revisit this.
  int _nextBatchId;

  /// An identifier for the highest numbered batch that has been acknowledged by the server. All
  /// [MutationBatch]es in this queue with batch_ids less than or equal to this value are considered
  /// to have been acknowledged by the server.
  int _lastAcknowledgedBatchId;

  /// A stream token that was previously sent by the server.
  ///
  /// See [StreamingWriteRequest] in datastore.proto for more details about usage.
  ///
  /// After sending this token, earlier tokens may not be used anymore so only a single stream token
  /// is retained.
  Uint8List _lastStreamToken;

  // MutationQueue implementation

  @override
  Future<void> start() async {
    await _loadNextBatchIdAcrossAllUsers();

    // On restart, _nextBatchId may end up lower than lastAcknowledgedBatchId since it's computed
    // from the queue contents, and there may be no mutations in the queue. In this case, we need to
    // reset [lastAcknowledgedBatchId] (which is safe since the queue must be empty).
    _lastAcknowledgedBatchId = MutationBatch.unknown;

    final List<Map<String, dynamic>> result = await db.query(
        // @formatter:off
        '''
          SELECT last_acknowledged_batch_id, last_stream_token
          FROM mutation_queues
          WHERE uid = ?;
        ''',
        // @formatter:on
        <String>[uid]);

    if (result.isNotEmpty) {
      final Map<String, dynamic> row = result.first;
      final int lastAcknowledgedBatchId = row['last_acknowledged_batch_id'];
      final Uint8List lastStreamToken = row['last_stream_token'];

      _lastAcknowledgedBatchId = lastAcknowledgedBatchId;
      _lastStreamToken = lastStreamToken;
    }

    if (result.isEmpty) {
      // Ensure we write a default entry in mutation_queues since [loadNextBatchIdAcrossAllUsers]
      // depends upon every queue having an entry.
      await _writeMutationQueueMetadata();
    } else if (_lastAcknowledgedBatchId >= _nextBatchId) {
      hardAssert(await isEmpty(), 'Reset _nextBatchId is only possible when the queue is empty');
      _lastAcknowledgedBatchId = MutationBatch.unknown;
      await _writeMutationQueueMetadata();
    }
  }

  /// Returns one larger than the largest batch ID that has been stored. If there are no mutations
  /// returns 0. Note that batch IDs are global.
  Future<void> _loadNextBatchIdAcrossAllUsers() async {
    // The dependent query below turned out to be ~500x faster than any other technique, given just
    // the primary key index on (uid, batch_id).
    //
    // naive: SELECT MAX(batch_id) FROM mutations
    // group: SELECT uid, MAX(batch_id) FROM mutations GROUP BY uid
    // join:  SELECT q.uid, MAX(b.batch_id) FROM mutation_queues q, mutations b WHERE q.uid = b.uid
    //
    // Given 1E9 mutations divvied up among 10 queues, timings looked like this:
    //
    // method       seconds
    // join:        0.3187
    // group_max:   0.1985
    // naive_scan:  0.1041
    // dependent:   0.0002

    final List<String> uids = <String>[];
    final List<Map<String, dynamic>> uidsRows = await db.query(
        // @formatter:off
        '''
          SELECT uid
          FROM mutation_queues;
        '''
        // @formatter:on
        );

    for (Map<String, dynamic> row in uidsRows) {
      uids.add(row['uid']);
    }

    _nextBatchId = 0;
    for (String uid in uids) {
      final List<Map<String, dynamic>> result = await db.query(
          // @formatter:off
          '''
            SELECT MAX(batch_id)
            FROM mutations
            WHERE uid = ?;
          ''',
          // @formatter:on
          <String>[uid]);

      for (Map<String, dynamic> row in result) {
        final int batchId = row['MAX(batch_id)'];
        _nextBatchId = batchId == null ? _nextBatchId : max(_nextBatchId, batchId);
      }
    }

    _nextBatchId += 1;
  }

  @override
  Future<bool> isEmpty() async {
    return (await db.query(
        // @formatter:off
        '''
          SELECT batch_id
          FROM mutations
          WHERE uid = ?
          LIMIT 1;
        ''',
        // @formatter:on
        <String>[uid])).isEmpty;
  }

  @override
  Future<void> acknowledgeBatch(MutationBatch batch, Uint8List streamToken) async {
    final int batchId = batch.batchId;
    hardAssert(
        batchId > _lastAcknowledgedBatchId, 'Mutation batchIds must be acknowledged in order');

    _lastAcknowledgedBatchId = batchId;
    _lastStreamToken = checkNotNull(streamToken);
    await _writeMutationQueueMetadata();
  }

  @override
  Uint8List get lastStreamToken => _lastStreamToken;

  @override
  Future<void> setLastStreamToken(Uint8List streamToken) async {
    _lastStreamToken = checkNotNull(streamToken);
    await _writeMutationQueueMetadata();
  }

  Future<void> _writeMutationQueueMetadata() async {
    await db.execute(
        // @formatter:off
        '''
        INSERT
        OR REPLACE INTO mutation_queues (uid, last_acknowledged_batch_id, last_stream_token)
        VALUES (?, ?, ?);
        ''',
        // @formatter:on
        <dynamic>[uid, _lastAcknowledgedBatchId, _lastStreamToken]);
  }

  @override
  Future<MutationBatch> addMutationBatch(Timestamp localWriteTime, List<Mutation> mutations) async {
    final int batchId = _nextBatchId;
    _nextBatchId += 1;

    final MutationBatch batch = MutationBatch(batchId, localWriteTime, mutations);
    final GeneratedMessage proto = serializer.encodeMutationBatch(batch);

    await db.execute(
        // @formatter:off
        '''
          INSERT INTO mutations (uid, batch_id, mutations)
          VALUES (?, ?, ?);
        ''',
        // @formatter:on
        <dynamic>[uid, batchId, proto.writeToBuffer()]);

    // PORTING NOTE: Unlike LevelDB, these entries must be unique. Since [user] and [batchId] are
    // fixed within this function body, it's enough to track unique keys added in this batch.
    final Set<DocumentKey> inserted = <DocumentKey>{};

    const String statement =
        // @formatter:off
        '''
        INSERT INTO document_mutations (uid, path, batch_id) 
        VALUES (?, ?, ?);
        ''';
    // @formatter:on

    for (Mutation mutation in mutations) {
      final DocumentKey key = mutation.key;
      if (!inserted.add(key)) {
        continue;
      }

      final String path = EncodedPath.encode(key.path);
      await db.execute(statement, <dynamic>[uid, path, batchId]);
    }

    return batch;
  }

  @override
  Future<MutationBatch> lookupMutationBatch(int batchId) async {
    final List<Map<String, dynamic>> result = await db.query(
        // @formatter:off
        '''
          SELECT mutations
          FROM mutations
          WHERE uid = ?
            AND batch_id = ?;
        ''',
        // @formatter:on
        <dynamic>[uid, batchId]);

    if (result.isNotEmpty) {
      return decodeMutationBatch(result.first['mutations']);
    } else {
      return null;
    }
  }

  @override
  Future<MutationBatch> getNextMutationBatchAfterBatchId(int batchId) async {
    // All batches with [batchId] <= [lastAcknowledgedBatchId] have been acknowledged so the first
    // unacknowledged batch after [batchId] will have a [batchID] larger than both of these values.
    final int _nextBatchId = max(batchId, _lastAcknowledgedBatchId) + 1;

    final List<Map<String, dynamic>> result = await db.query(
        // @formatter:off
        '''
          SELECT mutations
          FROM mutations
          WHERE uid = ?
            AND batch_id >= ?
          ORDER BY batch_id ASC
          LIMIT 1;
        ''',
        // @formatter:on
        <dynamic>[uid, _nextBatchId]);

    if (result.isNotEmpty) {
      return decodeMutationBatch(result.first['mutations']);
    } else {
      return null;
    }
  }

  @override
  Future<List<MutationBatch>> getAllMutationBatches() async {
    final List<MutationBatch> result = <MutationBatch>[];
    final List<Map<String, dynamic>> rows = await db.query(
        // @formatter:off
        '''
          SELECT mutations
          FROM mutations
          WHERE uid = ?
          ORDER BY batch_id ASC;
        ''',
        // @formatter:on
        <dynamic>[uid]);

    for (Map<String, dynamic> row in rows) {
      result.add(decodeMutationBatch(row['mutations']));
    }

    return result;
  }

  @override
  Future<List<MutationBatch>> getAllMutationBatchesAffectingDocumentKey(
      DocumentKey documentKey) async {
    final String path = EncodedPath.encode(documentKey.path);

    final List<MutationBatch> result = <MutationBatch>[];
    final List<Map<String, dynamic>> rows = await db.query(
        // @formatter:off
        '''
          SELECT m.mutations
          FROM document_mutations dm,
               mutations m
          WHERE dm.uid = ?
            AND dm.path = ?
            AND dm.uid = m.uid
            AND dm.batch_id = m.batch_id
          ORDER BY dm.batch_id;
        ''',
        // @formatter:on
        <String>[uid, path]);

    for (Map<String, dynamic> row in rows) {
      result.add(decodeMutationBatch(row['mutations']));
    }

    return result;
  }

  @override
  Future<List<MutationBatch>> getAllMutationBatchesAffectingDocumentKeys(
      Iterable<DocumentKey> documentKeys) async {
    final List<Object> args = <Object>[];
    for (DocumentKey key in documentKeys) {
      args.add(EncodedPath.encode(key.path));
    }

    final LongQuery longQuery = LongQuery(
        db,
        'SELECT DISTINCT dm.batch_id, m.mutations FROM document_mutations dm, mutations m WHERE dm.uid = ? AND dm.path IN (',
        <String>[uid],
        args,
        ') AND dm.uid = m.uid AND dm.batch_id = m.batch_id ORDER BY dm.batch_id');

    final List<MutationBatch> result = <MutationBatch>[];
    final Set<int> uniqueBatchIds = <int>{};
    while (longQuery.hasMoreSubqueries) {
      final List<Map<String, dynamic>> rows = await longQuery.performNextSubquery();
      for (Map<String, dynamic> row in rows) {
        final int batchId = row['batch_id'];
        if (!uniqueBatchIds.contains(batchId)) {
          uniqueBatchIds.add(batchId);
          result.add(decodeMutationBatch(row['mutations']));
        }
      }
    }

    // If more than one query was issued, batches might be in an unsorted order (batches are ordered
    // within one query's results, but not across queries). It's likely to be rare, so don't impose
    // performance penalty on the normal case.
    if (longQuery.subqueriesPerformed > 1) {
      result.sort((MutationBatch lhs, MutationBatch rhs) => lhs.batchId.compareTo(rhs.batchId));
    }
    return result;
  }

  @override
  Future<List<MutationBatch>> getAllMutationBatchesAffectingQuery(Query query) async {
    // Use the query path as a prefix for testing if a document matches the query.
    final ResourcePath prefix = query.path;
    final int immediateChildrenPathLength = prefix.length + 1;

    // Scan the document_mutations table looking for documents whose path has a prefix that matches
    // the query path.
    //
    // The most obvious way to do this would be with a LIKE query with a trailing wildcard
    // (e.g. path LIKE 'foo/%'). Unfortunately SQLite does not convert a trailing wildcard like that
    // into the equivalent range scan so a LIKE query ends up being a table scan. The query below is
    // equivalent but hits the index on both uid and path, so it's much faster.

    // TODO: Actually implement a single-collection query
    //
    // This is actually executing an ancestor query, traversing the whole subtree below the
    // collection which can be horrifically inefficient for some structures. The right way to solve
    // this is to implement the full value index, but that's not in the cards in the near future so
    // this is the best we can do for the moment.
    final String prefixPath = EncodedPath.encode(prefix);
    final String prefixSuccessorPath = EncodedPath.prefixSuccessor(prefixPath);

    final List<MutationBatch> result = <MutationBatch>[];
    final List<Map<String, dynamic>> rows = await db.query(
        // @formatter:off
        '''
          SELECT dm.batch_id, dm.path, m.mutations
          FROM document_mutations dm,
               mutations m
          WHERE dm.uid = ?
            AND dm.path >= ?
            AND dm.path < ?
            AND dm.uid = m.uid
            AND dm.batch_id = m.batch_id
          ORDER BY dm.batch_id;
        ''',
        // @formatter:on
        <dynamic>[uid, prefixPath, prefixSuccessorPath]);

    for (Map<String, dynamic> row in rows) {
      // Ensure unique batches only. This works because the batches come out in order so we only
      // need to ensure that the batchId of this row is different from the preceding one.
      final int batchId = row['batch_id'];
      final int size = result.length;
      if (size > 0 && batchId == result[size - 1].batchId) {
        continue;
      }

      // The query is actually returning any path that starts with the query path prefix which may
      // include documents in subcollections. For example, a query on 'rooms' will return
      // rooms/abc/messages/xyx but we shouldn't match it. Fix this by discarding rows with document
      // keys more than one segment longer than the query path.
      final ResourcePath path = EncodedPath.decodeResourcePath(row['path']);
      if (path.length != immediateChildrenPathLength) {
        continue;
      }

      result.add(decodeMutationBatch(row['mutations']));
    }

    return result;
  }

  @override
  Future<void> removeMutationBatch(MutationBatch batch) async {
    const String mutationDeleter =
        // @formatter:off
        '''
          DELETE
          FROM mutations
          WHERE uid = ?
            AND batch_id = ?;
        ''';
    // @formatter:on

    const String indexDeleter =
        // @formatter:off
        '''
          DELETE
          FROM document_mutations
          WHERE uid = ?
            AND path = ?
            AND batch_id = ?;
        ''';
    // @formatter:on

    final int batchId = batch.batchId;
    final int deleted = await db.delete(mutationDeleter, <dynamic>[uid, batchId]);

    hardAssert(deleted != 0, 'Mutation batch ($uid, ${batch.batchId}) did not exist');

    for (Mutation mutation in batch.mutations) {
      final DocumentKey key = mutation.key;
      final String path = EncodedPath.encode(key.path);
      await db.execute(indexDeleter, <dynamic>[uid, path, batchId]);
      await db.referenceDelegate.removeMutationReference(key);
    }
  }

  @override
  Future<void> performConsistencyCheck() async {
    final bool empty = await isEmpty();
    if (empty) {
      // Verify that there are no entries in the document_mutations index if the queue is empty.
      final List<ResourcePath> danglingMutationReferences = <ResourcePath>[];
      final List<Map<String, dynamic>> rows = await db.query(
          // @formatter:off
          '''
            SELECT path
            FROM document_mutations
            WHERE uid = ?;
          ''',
          // @formatter:on
          <String>[uid]);

      for (Map<String, dynamic> row in rows) {
        final ResourcePath path = EncodedPath.decodeResourcePath(row['path']);
        danglingMutationReferences.add(path);
      }

      hardAssert(
          danglingMutationReferences.isEmpty,
          'Document leak -- detected dangling mutation references when queue '
          'is empty. Dangling keys: $danglingMutationReferences');
    }
  }

  MutationBatch decodeMutationBatch(List<int> bytes) {
    try {
      return serializer.decodeMutationBatch(proto.WriteBatch.fromBuffer(bytes));
    } on InvalidProtocolBufferException catch (e) {
      throw fail('MutationBatch failed to parse: $e');
    }
  }
}
