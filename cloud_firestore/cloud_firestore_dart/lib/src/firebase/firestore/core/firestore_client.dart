// File created by
// Lung Razvan <long1eu>
// on 18/09/2018

import 'dart:async';

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/aggregate_field.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/app_check_token_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_reader.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/named_query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/database_info.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/event_manager.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/online_state.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query_stream.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/serial_queue.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/sync_engine.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/transaction.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/transaction_runner.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/view.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/view_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_settings.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/load_bundle_task.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/memory/memory_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local_cache_settings.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/no_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/datastore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_event.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/database.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/exponential_backoff.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/vector_query.dart';
import 'package:firebase_app_dart/internal.dart';
import 'package:grpc/grpc.dart';
import 'package:rxdart/rxdart.dart';

/// [FirestoreClient] is a top-level class that constructs and owns all of the pieces of the client SDK architecture.
class FirestoreClient implements RemoteStoreCallback {
  FirestoreClient._(
      this.databaseInfo, this.credentialsProvider, this.appCheckProvider);

  static const String logTag = 'FirestoreClient';

  final DatabaseInfo databaseInfo;
  final CredentialsProvider credentialsProvider;
  final AppCheckTokenProvider? appCheckProvider;

  late StreamSubscription<User> onCredentialChangeSubscription;
  late Persistence persistence;
  late LocalStore localStore;
  late RemoteStore remoteStore;
  late SyncEngine syncEngine;
  late EventManager eventManager;
  bool _isShutdown = false;
  Future<void>? _shutdownFuture;

  LruGarbageCollectorScheduler? _lruScheduler;

  static Future<FirestoreClient> initialize(
    DatabaseInfo databaseInfo,
    FirestoreSettings settings,
    CredentialsProvider credentialsProvider,
    OpenDatabase? openDatabase,
    BehaviorSubject<bool> onNetworkConnected,
    TaskScheduler scheduler, {
    AppCheckTokenProvider? appCheckProvider,
  }) async {
    final FirestoreClient client =
        FirestoreClient._(databaseInfo, credentialsProvider, appCheckProvider);

    final Completer<User> firstUser = Completer<User>();
    bool initialized = false;
    // Completes once the client is fully initialized. Credential changes that
    // arrive earlier are queued behind it (the Android SDK gets this for free
    // because the change handler runs on the worker queue).
    final Completer<void> initDone = Completer<void>();

    client.onCredentialChangeSubscription =
        credentialsProvider.onChange.listen((User user) {
      if (initialized == false) {
        initialized = true;
        hardAssert(!firstUser.isCompleted, 'Already fulfilled first user task');
        firstUser.complete(user);
      } else {
        // Wait for the initialization outside of the queue: the initialization itself runs on the queue.
        initDone.future.then<void>((_) {
          client._enqueue<void>(() async {
            if (client._isShutdown) {
              return;
            }
            Log.d(logTag, 'Credential changed. Current user: ${user.uid}');
            await client.syncEngine.handleCredentialChange(user);
          });
        });
      }
    });

    final User user = await firstUser.future;
    await client._enqueue<void>(() => client._initialize(
          user,
          // TODO(long1eu): Make sure you remove the openDatabase != null once we
          //  provide a default way to instantiate a db instance
          settings.persistenceEnabled && openDatabase != null,
          settings.cacheSizeBytes,
          openDatabase,
          onNetworkConnected,
          scheduler,
          memoryLruGcSettings: switch (settings.cacheSettings) {
            final MemoryCacheSettings memory => memory.gcSettings,
            _ => null,
          },
        ));
    initDone.complete();
    return client;
  }

  /// PORTING NOTE: the Android SDK runs every client operation, and every callback of the remote store, on a single
  /// worker queue, so an operation always observes the effects of the operations that were requested before it. This
  /// queue plays that role; it is shared with the [RemoteStore].
  final SerialQueue _queue = SerialQueue();

  Future<T> _enqueue<T>(Future<T> Function() task) => _queue.run<T>(task);

  /// Returns a future that completes when all the writes that are pending right now were acknowledged (or rejected)
  /// by the backend.
  Future<void> waitForPendingWrites() {
    _verifyNotShutdown();

    final Completer<void> source = Completer<void>();
    _enqueue<void>(() => syncEngine.registerPendingWritesTask(source))
        .catchError((Object error, StackTrace stackTrace) {
      if (!source.isCompleted) {
        source.completeError(error, stackTrace);
      }
    });
    return source.future;
  }

  /// Adds a listener that is called whenever all the snapshot listeners are in sync with each other (and once right
  /// away).
  Future<void> addSnapshotsInSyncListener(void Function() listener) {
    _verifyNotShutdown();
    return _enqueue<void>(
        () async => eventManager.addSnapshotsInSyncListener(listener));
  }

  /// Removes a listener that was added with [addSnapshotsInSyncListener]. A no-op after the client was shut down.
  Future<void> removeSnapshotsInSyncListener(void Function() listener) {
    if (_isShutdown) {
      return Future<void>.value();
    }
    return _enqueue<void>(
        () async => eventManager.removeSnapshotsInSyncListener(listener));
  }

  Future<void> disableNetwork() {
    _verifyNotShutdown();
    return _enqueue<void>(() => remoteStore.disableNetwork());
  }

  Future<void> enableNetwork() {
    _verifyNotShutdown();
    return _enqueue<void>(() => remoteStore.enableNetwork());
  }

  /// Shuts down this client, cancels all writes / listeners, and releases all resources.
  ///
  /// Concurrent calls share one shutdown: the second call completes when the first one does.
  Future<void> shutdown() => _shutdownFuture ??= _shutdown();

  Future<void> _shutdown() async {
    // Reject new client calls and stop the background GC before anything is closed, so nothing starts against a
    // closed database.
    _isShutdown = true;
    _lruScheduler?.stop();

    await onCredentialChangeSubscription.cancel();
    await appCheckProvider?.close();
    await remoteStore.shutdown();
    await persistence.shutdown();
  }

  /// Starts listening to a query. */
  Future<QueryStream> listen(Query query, ListenOptions options) async {
    _verifyNotShutdown();

    final QueryStream queryListener =
        QueryStream(query, options, stopListening);
    await _enqueue<int>(() => eventManager.addQueryListener(queryListener));
    return queryListener;
  }

  /// Stops listening to a query previously listened to.
  Future<void> stopListening(QueryStream listener) {
    // Removing a listener after the client was shut down is not an error (the listener is gone with the client).
    if (_isShutdown) {
      return Future<void>.value();
    }

    return _enqueue<bool>(() => eventManager.removeQueryListener(listener));
  }

  Future<Document?> getDocumentFromLocalCache(DocumentKey docKey) async {
    _verifyNotShutdown();

    final MaybeDocument? maybeDoc =
        await _enqueue<MaybeDocument?>(() => localStore.readDocument(docKey));

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
        await _enqueue<ImmutableSortedMap<DocumentKey, Document>>(
            () => localStore.executeQuery(query));

    final View view = View(query, ImmutableSortedSet<DocumentKey>());
    final ViewDocumentChanges viewDocChanges = view.computeDocChanges(docs);
    return view.applyChanges(viewDocChanges).snapshot!;
  }

  /// Loads the bundle read from [bundleData] into the local cache, reporting the progress to [resultTask].
  Future<void> loadBundle(
      Stream<List<int>> bundleData, LoadBundleTask resultTask) {
    _verifyNotShutdown();

    final BundleReader bundleReader = BundleReader(
        BundleSerializer(RemoteSerializer(databaseInfo.databaseId)),
        bundleData);
    return _enqueue<void>(
        () => syncEngine.loadBundle(bundleReader, resultTask));
  }

  /// Returns the named query saved by a loaded bundle under [queryName], or null if there is none.
  Future<Query?> getNamedQuery(String queryName) {
    _verifyNotShutdown();

    return _enqueue<Query?>(() async {
      final NamedQuery? namedQuery = await localStore.getNamedQuery(queryName);
      if (namedQuery == null) {
        return null;
      }
      return namedQuery.bundledQuery.toQuery();
    });
  }

  /// Writes mutations. The returned Future will be notified when it's written to the backend.
  Future<void> write(final List<Mutation> mutations) async {
    _verifyNotShutdown();

    final Completer<void> source = Completer<void>();
    await _enqueue<void>(() => syncEngine.writeMutations(mutations, source));
    await source.future;
  }

  /// Runs an aggregation over [query] on the server. Fails with an
  /// `unavailable` error when offline.
  Future<Map<String, FieldValue>> runAggregateQuery(
      Query query, List<AggregateField> aggregateFields) {
    _verifyNotShutdown();

    return _enqueue<Map<String, FieldValue>>(
        () => syncEngine.runAggregateQuery(query, aggregateFields));
  }

  /// Runs a vector query over [query] on the server. Fails with an
  /// `unavailable` error when offline.
  Future<List<Document>> runVectorQuery(Query query, VectorQuery vectorQuery) {
    _verifyNotShutdown();

    return _enqueue<List<Document>>(
        () => syncEngine.runVectorQuery(query, vectorQuery));
  }

  /// Executes the transaction in [updateFunction], with up to [maxAttempts] attempts (with a backoff in between).
  Future<TResult> transaction<TResult>(
      Future<TResult> Function(Transaction) updateFunction, int maxAttempts,
      {bool readOnly = false}) {
    _verifyNotShutdown();

    return TransactionRunner<TResult>(
      createTransaction: () => remoteStore.createTransaction(readOnly: readOnly),
      maxAttempts: maxAttempts,
      // A scheduler of its own: a [TaskScheduler] holds only one pending task per [TaskId], and transactions run
      // concurrently, each one waiting for its own backoff.
      backoff: ExponentialBackoff(
          TaskScheduler('transaction'), TaskId.retryTransaction),
      updateFunction: updateFunction,
    ).run();
  }

  Future<void> _initialize(
    User user,
    bool usePersistence,
    int cacheSizeBytes,
    OpenDatabase? openDatabase,
    BehaviorSubject<bool> onNetworkConnected,
    TaskScheduler scheduler, {
    MemoryGarbageCollectorSettings? memoryLruGcSettings,
  }) async {
    // Note: The initialization work must all be synchronous (we can't dispatch more work) since external write/listen
    // operations could get queued to run before that subsequent work completes.
    Log.d(logTag, 'Initializing. user=${user.uid}');

    LruGarbageCollector? gc;
    if (usePersistence && openDatabase != null) {
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
    } else if (memoryLruGcSettings is MemoryLruGcSettings) {
      final MemoryPersistence memoryPersistence =
          MemoryPersistence.createLruGcMemoryPersistence(
        LruGarbageCollectorParams.withCacheSizeBytes(
            memoryLruGcSettings.sizeBytes),
        LocalSerializer(RemoteSerializer(databaseInfo.databaseId)),
      );
      gc = (memoryPersistence.referenceDelegate as MemoryLruReferenceDelegate)
          .garbageCollector;
      persistence = memoryPersistence;
    } else {
      persistence = MemoryPersistence.createEagerGcMemoryPersistence();
    }

    await persistence.start();
    localStore = LocalStore(persistence, user);
    if (gc != null) {
      _lruScheduler = gc.newScheduler(scheduler, localStore) //
        ..start();
    }

    final Datastore datastore = Datastore(
        scheduler, databaseInfo, credentialsProvider,
        appCheckProvider: appCheckProvider);
    remoteStore = RemoteStore(
        this, localStore, datastore, onNetworkConnected, scheduler,
        queue: _queue);

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
  Future<void> handleRemoteEvent(RemoteEvent remoteEvent) {
    return _enqueue<void>(() => syncEngine.handleRemoteEvent(remoteEvent));
  }

  @override
  Future<void> handleRejectedListen(int targetId, GrpcError error) {
    return _enqueue<void>(
        () => syncEngine.handleRejectedListen(targetId, error));
  }

  @override
  Future<void> handleSuccessfulWrite(MutationBatchResult mutationBatchResult) {
    return _enqueue<void>(
        () => syncEngine.handleSuccessfulWrite(mutationBatchResult));
  }

  @override
  Future<void> handleRejectedWrite(int batchId, GrpcError error) {
    return _enqueue<void>(() => syncEngine.handleRejectedWrite(batchId, error));
  }

  @override
  Future<void> handleOnlineStateChange(OnlineState onlineState) {
    return _enqueue<void>(
        () => syncEngine.handleOnlineStateChange(onlineState));
  }

  @override
  ImmutableSortedSet<DocumentKey> Function(int targetId)
      get getRemoteKeysForTarget {
    return (int targetId) {
      return syncEngine.getRemoteKeysForTarget(targetId);
    };
  }
}
