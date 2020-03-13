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
import 'package:cloud_firestore_vm/src/firebase/firestore/local/memory_persistence.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistence.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/sqlite_lru_reference_delegate.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/sqlite_persistence.dart';
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
import 'package:cloud_firestore_vm/src/firebase/firestore/util/async_queue.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/database.dart';
import 'package:grpc/grpc.dart';
import 'package:rxdart/rxdart.dart';

/// [FirestoreClient] is a top-level class that constructs and owns all of the pieces of the client SDK architecture.
class FirestoreClient implements RemoteStoreCallback {
  FirestoreClient._(
    this.databaseInfo,
    this.credentialsProvider,
    this.asyncQueue,
  );

  static const String logTag = 'FirestoreClient';

  final DatabaseInfo databaseInfo;
  final CredentialsProvider credentialsProvider;
  final AsyncQueue asyncQueue;

  StreamSubscription<User> onCredentialChangeSubscription;
  Persistence persistence;
  LocalStore localStore;
  RemoteStore remoteStore;
  SyncEngine syncEngine;
  EventManager eventManager;

  LruGarbageCollectorScheduler _lruScheduler;

  static Future<FirestoreClient> initialize(
    DatabaseInfo databaseInfo,
    FirestoreSettings settings,
    CredentialsProvider credentialsProvider,
    AsyncQueue asyncQueue,
    OpenDatabase openDatabase,
    BehaviorSubject<bool> onNetworkConnected,
  ) async {
    final FirestoreClient client =
        FirestoreClient._(databaseInfo, credentialsProvider, asyncQueue);

    final Completer<User> firstUser = Completer<User>();
    bool initialized = false;

    client.onCredentialChangeSubscription =
        credentialsProvider.onChange.listen((User user) {
      if (initialized == false) {
        initialized = true;
        hardAssert(!firstUser.isCompleted, 'Already fulfilled first user task');
        firstUser.complete(user);
      } else {
        asyncQueue.enqueueAndForget(
          () async {
            Log.d(logTag, 'Credential changed. Current user: ${user.uid}');
            await client.syncEngine.handleCredentialChange(user);
          },
          'FirestoreClinet initialize',
        );
      }
    });

    final User user = await asyncQueue.enqueue(
        () => firstUser.future, 'FirestoreClinet initialize get user');
    await client._initialize(
      user,
      // TODO(long1eu): Make sure you remove the openDatabase != null once we
      //  provide a default way to instantiate a db instance
      settings.persistenceEnabled && openDatabase != null,
      settings.cacheSizeBytes,
      openDatabase,
      onNetworkConnected,
    );
    return client;
  }

  Future<void> disableNetwork() {
    return asyncQueue.enqueue(
        () => remoteStore.disableNetwork(), 'FirestoreClinet disableNetwork');
  }

  Future<void> enableNetwork() {
    return asyncQueue.enqueue(
        () => remoteStore.enableNetwork(), 'FirestoreClinet enableNetwork');
  }

  /// Shuts down this client, cancels all writes / listeners, and releases all resources.
  Future<void> shutdown() async {
    await onCredentialChangeSubscription.cancel();
    return asyncQueue.enqueue(
      () async {
        await remoteStore.shutdown();
        await persistence.shutdown();
        _lruScheduler?.stop();
      },
      'FirestoreClient shutdown',
    );
  }

  /// Starts listening to a query. */
  Future<QueryStream> listen(Query query, ListenOptions options) async {
    final QueryStream queryListener =
        QueryStream(query, options, stopListening);
    await asyncQueue.enqueue(() => eventManager.addQueryListener(queryListener),
        'FirestoreClinet listen');
    return queryListener;
  }

  /// Stops listening to a query previously listened to.
  void stopListening(QueryStream listener) {
    asyncQueue.enqueueAndForget(
        () => eventManager.removeQueryListener(listener),
        'FirestoreClinet stopListening');
  }

  Future<Document> getDocumentFromLocalCache(DocumentKey docKey) {
    return asyncQueue
        .enqueue(() => localStore.readDocument(docKey),
            'FirestoreClient getDocumentFromLocalCache')
        .then((MaybeDocument result) {
      final MaybeDocument maybeDoc = result;

      if (maybeDoc is Document) {
        return maybeDoc;
      } else if (maybeDoc is NoDocument) {
        return null;
      } else {
        throw FirebaseFirestoreError(
          'Failed to get document from cache. (However, this document may exist on the server. Run again without '
          'setting source to CACHE to attempt to retrieve the document from the server.)',
          FirestoreErrorCode.unavailable,
        );
      }
    });
  }

  Future<ViewSnapshot> getDocumentsFromLocalCache(Query query) {
    return asyncQueue.enqueue(
      () async {
        final ImmutableSortedMap<DocumentKey, Document> docs =
            await localStore.executeQuery(query);

        final View view = View(query, ImmutableSortedSet<DocumentKey>());
        final ViewDocumentChanges viewDocChanges = view.computeDocChanges(docs);
        return view.applyChanges(viewDocChanges).snapshot;
      },
      'FirestoreClient getDocumentsFromLocalCache',
    );
  }

  /// Writes mutations. The returned Future will be notified when it's written to the backend.
  Future<void> write(final List<Mutation> mutations) async {
    final Completer<void> source = Completer<void>();
    asyncQueue.enqueueAndForget(
        () => syncEngine.writeMutations(mutations, source),
        'FirestoreClient write');
    await source.future;
  }

  /// Tries to execute the transaction in updateFunction up to retries times.
  Future<TResult> transaction<TResult>(
      Future<TResult> Function(Transaction) updateFunction, int retries) {
    return syncEngine.transaction(asyncQueue, updateFunction, retries);
  }

  Future<void> _initialize(
    User user,
    bool usePersistence,
    int cacheSizeBytes,
    OpenDatabase openDatabase,
    BehaviorSubject<bool> onNetworkConnected,
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
      _lruScheduler = gc.newScheduler(asyncQueue, localStore) //
        ..start();
    }

    final Datastore datastore =
        Datastore(databaseInfo, asyncQueue, credentialsProvider);
    remoteStore = RemoteStore(
      this,
      localStore,
      datastore,
      onNetworkConnected,
      asyncQueue,
    );

    syncEngine = SyncEngine(localStore, remoteStore, user);
    eventManager = EventManager(syncEngine);

    // NOTE: RemoteStore depends on LocalStore (for persisting stream tokens, refilling mutation queue, etc.) so must be
    // started after LocalStore.
    await localStore.start();
    await remoteStore.start();
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
