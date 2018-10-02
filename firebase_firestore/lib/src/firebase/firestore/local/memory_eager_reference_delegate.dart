// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

import 'dart:async';

import 'package:firebase_firestore/src/firebase/firestore/core/listent_sequence.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/memory_mutation_queue.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/memory_persistence.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/memory_query_cache.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/memory_remote_document_cache.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_data.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/reference_delegate.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/reference_set.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';

/// Provides eager garbage collection for [MemoryPersistence].
class MemoryEagerReferenceDelegate implements ReferenceDelegate {
  final MemoryPersistence persistence;

  Set<DocumentKey> orphanedDocuments;

  MemoryEagerReferenceDelegate(this.persistence);

  @override
  ReferenceSet additionalReferences;

  @override
  int get currentSequenceNumber => ListenSequence.invalid;

  @override
  Future<void> addReference(DocumentKey key) async {
    orphanedDocuments.remove(key);
  }

  @override
  Future<void> removeReference(DocumentKey key) async {
    orphanedDocuments.add(key);
  }

  @override
  Future<void> removeMutationReference(DocumentKey key) async {
    orphanedDocuments.add(key);
  }

  @override
  Future<void> removeTarget(QueryData queryData) async {
    final MemoryQueryCache queryCache = persistence.queryCache;
    (await queryCache.getMatchingKeysForTargetId(queryData.targetId))
        .forEach(orphanedDocuments.add);

    queryCache.removeQueryData(queryData);
  }

  @override
  void onTransactionStarted() => orphanedDocuments = Set<DocumentKey>();

  /// In eager garbage collection, collection is run on transaction commit.
  @override
  void onTransactionCommitted() async {
    final MemoryRemoteDocumentCache remoteDocuments =
        persistence.remoteDocumentCache;
    for (DocumentKey key in orphanedDocuments) {
      if (!(await _isReferenced(key))) {
        remoteDocuments.remove(key);
      }
    }
    orphanedDocuments = null;
  }

  @override
  Future<void> updateLimboDocument(DocumentKey key) async {
    if (await _isReferenced(key)) {
      orphanedDocuments.remove(key);
    } else {
      orphanedDocuments.add(key);
    }
  }

  bool _mutationQueuesContainKey(DocumentKey key) {
    for (MemoryMutationQueue queue in persistence.getMutationQueues()) {
      if (queue.containsKey(key)) {
        return true;
      }
    }
    return false;
  }

  /// Returns true if the given document is referenced by anything.
  Future<bool> _isReferenced(DocumentKey key) async {
    if (await persistence.queryCache.containsKey(key)) {
      return true;
    }

    if (_mutationQueuesContainKey(key)) {
      return true;
    }

    if (additionalReferences != null && additionalReferences.containsKey(key)) {
      return true;
    }

    return false;
  }
}
