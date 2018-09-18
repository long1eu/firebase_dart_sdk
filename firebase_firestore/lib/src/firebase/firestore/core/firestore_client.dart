// File created by
// Lung Razvan <long1eu>
// on 18/09/2018

import 'package:firebase_firestore/firebase_firestore.dart';
import 'package:firebase_firestore/src/firebase/firestore/auth/credentials_provider.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/database_info.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/event_manager.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query_listener.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/view_snapshot.dart';
import 'package:firebase_firestore/src/firebase/firestore/event_listener.dart';
import 'package:firebase_firestore/src/firebase/firestore/firebase_firestore_error.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/maybe_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/no_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/remote_state.dart';
import 'package:grpc/grpc.dart';

/**
 * FirestoreClient is a top-level class that constructs and owns all of the pieces of the client SDK
 * architecture.
 */
class FirestoreClient implements RemoteStoreCallback {

  static const String logTag = "FirestoreClient";

  final DatabaseInfo databaseInfo;
  final CredentialsProvider credentialsProvider;
  final AsyncQueue asyncQueue;

  Persistence persistence;
  LocalStore localStore;
  RemoteStore remoteStore;
  SyncEngine syncEngine;
  EventManager eventManager;

  FirestoreClient(

      DatabaseInfo databaseInfo,
      final bool usePersistence,
      CredentialsProvider credentialsProvider,
      final AsyncQueue asyncQueue) {
    this.databaseInfo = databaseInfo;
    this.credentialsProvider = credentialsProvider;
    this.asyncQueue = asyncQueue;

    TaskCompletionSource<User> firstUser = new TaskCompletionSource<>();
    final AtomicBoolean initialized = new AtomicBoolean(false);
    credentialsProvider.setChangeListener(
        (User user) -> {
          if (initialized.compareAndSet(false, true)) {
            hardAssert(!firstUser.getTask().isComplete(), "Already fulfilled first user task");
            firstUser.setResult(user);
          } else {
            asyncQueue.enqueueAndForget(
                () -> {
                  Logger.debug(LOG_TAG, "Credential changed. Current user: %s", user.getUid());
                  syncEngine.handleCredentialChange(user);
                });
          }
        });

    // Defer initialization until we get the current user from the changeListener. This is
    // guaranteed to be synchronously dispatched onto our worker queue, so we will be initialized
    // before any subsequently queued work runs.
    asyncQueue.enqueueAndForget(
        () -> {
          try {
            // Block on initial user being available
            User initialUser = Tasks.await(firstUser.getTask());
            initialize(context, initialUser, usePersistence);
          } catch (InterruptedException | ExecutionException e) {
            throw new RuntimeException(e);
          }
        });
  }

  Future<void> disableNetwork() {
    return asyncQueue.enqueue(() => remoteStore.disableNetwork());
  }

  Future<void> enableNetwork() {
    return asyncQueue.enqueue(() => remoteStore.enableNetwork());
  }

  /** Shuts down this client, cancels all writes / listeners, and releases all resources. */
  Future<void> shutdown() {
    credentialsProvider.removeChangeListener();
    return asyncQueue.enqueue(
        () {
          remoteStore.shutdown();
          persistence.shutdown();
        });
  }

  /** Starts listening to a query. */
  QueryListener listen(
      Query query, ListenOptions options, EventListener<ViewSnapshot> listener) {
    QueryListener queryListener = new QueryListener(query, options, listener);
    asyncQueue.enqueueAndForget(() => eventManager.addQueryListener(queryListener));
    return queryListener;
  }

  /** Stops listening to a query previously listened to. */
  void stopListening(QueryListener listener) {
    asyncQueue.enqueueAndForget(() => eventManager.removeQueryListener(listener));
  }

  Future<Document> getDocumentFromLocalCache(DocumentKey docKey) {
    return asyncQueue
        .enqueue(() => localStore.readDocument(docKey))
        .continueWith(
            (result) {
              MaybeDocument maybeDoc = result.getResult();

              if (maybeDoc is Document) {
                return  maybeDoc ;
              } else if (maybeDoc is NoDocument) {
                return null;
              } else {
                throw new FirebaseFirestoreError(
                    "Failed to get document from cache. (However, this document may exist on the "
                        "server. Run again without setting source to CACHE to attempt "
                         "to retrieve the document from the server.)", FirebaseFirestoreErrorCode.unavailable);
              }
            });
  }

  Future<ViewSnapshot> getDocumentsFromLocalCache(Query query) {
    return asyncQueue.enqueue(
        ()  {
          ImmutableSortedMap<DocumentKey, Document> docs = localStore.executeQuery(query);

          View view =
              new View(
                  query,
                  new ImmutableSortedSet<DocumentKey>(
                      Collections.emptyList(), DocumentKey::compareTo));
          View.DocumentChanges viewDocChanges = view.computeDocChanges(docs);
          return view.applyChanges(viewDocChanges).getSnapshot();
        });
  }

  /** Writes mutations. The returned task will be notified when it's written to the backend. */
  public Future<void> write(final List<Mutation> mutations) {
    final TaskCompletionSource<Void> source = new TaskCompletionSource<>();
    asyncQueue.enqueueAndForget(() -> syncEngine.writeMutations(mutations, source));
    return source.getTask();
  }

  /** Tries to execute the transaction in updateFunction up to retries times. */
  public <TResult> Future<TResult> transaction(
      Function<Transaction, Future<TResult>> updateFunction, int retries) {
    return AsyncQueue.callTask(
        asyncQueue.getExecutor(),
        () -> syncEngine.transaction(asyncQueue, updateFunction, retries));
  }

  private void initialize(Context context, User user, bool usePersistence) {
    // Note: The initialization work must all be synchronous (we can't dispatch more work) since
    // external write/listen operations could get queued to run before that subsequent work
    // completes.
    Logger.debug(LOG_TAG, "Initializing. user=%s", user.getUid());

    if (usePersistence) {
      LocalSerializer serializer =
          new LocalSerializer(new RemoteSerializer(databaseInfo.getDatabaseId()));
      persistence =
          new SQLitePersistence(
              context, databaseInfo.getPersistenceKey(), databaseInfo.getDatabaseId(), serializer);
    } else {
      persistence = MemoryPersistence.createEagerGcMemoryPersistence();
    }

    persistence.start();
    localStore = new LocalStore(persistence, user);

    Datastore datastore = new Datastore(databaseInfo, asyncQueue, credentialsProvider);
    remoteStore = new RemoteStore(this, localStore, datastore, asyncQueue);

    syncEngine = new SyncEngine(localStore, remoteStore, user);
    eventManager = new EventManager(syncEngine);

    // NOTE: RemoteStore depends on LocalStore (for persisting stream tokens, refilling mutation
    // queue, etc.) so must be started after LocalStore.
    localStore.start();
    remoteStore.start();
  }

  @Override
  public void handleRemoteEvent(RemoteEvent remoteEvent) {
    syncEngine.handleRemoteEvent(remoteEvent);
  }

  @Override
  public void handleRejectedListen(int targetId, Status error) {
    syncEngine.handleRejectedListen(targetId, error);
  }

  @Override
  public void handleSuccessfulWrite(MutationBatchResult mutationBatchResult) {
    syncEngine.handleSuccessfulWrite(mutationBatchResult);
  }

  @Override
  public void handleRejectedWrite(int batchId, Status error) {
    syncEngine.handleRejectedWrite(batchId, error);
  }

  @Override
  public void handleOnlineStateChange(OnlineState onlineState) {
    syncEngine.handleOnlineStateChange(onlineState);
    eventManager.handleOnlineStateChange(onlineState);
  }

  @Override
  public ImmutableSortedSet<DocumentKey> getRemoteKeysForTarget(int targetId) {
    return syncEngine.getRemoteKeysForTarget(targetId);
  }
}
