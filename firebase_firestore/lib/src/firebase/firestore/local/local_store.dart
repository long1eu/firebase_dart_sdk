// File created by
// Lung Razvan <int1eu>
// on 23/09/2018


import 'package:firebase_firestore/src/firebase/firestore/local/mutation_queue.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/persistence.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_cache.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_data.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_engine.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/reference_set.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/remote_document_cache.dart';
import 'package:firebase_firestore/src/firebase/firestore/auth/user.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/target_id_generator.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/maybe_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/snapshot_version.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation_batch_result.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/local_documents_view.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';
import 'package:sqflite/sqflite.dart';

/// Local storage in the Firestore client. Coordinates persistence components like the mutation queue
/// and remote document cache to present a latency compensated view of stored data.
/// 
/// * The LocalStore is responsible for accepting mutations from the Sync Engine. Writes from the
/// client are put into a queue as provisional Mutations until they are processed by the RemoteStore
/// and confirmed as having been written to the server.
/// 
/// * The local store provides the local version of documents that have been modified locally. It
/// maintains the constraint:
/// 
/// * LocalDocument = RemoteDocument + Active(LocalMutations)
/// 
/// * (Active mutations are those that are enqueued and have not been previously acknowledged or
/// rejected).
/// 
/// * The RemoteDocument ("ground truth") state is provided via the applyChangeBatch method. It will
/// be some version of a server-provided document OR will be a server-provided document PLUS
/// acknowledged mutations:
/// 
/// * RemoteDocument' = RemoteDocument + Acknowledged(LocalMutations)
/// 
/// * Note that this "dirty" version of a RemoteDocument will not be identical to a server base
/// version, since it has LocalMutations added to it pending getting an authoritative copy from the
/// server.
/// 
/// * Since LocalMutations can be rejected by the server, we have to be able to revert a
/// LocalMutation that has already been applied to the LocalDocument (typically done by replaying all
/// remaining LocalMutations to the RemoteDocument to re-apply).
/// 
/// * The LocalStore is responsible for the garbage collection of the documents it contains. For
/// now, it every doc referenced by a view, the mutation queue, or the RemoteStore.
/// 
/// * It also maintains the persistence of mapping queries to resume tokens and target ids. It needs
/// to know this data about queries to properly know what docs it would be allowed to garbage
/// collect.
/// 
/// * The LocalStore must be able to efficiently execute queries against its local cache of the
/// documents, to provide the initial set of results before any remote changes have been received.
class LocalStore {
  /**
   * The maximum time to leave a resume token buffered without writing it out. This value is
   * arbitrary: it's int enough to avoid several writes (possibly indefinitely if updates come more
   * frequently than this) but short enough that restarting after crashing will still have a pretty
   * recent resume token.
   */
  /*private*/
  static final int RESUME_TOKEN_MAX_AGE_SECONDS = TimeUnit.MINUTES.toSeconds(5);

  /** Manages our in-memory or durable persistence. */
  /*private*/
  final Persistence persistence;

  /** The set of all mutations that have been sent but not yet been applied to the backend. */
  /*private*/
  MutationQueue mutationQueue;

  /** The last known state of all referenced documents according to the backend. */
  /*private*/
  final RemoteDocumentCache remoteDocuments;

  /** The current state of all referenced documents, reflecting local changes. */
  /*private*/
  LocalDocumentsView localDocuments;

  /** Performs queries over the localDocuments (and potentially maintains indexes). */
  /*private*/
  QueryEngine queryEngine;

  /** The set of document references maintained by any local views. */
  /*private*/
  final ReferenceSet localViewReferences;

  /** Maps a query to the data about that query. */
  /*private*/
  final QueryCache queryCache;

  /** Maps a targetId to data about its query. */
  /*private*/
  final SparseArray<QueryData> targetIds;

  /** Used to generate targetIds for queries tracked locally. */
  /*private*/
  final TargetIdGenerator targetIdGenerator;

  /**
   * A heldBatchResult is a mutation batch result (from a write acknowledgement) that arrived before
   * the watch stream got notified of a snapshot that includes the write. So we "hold" it until the
   * watch stream catches up. It ensures that the local write remains visible (latency compensation)
   * and doesn't temporarily appear reverted because the watch stream is slower than the write
   * stream and so wasn't reflecting it.
   *
   * * NOTE: Eventually we want to move this functionality into the remote store.
   */
  /*private*/
  final List<MutationBatchResult> heldBatchResults;

  LocalStore(Persistence persistence, User initialUser) {
    Assert.hardAssert(
        persistence.isStarted(),
        "LocalStore was passed an unstarted persistence implementation");
    this.persistence = persistence;
    queryCache = persistence.getQueryCache();
    targetIdGenerator = TargetIdGenerator.getLocalStoreIdGenerator(
        queryCache.getHighestTargetId());
    mutationQueue = persistence.getMutationQueue(initialUser);
    remoteDocuments = persistence.getRemoteDocumentCache();
    localDocuments = new LocalDocumentsView(remoteDocuments, mutationQueue);
    // TODO: Use IndexedQueryEngine as appropriate.
    queryEngine = new SimpleQueryEngine(localDocuments);

    localViewReferences = new ReferenceSet();
    persistence.getReferenceDelegate().setAdditionalReferences(
        localViewReferences);

    targetIds = new SparseArray();
    heldBatchResults = new List();
  }

  void start() {
    _startMutationQueue();
  }

  void _startMutationQueue() {
    persistence.runTransaction(
        "Start MutationQueue",
            ([_]) async {
          await mutationQueue.start();

          // If we have any leftover mutation batch results from a prior run,
          // just drop them.

          // TODO: We may need to repopulate heldBatchResults or similar
          // instead, but that is not straightforward since we're not persisting
          // the write ack versions.
          heldBatchResults.clear();

          // TODO: This is the only usage of
          // getAllMutationBatchesThroughBatchId().
          // Consider removing it in favor of a getAcknowledgedBatches method.
          final int highestAck = mutationQueue.highestAcknowledgedBatchId;
          if (highestAck != MutationBatch.unknown) {
            final List<MutationBatch> batches =
            await mutationQueue.getAllMutationBatchesThroughBatchId(highestAck);
            if (batches.isNotEmpty) {
              // NOTE: This could be more efficient if we had a
              // [removeBatchesThroughBatchId], but this set should be very
              // small and this code should go away eventually.
              mutationQueue.removeMutationBatches(batches);
            }
          }
        });
  }

  // PORTING NOTE: no shutdown for LocalStore or persistence components on Android.

  ImmutableSortedMap<DocumentKey, MaybeDocument> handleUserChange(User user) {
    // Swap out the mutation queue, grabbing the pending mutation batches before and after.
    List<MutationBatch> oldBatches = mutationQueue.getAllMutationBatches();

    mutationQueue = persistence.getMutationQueue(user);
    _startMutationQueue();

    List<MutationBatch> newBatches = mutationQueue.getAllMutationBatches();

    // Recreate our LocalDocumentsView using the new MutationQueue.
    localDocuments = new LocalDocumentsView(remoteDocuments, mutationQueue);
    // TODO: Use IndexedQueryEngine as appropriate.
    queryEngine = new SimpleQueryEngine(localDocuments);

    // Union the old/new changed keys.
    ImmutableSortedSet<DocumentKey> changedKeys = DocumentKey.emptyKeySet();
    for (List<MutationBatch> batches in asList(oldBatches, newBatches)) {
      for (MutationBatch batch in batches) {
        for (Mutation mutation in batch.getMutations()) {
          changedKeys = changedKeys.insert(mutation.getKey());
        }
      }
    }

    // Return the set of all (potentially) changed documents as the result of the user change.
    return localDocuments.getDocuments(changedKeys);
  }

  /** Accepts locally generated Mutations and commits them to storage. */
  LocalWriteResult writeLocally(List<Mutation> mutations) {
    Timestamp localWriteTime = Timestamp.now();
    // TODO: Call queryEngine.handleDocumentChange() appropriately.
    MutationBatch batch =
    persistence.runTransaction(
        "Locally write mutations",
            () => mutationQueue.addMutationBatch(localWriteTime, mutations));

    Set<DocumentKey> keys = batch.getKeys();
    ImmutableSortedMap<DocumentKey, MaybeDocument> changedDocuments =
    localDocuments.getDocuments(keys);
    return new LocalWriteResult(batch.getBatchId(), changedDocuments);
  }

  /**
   * Acknowledges the given batch.
   *
   * * On the happy path when a batch is acknowledged, the local store will
   *
   * <ul>
   *   <li>remove the batch from the mutation queue;
   *   <li>apply the changes to the remote document cache;
   *   <li>recalculate the latency compensated view implied by those changes (there may be mutations
   *       in the queue that affect the documents but haven't been acknowledged yet); and
   *   <li>give the changed documents back the sync engine
   * </ul>
   *
   * @return The resulting (modified) documents.
   */
  ImmutableSortedMap<DocumentKey, MaybeDocument> acknowledgeBatch(
      MutationBatchResult batchResult) {
    return persistence.runTransaction(
        "Acknowledge batch",
            () {
          mutationQueue.acknowledgeBatch(
              batchResult.getBatch(), batchResult.getStreamToken());

          Set<DocumentKey> affected;
          if (shouldHoldBatchResult(batchResult.getCommitVersion())) {
            heldBatchResults.add(batchResult);
            affected = Collections.emptySet();
          } else {
            affected = releaseBatchResults(singletonList(batchResult));
          }

          mutationQueue.performConsistencyCheck();
          return localDocuments.getDocuments(affected);
        });
  }

  /**
   * Removes mutations from the MutationQueue for the specified batch. LocalDocuments will be
   * recalculated.
   *
   * @return The resulting (modified) documents.
   */
  ImmutableSortedMap<DocumentKey, MaybeDocument> rejectBatch(int batchId) {
    // TODO: Call queryEngine.handleDocumentChange() appropriately.

    return persistence.runTransaction(
        "Reject batch",
            () {
          MutationBatch toReject = mutationQueue.lookupMutationBatch(batchId);
          Assert.hardAssert(
              toReject != null, "Attempt to reject nonexistent batch!");

          int lastAcked = mutationQueue.getHighestAcknowledgedBatchId();
          Assert.hardAssert(
              batchId > lastAcked, "Acknowledged batches can't be rejected.");

          Set<DocumentKey> affectedKeys = removeMutationBatch(toReject);
          mutationQueue.performConsistencyCheck();
          return localDocuments.getDocuments(affectedKeys);
        });
  }

  /** Returns the last recorded stream token for the current user. */
  ByteString getLastStreamToken() {
    return mutationQueue.getLastStreamToken();
  }

  /**
   * Sets the stream token for the current user without acknowledging any mutation batch. This is
   * usually only useful after a stream handshake or in response to an error that requires clearing
   * the stream token.
   *
   * @param streamToken The streamToken to record. Use {@code WriteStream.EMPTY_STREAM_TOKEN} to
   *     clear the current value.
   */
  void setLastStreamToken(ByteString streamToken) {
    persistence.runTransaction(
        "Set stream token", () mutationQueue.setLastStreamToken(streamToken));
  }

  /**
   * Returns the last consistent snapshot processed (used by the RemoteStore to determine whether to
   * buffer incoming snapshots from the backend).
   */
  SnapshotVersion getLastRemoteSnapshotVersion() {
    return queryCache.getLastRemoteSnapshotVersion();
  }

  /**
   * Updates the "ground-state" (remote) documents. We assume that the remote event reflects any
   * write batches that have been acknowledged or rejected (i.e. we do not re-apply local mutations
   * to updates from this event).
   *
   * * LocalDocuments are re-calculated if there are remaining mutations in the queue.
   */
  ImmutableSortedMap<DocumentKey, MaybeDocument> applyRemoteEvent(
      RemoteEvent remoteEvent) {
    // TODO: Call queryEngine.handleDocumentChange() appropriately.
    return persistence.runTransaction(
        "Apply remote event",
            () {
          int sequenceNumber = persistence.getReferenceDelegate()
              .getCurrentSequenceNumber();
          Set<DocumentKey> authoritativeUpdates = new HashSet();

          Map<Integer, TargetChange> targetChanges = remoteEvent
              .getTargetChanges();
          for (Map.Entry<Integer, TargetChange> entry in targetChanges
              .entrySet()) {
            Integer boxedTargetId = entry.getKey();
            int targetId = boxedTargetId;
            TargetChange change = entry.getValue();

            // Do not ref/unref unassigned targetIds - it may lead to leaks.
            QueryData queryData = targetIds.get(targetId);
            if (queryData == null) {
              continue;
            }

            // When a global snapshot contains updates (either add or modify) we can completely
            // trust these updates as authoritative and blindly apply them to our cache (as a
            // defensive measure to promote self-healing in the unfortunate case that our cache
            // is ever somehow corrupted / out-of-sync).
            //
            // If the document is only updated while removing it from a target then watch isn't
            // obligated to send the absolute latest version: it can send the first version that
            // caused the document not to match.
            for (DocumentKey key in change.getAddedDocuments()) {
              authoritativeUpdates.add(key);
            }
            for (DocumentKey key in change.getModifiedDocuments()) {
              authoritativeUpdates.add(key);
            }

            queryCache.removeMatchingKeys(
                change.getRemovedDocuments(), targetId);
            queryCache.addMatchingKeys(change.getAddedDocuments(), targetId);

            // Update the resume token if the change includes one. Don't clear any preexisting
            // value.
            ByteString resumeToken = change.getResumeToken();
            if (!resumeToken.isEmpty()) {
              QueryData oldQueryData = queryData;
              queryData =
                  queryData.copy(remoteEvent.getSnapshotVersion(), resumeToken,
                      sequenceNumber);
              targetIds.put(boxedTargetId, queryData);

              if (shouldPersistQueryData(oldQueryData, queryData, change)) {
                queryCache.updateQueryData(queryData);
              }
            }
          }

          Set<DocumentKey> changedDocKeys = new HashSet();
          Map<DocumentKey, MaybeDocument> documentUpdates = remoteEvent
              .getDocumentUpdates();
          Set<DocumentKey> limboDocuments = remoteEvent
              .getResolvedLimboDocuments();
          for (Entry<DocumentKey, MaybeDocument> entry in documentUpdates
              .entrySet()) {
            DocumentKey key = entry.getKey();
            MaybeDocument doc = entry.getValue();
            changedDocKeys.add(key);
            MaybeDocument existingDoc = remoteDocuments.get(key);
            // If a document update isn't authoritative, make sure we don't
            // apply an old document version to the remote cache. We make an
            // exception for SnapshotVersion.MIN which can happen for
            // manufactured events (e.g. in the case of a limbo document
            // resolution failing).
            if (existingDoc == null
                || doc.getVersion().equals(SnapshotVersion.NONE)
                || authoritativeUpdates.contains(doc.getKey())
                || doc.getVersion().compareTo(existingDoc.getVersion()) >= 0) {
              remoteDocuments.add(doc);
            } else {
              Logger.debug(
                  "LocalStore",
                  "Ignoring outdated watch update for %s."
                      + "Current version: %s  Watch version: %s",
                  key,
                  existingDoc.getVersion(),
                  doc.getVersion());
            }

            if (limboDocuments.contains(key)) {
              persistence.getReferenceDelegate().updateLimboDocument(key);
            }
          }

          // HACK: The only reason we allow snapshot version NONE is so that we can synthesize
          // remote events when we get permission denied errors while trying to resolve the
          // state of a locally cached document that is in limbo.
          SnapshotVersion lastRemoteVersion = queryCache
              .getLastRemoteSnapshotVersion();
          SnapshotVersion remoteVersion = remoteEvent.getSnapshotVersion();
          if (!remoteVersion.equals(SnapshotVersion.NONE)) {
            Assert.hardAssert(
                remoteVersion.compareTo(lastRemoteVersion) >= 0,
                "Watch stream reverted to previous snapshot?? (%s < %s)",
                remoteVersion,
                lastRemoteVersion);
            queryCache.setLastRemoteSnapshotVersion(remoteVersion);
          }

          Set<DocumentKey> releasedWriteKeys = releaseHeldBatchResults();

          // Union the two key sets.
          changedDocKeys.addAll(releasedWriteKeys);
          return localDocuments.getDocuments(changedDocKeys);
        });
  }

  /**
   * Returns true if the newQueryData should be persisted during an update of an active target.
   * QueryData should always be persisted when a target is being released and should not call this
   * function.
   *
   * * While the target is active, QueryData updates can be omitted when nothing about the target
   * has changed except metadata like the resume token or snapshot version. Occasionally it's worth
   * the extra write to prevent these values from getting too stale after a crash, but this doesn't
   * have to be too frequent.
   */
  /*private*/
  static bool shouldPersistQueryData(QueryData oldQueryData,
      QueryData newQueryData, TargetChange change) {
    // Avoid clearing any existing value
    if (newQueryData.getResumeToken().isEmpty()) return false;

    // Any resume token is interesting if there isn't one already.
    if (oldQueryData.getResumeToken().isEmpty()) return true;

    // Don't allow resume token changes to be buffered indefinitely. This allows us to be reasonably
    // up-to-date after a crash and avoids needing to loop over all active queries on shutdown.
    // Especially in the browser we may not get time to do anything interesting while the current
    // tab is closing.
    int newSeconds = newQueryData.getSnapshotVersion()
        .getTimestamp()
        .getSeconds();
    int oldSeconds = oldQueryData.getSnapshotVersion()
        .getTimestamp()
        .getSeconds();
    int timeDelta = newSeconds - oldSeconds;
    if (timeDelta >= RESUME_TOKEN_MAX_AGE_SECONDS) return true;

    // Otherwise if the only thing that has changed about a target is its resume token it's not
    // worth persisting. Note that the RemoteStore keeps an in-memory view of the currently active
    // targets which includes the current resume token, so stream failure or user changes will still
    // use an up-to-date resume token regardless of what we do here.
    int changes =
        change.getAddedDocuments().size()
            + change.getModifiedDocuments().size()
            + change.getRemovedDocuments().size();
    return changes > 0;
  }

  /** Notify the local store of the changed views to locally pin / unpin documents. */
  void notifyLocalViewChanges(List<LocalViewChanges> viewChanges) {
    persistence.runTransaction(
        "notifyLocalViewChanges",
            () {
          for (LocalViewChanges viewChange in viewChanges) {
            localViewReferences.addReferences(
                viewChange.getAdded(), viewChange.getTargetId());
            ImmutableSortedSet<DocumentKey> removed = viewChange.getRemoved();
            for (DocumentKey key in removed) {
              persistence.getReferenceDelegate().removeReference(key);
            }
            localViewReferences.removeReferences(
                removed, viewChange.getTargetId());
          }
        });
  }

  /**
   * Returns the mutation batch after the passed in batchId in the mutation queue or null if empty.
   *
   * @param afterBatchId The batch to search after, or -1 for the first mutation in the queue.
   * @return The next mutation or null if there wasn't one.
   */
  MutationBatch getNextMutationBatch(int afterBatchId) {
    return mutationQueue.getNextMutationBatchAfterBatchId(afterBatchId);
  }

  /** Returns the current value of a document with a given key, or null if not found. */

  MaybeDocument readDocument(DocumentKey key) {
    return localDocuments.getDocument(key);
  }

  /**
   * Assigns the given query an internal ID so that its results can be pinned so they don't get
   * GC'd. A query must be allocated in the local store before the store can be used to manage its
   * view.
   */
  QueryData allocateQuery(Query query) {
    int targetId;
    QueryData cached = queryCache.getQueryData(query);
    if (cached != null) {
      // This query has been listened to previously, so reuse the previous targetID.
      // TODO: freshen last accessed date?
      targetId = cached.getTargetId();
    } else {
      final AllocateQueryHolder holder = new AllocateQueryHolder();
      persistence.runTransaction(
          "Allocate query",
              () {
            holder.targetId = targetIdGenerator.nextId();
            holder.cached =
            new QueryData(
                query,
                holder.targetId,
                persistence.getReferenceDelegate().getCurrentSequenceNumber(),
                QueryPurpose.LISTEN);
            queryCache.addQueryData(holder.cached);
          });
      targetId = holder.targetId;
      cached = holder.cached;
    }

    // Sanity check to ensure that even when resuming a query it's not currently active.
    Assert.hardAssert(
        targetIds.get(targetId) == null,
        "Tried to allocate an already allocated query: %s", query);
    targetIds.put(targetId, cached);
    return cached;
  }


  /** Unpin all the documents associated with the given query. */
  void releaseQuery(Query query) {
    persistence.runTransaction(
        "Release query",
            () {
          QueryData queryData = queryCache.getQueryData(query);
          Assert.hardAssert(
              queryData != null, "Tried to release nonexistent query: %s",
              query);

          int targetId = queryData.getTargetId();
          QueryData cachedQueryData = targetIds.get(targetId);
          if (cachedQueryData.getSnapshotVersion().compareTo(
              queryData.getSnapshotVersion()) > 0) {
            // If we've been avoiding persisting the resumeToken (see shouldPersistQueryData for
            // conditions and rationale) we need to persist the token now because there will no
            // inter be an in-memory version to fall back on.
            queryData = cachedQueryData;
            queryCache.updateQueryData(queryData);
          }

          localViewReferences.removeReferencesForId(queryData.getTargetId());
          persistence.getReferenceDelegate().removeTarget(queryData);
          targetIds.remove(queryData.getTargetId());

          // If this was the last watch target, then we won't get any more watch snapshots, so we
          // should release any held batch results.
          if (targetIds.size() == 0) {
            releaseHeldBatchResults();
          }
        });
  }

  /** Runs the given query against all the documents in the local store and returns the results. */
  ImmutableSortedMap<DocumentKey, Document> executeQuery(Query query) {
    return queryEngine.getDocumentsMatchingQuery(query);
  }

  /**
   * Returns the keys of the documents that are associated with the given target id in the remote
   * table.
   */
  ImmutableSortedSet<DocumentKey> getRemoteDocumentKeys(int targetId) {
    return queryCache.getMatchingKeysForTargetId(targetId);
  }

  /**
   * Releases all the held batch results up to the current remote version received, and applies
   * their mutations to the docs in the remote documents cache.
   *
   * @return the set of keys of docs that were modified by those writes.
   */
  /*private*/
  Set<DocumentKey> releaseHeldBatchResults() {
    List<MutationBatchResult> toRelease = new List();
    for (MutationBatchResult batchResult in heldBatchResults) {
      if (!isRemoteUpToVersion(batchResult.getCommitVersion())) {
        break;
      }
      toRelease.add(batchResult);
    }

    if (toRelease.isEmpty()) {
      return Collections.emptySet();
    } else {
      heldBatchResults.subList(0, toRelease.size()).clear();
      return releaseBatchResults(toRelease);
    }
  }

  /*private*/
  bool isRemoteUpToVersion(SnapshotVersion snapshotVersion) {
    // If there are no watch targets, then we won't get remote snapshots, and are always
    // "up-to-date."
    return snapshotVersion.compareTo(
        queryCache.getLastRemoteSnapshotVersion()) <= 0
        || targetIds.size() == 0;
  }

  /*private*/
  bool shouldHoldBatchResult(SnapshotVersion snapshotVersion) {
    // Check if watcher isn't up to date or prior results are already held.
    return !isRemoteUpToVersion(snapshotVersion) || !heldBatchResults.isEmpty();
  }

  /*private*/
  Set<DocumentKey> releaseBatchResults(List<MutationBatchResult> batchResults) {
    List<MutationBatch> batches = new List(batchResults.size());
    // TODO: Call queryEngine.handleDocumentChange() as appropriate.
    for (MutationBatchResult batchResult in batchResults) {
      applyBatchResult(batchResult);
      batches.add(batchResult.getBatch());
    }

    return removeMutationBatches(batches);
  }

  /*private*/
  Set<DocumentKey> removeMutationBatch(MutationBatch batch) {
    return removeMutationBatches(singletonList(batch));
  }

  /** Removes the given mutation batches. */
  /*private*/
  Set<DocumentKey> removeMutationBatches(List<MutationBatch> batches) {
    Set<DocumentKey> affectedDocs = new HashSet();
    for (MutationBatch batch in batches) {
      for (Mutation mutation in batch.getMutations()) {
        affectedDocs.add(mutation.getKey());
      }
    }

    mutationQueue.removeMutationBatches(batches);
    return affectedDocs;
  }

  /*private*/
  void applyBatchResult(MutationBatchResult batchResult) {
    MutationBatch batch = batchResult.getBatch();
    Set<DocumentKey> docKeys = batch.getKeys();
    for (DocumentKey docKey in docKeys) {
      MaybeDocument remoteDoc = remoteDocuments.get(docKey);
      MaybeDocument doc = remoteDoc;
      SnapshotVersion ackVersion = batchResult.getDocVersions().get(docKey);
      Assert.hardAssert(ackVersion != null,
          "docVersions should contain every doc in the write.");

      if (doc == null || doc.getVersion().compareTo(ackVersion) < 0) {
        doc = batch.applyToRemoteDocument(docKey, doc, batchResult);
        if (doc == null) {
          Assert.hardAssert(
              remoteDoc == null,
              "Mutation batch %s applied to document %s resulted in null.",
              batch,
              remoteDoc);
        } else {
          remoteDocuments.add(doc);
        }
      }
    }
  }
}


/** Mutable state for the transaction in allocateQuery. */
/*private*/
class AllocateQueryHolder {
  QueryData cached;
  int targetId;
}