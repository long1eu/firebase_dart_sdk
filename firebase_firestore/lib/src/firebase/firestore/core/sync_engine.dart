// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'dart:async';

import 'package:firebase_database_collection/firebase_database_collection.dart';
import 'package:firebase_firestore/src/firebase/firestore/auth/user.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/event_manager.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query_view.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/target_id_generator.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/transaction.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/view.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/view_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/view_snapshot.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/local_write_result.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_data.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/reference_set.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/remote_store.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/async_queue.dart';
import 'package:grpc/grpc.dart';

/**
 * SyncEngine is the central controller in the client SDK architecture. It is the glue code between
 * the EventManager, LocalStore, and RemoteStore. Some of SyncEngine's responsibilities include:
 *
 * <ol>
 *   <li>Coordinating client requests and remote events between the EventManager and the local and
 *       remote data stores.
 *   <li>Managing a View object for each query, providing the unified view between the local and
 *       remote data stores.
 *   <li>Notifying the RemoteStore when the LocalStore has new mutations in its queue that need
 *       sending to the backend.
 * </ol>
 *
 * <p>The SyncEngine’s methods should only ever be called by methods running on our own worker
 * dispatch queue.
 */
class SyncEngine implements RemoteStoreCallback {
  /*private*/
  static final String TAG = 'SyncEngine';

  /** The local store, used to persist mutations and cached documents. */
  /*private*/
  final LocalStore localStore;

  /** The remote store for sending writes, watches, etc. to the backend. */
  /*private*/
  final RemoteStore remoteStore;

  /** QueryViews for all active queries, indexed by query. */
  /*private*/
  final Map<Query, QueryView> queryViewsByQuery;

  /** QueryViews for all active queries, indexed by target ID. */
  /*private*/
  final Map<int, QueryView> queryViewsByTarget;

  /**
   * When a document is in limbo, we create a special listen to resolve it. This maps the
   * DocumentKey of each limbo document to the target ID of the listen resolving it.
   */
  /*private*/
  final Map<DocumentKey, int> limboTargetsByKey;

  /**
   * Basically the inverse of limboTargetsByKey, a map of target ID to a LimboResolution (which
   * includes the DocumentKey as well as whether we've received a document for the target).
   */
  /*private*/
  final Map<int, LimboResolution> limboResolutionsByTarget;

  /** Used to track any documents that are currently in limbo. */
  /*private*/
  final ReferenceSet limboDocumentRefs;

  /** Stores user completion blocks, indexed by user and batch ID. */
  /*private*/
  final Map<User, Map<int, Completer>> mutationUserCallbacks;

  /** Used for creating the target IDs for the listens used to resolve limbo documents. */
  /*private*/
  final TargetIdGenerator targetIdGenerator;

  /*private*/
  User currentUser;

  /*private*/
  SyncEngineCallback callback;

  SyncEngine(LocalStore localStore, RemoteStore remoteStore, User initialUser) {
    this.localStore = localStore;
    this.remoteStore = remoteStore;

    queryViewsByQuery = {};
    queryViewsByTarget = {};

    limboTargetsByKey = {};
    limboResolutionsByTarget = {};
    limboDocumentRefs = new ReferenceSet();

    mutationUserCallbacks = {};
    targetIdGenerator = TargetIdGenerator.getSyncEngineGenerator(0);
    currentUser = initialUser;
  }
/*
  void setCallback(SyncEngineCallback callback) {
    this.callback = callback;
  }
  /*private*/
  void assertCallback(String method) {
    Assert.hardAssert(
        callback != null, 'Trying to call $method before setting callback');
  }

  /**
   * Initiates a new listen. The LocalStore will be queried for initial data and the listen will be
   * sent to the RemoteStore to get remote data. The registered SyncEngineCallback will be notified
   * of resulting view snapshots and/or listen errors.
   *
   * @return the target ID assigned to the query.
   */
  int listen(Query query) {
    assertCallback("listen");
    Assert.hardAssert(!queryViewsByQuery.containsKey(query),
        "We already listen to query: %s", query);

    QueryData queryData = localStore.allocateQuery(query);
    ImmutableSortedMap<DocumentKey, Document> docs =
    localStore.executeQuery(query);
    ImmutableSortedSet<DocumentKey> remoteKeys =
    localStore.getRemoteDocumentKeys(queryData.getTargetId());

    View view = new View(query, remoteKeys);
    DocumentChanges viewDocChanges = view.computeDocChanges(docs);
    ViewChange viewChange = view.applyChanges(viewDocChanges);
    Assert.hardAssert(view.getLimboDocuments().size() == 0,
        "View returned limbo docs before target ack from the server");

    QueryView queryView = new QueryView(query, queryData.getTargetId(), view);
    queryViewsByQuery.put(query, queryView);
    queryViewsByTarget.put(queryData.getTargetId(), queryView);
    callback.onViewSnapshots([viewChange.getSnapshot()]);

    remoteStore.listen(queryData);
    return queryData.getTargetId();
  }

  /** Stops listening to a query previously listened to via listen. */
  void stopListening(Query query) {
    assertCallback("stopListening");

    QueryView queryView = queryViewsByQuery.get(query);
    Assert.hardAssert(
        queryView != null, "Trying to stop listening to a query not found");

    localStore.releaseQuery(query);
    remoteStore.stopListening(queryView.getTargetId());
    removeAndCleanup(queryView);
  }

  /**
   * Initiates the write of local mutation batch which involves adding the writes to the mutation
   * queue, notifying the remote store about new mutations, and raising events for any changes this
   * write caused. The provided task will be resolved once the write has been acked/rejected by the
   * backend (or failed locally for any other reason).
   */
  void writeMutations(List<Mutation> mutations, Completer<void> userTask) {
    assertCallback("writeMutations");

    LocalWriteResult result = localStore.writeLocally(mutations);
    addUserCallback(result.getBatchId(), userTask);

    emitNewSnapshot(result.getChanges(), /*remoteEvent=*/ null);
    remoteStore.fillWritePipeline();
  }

  /*private*/
  void addUserCallback(int batchId, Completer<void> userTask) {
    Map<int, Completer<void>> userTasks =
    mutationUserCallbacks.get(currentUser);
    if (userTasks == null) {
      userTasks = {};
      mutationUserCallbacks.put(currentUser, userTasks);
    }
    userTasks.put(batchId, userTask);
  }


  /**
   * Takes an updateFunction in which a set of reads and writes can be performed atomically. In the
   * updateFunction, the client can read and write values using the supplied transaction object.
   * After the updateFunction, all changes will be committed. If some other client has changed any
   * of the data referenced, then the updateFunction will be called again. If the updateFunction
   * still fails after the given number of retries, then the transaction will be rejected.
   *
   * <p>The transaction object passed to the updateFunction contains methods for accessing documents
   * and collections. Unlike other datastore access, data accessed with the transaction will not
   * reflect local changes that have not been committed. For this reason, it is required that all
   * reads are performed before any writes. Transactions must be performed while online.
   *
   * <p>The Task returned is resolved when the transaction is fully committed.
   */
  Task<TResult> transaction<TResult>(AsyncQueue asyncQueue,
      Task<TResult> Function(Transaction) updateFunction, int retries) {
    Assert.hardAssert(
        retries >= 0, "Got negative number of retries for transaction.");
    final Transaction transaction = remoteStore.createTransaction();
    return updateFunction
        .apply(transaction)
        .continueWithTask(asyncQueue.getExecutor(), (userTask) {
      if (!userTask.isSuccessful()) {
        return userTask;
      }
      return transaction.commit().continueWithTask(asyncQueue.getExecutor(),
          (commitTask) {
        if (commitTask.isSuccessful()) {
          return Tasks.forResult(userTask.getResult());
        }
        // TODO: Only retry on real transaction failures.
        if (retries == 0) {
          Exception e = new FirebaseFirestoreException(
              "Transaction failed all retries.",
              Code.ABORTED,
              commitTask.getException());
          return Tasks.forException(e);
        }
        return transaction(asyncQueue, updateFunction, retries - 1);
      });
    });
  }

  /** Called by FirestoreClient to notify us of a new remote event. */
  @override
   void handleRemoteEvent(RemoteEvent event) {
    assertCallback("handleRemoteEvent");

    // Update `receivedDocument` as appropriate for any limbo targets.
    for (MapEntry<int, TargetChange> entry in event.getTargetChanges().entrySet()) {
      int targetId = entry.getKey();
      TargetChange targetChange = entry.getValue();
      LimboResolution limboResolution = limboResolutionsByTarget.get(targetId);
      if (limboResolution != null) {
        // Since this is a limbo resolution lookup, it's for a single document and it could be
        // added, modified, or removed, but not a combination.
        Assert.hardAssert(
            targetChange.getAddedDocuments().size()
                    + targetChange.getModifiedDocuments().size()
                    + targetChange.getRemovedDocuments().size()
                <= 1,
            "Limbo resolution for single document contains multiple changes.");
        if (targetChange.getAddedDocuments().size() > 0) {
          limboResolution.receivedDocument = true;
        } else if (targetChange.getModifiedDocuments().size() > 0) {
          Assert.hardAssert(
              limboResolution.receivedDocument,
              "Received change for limbo target document without add.");
        } else if (targetChange.getRemovedDocuments().size() > 0) {
          Assert.hardAssert(
              limboResolution.receivedDocument,
              "Received remove for limbo target document without add.");
          limboResolution.receivedDocument = false;
        } else {
          // This was probably just a CURRENT targetChange or similar.
        }
      }
    }

    ImmutableSortedMap<DocumentKey, MaybeDocument> changes = localStore.applyRemoteEvent(event);
    emitNewSnapshot(changes, event);
  }
/*
  /** Applies an OnlineState change to the sync engine and notifies any views of the change. */
  @override
   void handleOnlineStateChange(OnlineState onlineState) {
    ArrayList<ViewSnapshot> newViewSnapshots = new ArrayList();
    for (MapEntry<Query, QueryView> entry in queryViewsByQuery.entrySet()) {
      View view = entry.getValue().getView();
      ViewChange viewChange = view.applyOnlineStateChange(onlineState);
      Assert.hardAssert(
          viewChange.getLimboChanges().isEmpty(), "OnlineState should not affect limbo documents.");
      if (viewChange.getSnapshot() != null) {
        newViewSnapshots.add(viewChange.getSnapshot());
      }
    }
    callback.onViewSnapshots(newViewSnapshots);
  }

  @override
   ImmutableSortedSet<DocumentKey> getRemoteKeysForTarget(int targetId) {
    LimboResolution limboResolution = limboResolutionsByTarget.get(targetId);
    if (limboResolution != null && limboResolution.receivedDocument) {
      return DocumentKey.emptyKeySet().insert(limboResolution.key);
    } else {
      QueryView queryView = queryViewsByTarget.get(targetId);
      return queryView != null
          ? queryView.getView().getSyncedDocuments()
          : DocumentKey.emptyKeySet();
    }
  }

  /** Called by FirestoreClient to notify us of a rejected listen. */
  @override
   void handleRejectedListen(int targetId, Status error) {
    assertCallback("handleRejectedListen");

    LimboResolution limboResolution = limboResolutionsByTarget.get(targetId);
    DocumentKey limboKey = limboResolution != null ? limboResolution.key : null;
    if (limboKey != null) {
      // Since this query failed, we won't want to manually unlisten to it.
      // So go ahead and remove it from bookkeeping.
      limboTargetsByKey.remove(limboKey);
      limboResolutionsByTarget.remove(targetId);

      // TODO: Retry on transient errors?

      // It's a limbo doc. Create a synthetic event saying it was deleted. This is kind of a hack.
      // Ideally, we would have a method in the local store to purge a document. However, it would
      // be tricky to keep all of the local store's invariants with another method.
      Map<DocumentKey, MaybeDocument> documentUpdates =
          Collections.singletonMap(limboKey, new NoDocument(limboKey, SnapshotVersion.NONE));
      Set<DocumentKey> limboDocuments = Collections.singleton(limboKey);
      RemoteEvent event =
          new RemoteEvent(
              SnapshotVersion.NONE,
              /* targetChanges= */ Collections.emptyMap(),
              /* targetMismatches= */ Collections.emptySet(),
              documentUpdates,
              limboDocuments);
      handleRemoteEvent(event);
    } else {
      QueryView queryView = queryViewsByTarget.get(targetId);
      Assert.hardAssert(queryView != null, "Unknown target: %s", targetId);
      localStore.releaseQuery(queryView.getQuery());
      removeAndCleanup(queryView);
      callback.onError(queryView.getQuery(), error);
    }
  }

  @override
   void handleSuccessfulWrite(MutationBatchResult mutationBatchResult) {
    assertCallback("handleSuccessfulWrite");

    // The local store may or may not be able to apply the write result and raise events immediately
    // (depending on whether the watcher is caught up), so we raise user callbacks first so that
    // they consistently happen before listen events.
    notifyUser(mutationBatchResult.getBatch().getBatchId(), /*status=*/ null);

    ImmutableSortedMap<DocumentKey, MaybeDocument> changes =
        localStore.acknowledgeBatch(mutationBatchResult);

    emitNewSnapshot(changes, /*remoteEvent=*/ null);
  }

  @override
   void handleRejectedWrite(int batchId, Status status) {
    assertCallback("handleRejectedWrite");

    // The local store may or may not be able to apply the write result and raise events immediately
    // (depending on whether the watcher is caught up), so we raise user callbacks first so that
    // they consistently happen before listen events.
    notifyUser(batchId, status);

    ImmutableSortedMap<DocumentKey, MaybeDocument> changes = localStore.rejectBatch(batchId);
    emitNewSnapshot(changes, /*remoteEvent=*/ null);
  }

  /** Resolves the task corresponding to this write result. */
  /*private*/ void notifyUser(int batchId,  Status status) {
    Map<int, Completer<void>> userTasks = mutationUserCallbacks.get(currentUser);

    // NOTE: Mutations restored from persistence won't have task completion sources, so it's okay
    // for this (or the task below) to be null.
    if (userTasks != null) {
      int boxedBatchId = batchId;
      Completer<void> userTask = userTasks.get(boxedBatchId);
      if (userTask != null) {
        if (status != null) {
          userTask.setException(Util.exceptionFromStatus(status));
        } else {
          userTask.setResult(null);
        }
        userTasks.remove(boxedBatchId);
      }
    }
  }

  /*private*/ void removeAndCleanup(QueryView view) {
    queryViewsByQuery.remove(view.getQuery());
    queryViewsByTarget.remove(view.getTargetId());

    ImmutableSortedSet<DocumentKey> limboKeys =
        limboDocumentRefs.referencesForId(view.getTargetId());
    limboDocumentRefs.removeReferencesForId(view.getTargetId());
    for (DocumentKey key in limboKeys) {
      if (!limboDocumentRefs.containsKey(key)) {
        // We removed the last reference for this key.
        removeLimboTarget(key);
      }
    }
  }

  /*private*/ void removeLimboTarget(DocumentKey key) {
    // It's possible that the target already got removed because the query failed. In that case,
    // the key won't exist in `limboTargetsByKey`. Only do the cleanup if we still have the target.
    int targetId = limboTargetsByKey.get(key);
    if (targetId != null) {
      remoteStore.stopListening(targetId);
      limboTargetsByKey.remove(key);
      limboResolutionsByTarget.remove(targetId);
    }
  }

  /**
   * Computes a new snapshot from the changes and calls the registered callback with the new
   * snapshot.
   */
  /*private*/ void emitNewSnapshot(
      ImmutableSortedMap<DocumentKey, MaybeDocument> changes,  RemoteEvent remoteEvent) {
    List<ViewSnapshot> newSnapshots = new ArrayList();
    List<LocalViewChanges> documentChangesInAllViews = new ArrayList();

    for (MapEntry<Query, QueryView> entry in queryViewsByQuery.entrySet()) {
      QueryView queryView = entry.getValue();
      View view = queryView.getView();
      View.DocumentChanges viewDocChanges = view.computeDocChanges(changes);
      if (viewDocChanges.needsRefill()) {
        // The query has a limit and some docs were removed/updated, so we need to re-run the query
        // against the local store to make sure we didn't lose any good docs that had been past the
        // limit.
        ImmutableSortedMap<DocumentKey, Document> docs =
            localStore.executeQuery(queryView.getQuery());
        viewDocChanges = view.computeDocChanges(docs, viewDocChanges);
      }
      TargetChange targetChange =
          remoteEvent == null ? null : remoteEvent.getTargetChanges().get(queryView.getTargetId());
      ViewChange viewChange = queryView.getView().applyChanges(viewDocChanges, targetChange);
      updateTrackedLimboDocuments(viewChange.getLimboChanges(), queryView.getTargetId());

      if (viewChange.getSnapshot() != null) {
        newSnapshots.add(viewChange.getSnapshot());
        LocalViewChanges docChanges =
            LocalViewChanges.fromViewSnapshot(queryView.getTargetId(), viewChange.getSnapshot());
        documentChangesInAllViews.add(docChanges);
      }
    }
    callback.onViewSnapshots(newSnapshots);
    localStore.notifyLocalViewChanges(documentChangesInAllViews);
  }

  /** Updates the limbo document state for the given targetId. */
  /*private*/ void updateTrackedLimboDocuments(List<LimboDocumentChange> limboChanges, int targetId) {
    for (LimboDocumentChange limboChange in limboChanges) {
      switch (limboChange.getType()) {
        case ADDED:
          limboDocumentRefs.addReference(limboChange.getKey(), targetId);
          trackLimboChange(limboChange);
          break;
        case REMOVED:
          Logger.debug(TAG, "Document no longer in limbo: %s", limboChange.getKey());
          DocumentKey limboDocKey = limboChange.getKey();
          limboDocumentRefs.removeReference(limboDocKey, targetId);
          if (!limboDocumentRefs.containsKey(limboDocKey)) {
            // We removed the last reference for this key
            removeLimboTarget(limboDocKey);
          }
          break;
        default:
          throw fail("Unknown limbo change type: %s", limboChange.getType());
      }
    }
  }

  /*private*/ void trackLimboChange(LimboDocumentChange change) {
    DocumentKey key = change.getKey();
    if (!limboTargetsByKey.containsKey(key)) {
      Logger.debug(TAG, "New document in limbo: %s", key);
      int limboTargetId = targetIdGenerator.nextId();
      Query query = Query.atPath(key.getPath());
      QueryData queryData =
          new QueryData(
              query, limboTargetId, ListenSequence.INVALID, QueryPurpose.LIMBO_RESOLUTION);
      limboResolutionsByTarget.put(limboTargetId, new LimboResolution(key));
      remoteStore.listen(queryData);
      limboTargetsByKey.put(key, limboTargetId);
    }
  }

  @visibleForTesting
   Map<DocumentKey, int> getCurrentLimboDocuments() {
    // Make a defensive copy as the Map continues to be modified.
    return new HashMap(limboTargetsByKey);
  }

   void handleCredentialChange(User user) {
    bool userChanged = !currentUser.equals(user);
    currentUser = user;

    if (userChanged) {
      // Notify local store and emit any resulting events from swapping out the mutation queue.
      ImmutableSortedMap<DocumentKey, MaybeDocument> changes = localStore.handleUserChange(user);
      emitNewSnapshot(changes, /*remoteEvent=*/ null);
    }

    // Notify remote store so it can restart its streams.
    remoteStore.handleCredentialChange();
  }*/
  */
}

/** Tracks a limbo resolution. */
/*private*/
class LimboResolution {
  /*private*/ final DocumentKey key;

  /**
   * Set to true once we've received a document. This is used in getRemoteKeysForTarget() and
   * ultimately used by WatchChangeAggregator to decide whether it needs to manufacture a delete
   * event for the target once the target is CURRENT.
   */
  /*private*/
  bool receivedDocument;

  LimboResolution(DocumentKey key) {
    this.key = key;
  }
}

/// A callback used to handle events from the SyncEngine
abstract class SyncEngineCallback {
  void onViewSnapshots(List<ViewSnapshot> snapshotList);

  void onError(Query query, GrpcError error);
}
