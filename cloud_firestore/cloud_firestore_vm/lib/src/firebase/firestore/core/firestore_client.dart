// File created by
// Lung Razvan <long1eu>
// on 18/09/2018

import 'dart:async';

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/auth/credentials_provider.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/component_provider.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/database_info.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/event_manager.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/memory_component_provider.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/query_stream.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/sqlite_component_provider.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/sync_engine.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/transaction.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/view.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/view_snapshot.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore_settings.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/garbage_collection_scheduler.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistence/persistence.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/query_result.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/no_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/datastore.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/firebase_client_grpc_metadata_provider.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/remote_store.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/async_task.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/database.dart';
import 'package:rxdart/rxdart.dart';

/// [FirestoreClient] is a top-level class that constructs and owns all of the pieces of the client SDK architecture.
class FirestoreClient {
  FirestoreClient._(this.databaseInfo, this.credentialsProvider);

  static const String logTag = 'FirestoreClient';
  static const int _kMaxConcurrentLimboResolutions = 100;

  final DatabaseInfo databaseInfo;
  final CredentialsProvider credentialsProvider;

  AsyncQueue asyncQueue;
  StreamSubscription<User> onCredentialChangeSubscription;
  Persistence persistence;
  LocalStore localStore;
  RemoteStore remoteStore;
  SyncEngine syncEngine;
  EventManager eventManager;

  GarbageCollectionScheduler _gcScheduler;

  static Future<FirestoreClient> initialize(
    DatabaseInfo databaseInfo,
    FirestoreSettings settings,
    CredentialsProvider credentialsProvider,
    OpenDatabase openDatabase,
    BehaviorSubject<bool> onNetworkConnected,
    AsyncQueue scheduler,
    GrpcMetadataProvider metadataProvider,
  ) async {
    final FirestoreClient client = FirestoreClient._(databaseInfo, credentialsProvider);

    final Completer<User> firstUser = Completer<User>();
    bool initialized = false;

    await scheduler.enqueue(() async {
      final User user = await firstUser.future;
      await client._initialize(
        user,
        settings,
        openDatabase,
        onNetworkConnected,
        scheduler,
        metadataProvider,
      );
    });

    client.onCredentialChangeSubscription = credentialsProvider.onChange.listen((User user) {
      if (initialized == false) {
        initialized = true;
        hardAssert(!firstUser.isCompleted, 'Already fulfilled first user task');
        firstUser.complete(user);
      } else {
        Log.d(logTag, 'Credential changed. Current user: ${user.uid}');
        client.syncEngine.handleCredentialChange(user);
      }
    });

    return client;
  }

  Future<void> disableNetwork() {
    _verifyNotTerminated();
    return asyncQueue.enqueue(() => remoteStore.disableNetwork());
  }

  Future<void> enableNetwork() {
    _verifyNotTerminated();
    return asyncQueue.enqueue(() => remoteStore.enableNetwork());
  }

  /// Shuts down this client, cancels all writes / listeners, and releases all resources.
  Future<void> terminate() async {
    if (isTerminated) {
      return;
    }

    await onCredentialChangeSubscription.cancel();

    await asyncQueue.enqueueAndInitiateShutdown(() async {
      await remoteStore.shutdown();
      await persistence.shutdown();
      _gcScheduler?.stop();
    });
  }

  /// Returns true if this client has been terminated.
  bool get isTerminated {
    // Technically, the asyncQueue is still running, but only accepting tasks related to shutdown
    // or supposed to be run after shutdown. It is effectively shut down to the eyes of users.
    return asyncQueue.isShuttingDown;
  }

  /// Starts listening to a query. */
  Future<QueryStream> listen(Query query, ListenOptions options) async {
    _verifyNotTerminated();

    final QueryStream queryListener = QueryStream(query, options, stopListening);
    asyncQueue.enqueueAndForget(() => eventManager.addQueryListener(queryListener));
    return queryListener;
  }

  /// Stops listening to a query previously listened to.
  void stopListening(QueryStream listener) {
    // Checks for terminate but does not raise error, allowing it to be a no-op if client is already
    // terminated.
    if (isTerminated) {
      return;
    }
    asyncQueue.enqueueAndForget(() => eventManager.removeQueryListener(listener));
  }

  Future<Document> getDocumentFromLocalCache(DocumentKey docKey) async {
    _verifyNotTerminated();

    final MaybeDocument maybeDoc = await asyncQueue.enqueue(() => localStore.readDocument(docKey));

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
    _verifyNotTerminated();
    return asyncQueue.enqueue(() async {
      final QueryResult queryResult = await localStore.executeQuery(query, /* usePreviousResults= */ true);
      final View view = View(query, queryResult.remoteKeys);
      final ViewDocumentChanges viewDocChanges = view.computeDocChanges(queryResult.documents);
      return view.applyChanges(viewDocChanges).snapshot;
    });
  }

  /// Writes mutations. The returned Future will be notified when it's written to the backend.
  Future<void> write(final List<Mutation> mutations) async {
    _verifyNotTerminated();

    final Completer<void> source = Completer<void>();
    asyncQueue.enqueueAndForget(() => syncEngine.writeMutations(mutations, source));
    await source.future;
  }

  /// Tries to execute the transaction in transaction.
  Future<TResult> transaction<TResult>(Future<TResult> Function(Transaction) updateFunction) {
    _verifyNotTerminated();
    return asyncQueue.enqueue(() => syncEngine.transaction(asyncQueue, updateFunction));
  }

  /// Returns a task resolves when all the pending writes at the time when this method is called
  /// received server acknowledgement. An acknowledgement can be either acceptance or rejections.
  Future<void> waitForPendingWrites() {
    _verifyNotTerminated();

    final Completer<void> source = Completer<void>();
    asyncQueue.enqueueAndForget(() => syncEngine.registerPendingWritesTask(source));
    return source.future;
  }

  Future<void> _initialize(
    User user,
    FirestoreSettings settings,
    OpenDatabase openDatabase,
    BehaviorSubject<bool> onNetworkConnected,
    AsyncQueue asyncQueue,
    GrpcMetadataProvider metadataProvider,
  ) async {
    // Note: The initialization work must all be synchronous (we can't dispatch more work) since external write/listen
    // operations could get queued to run before that subsequent work completes.
    Log.d(logTag, 'Initializing. user=${user.uid}');
    final Datastore datastore = Datastore(
      databaseInfo: databaseInfo,
      workerQueue: asyncQueue,
      credentialsProvider: credentialsProvider,
      metadataProvider: metadataProvider,
    );

    final ComponentProviderConfiguration configuration = ComponentProviderConfiguration(
      asyncQueue: asyncQueue,
      databaseInfo: databaseInfo,
      datastore: datastore,
      initialUser: user,
      maxConcurrentLimboResolutions: _kMaxConcurrentLimboResolutions,
      settings: settings,
      onNetworkConnected: onNetworkConnected,
      openDatabase: openDatabase,
    );

    final ComponentProvider provider =
        settings.persistenceEnabled ? SQLiteComponentProvider() : MemoryComponentProvider();

    await provider.initialize(configuration);
    persistence = provider.persistence;
    _gcScheduler = provider.gargabeCollectionScheduler;
    localStore = provider.localStore;
    remoteStore = provider.remoteStore;
    syncEngine = provider.syncEngine;
    eventManager = provider.eventManager;
    _gcScheduler?.start();
  }

  Stream<void> get snapshotsInSync {
    _verifyNotTerminated();
    return eventManager.snapshotsInSync;
  }

  void _verifyNotTerminated() {
    if (isTerminated) {
      throw ArgumentError('The client has already been shutdown');
    }
  }
}
