// File created by
// Lung Razvan <long1eu>
// on 21/09/2018

import 'package:firebase_firestore/src/firebase/firestore/core/listent_sequence.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/lru_delegate.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/memory_mutation_queue.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/memory_persistence.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_data.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/reference_delegate.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/reference_set.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/types.dart';

/// Provides LRU garbage collection functionality for [MemoryPersistence].
class MemoryLruReferenceDelegate implements ReferenceDelegate, LruDelegate {
  final MemoryPersistence persistence;
  Map<DocumentKey, int> orphanedSequenceNumbers;

  ListenSequence listenSequence;
  int _currentSequenceNumber;

  MemoryLruReferenceDelegate(this.persistence)
      : orphanedSequenceNumbers = {},
        listenSequence =
            ListenSequence(persistence.queryCache.highestListenSequenceNumber),
        _currentSequenceNumber = ListenSequence.INVALID {
    this.garbageCollector = new LruGarbageCollector(this);
  }

  @override
  ReferenceSet additionalReferences;

  @override
  LruGarbageCollector garbageCollector;

  @override
  int get targetCount => persistence.queryCache.targetCount;

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
  void forEachTarget(Consumer<QueryData> consumer) {
    persistence.queryCache.forEachTarget(consumer);
  }

  @override
  void forEachOrphanedDocumentSequenceNumber(Consumer<int> consumer) {
    for (int sequenceNumber in orphanedSequenceNumbers.values) {
      consumer(sequenceNumber);
    }
  }

  @override
  int removeQueries(int upperBound, Set<int> activeTargetIds) {
    return persistence.queryCache.removeQueries(upperBound, activeTargetIds);
  }

  @override
  int removeOrphanedDocuments(int upperBound) {
    return persistence.remoteDocumentCache
        .removeOrphanedDocuments(this, upperBound);
  }

  @override
  void removeMutationReference(DocumentKey key) {
    orphanedSequenceNumbers[key] = currentSequenceNumber;
  }

  @override
  void removeTarget(QueryData queryData) {
    final QueryData updated = queryData.copy(queryData.snapshotVersion,
        queryData.resumeToken, currentSequenceNumber);
    persistence.queryCache.updateQueryData(updated);
  }

  @override
  void addReference(DocumentKey key) {
    orphanedSequenceNumbers[key] = currentSequenceNumber;
  }

  @override
  void removeReference(DocumentKey key) {
    orphanedSequenceNumbers[key] = currentSequenceNumber;
  }

  @override
  void updateLimboDocument(DocumentKey key) {
    orphanedSequenceNumbers[key] = currentSequenceNumber;
  }

  bool _mutationQueuesContainsKey(DocumentKey key) {
    for (MemoryMutationQueue mutationQueue in persistence.getMutationQueues()) {
      if (mutationQueue.containsKey(key)) {
        return true;
      }
    }
    return false;
  }

  bool isPinned(DocumentKey key, int upperBound) {
    if (_mutationQueuesContainsKey(key)) {
      return true;
    }

    if (additionalReferences.containsKey(key)) {
      return true;
    }

    if (persistence.queryCache.containsKey(key)) {
      return true;
    }

    int sequenceNumber = orphanedSequenceNumbers[key];
    return sequenceNumber != null && sequenceNumber > upperBound;
  }
}
