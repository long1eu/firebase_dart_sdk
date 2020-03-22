// File created by
// Lung Razvan <long1eu>
// on 18/09/2018

import 'dart:async';

import 'package:_firebase_database_collection_vm/_firebase_database_collection_vm.dart';
import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/auth/credentials_provider.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/database_info.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/event_manager.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/online_state.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/query_stream.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/sync_engine.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/transaction.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/view.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/view_snapshot.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore_settings.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/memory/memory_persistence.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation_batch_result.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/no_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/datastore/datastore.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/remote_event.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/remote_store.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/database.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/timer_task.dart';
import 'package:grpc/grpc.dart';
import 'package:rxdart/rxdart.dart';

/// [FirestoreClient] is a top-level class that constructs and owns all of the pieces of the client SDK architecture.
class FirestoreClient implements RemoteStoreCallback {
  FirestoreClient._(this.databaseInfo, this.credentialsProvider);

  static const String logTag = 'FirestoreClient';

  final DatabaseInfo databaseInfo;
  final CredentialsProvider credentialsProvider;

  StreamSubscription<User> onCredentialChangeSubscription;
  Persistence persistence;
  LocalStore localStore;
  RemoteStore remoteStore;
  SyncEngine syncEngine;
  EventManager eventManager;
  bool _isShutdown = false;

  LruGarbageCollectorScheduler _lruScheduler;

  static Future<FirestoreClient> initialize(
    DatabaseInfo databaseInfo,
    FirestoreSettings settings,
    CredentialsProvider credentialsProvider,
    OpenDatabase openDatabase,
    BehaviorSubject<bool> onNetworkConnected,
    TaskScheduler scheduler,
  ) async {
    final FirestoreClient client =
        FirestoreClient._(databaseInfo, credentialsProvider);

    final Completer<User> firstUser = Completer<User>();
    bool initialized = false;

    client.onCredentialChangeSubscription =
        credentialsProvider.onChange.listen((User user) {
      if (initialized == false) {
        initialized = true;
        hardAssert(!firstUser.isCompleted, 'Already fulfilled first user task');
        firstUser.complete(user);
      } else {
        Log.d(logTag, 'Credential changed. Current user: ${user.uid}');
        client.syncEngine.handleCredentialChange(user);
      }
    });

    final User user = await firstUser.future;
    await client._initialize(
      user,
      // TODO(long1eu): Make sure you remove the openDatabase != null once we
      //  provide a default way to instantiate a db instance
      settings.persistenceEnabled && openDatabase != null,
      settings.cacheSizeBytes,
      openDatabase,
      onNetworkConnected,
      scheduler,
    );
    return client;
  }

  Future<void> disableNetwork() {
    _verifyNotShutdown();
    return remoteStore.disableNetwork();
  }

  Future<void> enableNetwork() {
    _verifyNotShutdown();
    return remoteStore.enableNetwork();
  }

  /// Shuts down this client, cancels all writes / listeners, and releases all resources.
  Future<void> shutdown() async {
    if (_isShutdown) {
      return;
    }

    await onCredentialChangeSubscription.cancel();
    await remoteStore.shutdown();
    await persistence.shutdown();
    _lruScheduler?.stop();
    _isShutdown = true;
  }

  /// Starts listening to a query. */
  Future<QueryStream> listen(Query query, ListenOptions options) async {
    _verifyNotShutdown();

    final QueryStream queryListener =
        QueryStream(query, options, stopListening);
    await eventManager.addQueryListener(queryListener);
    return queryListener;
  }

  /// Stops listening to a query previously listened to.
  Future<void> stopListening(QueryStream listener) {
    _verifyNotShutdown();

    return eventManager.removeQueryListener(listener);
  }

  Future<Document> getDocumentFromLocalCache(DocumentKey docKey) async {
    _verifyNotShutdown();

    final MaybeDocument maybeDoc = await localStore.readDocument(docKey);

    if (maybeDoc is Document) {
      return maybeDoc;
    } else if (maybeDoc is NoDocument) {
      return null;
    } else {
      throw FirestoreError(
        'Failed to get document from cache. (However, this document may exist on the server. Run again without '
        'setting source to CACHE to attempt to retrieve the document from the server.)',
        FirestoreErrorCode.unavailable,
      );
    }
  }

  Future<ViewSnapshot> getDocumentsFromLocalCache(Query query) async {
    _verifyNotShutdown();

    final ImmutableSortedMap<DocumentKey, Document> docs =
        await localStore.executeQuery(query);

    final View view = View(query, ImmutableSortedSet<DocumentKey>());
    final ViewDocumentChanges viewDocChanges = view.computeDocChanges(docs);
    return view.applyChanges(viewDocChanges).snapshot;
  }

  /// Writes mutations. The returned Future will be notified when it's written to the backend.
  Future<void> write(final List<Mutation> mutations) async {
    _verifyNotShutdown();

    final Completer<void> source = Completer<void>();
    await syncEngine.writeMutations(mutations, source);
    await source.future;
  }

  /// Tries to execute the transaction in updateFunction up to retries times.
  Future<TResult> transaction<TResult>(
      Future<TResult> Function(Transaction) updateFunction, int retries) {
    _verifyNotShutdown();

    return syncEngine.transaction(updateFunction, retries);
  }

  Future<void> _initialize(
    User user,
    bool usePersistence,
    int cacheSizeBytes,
    OpenDatabase openDatabase,
    BehaviorSubject<bool> onNetworkConnected,
    TaskScheduler scheduler,
  ) async {
    // Note: The initialization work must all be synchronous (we can't dispatch more work) since external write/listen
    // operations could get queued to run before that subsequent work completes.
    Log.d(logTag, 'Initializing. user=${user.uid}');

    LruGarbageCollector gc;
    if (usePersistence) {
      final LocalSerializer serializer =
          LocalSerializer(RemoteSerializer(databaseInfo.databaseId));
      final LruGarbageCollectorParams params =
          LruGarbageCollectorParams.withCacheSizeBytes(cacheSizeBytes);

      final SQLitePersistence persistence = await SQLitePersistence.create(
          databaseInfo.persistenceKey,
          databaseInfo.databaseId,
          serializer,
          openDatabase,
          params);

      final SQLiteLruReferenceDelegate lruDelegate =
          persistence.referenceDelegate;
      gc = lruDelegate.garbageCollector;
      this.persistence = persistence;
    } else {
      persistence = MemoryPersistence.createEagerGcMemoryPersistence();
    }

    await persistence.start();
    localStore = LocalStore(persistence, user);
    if (gc != null) {
      _lruScheduler = gc.newScheduler(scheduler, localStore) //
        ..start();
    }

    final Datastore datastore =
        Datastore(scheduler, databaseInfo, credentialsProvider);
    remoteStore =
        RemoteStore(this, localStore, datastore, onNetworkConnected, scheduler);

    syncEngine = SyncEngine(localStore, remoteStore, user);
    eventManager = EventManager(syncEngine);

    // NOTE: RemoteStore depends on LocalStore (for persisting stream tokens,
    // refilling mutation queue, etc.) so must be started after LocalStore.
    await localStore.start();
    await remoteStore.start();
  }

  void _verifyNotShutdown() {
    if (_isShutdown) {
      throw ArgumentError('The client has already been shutdown');
    }
  }

  @override
  Future<void> handleRemoteEvent(RemoteEvent remoteEvent) async {
    await syncEngine.handleRemoteEvent(remoteEvent);
  }

  @override
  Future<void> handleRejectedListen(int targetId, GrpcError error) async {
    await syncEngine.handleRejectedListen(targetId, error);
  }

  @override
  Future<void> handleSuccessfulWrite(
      MutationBatchResult mutationBatchResult) async {
    await syncEngine.handleSuccessfulWrite(mutationBatchResult);
  }

  @override
  Future<void> handleRejectedWrite(int batchId, GrpcError error) async {
    await syncEngine.handleRejectedWrite(batchId, error);
  }

  @override
  Future<void> handleOnlineStateChange(OnlineState onlineState) async {
    await syncEngine.handleOnlineStateChange(onlineState);
  }

  @override
  ImmutableSortedSet<DocumentKey> Function(int targetId)
      get getRemoteKeysForTarget {
    return (int targetId) {
      return syncEngine.getRemoteKeysForTarget(targetId);
    };
  }
}
