// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

library memory_persistence;

import 'dart:async';
import 'dart:typed_data';

import 'package:_firebase_database_collection_vm/_firebase_database_collection_vm.dart';
import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/listent_sequence.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/document_reference.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/lru_delegate.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistance/index_manager.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistance/mutation_queue.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistance/query_cache.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistance/reference_delegate.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistance/remote_document_cache.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/reference_set.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_collections.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/types.dart';
import 'package:cloud_firestore_vm/src/firebase/timestamp.dart';
import 'package:semaphore/semaphore.dart';

part 'memory_eager_reference_delegate.dart';
part 'memory_index_manager.dart';
part 'memory_lru_reference_delegate.dart';
part 'memory_mutation_queue.dart';
part 'memory_query_cache.dart';
part 'memory_remote_document_cache.dart';

class MemoryPersistence extends Persistence {
  /// Use factory constructors to instantiate
  MemoryPersistence._()
      : mutationQueues = <User, MemoryMutationQueue>{},
        _semaphore = GlobalSemaphore(),
        indexManager = MemoryIndexManager() {
    queryCache = MemoryQueryCache(this);
    remoteDocumentCache = MemoryRemoteDocumentCache(this);
  }

  factory MemoryPersistence.createEagerGcMemoryPersistence() {
    final MemoryPersistence persistence = MemoryPersistence._();
    persistence.referenceDelegate = MemoryEagerReferenceDelegate(persistence);
    return persistence;
  }

  factory MemoryPersistence.createLruGcMemoryPersistence(
      LruGarbageCollectorParams params, LocalSerializer serializer) {
    final MemoryPersistence persistence = MemoryPersistence._();
    persistence.referenceDelegate =
        MemoryLruReferenceDelegate(persistence, params, serializer);
    return persistence;
  }

  final Semaphore _semaphore;
  @override
  final MemoryIndexManager indexManager;

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
  bool started = false;

  @override
  Future<void> start() async {
    await _semaphore.acquire();
    hardAssert(!started, 'MemoryPersistence double-started!');
    started = true;
    _semaphore.release();
  }

  @override
  Future<void> shutdown() async {
    await _semaphore.acquire();
    // TODO(long1eu): This assertion seems problematic, since we may attempt
    //  shutdown in the finally block after failing to initialize.
    hardAssert(started, 'MemoryPersistence shutdown without start');
    started = false;
    _semaphore.release();
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
    return runTransactionAndReturn(action, operation);
  }

  @override
  Future<T> runTransactionAndReturn<T>(
      String action, Transaction<T> operation) async {
    await _semaphore.acquire();

    Log.d('$runtimeType', 'Starting transaction: $action');
    referenceDelegate.onTransactionStarted();
    final T result = await operation();
    Log.d('$runtimeType', 'Commit transaction: $action');
    await referenceDelegate.onTransactionCommitted();

    _semaphore.release();
    return result;
  }
}
