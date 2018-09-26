// File created by
// Lung Razvan <long1eu>
// on 21/09/2018

import 'dart:async';

import 'package:firebase_firestore/src/firebase/firestore/core/listent_sequence.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/encoded_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/lru_delegate.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_data.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/reference_delegate.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/reference_set.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/sqlite_persistence.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/resource_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/types.dart';
import 'package:sqflite/sqflite.dart';

class SQLiteLruReferenceDelegate implements ReferenceDelegate, LruDelegate {
  final SQLitePersistence persistence;
  ListenSequence listenSequence;
  int _currentSequenceNumber;

  SQLiteLruReferenceDelegate(this.persistence)
      : _currentSequenceNumber = ListenSequence.INVALID {
    garbageCollector = LruGarbageCollector(this);
  }

  @override
  ReferenceSet additionalReferences;

  @override
  LruGarbageCollector garbageCollector;

  void start(int highestSequenceNumber) {
    listenSequence = ListenSequence(highestSequenceNumber);
  }

  @override
  void onTransactionStarted() {
    Assert.hardAssert(_currentSequenceNumber == ListenSequence.INVALID,
        'Starting a transaction without committing the previous one');
    _currentSequenceNumber = listenSequence.next();
  }

  @override
  void onTransactionCommitted() {
    Assert.hardAssert(_currentSequenceNumber != ListenSequence.INVALID,
        'Committing a transaction without having started one');
    _currentSequenceNumber = ListenSequence.INVALID;
  }

  @override
  int get currentSequenceNumber {
    Assert.hardAssert(_currentSequenceNumber != ListenSequence.INVALID,
        'Attempting to get a sequence number outside of a transaction');
    return _currentSequenceNumber;
  }

  @override
  int get targetCount => persistence.queryCache.targetCount;

  @override
  Future<void> forEachTarget(
      DatabaseExecutor tx, Consumer<QueryData> consumer) async {
    await persistence.queryCache.forEachTarget(tx, consumer);
  }

  @override
  Future<void> forEachOrphanedDocumentSequenceNumber(
      DatabaseExecutor tx, Consumer<int> consumer) async {
    final List<Map<String, dynamic>> result = await persistence.query(tx,
        // @formatter:off
        '''
         SELECT sequence_number
         FROM target_documents
         GROUP BY path
         HAVING COUNT(*) = 1
          AND target_id = 0;
        '''
        // @formatter:on
        );

    for (Map<String, dynamic> row in result) {
      consumer(row['sequence_number'] as int);
    }
  }

  @override
  Future<void> addReference(DatabaseExecutor tx, DocumentKey key) async {
    await _writeSentinel(tx, key);
  }

  @override
  Future<void> removeReference(DatabaseExecutor tx, DocumentKey key) async {
    await _writeSentinel(tx, key);
  }

  @override
  Future<int> removeQueries(
      DatabaseExecutor tx, int upperBound, Set<int> activeTargetIds) {
    return persistence.queryCache
        .removeQueries(tx, upperBound, activeTargetIds);
  }

  @override
  Future<void> removeMutationReference(
      DatabaseExecutor tx, DocumentKey key) async {
    await _writeSentinel(tx, key);
  }

  /// Returns true if any mutation queue contains the given document.
  Future<bool> _mutationQueuesContainKey(
      DatabaseExecutor tx, DocumentKey key) async {
    return (await persistence.query(tx,
        // @formatter:off
        '''
          SELECT 1
          FROM document_mutations
          WHERE path = ?;
        ''',
        // @formatter:on
        <String>[EncodedPath.encode(key.path)])).isNotEmpty;
  }

  /// Returns true if anything would prevent this document from being garbage
  /// collected, given that the document in question is not present in any
  /// targets and has a sequence number less than or equal to the upper bound
  /// for the collection run.
  Future<bool> _isPinned(DatabaseExecutor tx, DocumentKey key) async {
    if (additionalReferences.containsKey(key)) {
      return true;
    }

    return _mutationQueuesContainKey(tx, key);
  }

  Future<void> _removeSentinel(DatabaseExecutor tx, DocumentKey key) async {
    await persistence.execute(tx,
        // @formatter:off
        '''
          DELETE
          FROM target_documents
          WHERE path = ?
             AND target_id = 0;
        ''',
        // @formatter:on
        <String>[EncodedPath.encode(key.path)]);
  }

  @override
  Future<int> removeOrphanedDocuments(
      DatabaseExecutor tx, int upperBound) async {
    int count = 0;
    final List<Map<String, dynamic>> result = await persistence.query(tx,
        // @formatter:off
        '''
          SELECT path
          FROM target_documents
          GROUP BY path
          HAVING count(*) = 1
             AND target_id = 0
             AND sequence_number <= ?;
        ''',
        // @formatter:on
        <int>[upperBound]);

    for (Map<String, dynamic> row in result) {
      final ResourcePath path =
          EncodedPath.decodeResourcePath(row['path'] as String);
      final DocumentKey key = DocumentKey.fromPath(path);
      if (!await _isPinned(tx, key)) {
        count++;
        await persistence.remoteDocumentCache.remove(tx, key);
        await _removeSentinel(tx, key);
      }
    }

    return count;
  }

  @override
  Future<void> removeTarget(DatabaseExecutor tx, QueryData queryData) async {
    final QueryData updated = queryData.copy(
      queryData.snapshotVersion,
      queryData.resumeToken,
      currentSequenceNumber,
    );

    await persistence.queryCache.updateQueryData(tx, updated);
  }

  @override
  Future<void> updateLimboDocument(DatabaseExecutor tx, DocumentKey key) async {
    await _writeSentinel(tx, key);
  }

  Future<void> _writeSentinel(DatabaseExecutor tx, DocumentKey key) async {
    final String path = EncodedPath.encode(key.path);
    await persistence.execute(tx,
        // @formatter:off
        '''
          INSERT
          OR REPLACE INTO target_documents (target_id, path, sequence_number)
          VALUES (0, ?, ?);
        ''',
        // @formatter:on
        <dynamic>[path, currentSequenceNumber]);
  }
}
