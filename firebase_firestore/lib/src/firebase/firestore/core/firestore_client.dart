// File created by
// Lung Razvan <long1eu>
// on 18/09/2018

import 'dart:async';

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_database_collection/firebase_database_collection.dart';
import 'package:firebase_firestore/firebase_firestore.dart';
import 'package:firebase_firestore/src/firebase/firestore/auth/credentials_provider.dart';
import 'package:firebase_firestore/src/firebase/firestore/auth/user.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/database_info.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/event_manager.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/online_state.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query_listener.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/sync_engine.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/transaction.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/view.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/view_snapshot.dart';
import 'package:firebase_firestore/src/firebase/firestore/firebase_firestore_error.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/local_serializer.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/local_store.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/memory_persistence.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/persistence.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/sqlite_persistence.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/maybe_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation_batch_result.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/no_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/datastore.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/remote_event.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/remote_store.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/async_queue.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/types.dart'
    hide Transaction;
import 'package:grpc/grpc.dart';

/// [FirestoreClient] is a top-level class that constructs and owns all of the
/// pieces of the client SDK architecture.
class FirestoreClient implements RemoteStoreCallback {
  static const String logTag = 'FirestoreClient';

  final DatabaseInfo databaseInfo;
  final CredentialsProvider credentialsProvider;
  final AsyncQueue asyncQueue;

  Persistence persistence;
  LocalStore localStore;
  RemoteStore remoteStore;
  SyncEngine syncEngine;
  EventManager eventManager;

  FirestoreClient(this.databaseInfo, final bool usePersistence,
      this.credentialsProvider, this.asyncQueue) {
    final Completer<User> firstUser = Completer<User>();
    bool initialized = false;
    credentialsProvider.setChangeListener((User user) {
      if (initialized == false) {
        initialized = true;
        Assert.hardAssert(
            !firstUser.isCompleted, 'Already fulfilled first user task');
        firstUser.complete(user);
      } else {
        asyncQueue.enqueueAndForget(() async {
          Log.d(logTag, 'Credential changed. Current user: ${user.uid}');
          syncEngine.handleCredentialChange(user);
        });
      }
    });

    // todo move this to a static method
    // Defer initialization until we get the current user from the changeListener. This is
    // guaranteed to be synchronously dispatched onto our worker queue, so we will be initialized
    // before any subsequently queued work runs.
    asyncQueue.enqueueAndForget(() async {
      // Block on initial user being available
      final User initialUser = await firstUser.future;
      await _initialize(initialUser, usePersistence);
    });
  }

  Future<void> disableNetwork() {
    return asyncQueue.enqueue(() async {
      remoteStore.disableNetwork();
    });
  }

  Future<void> enableNetwork() {
    return asyncQueue.enqueue(() => remoteStore.enableNetwork());
  }

  /// Shuts down this client, cancels all writes / listeners, and releases all
  /// resources.
  Future<void> shutdown() {
    credentialsProvider.removeChangeListener();
    return asyncQueue.enqueue(() async {
      remoteStore.shutdown();
      persistence.shutdown();
    });
  }

  /// Starts listening to a query. */
  QueryListener listen(Query query, ListenOptions options,
      EventListener<ViewSnapshot> listener) {
    final QueryListener queryListener = QueryListener(query, options, listener);
    asyncQueue
        .enqueueAndForget(() => eventManager.addQueryListener(queryListener));
    return queryListener;
  }

  /// Stops listening to a query previously listened to.
  void stopListening(QueryListener listener) {
    asyncQueue.enqueueAndForget(
        () async => eventManager.removeQueryListener(listener));
  }

  Future<Document> getDocumentFromLocalCache(DocumentKey docKey) {
    return asyncQueue
        .enqueue(() => localStore.readDocument(docKey))
        .then((MaybeDocument result) {
      final MaybeDocument maybeDoc = result;

      if (maybeDoc is Document) {
        return maybeDoc;
      } else if (maybeDoc is NoDocument) {
        return null;
      } else {
        throw FirebaseFirestoreError(
            'Failed to get document from cache. (However, this document may '
            'exist on the server. Run again without setting source to CACHE to '
            'attempt to retrieve the document from the server.)',
            FirebaseFirestoreErrorCode.unavailable);
      }
    });
  }

  Future<ViewSnapshot> getDocumentsFromLocalCache(Query query) {
    return asyncQueue.enqueue(() async {
      final ImmutableSortedMap<DocumentKey, Document> docs =
          await localStore.executeQuery(query);

      final View view = View(query, ImmutableSortedSet<DocumentKey>());
      final DocumentChanges viewDocChanges = view.computeDocChanges(docs);
      return view.applyChanges(viewDocChanges).snapshot;
    });
  }

  /// Writes mutations. The returned Future will be notified when it's written
  /// to the backend.
  Future<void> write(final List<Mutation> mutations) {
    final Completer<void> source = Completer<void>();
    asyncQueue
        .enqueueAndForget(() => syncEngine.writeMutations(mutations, source));
    return source.future;
  }

  /// Tries to execute the transaction in updateFunction up to retries times. */
  Future<TResult> transaction<TResult>(
      Future<TResult> Function(Transaction) updateFunction, int retries) {
    return AsyncQueue.callTask(asyncQueue.executor,
        () => syncEngine.transaction(asyncQueue, updateFunction, retries));
  }

  Future<void> _initialize(User user, bool usePersistence) async {
    // Note: The initialization work must all be synchronous (we can't dispatch
    // more work) since external write/listen operations could get queued to run
    // before that subsequent work completes.
    Log.d(logTag, 'Initializing. user=${user.uid}');

    if (usePersistence) {
      final LocalSerializer serializer =
          LocalSerializer(RemoteSerializer(databaseInfo.databaseId));

      persistence = await SQLitePersistence.create(
        databaseInfo.persistenceKey,
        databaseInfo.databaseId,
        serializer,
      );
    } else {
      persistence = MemoryPersistence.createEagerGcMemoryPersistence();
    }

    persistence.start();
    localStore = LocalStore(persistence, user);

    final Datastore datastore =
        Datastore(databaseInfo, asyncQueue, credentialsProvider);
    remoteStore = RemoteStore(this, localStore, datastore, asyncQueue);

    syncEngine = SyncEngine(localStore, remoteStore, user);
    eventManager = EventManager(syncEngine);

    // NOTE: RemoteStore depends on LocalStore (for persisting stream tokens, refilling mutation
    // queue, etc.) so must be started after LocalStore.
    localStore.start();
    remoteStore.start();
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
  void handleOnlineStateChange(OnlineState onlineState) {
    syncEngine.handleOnlineStateChange(onlineState);
    eventManager.handleOnlineStateChange(onlineState);
  }

  @override
  ImmutableSortedSet<DocumentKey> Function(int targetId)
      get getRemoteKeysForTarget => (int targetId) {
            return syncEngine.getRemoteKeysForTarget(targetId);
          };
}
