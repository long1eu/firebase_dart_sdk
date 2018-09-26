// File created by
// Lung Razvan <long1eu>
// on 20/09/2018
import 'dart:async';

import 'package:firebase_firestore/src/firebase/firestore/auth/user.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/memory_eager_reference_delegate.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/memory_lru_reference_delegate.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/memory_mutation_queue.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/memory_query_cache.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/memory_remote_document_cache.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/mutation_queue.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/persistence.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/reference_delegate.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/types.dart';

class MemoryPersistence extends Persistence {
  // The persistence objects backing MemoryPersistence are retained here to make
  // it easier to write tests affecting both the in-memory and SQLite-backed
  // persistence layers. Tests can create a new LocalStore wrapping this
  // Persistence instance and this will make the in-memory persistence layer
  // behave as if it were actually persisting values.
  Map<User, MemoryMutationQueue> mutationQueues;

  @override
  MemoryRemoteDocumentCache remoteDocumentCache;

  @override
  MemoryQueryCache queryCache;

  @override
  ReferenceDelegate referenceDelegate;

  @override
  bool started;

  /// Use static helpers to instantiate
  MemoryPersistence._()
      : mutationQueues = <User, MemoryMutationQueue>{},
        remoteDocumentCache = MemoryRemoteDocumentCache() {
    queryCache = MemoryQueryCache(this);
  }

  static MemoryPersistence createEagerGcMemoryPersistence() {
    final MemoryPersistence persistence = MemoryPersistence._();
    persistence
        ._setReferenceDelegate(MemoryEagerReferenceDelegate(persistence));
    return persistence;
  }

  static MemoryPersistence createLruGcMemoryPersistence() {
    final MemoryPersistence persistence = MemoryPersistence._();
    persistence._setReferenceDelegate(MemoryLruReferenceDelegate(persistence));
    return persistence;
  }

  @override
  Future<void> start() async {
    Assert.hardAssert(!started, 'MemoryPersistence double-started!');
    started = true;
  }

  @override
  Future<void> shutdown() async {
    // TODO: This assertion seems problematic, since we may attempt shutdown in
    // the finally block after failing to initialize.
    Assert.hardAssert(started, 'MemoryPersistence shutdown without start');
    started = false;
  }

  void _setReferenceDelegate(ReferenceDelegate delegate) {
    referenceDelegate = delegate;
  }

  @override
  MutationQueue getMutationQueue(User user) {
    MemoryMutationQueue queue = mutationQueues[user];
    if (queue == null) {
      queue = MemoryMutationQueue(this);
      mutationQueues[user] = queue;
    }
    return queue;
  }

  Iterable<MemoryMutationQueue> getMutationQueues() => mutationQueues.values;

  @override
  Future<void> runTransaction(
      String action, Transaction<void> operation) async {
    referenceDelegate.onTransactionStarted();
    try {
      operation(null);
    } finally {
      referenceDelegate.onTransactionCommitted();
    }
  }

  @override
  Future<T> runTransactionAndReturn<T>(
      String action, Transaction<T> operation) async {
    referenceDelegate.onTransactionStarted();
    final T result = await operation(null);
    referenceDelegate.onTransactionCommitted();
    return result;
  }
}
