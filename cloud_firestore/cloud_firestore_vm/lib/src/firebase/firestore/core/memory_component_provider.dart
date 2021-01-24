// File created by
// Lung Razvan <long1eu>
// on 16/01/2021

import 'package:_firebase_database_collection_vm/_firebase_database_collection_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/component_provider.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/event_manager.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/online_state.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/sync_engine.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/default_query_engine.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/garbage_collection_scheduler.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/memory/memory_persistence.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistence/persistence.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation_batch_result.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/remote_event.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/remote_store.dart';
import 'package:grpc/grpc.dart';

/// Provides all components needed for Firestore with in-memory persistence. Uses EagerGC garbage
/// collection.
class MemoryComponentProvider extends ComponentProvider {
  @override
  GarbageCollectionScheduler createGarbageCollectionScheduler(ComponentProviderConfiguration configuration) {
    return null;
  }

  @override
  EventManager createEventManager(ComponentProviderConfiguration configuration) {
    return EventManager(syncEngine);
  }

  @override
  LocalStore createLocalStore(ComponentProviderConfiguration configuration) {
    return LocalStore(persistence, DefaultQueryEngine(), configuration.initialUser);
  }

  @override
  Future<Persistence> createPersistence(ComponentProviderConfiguration configuration) async {
    return MemoryPersistence.createEagerGcMemoryPersistence();
  }

  @override
  RemoteStore createRemoteStore(ComponentProviderConfiguration configuration) {
    return RemoteStore(
      _RemoteStoreCallbackImpl(this),
      localStore,
      configuration.datastore,
      configuration.asyncQueue,
      configuration.onNetworkConnected,
    );
  }

  @override
  SyncEngine createSyncEngine(ComponentProviderConfiguration configuration) {
    return SyncEngine(
      localStore,
      remoteStore,
      configuration.initialUser,
      configuration.maxConcurrentLimboResolutions,
    );
  }
}

/// A callback interface used by RemoteStore. All calls are forwarded to SyncEngine.
///
/// This interface exists to allow RemoteStore to access functionality provided by SyncEngine
/// even though SyncEngine is created after RemoteStore.
class _RemoteStoreCallbackImpl implements RemoteStoreCallback {
  _RemoteStoreCallbackImpl(this._provider);

  final ComponentProvider _provider;

  @override
  ImmutableSortedSet<DocumentKey> getRemoteKeysForTarget(int targetId) {
    return _provider.syncEngine.getRemoteKeysForTarget(targetId);
  }

  @override
  Future<void> handleOnlineStateChange(OnlineState onlineState) {
    return _provider.syncEngine.handleOnlineStateChange(onlineState);
  }

  @override
  Future<void> handleRejectedListen(int targetId, GrpcError error) {
    return _provider.syncEngine.handleRejectedListen(targetId, error);
  }

  @override
  Future<void> handleRejectedWrite(int batchId, GrpcError error) {
    return _provider.syncEngine.handleRejectedWrite(batchId, error);
  }

  @override
  Future<void> handleRemoteEvent(RemoteEvent remoteEvent) {
    return _provider.syncEngine.handleRemoteEvent(remoteEvent);
  }

  @override
  Future<void> handleSuccessfulWrite(MutationBatchResult successfulWrite) {
    return _provider.syncEngine.handleSuccessfulWrite(successfulWrite);
  }
}
