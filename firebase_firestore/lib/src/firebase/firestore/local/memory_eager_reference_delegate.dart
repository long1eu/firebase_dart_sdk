// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

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
  int get currentSequenceNumber => ListenSequence.INVALID;

  @override
  void addReference(DocumentKey key) => orphanedDocuments.remove(key);

  @override
  void removeReference(DocumentKey key) => orphanedDocuments.add(key);

  @override
  void removeMutationReference(DocumentKey key) => orphanedDocuments.add(key);

  @override
  void removeTarget(QueryData queryData) {
    final MemoryQueryCache queryCache = persistence.queryCache;
    for (DocumentKey key
        in queryCache.getMatchingKeysForTargetId(queryData.targetId)) {
      orphanedDocuments.add(key);
    }
    queryCache.removeQueryData(queryData);
  }

  @override
  void onTransactionStarted() => orphanedDocuments = Set<DocumentKey>();

  /// In eager garbage collection, collection is run on transaction commit.
  @override
  void onTransactionCommitted() {
    final MemoryRemoteDocumentCache remoteDocuments =
        persistence.remoteDocumentCache;
    for (DocumentKey key in orphanedDocuments) {
      if (!_isReferenced(key)) {
        remoteDocuments.remove(key);
      }
    }
    orphanedDocuments = null;
  }

  @override
  void updateLimboDocument(DocumentKey key) {
    if (_isReferenced(key)) {
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
  bool _isReferenced(DocumentKey key) {
    if (persistence.queryCache.containsKey(key)) {
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
