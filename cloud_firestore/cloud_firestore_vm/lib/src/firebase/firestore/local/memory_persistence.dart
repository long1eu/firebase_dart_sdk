// File created by
// Lung Razvan <long1eu>
// on 20/09/2018
import 'dart:async';

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_firestore/src/firebase/firestore/auth/user.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/local_serializer.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/lru_garbage_collector.dart';
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
  /// Use factory constructors to instantiate
  MemoryPersistence._()
      : mutationQueues = <User, MemoryMutationQueue>{},
        remoteDocumentCache = MemoryRemoteDocumentCache() {
    queryCache = MemoryQueryCache(this);
  }

  factory MemoryPersistence.createEagerGcMemoryPersistence() {
    final MemoryPersistence persistence = MemoryPersistence._();
    persistence.referenceDelegate = MemoryEagerReferenceDelegate(persistence);
    return persistence;
  }

  factory MemoryPersistence.createLruGcMemoryPersistence(LruGarbageCollectorParams params, LocalSerializer serializer) {
    final MemoryPersistence persistence = MemoryPersistence._();
    persistence.referenceDelegate = MemoryLruReferenceDelegate(persistence, params, serializer);
    return persistence;
  }

  static const String tag = 'MemoryPersistence';

  // The persistence objects backing MemoryPersistence are retained here to make it easier to write tests affecting both
  // the in-memory and SQLite-backed persistence layers. Tests can create a new LocalStore wrapping this Persistence
  // instance and this will make the in-memory persistence layer behave as if it were actually persisting values.
  Map<User, MemoryMutationQueue> mutationQueues;

  @override
  MemoryRemoteDocumentCache remoteDocumentCache;

  @override
  MemoryQueryCache queryCache;

  @override
  ReferenceDelegate referenceDelegate;

  @override
  bool started = false;

  @override
  Future<void> start() async {
    hardAssert(!started, 'MemoryPersistence double-started!');
    started = true;
  }

  @override
  Future<void> shutdown() async {
    // TODO(long1eu): This assertion seems problematic, since we may attempt shutdown in the finally block after failing
    //  to initialize.
    hardAssert(started, 'MemoryPersistence shutdown without start');
    started = false;
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
  Future<void> runTransaction(String action, Transaction<void> operation) async {
    Log.d(tag, 'Starting transaction: $action');

    referenceDelegate.onTransactionStarted();
    await operation();
    await referenceDelegate.onTransactionCommitted();
  }

  @override
  Future<T> runTransactionAndReturn<T>(String action, Transaction<T> operation) async {
    Log.d(tag, 'Starting transaction: $action');
    referenceDelegate.onTransactionStarted();
    final T result = await operation();
    await referenceDelegate.onTransactionCommitted();
    return result;
  }
}
