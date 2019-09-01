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

class SQLiteLruReferenceDelegate implements ReferenceDelegate, LruDelegate {
  SQLiteLruReferenceDelegate(this.persistence)
      : _currentSequenceNumber = ListenSequence.invalid {
    garbageCollector = LruGarbageCollector(this);
  }

  final SQLitePersistence persistence;
  ListenSequence listenSequence;
  int _currentSequenceNumber;


  @override
  ReferenceSet inMemoryPins;

  @override
  LruGarbageCollector garbageCollector;

  void start(int highestSequenceNumber) {
    listenSequence = ListenSequence(highestSequenceNumber);
  }

  @override
  void onTransactionStarted() {
    Assert.hardAssert(_currentSequenceNumber == ListenSequence.invalid,
        'Starting a transaction without committing the previous one');
    _currentSequenceNumber = listenSequence.next();
  }

  @override
  Future<void> onTransactionCommitted() async {
    Assert.hardAssert(_currentSequenceNumber != ListenSequence.invalid,
        'Committing a transaction without having started one');
    _currentSequenceNumber = ListenSequence.invalid;
  }

  @override
  int get currentSequenceNumber {
    Assert.hardAssert(_currentSequenceNumber != ListenSequence.invalid,
        'Attempting to get a sequence number outside of a transaction');
    return _currentSequenceNumber;
  }

  @override
  int get targetCount => persistence.queryCache.targetCount;

  @override
  Future<void> forEachTarget(Consumer<QueryData> consumer) async {
    await persistence.queryCache.forEachTarget(consumer);
  }

  @override
  Future<void> forEachOrphanedDocumentSequenceNumber(
      Consumer<int> consumer) async {
    final List<Map<String, dynamic>> result = await persistence.query(
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
      consumer(row['sequence_number']);
    }
  }

  @override
  Future<void> addReference(DocumentKey key) async {
    await _writeSentinel(key);
  }

  @override
  Future<void> removeReference(DocumentKey key) async {
    await _writeSentinel(key);
  }

  @override
  Future<int> removeTargets(int upperBound, Set<int> activeTargetIds) {
    return persistence.queryCache.removeQueries(upperBound, activeTargetIds);
  }

  @override
  Future<void> removeMutationReference(DocumentKey key) async {
    await _writeSentinel(key);
  }

  /// Returns true if any mutation queue contains the given document.
  Future<bool> _mutationQueuesContainKey(DocumentKey key) async {
    return (await persistence.query(
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
  Future<bool> _isPinned(DocumentKey key) async {
    if (inMemoryPins.containsKey(key)) {
      return true;
    }

    return _mutationQueuesContainKey(key);
  }

  Future<void> _removeSentinel(DocumentKey key) async {
    await persistence.execute(
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
  Future<int> removeOrphanedDocuments(int upperBound) async {
    int count = 0;
    final List<Map<String, dynamic>> result = await persistence.query(
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
      final ResourcePath path = EncodedPath.decodeResourcePath(row['path']);
      final DocumentKey key = DocumentKey.fromPath(path);
      if (!await _isPinned(key)) {
        count++;
        await persistence.remoteDocumentCache.remove(key);
        await _removeSentinel(key);
      }
    }

    return count;
  }

  @override
  Future<void> removeTarget(QueryData queryData) async {
    final QueryData updated = queryData.copyWith(
      snapshotVersion: queryData.snapshotVersion,
      resumeToken: queryData.resumeToken,
      sequenceNumber: currentSequenceNumber,
    );

    await persistence.queryCache.updateQueryData(updated);
  }

  @override
  Future<void> updateLimboDocument(DocumentKey key) async {
    await _writeSentinel(key);
  }

  Future<void> _writeSentinel(DocumentKey key) async {
    final String path = EncodedPath.encode(key.path);
    await persistence.execute(
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
