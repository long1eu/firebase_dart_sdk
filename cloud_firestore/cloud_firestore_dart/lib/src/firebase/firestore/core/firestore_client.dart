// File created by
// Lung Razvan <long1eu>
// on 18/09/2018

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
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
import 'package:cloud_firestore_dart/src/firebase/firestore/local/index_backfiller.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/memory/memory_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/client_metadata_refresher.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local_cache_settings.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/no_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/connectivity_change_detector.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/datastore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_event.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/database.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/exponential_backoff.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/grpc_status.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/vector_query.dart';
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:firebase_app_dart/internal.dart';
import 'package:meta/meta.dart';
import 'package:rxdart/rxdart.dart';

/// [FirestoreClient] is a top-level class that constructs and owns all of the pieces of the client SDK architecture.
class FirestoreClient implements RemoteStoreCallback {
  FirestoreClient._(
    this.databaseInfo,
    this.credentialsProvider,
    this.appCheckProvider,
    this.supportsFieldIndexes,
  );

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

  /// Fills the field indexes in the background. Only with SQLite persistence: memory persistence has no field indexes.
  IndexBackfillerScheduler? _indexBackfillScheduler;
  IndexBackfiller? _indexBackfiller;

  /// Refreshes the client metadata and the primary lease. Only with SQLite persistence.
  ClientMetadataRefresher? _clientMetadataRefresher;

  /// Whether this client holds the primary lease of its cache. Always true with memory persistence. Only the primary
  /// client uses the network, collects garbage and backfills indexes; the clients of one cache share no other state
  /// yet (stage 1 of the multi-client plan).
  @visibleForTesting
  bool get isPrimaryClient {
    final Persistence persistence = this.persistence;
    return persistence is! SQLitePersistence || persistence.isPrimary;
  }

  /// Whether this client has field indexes: only with SQLite persistence. Known when the client is created, before
  /// the persistence is opened.
  final bool supportsFieldIndexes;

  /// Completes when the client is initialized: the first user is known, the persistence is open (and migrated) and
  /// the local and remote stores are started. Fails with the error of the initialization.
  late final Future<void> _initialized;

  /// The error the initialization failed with: every operation fails with it.
  Object? _initError;
  StackTrace? _initStackTrace;

  /// Whether [persistence] was started and [remoteStore] created, so that [shutdown] knows what to close after an
  /// initialization that failed half way.
  bool _persistenceStarted = false;
  bool _remoteStoreCreated = false;

  /// Waits for the initialization of the client (see [start]) and throws its error if it failed.
  Future<void> get initialized => _initialized;

  /// Creates a client and starts it [initialize]s, then returns once that is done (or throws its error).
  static Future<FirestoreClient> initialize(
    DatabaseInfo databaseInfo,
    FirestoreSettings settings,
    CredentialsProvider credentialsProvider,
    OpenDatabase? openDatabase,
    BehaviorSubject<bool> onNetworkConnected,
    TaskScheduler scheduler, {
    AppCheckTokenProvider? appCheckProvider,
    ConnectivityChangeDetector? connectivityDetector,
  }) async {
    final FirestoreClient client = start(
      databaseInfo,
      settings,
      credentialsProvider,
      openDatabase,
      onNetworkConnected,
      scheduler,
      appCheckProvider: appCheckProvider,
      connectivityDetector: connectivityDetector,
    );
    await client._initialized;
    return client;
  }

  /// Creates a client and returns it at once. The initialization (waiting for the first user of [credentialsProvider],
  /// opening the persistence, starting the stores) is the first task of the client's queue, so every operation runs
  /// after it, as in the Android and JS SDKs. If [after] is given, the initialization waits for it first (and ignores
  /// its error): the shutdown of another client that has the same persistence open.
  ///
  /// When the initialization fails, every operation fails with its error.
  static FirestoreClient start(
    DatabaseInfo databaseInfo,
    FirestoreSettings settings,
    CredentialsProvider credentialsProvider,
    OpenDatabase? openDatabase,
    BehaviorSubject<bool> onNetworkConnected,
    TaskScheduler scheduler, {
    AppCheckTokenProvider? appCheckProvider,
    ConnectivityChangeDetector? connectivityDetector,
    Future<void>? after,
  }) {
    final bool usePersistence =
        // TODO(long1eu): Make sure you remove the openDatabase != null once we
        //  provide a default way to instantiate a db instance
        settings.persistenceEnabled && openDatabase != null;
    final FirestoreClient client = FirestoreClient._(
      databaseInfo,
      credentialsProvider,
      appCheckProvider,
      usePersistence,
    );

    final Completer<User> firstUser = Completer<User>();
    bool initialized = false;
    // Completes once the client is fully initialized. Credential changes that
    // arrive earlier are queued behind it (the Android SDK gets this for free
    // because the change handler runs on the worker queue).
    final Completer<void> initDone = Completer<void>();

    client
        .onCredentialChangeSubscription = credentialsProvider.onChange.listen((
      User user,
    ) {
      if (initialized == false) {
        initialized = true;
        hardAssert(!firstUser.isCompleted, 'Already fulfilled first user task');
        firstUser.complete(user);
      } else {
        // Wait for the initialization outside of the queue: the initialization itself runs on the queue. The change
        // is a retryable operation that queues itself (as the JS credential providers call `enqueueRetryable`).
        initDone.future.then<void>((_) {
          if (client._isShutdown) {
            return;
          }
          Log.d(logTag, 'Credential changed. Current user: ${user.uid}');
          client.syncEngine.handleCredentialChange(user);
        });
      }
    });

    // The first task of the queue: every operation is queued behind it. An initialization that fails is an expected
    // error (a cache that can not be opened): the task settles [_initialized] itself.
    final Completer<void> initialization = Completer<void>();
    client._initialized = initialization.future;
    client._queue.run<void>(() async {
      try {
        if (after != null) {
          await after.then<void>((_) {}, onError: (Object _) {});
        }
        final User user = await firstUser.future;
        await client._initialize(
          user,
          usePersistence,
          settings.cacheSizeBytes,
          openDatabase,
          onNetworkConnected,
          scheduler,
          connectivityDetector: connectivityDetector,
          memoryLruGcSettings: switch (settings.cacheSettings) {
            final MemoryCacheSettings memory => memory.gcSettings,
            _ => null,
          },
        );
        initialization.complete();
      } catch (error, stackTrace) {
        initialization.completeError(error, stackTrace);
      }
    });
    client._initialized.then<void>(
      (_) => initDone.complete(),
      onError: (Object error, StackTrace stackTrace) {
        client._initError = error;
        client._initStackTrace = stackTrace;
        Log.w(logTag, 'Initializing the client failed: $error');
      },
    );
    return client;
  }

  /// PORTING NOTE: the Android SDK runs every client operation, and every callback of the remote store, on a single
  /// worker queue, so an operation always observes the effects of the operations that were requested before it. This
  /// queue plays that role; it is shared with the [RemoteStore].
  final SerialQueue _queue = SerialQueue();

  /// The queue of this client, for tests.
  @visibleForTesting
  SerialQueue get queue => _queue;

  /// Runs [task] on the queue, after the initialization. Fails with the error of the initialization if that failed.
  ///
  /// The operation on the queue settles the returned future itself, with the result or the error of [task] (the JS
  /// operations do that with a `Deferred`): the error of a client operation is for its caller and never leaves the
  /// operation on the queue.
  ///
  /// The initialization future is awaited rather than [_initError] read: a task that was queued while the
  /// initialization ran starts before the listener that records the error (the queue listens to the future first),
  /// and would otherwise run against a client whose stores were never created.
  Future<T> _enqueue<T>(Future<T> Function() task) {
    final Completer<T> result = Completer<T>();
    _queue.run<void>(() async {
      try {
        final Object? initError = _initError;
        if (initError != null) {
          Error.throwWithStackTrace(initError, _initStackTrace!);
        }
        await _initialized;
        result.complete(await task());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  /// Returns a future that completes when all the writes that are pending right now were acknowledged (or rejected)
  /// by the backend.
  Future<void> waitForPendingWrites() async {
    _verifyNotShutdown();

    final Completer<void> source = Completer<void>();
    unawaited(
      _enqueue<void>(
        () => syncEngine.registerPendingWritesTask(source),
      ).catchError((Object error, StackTrace stackTrace) {
        if (!source.isCompleted) {
          source.completeError(error, stackTrace);
        }
      }),
    );
    return source.future;
  }

  /// Adds a listener that is called whenever all the snapshot listeners are in sync with each other (and once right
  /// away).
  Future<void> addSnapshotsInSyncListener(void Function() listener) async {
    _verifyNotShutdown();
    return _enqueue<void>(
      () async => eventManager.addSnapshotsInSyncListener(listener),
    );
  }

  /// Removes a listener that was added with [addSnapshotsInSyncListener]. A no-op after the client was shut down.
  Future<void> removeSnapshotsInSyncListener(void Function() listener) {
    if (_isShutdown) {
      return Future<void>.value();
    }
    return _enqueue<void>(
      () async => eventManager.removeSnapshotsInSyncListener(listener),
    );
  }

  Future<void> disableNetwork() async {
    _verifyNotShutdown();
    return _enqueue<void>(() async {
      await remoteStore.disableNetwork();
      await _setPersistenceNetworkEnabled(false);
    });
  }

  Future<void> enableNetwork() async {
    _verifyNotShutdown();
    return _enqueue<void>(() async {
      await remoteStore.enableNetwork();
      await _setPersistenceNetworkEnabled(true);
    });
  }

  /// Shuts down this client, cancels all writes / listeners, and releases all resources.
  ///
  /// Concurrent calls share one shutdown: the second call completes when the first one does.
  Future<void> shutdown() => _shutdownFuture ??= _shutdown();

  Future<void> _shutdown() async {
    // Reject new client calls and stop the background GC before anything is closed, so nothing starts against a
    // closed database.
    _isShutdown = true;
    // An initialization that is still running (the instance was terminated right after it was created) finishes
    // first: it may already have opened the persistence, and clearPersistence needs to know the file it opened.
    try {
      await _initialized;
    } catch (_) {
      // Close what the failed initialization opened.
    }
    _lruScheduler?.stop();
    _indexBackfillScheduler?.stop();
    _clientMetadataRefresher?.stop();

    await onCredentialChangeSubscription.cancel();
    await appCheckProvider?.close();
    if (_remoteStoreCreated) {
      await remoteStore.shutdown();
    }
    if (_persistenceStarted) {
      await persistence.shutdown();
    }
  }

  /// Whether [shutdown] was called on this client.
  bool get isTerminated => _isShutdown;

  /// Deletes the local persistence files of this client. Only allowed after
  /// [shutdown]; a no-op for memory persistence.
  ///
  /// Throws a [FirestoreError] with [FirestoreErrorCode.failedPrecondition]
  /// while the client is running, and one with [FirestoreErrorCode.unknown]
  /// when a file can't be deleted (like upstream).
  Future<void> clearPersistence() async {
    if (!_isShutdown) {
      throw FirestoreError(
        'Persistence cannot be cleared while the firestore instance is running.',
        FirestoreErrorCode.failedPrecondition,
      );
    }
    // The database has to be closed before its files go away.
    await _shutdownFuture;
    if (!_persistenceStarted) {
      // The initialization failed before the persistence was opened: there is no file this client knows of.
      return;
    }
    final Persistence persistence = this.persistence;
    if (persistence is SQLitePersistence) {
      await persistence.clearPersistence();
    }
  }

  /// Starts listening to a query. */
  Future<QueryStream> listen(Query query, ListenOptions options) async {
    _verifyNotShutdown();

    final QueryStream queryListener = QueryStream(
      query,
      options,
      stopListening,
    );
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

    // As the JS `readDocumentFromCache`: the error of the read is turned into the error of the user on the queue.
    final MaybeDocument? maybeDoc = await _enqueue<MaybeDocument?>(
      () => _userErrorIfRecoverable(
        localStore.readDocument(docKey),
        'Failed to get document \'${docKey.path}\' from cache',
      ),
    );

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

  /// Fails with an `unavailable` [FirestoreError] when [future] fails because the persistence is not available (the JS
  /// `wrapInUserErrorIfRecoverable`).
  static Future<T> _userErrorIfRecoverable<T>(
    Future<T> future,
    String message,
  ) {
    return future.catchError(
      (Object error) => throw FirestoreError(
        '$message: $error',
        FirestoreErrorCode.unavailable,
      ),
      test: isRecoverablePersistenceError,
    );
  }

  Future<ViewSnapshot> getDocumentsFromLocalCache(Query query) async {
    _verifyNotShutdown();

    // As the JS `executeQueryFromCache`.
    final QueryResult queryResult = await _enqueue<QueryResult>(
      () => _userErrorIfRecoverable(
        localStore.executeQuery(query, /* usePreviousResults= */ true),
        'Failed to execute query \'$query\' against cache',
      ),
    );

    final View view = View(query, queryResult.remoteKeys);
    final ViewDocumentChanges viewDocChanges = view.computeDocChanges(
      queryResult.documents,
    );
    return view.applyChanges(viewDocChanges).snapshot!;
  }

  /// Loads the bundle read from [bundleData] into the local cache, reporting the progress to [resultTask].
  Future<void> loadBundle(
    Stream<List<int>> bundleData,
    LoadBundleTask resultTask,
  ) async {
    _verifyNotShutdown();

    final BundleReader bundleReader = BundleReader(
      BundleSerializer(RemoteSerializer(databaseInfo.databaseId)),
      bundleData,
    );
    return _enqueue<void>(
      () => syncEngine.loadBundle(bundleReader, resultTask),
    );
  }

  /// Makes [fieldIndexes] the configured field indexes, see [LocalStore.configureFieldIndexes].
  Future<void> configureFieldIndexes(List<FieldIndex> fieldIndexes) async {
    _verifyNotShutdown();
    return _enqueue<void>(() => localStore.configureFieldIndexes(fieldIndexes));
  }

  /// Turns the automatic creation of field indexes on or off.
  Future<void> setIndexAutoCreationEnabled({required bool enabled}) async {
    _verifyNotShutdown();
    return _enqueue<void>(
      () async => localStore.indexAutoCreationEnabled = enabled,
    );
  }

  /// Removes all field indexes and their entries.
  Future<void> deleteAllFieldIndexes() async {
    _verifyNotShutdown();
    return _enqueue<void>(() => localStore.deleteAllFieldIndexes());
  }

  /// Runs one index backfill now, without waiting for the scheduled one, and returns the number of documents that
  /// were processed (at most 50 per run; 0 when the indexes are up to date or the client has no field indexes).
  @visibleForTesting
  Future<int> backfillIndexes() async {
    _verifyNotShutdown();
    return _enqueue<int>(() async {
      final IndexBackfiller? backfiller = _indexBackfiller;
      if (backfiller == null) {
        return 0;
      }
      try {
        return await backfiller.backfill();
      } on FirestoreError catch (e) {
        // Only the primary client of the cache backfills.
        if (isPrimaryLeaseLoss(e)) {
          return 0;
        }
        rethrow;
      }
    });
  }

  /// Returns the named query saved by a loaded bundle under [queryName], or null if there is none.
  Future<Query?> getNamedQuery(String queryName) async {
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

    // As firestoreClientWrite in the JS SDK: the caller listens to the future of the write from the start. The sync
    // engine can fail it while the queued task is still running (a mutation that could not be stored), and awaiting
    // the task first would leave that error without a listener.
    final Completer<void> source = Completer<void>();
    unawaited(
      _enqueue<void>(
        () => syncEngine.writeMutations(mutations, source),
      ).catchError((Object error, StackTrace stackTrace) {
        if (!source.isCompleted) {
          source.completeError(error, stackTrace);
        }
      }),
    );
    return source.future;
  }

  /// Runs an aggregation over [query] on the server. Fails with an
  /// `unavailable` error when offline.
  Future<Map<String, FieldValue>> runAggregateQuery(
    Query query,
    List<AggregateField> aggregateFields,
  ) async {
    _verifyNotShutdown();

    return _enqueue<Map<String, FieldValue>>(
      () => syncEngine.runAggregateQuery(query, aggregateFields),
    );
  }

  /// Runs a vector query over [query] on the server. Fails with an
  /// `unavailable` error when offline.
  Future<List<Document>> runVectorQuery(
    Query query,
    VectorQuery vectorQuery,
  ) async {
    _verifyNotShutdown();

    return _enqueue<List<Document>>(
      () => syncEngine.runVectorQuery(query, vectorQuery),
    );
  }

  /// Executes a pipeline on the server. Fails with an `unavailable` error when
  /// offline.
  Future<List<proto.ExecutePipelineResponse>> executePipeline(
    proto.ExecutePipelineRequest request,
  ) async {
    _verifyNotShutdown();

    return _enqueue<List<proto.ExecutePipelineResponse>>(
      () => remoteStore.executePipeline(request),
    );
  }

  /// Executes the transaction in [updateFunction], with up to [maxAttempts] attempts (with a backoff in between).
  Future<TResult> transaction<TResult>(
    Future<TResult> Function(Transaction) updateFunction,
    int maxAttempts, {
    bool readOnly = false,
    SnapshotVersion? readTime,
  }) async {
    _verifyNotShutdown();
    // The runner calls the remote store outside the queue: it has to exist.
    await _initialized;

    return TransactionRunner<TResult>(
      createTransaction: () =>
          remoteStore.createTransaction(readOnly: readOnly, readTime: readTime),
      maxAttempts: maxAttempts,
      // A scheduler of its own: a [TaskScheduler] holds only one pending task per [TaskId], and transactions run
      // concurrently, each one waiting for its own backoff.
      backoff: ExponentialBackoff(
        TaskScheduler('transaction'),
        TaskId.retryTransaction,
      ),
      updateFunction: updateFunction,
      isTerminated: () => _isShutdown,
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
    ConnectivityChangeDetector? connectivityDetector,
  }) async {
    // Note: The initialization work must all be synchronous (we can't dispatch more work) since external write/listen
    // operations could get queued to run before that subsequent work completes.
    Log.d(logTag, 'Initializing. user=${user.uid}');

    LruGarbageCollector? gc;
    if (usePersistence && openDatabase != null) {
      final LocalSerializer serializer = LocalSerializer(
        RemoteSerializer(databaseInfo.databaseId),
      );
      final LruGarbageCollectorParams params =
          LruGarbageCollectorParams.withCacheSizeBytes(cacheSizeBytes);

      final SQLitePersistence persistence = await SQLitePersistence.create(
        databaseInfo.persistenceKey,
        databaseInfo.databaseId,
        serializer,
        openDatabase,
        params,
      );

      final SQLiteLruReferenceDelegate lruDelegate =
          persistence.referenceDelegate;
      gc = lruDelegate.garbageCollector;
      this.persistence = persistence;
    } else if (memoryLruGcSettings is MemoryLruGcSettings) {
      final MemoryPersistence memoryPersistence =
          MemoryPersistence.createLruGcMemoryPersistence(
            LruGarbageCollectorParams.withCacheSizeBytes(
              memoryLruGcSettings.sizeBytes,
            ),
            LocalSerializer(RemoteSerializer(databaseInfo.databaseId)),
          );
      gc = (memoryPersistence.referenceDelegate as MemoryLruReferenceDelegate)
          .garbageCollector;
      persistence = memoryPersistence;
    } else {
      persistence = MemoryPersistence.createEagerGcMemoryPersistence();
    }

    await persistence.start();
    _persistenceStarted = true;
    localStore = LocalStore(persistence, user);
    if (gc != null) {
      _lruScheduler =
          gc.newScheduler(scheduler, localStore) //
            ..start();
    }
    final Persistence started = persistence;
    if (started is SQLitePersistence) {
      final IndexBackfiller indexBackfiller = _indexBackfiller =
          IndexBackfiller(started, localStore);
      _indexBackfillScheduler = IndexBackfillerScheduler(
        indexBackfiller,
        scheduler,
        // On the queue of the client, like every other operation of the local store.
        run: (Future<int> Function() backfill) =>
            _enqueue<int>(() async => _isShutdown ? 0 : await backfill()),
      )..start();
      // Another client that clears the cache while this one runs ends this one, as in the JS SDK.
      started.databaseClearedListener = () => shutdown();
      _clientMetadataRefresher = ClientMetadataRefresher(
        scheduler,
        run: () => _enqueue<void>(() async {
          if (!_isShutdown) {
            await started.refreshClientMetadata();
            await syncEngine.handleClientMetadataRefresh();
          }
        }),
      )..start();
    }

    final Datastore datastore = Datastore(
      scheduler,
      databaseInfo,
      credentialsProvider,
      appCheckProvider: appCheckProvider,
    );
    remoteStore = RemoteStore(
      this,
      localStore,
      datastore,
      onNetworkConnected,
      scheduler,
      queue: _queue,
      connectivityDetector: connectivityDetector,
    );
    _remoteStoreCreated = true;

    syncEngine = SyncEngine(localStore, remoteStore, user);
    eventManager = EventManager(syncEngine);

    // NOTE: RemoteStore depends on LocalStore (for persisting stream tokens,
    // refilling mutation queue, etc.) so must be started after LocalStore.
    await localStore.start();
    await remoteStore.start();

    // Called right away with the current state; a lone client is always primary, and nothing changes then.
    persistence.setPrimaryStateListener((bool isPrimary) {
      // Called inside a transaction of the persistence: the work is queued behind the task that is running. A
      // retryable operation, as in JS: it is retried while the persistence fails.
      remoteStore
          .enqueueRetryable(() => _applyPrimaryState(isPrimary))
          .catchError((Object error) {
            Log.w(
              logTag,
              'Applying the primary state $isPrimary failed: $error',
            );
          });
    });
  }

  /// Only the primary client of a cache uses the network, collects garbage and backfills indexes
  /// (`setPrimaryStateListener` in the `MultiTabOfflineComponentProvider` of the JS SDK).
  Future<void> _applyPrimaryState(bool isPrimary) async {
    if (_isShutdown) {
      return;
    }
    await syncEngine.applyPrimaryState(isPrimary);
    if (isPrimary) {
      _lruScheduler?.start();
      _indexBackfillScheduler?.start();
    } else {
      _lruScheduler?.stop();
      _indexBackfillScheduler?.stop();
    }
  }

  /// A client without network gives the primary lease to a client with network (as in the JS SDK).
  Future<void> _setPersistenceNetworkEnabled(bool enabled) async {
    final Persistence persistence = this.persistence;
    if (persistence is SQLitePersistence) {
      await persistence.setNetworkEnabled(enabled);
    }
  }

  /// Throws the error of a terminated client, see [_verifyNotShutdown]. For the entry points of `Firestore` that
  /// check something else before they reach the client.
  void verifyNotTerminated() => _verifyNotShutdown();

  /// Throws the error every client call fails with once [shutdown] was called: a [FirestoreError] with
  /// [FirestoreErrorCode.failedPrecondition], as the JS SDK (Android throws an IllegalStateException with the same
  /// message). The methods that call it are `async`, so callers get it through the returned future.
  void _verifyNotShutdown() {
    if (_isShutdown) {
      throw FirestoreError(
        terminatedMessage,
        FirestoreErrorCode.failedPrecondition,
      );
    }
  }

  /// The message of the error for a call on a terminated client.
  static const String terminatedMessage =
      'The client has already been terminated.';

  // The callbacks of the remote store run on the queue already (they are the JS `remoteSyncer`): they call the sync
  // engine directly.

  @override
  Future<void> handleRemoteEvent(RemoteEvent remoteEvent) =>
      syncEngine.handleRemoteEvent(remoteEvent);

  @override
  Future<void> handleRejectedListen(int targetId, GrpcError error) =>
      syncEngine.handleRejectedListen(targetId, error);

  @override
  Future<void> handleSuccessfulWrite(MutationBatchResult mutationBatchResult) =>
      syncEngine.handleSuccessfulWrite(mutationBatchResult);

  @override
  Future<void> handleRejectedWrite(int batchId, GrpcError error) =>
      syncEngine.handleRejectedWrite(batchId, error);

  @override
  Future<void> handleOnlineStateChange(OnlineState onlineState) =>
      syncEngine.handleOnlineStateChange(onlineState);

  @override
  ImmutableSortedSet<DocumentKey> Function(int targetId)
  get getRemoteKeysForTarget {
    return (int targetId) {
      return syncEngine.getRemoteKeysForTarget(targetId);
    };
  }
}
