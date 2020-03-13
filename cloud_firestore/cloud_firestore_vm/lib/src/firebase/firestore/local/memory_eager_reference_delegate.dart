// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

import 'dart:async';

import 'package:cloud_firestore_vm/src/firebase/firestore/core/listent_sequence.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/memory_mutation_queue.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/memory_persistence.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/memory_query_cache.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/memory_remote_document_cache.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/reference_delegate.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/reference_set.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';

/// Provides eager garbage collection for [MemoryPersistence].
class MemoryEagerReferenceDelegate implements ReferenceDelegate {
  MemoryEagerReferenceDelegate(this.persistence);

  final MemoryPersistence persistence;

  Set<DocumentKey> orphanedDocuments;

  @override
  ReferenceSet inMemoryPins;

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

    await queryCache.removeQueryData(queryData);
  }

  @override
  void onTransactionStarted() {
    orphanedDocuments = <DocumentKey>{};
  }

  /// In eager garbage collection, collection is run on transaction commit.
  @override
  Future<void> onTransactionCommitted() async {
    final MemoryRemoteDocumentCache remoteDocuments =
        persistence.remoteDocumentCache;

    for (DocumentKey key in orphanedDocuments) {
      final bool isReferenced = await _isReferenced(key);
      if (!isReferenced) {
        await remoteDocuments.remove(key);
      }
    }
    orphanedDocuments = null;
  }

  @override
  Future<void> updateLimboDocument(DocumentKey key) async {
    final bool isReferenced = await _isReferenced(key);
    if (isReferenced) {
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
    final bool containsKey = await persistence.queryCache.containsKey(key);
    if (containsKey) {
      return true;
    }

    if (_mutationQueuesContainKey(key)) {
      return true;
    }

    if (inMemoryPins != null && inMemoryPins.containsKey(key)) {
      return true;
    }

    return false;
  }
}
