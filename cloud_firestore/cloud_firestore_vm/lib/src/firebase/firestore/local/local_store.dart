// File created by
// Lung Razvan <long1eu>
// on 23/09/2018

import 'dart:async';
import 'dart:typed_data';

import 'package:_firebase_database_collection_vm/_firebase_database_collection_vm.dart';
import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/target.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/target_id_generator.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/local_documents_view.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/local_view_changes.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/local_write_result.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistence/lru_garbage_collector.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistence/mutation_queue.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistence/persistence.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistence/remote_document_cache.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistence/target_cache.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistence/target_data.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/query_engine.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/query_purpose.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/query_result.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/reference_set.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation_batch_result.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/patch_mutation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/no_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/object_value.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/remote_event.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/remote_store.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/target_change.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_vm/src/firebase/timestamp.dart';
import 'package:meta/meta.dart';

/// Local storage in the Firestore client. Coordinates persistence components like the mutation queue and remote
/// document cache to present a latency compensated view of stored data.
///
/// The [LocalStore] is responsible for accepting mutations from the [SyncEngine]. Writes from the client are put into a
/// queue as provisional [Mutations] until they are processed by the [RemoteStore] and confirmed as having been written
/// to the server.
///
/// The local store provides the local version of documents that have been modified locally.
/// It maintains the constraint:
///   LocalDocument = RemoteDocument + Active(LocalMutations)
///   (Active mutations are those that are enqueued and have not been previously acknowledged or rejected).
///
/// The RemoteDocument ('ground truth') state is provided via the applyChangeBatch method. It will be some version of a
/// server-provided document OR will be a server-provided document PLUS acknowledged mutations:
///   RemoteDocument = RemoteDocument + Acknowledged(LocalMutations)
///
/// Note that this 'dirty' version of a RemoteDocument will not be identical to a server base version, since it has
/// LocalMutations added to it pending getting an authoritative copy from the server.
///
/// Since LocalMutations can be rejected by the server, we have to be able to revert a LocalMutation that has already
/// been applied to the LocalDocument (typically done by replaying all remaining LocalMutations to the RemoteDocument to
/// re-apply).
///
/// The [LocalStore] is responsible for the garbage collection of the documents it contains. For now, it every doc
/// referenced by a view, the mutation queue, or the [RemoteStore].
///
/// It also maintains the persistence of mapping queries to resume tokens and target ids. It needs to know this data
/// about queries to properly know what docs it would be allowed to garbage collect.
///
/// The [LocalStore] must be able to efficiently execute queries against its local cache of the documents, to provide
/// the initial set of results before any remote changes have been received.
class LocalStore {
  factory LocalStore(Persistence persistence, QueryEngine queryEngine, User initialUser) {
    hardAssert(persistence.started, 'LocalStore was passed an unstarted persistence implementation');

    final TargetCache targetCache = persistence.targetCache;
    final TargetIdGenerator targetIdGenerator = TargetIdGenerator.forTargetCache(targetCache.highestTargetId);
    final MutationQueue mutationQueue = persistence.getMutationQueue(initialUser);
    final RemoteDocumentCache remoteDocuments = persistence.remoteDocumentCache;
    final LocalDocumentsView localDocuments = LocalDocumentsView(
      remoteDocumentCache: remoteDocuments,
      mutationQueue: mutationQueue,
      indexManager: persistence.indexManager,
    );

    queryEngine.localDocumentsView = localDocuments;

    final ReferenceSet localViewReferences = ReferenceSet();
    persistence.referenceDelegate.inMemoryPins = localViewReferences;

    return LocalStore._(
      persistence,
      targetCache,
      targetIdGenerator,
      mutationQueue,
      remoteDocuments,
      localDocuments,
      queryEngine,
      localViewReferences,
      <int, TargetData>{},
      <Target, int>{},
    );
  }

  LocalStore._(
    this._persistence,
    this._targetCache,
    this._targetIdGenerator,
    this._mutationQueue,
    this._remoteDocuments,
    this._localDocuments,
    this._queryEngine,
    this._localViewReferences,
    this._queryDataByTarget,
    this._targetIdByTarget,
  );

  /// The maximum time to leave a resume token buffered without writing it out.
  ///
  /// This value is arbitrary: it's long enough to avoid several writes (possibly indefinitely if updates come more
  /// frequently than this) but short enough that restarting after crashing will still have a pretty recent resume
  /// token.
  static final int _resultTokenMaxAgeSeconds = const Duration(minutes: 5).inSeconds;

  /// Manages our in-memory or durable persistence.
  final Persistence _persistence;

  /// The set of all mutations that have been sent but not yet been applied to the backend.
  MutationQueue _mutationQueue;

  /// The last known state of all referenced documents according to the backend.
  final RemoteDocumentCache _remoteDocuments;

  /// The current state of all referenced documents, reflecting local changes.
  LocalDocumentsView _localDocuments;

  /// Performs queries over the [_localDocuments] (and potentially maintains
  /// indexes).
  QueryEngine _queryEngine;

  /// The set of document references maintained by any local views.
  final ReferenceSet _localViewReferences;

  /// Maps a query to the data about that query.
  final TargetCache _targetCache;

  /// Maps a targetId to data about its query.
  final Map<int, TargetData> _queryDataByTarget;

  /// Maps a target to its targetID.
  final Map<Target, int> _targetIdByTarget;

  /// Used to generate targetIds for queries tracked locally.
  final TargetIdGenerator _targetIdGenerator;

  Future<void> start() async {
    return startMutationQueue();
  }

  Future<void> startMutationQueue() {
    return _persistence.runTransaction('Start MutationQueue', _mutationQueue.start);
  }

  // PORTING NOTE: no shutdown for [LocalStore] or persistence components on Android.
  Future<ImmutableSortedMap<DocumentKey, MaybeDocument>> handleUserChange(User user) async {
    // Swap out the mutation queue, grabbing the pending mutation batches before and after.
    final List<MutationBatch> oldBatches = await _mutationQueue.getAllMutationBatches();

    _mutationQueue = _persistence.getMutationQueue(user);
    await startMutationQueue();

    final List<MutationBatch> newBatches = await _mutationQueue.getAllMutationBatches();

    // Recreate our LocalDocumentsView using the new MutationQueue.
    _localDocuments = LocalDocumentsView(
      remoteDocumentCache: _remoteDocuments,
      mutationQueue: _mutationQueue,
      indexManager: _persistence.indexManager,
    );
    _queryEngine.localDocumentsView = _localDocuments;

    // Union the old/new changed keys.
    ImmutableSortedSet<DocumentKey> changedKeys = DocumentKey.emptyKeySet;
    for (List<MutationBatch> batches in <List<MutationBatch>>[oldBatches, newBatches]) {
      for (MutationBatch batch in batches) {
        for (Mutation mutation in batch.mutations) {
          changedKeys = changedKeys.insert(mutation.key);
        }
      }
    }

    // Return the set of all (potentially) changed documents as the result of the user change.
    return _localDocuments.getDocuments(changedKeys);
  }

  /// Accepts locally generated [Mutations] and commits them to storage.
  Future<LocalWriteResult> writeLocally(List<Mutation> mutations) async {
    final Timestamp localWriteTime = Timestamp.now();
    // TODO(long1eu): Call queryEngine.handleDocumentChange() appropriately.

    final Set<DocumentKey> keys = mutations.map((Mutation e) => e.key).toSet();
    return _persistence.runTransactionAndReturn(
      'Locally write mutations',
      () async {
        // Load and apply all existing mutations. This lets us compute the
        // current base state for all non-idempotent transforms before applying
        // any additional user-provided writes.
        final ImmutableSortedMap<DocumentKey, MaybeDocument> existingDocuments =
            await _localDocuments.getDocuments(keys);

        // For non-idempotent mutations (such as `FieldValue.increment()`), we
        // record the base state in a separate patch mutation. This is later
        // used to guarantee consistent values and prevents flicker even if the
        // backend sends us an update that already includes our transform.
        final List<Mutation> baseMutations = <Mutation>[];
        for (Mutation mutation in mutations) {
          final ObjectValue baseValue = mutation.extractTransformBaseValue(existingDocuments[mutation.key]);
          if (baseValue != null) {
            // NOTE: The base state should only be applied if there's some existing
            // document to override, so use a Precondition of exists=true
            baseMutations.add(PatchMutation(mutation.key, baseValue, baseValue.fieldMask, Precondition(exists: true)));
          }
        }

        final MutationBatch batch = await _mutationQueue.addMutationBatch(localWriteTime, baseMutations, mutations);
        final ImmutableSortedMap<DocumentKey, MaybeDocument> changedDocuments =
            batch.applyToLocalDocumentSet(existingDocuments);
        return LocalWriteResult(batch.batchId, changedDocuments);
      },
    );
  }

  /// Acknowledges the given batch.
  ///
  /// On the happy path when a batch is acknowledged, the local store will
  ///   * remove the batch from the mutation queue;
  ///   * apply the changes to the remote document cache;
  ///   * recalculate the latency compensated view implied by those changes
  ///     (there may be mutations in the queue that affect the documents but
  ///     haven't been acknowledged yet); and
  ///   * give the changed documents back the sync engine
  Future<ImmutableSortedMap<DocumentKey, MaybeDocument>> acknowledgeBatch(MutationBatchResult batchResult) {
    return _persistence.runTransactionAndReturn<ImmutableSortedMap<DocumentKey, MaybeDocument>>('Acknowledge batch',
        () async {
      final MutationBatch batch = batchResult.batch;
      await _mutationQueue.acknowledgeBatch(batch, batchResult.streamToken);
      await _applyWriteToRemoteDocuments(batchResult);
      await _mutationQueue.performConsistencyCheck();
      return _localDocuments.getDocuments(batch.keys);
    });
  }

  /// Removes mutations from the [MutationQueue] for the specified batch. LocalDocuments will be recalculated.
  Future<ImmutableSortedMap<DocumentKey, MaybeDocument>> rejectBatch(int batchId) {
    // TODO(long1eu): Call queryEngine.handleDocumentChange() appropriately.
    return _persistence.runTransactionAndReturn<ImmutableSortedMap<DocumentKey, MaybeDocument>>('Reject batch',
        () async {
      final MutationBatch toReject = await _mutationQueue.lookupMutationBatch(batchId);
      hardAssert(toReject != null, 'Attempt to reject nonexistent batch!');

      await _mutationQueue.removeMutationBatch(toReject);
      await _mutationQueue.performConsistencyCheck();
      return _localDocuments.getDocuments(toReject.keys);
    });
  }

  /// Returns the largest (latest) batch id in mutation queue that is pending server response.
  /// Returns [MutationBatch.unknown] if the queue is empty.
  Future<int> getHighestUnacknowledgedBatchId() => _mutationQueue.getHighestUnacknowledgedBatchId();

  /// Returns the last recorded stream token for the current user.
  Uint8List get lastStreamToken => _mutationQueue.lastStreamToken;

  /// Sets the stream token for the current user without acknowledging any mutation batch. This is usually only useful
  /// after a stream handshake or in response to an error that requires clearing the stream token.
  ///
  /// Use [WriteStream.emptyStreamToken] to clear the current value.
  Future<void> setLastStreamToken(Uint8List streamToken) async {
    await _persistence.runTransaction('Set stream token', () => _mutationQueue.setLastStreamToken(streamToken));
  }

  /// Returns the last consistent snapshot processed (used by the [RemoteStore] to determine whether to buffer incoming
  /// snapshots from the backend).
  SnapshotVersion getLastRemoteSnapshotVersion() {
    return _targetCache.lastRemoteSnapshotVersion;
  }

  /// Updates the 'ground-state' (remote) documents. We assume that the remote event reflects any write batches that
  /// have been acknowledged or rejected (i.e. we do not re-apply local mutations to updates from this event).
  ///
  /// [LocalDocuments] are re-calculated if there are remaining mutations in the queue.
  Future<ImmutableSortedMap<DocumentKey, MaybeDocument>> applyRemoteEvent(RemoteEvent remoteEvent) {
    final SnapshotVersion remoteVersion = remoteEvent.snapshotVersion;

    // TODO: Call queryEngine.handleDocumentChange() appropriately.
    return _persistence.runTransactionAndReturn<ImmutableSortedMap<DocumentKey, MaybeDocument>>(
      'Apply remote event',
      () async {
        final Map<int, TargetChange> targetChanges = remoteEvent.targetChanges;
        final int sequenceNumber = _persistence.referenceDelegate.currentSequenceNumber;

        for (MapEntry<int, TargetChange> entry in targetChanges.entries) {
          final int boxedTargetId = entry.key;
          final int targetId = boxedTargetId;
          final TargetChange change = entry.value;

          final TargetData oldTargetData = _queryDataByTarget[targetId];
          if (oldTargetData == null) {
            // We don't update the remote keys if the query is not active. This ensures that
            // we persist the updated query data along with the updated assignment.
            continue;
          }

          await _targetCache.removeMatchingKeys(change.removedDocuments, targetId);
          await _targetCache.addMatchingKeys(change.addedDocuments, targetId);

          final Uint8List resumeToken = change.resumeToken;
          // Update the resume token if the change includes one.
          if (resumeToken.isNotEmpty) {
            final TargetData newTargetData = oldTargetData.copyWith(
              snapshotVersion: remoteEvent.snapshotVersion,
              resumeToken: resumeToken,
              sequenceNumber: sequenceNumber,
            );
            _queryDataByTarget[targetId] = newTargetData;

            // Update the query data if there are target changes (or if sufficient time has
            // passed since the last update).
            if (_shouldPersistTargetData(oldTargetData, newTargetData, change)) {
              await _targetCache.updateTargetData(newTargetData);
            }
          }
        }

        final Map<DocumentKey, MaybeDocument> changedDocs = <DocumentKey, MaybeDocument>{};
        final Map<DocumentKey, MaybeDocument> documentUpdates = remoteEvent.documentUpdates;
        final Set<DocumentKey> limboDocuments = remoteEvent.resolvedLimboDocuments;
        // Each loop iteration only affects its "own" doc, so it's safe to get all the remote documents in advance in a
        // single call.
        final Map<DocumentKey, MaybeDocument> existingDocs = await _remoteDocuments.getAll(documentUpdates.keys);
        for (MapEntry<DocumentKey, MaybeDocument> entry in documentUpdates.entries) {
          final DocumentKey key = entry.key;
          final MaybeDocument doc = entry.value;
          final MaybeDocument existingDoc = existingDocs[key];

          // Note: The order of the steps below is important, since we want to ensure that
          // rejected limbo resolutions (which fabricate NoDocuments with SnapshotVersion.NONE)
          // never add documents to cache.
          if (doc is NoDocument && doc.version == SnapshotVersion.none) {
            // NoDocuments with SnapshotVersion.NONE are used in manufactured events. We remove
            // these documents from cache since we lost access.
            await _remoteDocuments.remove(doc.key);
            changedDocs[key] = doc;
          } else if (existingDoc == null ||
              doc.version.compareTo(existingDoc.version) > 0 ||
              (doc.version.compareTo(existingDoc.version) == 0 && existingDoc.hasPendingWrites)) {
            hardAssert(SnapshotVersion.none != remoteEvent.snapshotVersion,
                'Cannot add a document when the remote version is zero');
            await _remoteDocuments.add(doc, remoteEvent.snapshotVersion);
            changedDocs[key] = doc;
          } else {
            Log.d(
              'LocalStore',
              'Ignoring outdated watch update for $key. Current version: ${existingDoc.version}  Watch version: ${doc.version}',
            );
          }

          if (limboDocuments.contains(key)) {
            await _persistence.referenceDelegate.updateLimboDocument(key);
          }
        }

        // HACK: The only reason we allow snapshot version none is so that we can synthesize remote events when we get
        // permission denied errors while trying to resolve the state of a locally cached document that is in limbo.
        final SnapshotVersion lastRemoteVersion = _targetCache.lastRemoteSnapshotVersion;
        if (remoteVersion != SnapshotVersion.none) {
          hardAssert(remoteVersion.compareTo(lastRemoteVersion) >= 0,
              'Watch stream reverted to previous snapshot?? ($remoteVersion < $lastRemoteVersion)');
          await _targetCache.setLastRemoteSnapshotVersion(remoteVersion);
        }

        return _localDocuments.getLocalViewOfDocuments(changedDocs);
      },
    );
  }

  /// Returns true if the [newTargetData] should be persisted during an update of an active target. [TargetData] should
  /// always be persisted when a target is being released and should not call this function.
  ///
  /// While the target is active, [TargetData] updates can be omitted when nothing about the target has changed except
  /// metadata like the resume token or snapshot version. Occasionally it's worth the extra write to prevent these
  /// values from getting too stale after a crash, but this doesn't have to be too frequent.
  static bool _shouldPersistTargetData(TargetData oldTargetData, TargetData newTargetData, TargetChange change) {
    hardAssert(newTargetData.resumeToken.isNotEmpty, 'Attempted to persist query data with empty resume token');

    // Always persist query data if we don't already have a resume token.
    if (oldTargetData.resumeToken.isEmpty) {
      return true;
    }

    // Don't allow resume token changes to be buffered indefinitely. This allows us to be reasonably up-to-date after a
    // crash and avoids needing to loop over all active queries on shutdown. Especially in the browser we may not get
    // time to do anything interesting while the current tab is closing.
    final int newSeconds = newTargetData.snapshotVersion.timestamp.seconds;
    final int oldSeconds = oldTargetData.snapshotVersion.timestamp.seconds;
    final int timeDelta = newSeconds - oldSeconds;
    if (timeDelta >= _resultTokenMaxAgeSeconds) {
      return true;
    }

    // Otherwise if the only thing that has changed about a target is its resume token it's not worth persisting. Note
    // that the [RemoteStore] keeps an in-memory view of the currently active targets which includes the current resume
    // token, so stream failure or user changes will still use an up-to-date resume token regardless of what we do here.
    final int changes = change.addedDocuments.length + change.modifiedDocuments.length + change.removedDocuments.length;
    return changes > 0;
  }

  /// Notify the local store of the changed views to locally pin / unpin documents.
  Future<void> notifyLocalViewChanges(List<LocalViewChanges> viewChanges) async {
    await _persistence.runTransaction('notifyLocalViewChanges', () async {
      for (LocalViewChanges viewChange in viewChanges) {
        final int targetId = viewChange.targetId;

        _localViewReferences.addReferences(viewChange.added, targetId);
        final ImmutableSortedSet<DocumentKey> removed = viewChange.removed;
        for (DocumentKey key in removed) {
          await _persistence.referenceDelegate.removeReference(key);
        }
        _localViewReferences.removeReferences(removed, targetId);

        if (!viewChange.fromCache) {
          final TargetData targetData = _queryDataByTarget[targetId];
          hardAssert(targetData != null, "Can't set limbo-free snapshot version for unknown target: $targetId");

          // Advance the last limbo free snapshot version
          final SnapshotVersion lastLimboFreeSnapshotVersion = targetData.snapshotVersion;
          final TargetData updatedTargetData =
              targetData.copyWith(lastLimboFreeSnapshotVersion: lastLimboFreeSnapshotVersion);
          _queryDataByTarget[targetId] = updatedTargetData;
        }
      }
    });
  }

  /// Returns the mutation batch after the passed in [batchId] in the mutation queue or null if empty.
  ///
  /// [afterBatchId] The batch to search after, or -1 for the first mutation in the queue.
  ///
  /// Returns the next mutation or null if there wasn't one.
  Future<MutationBatch> getNextMutationBatch(int afterBatchId) {
    return _mutationQueue.getNextMutationBatchAfterBatchId(afterBatchId);
  }

  /// Returns the current value of a document with a given key, or null if not found.
  Future<MaybeDocument> readDocument(DocumentKey key) async {
    return _localDocuments.getDocument(key);
  }

  /// Assigns the given query an internal id so that its results can be pinned so they don't get GC'd. A query must be
  /// allocated in the local store before the store can be used to manage its view.
  Future<TargetData> allocateTarget(Target target) async {
    int targetId;
    TargetData cached = await _targetCache.getTargetData(target);

    if (cached != null) {
      // This query has been listened to previously, so reuse the previous targetId.
      // TODO(long1eu): freshen last accessed date?
      targetId = cached.targetId;
    } else {
      await _persistence.runTransaction('Allocate target', () async {
        targetId = _targetIdGenerator.nextId;
        cached = TargetData(
          target,
          targetId,
          _persistence.referenceDelegate.currentSequenceNumber,
          QueryPurpose.listen,
        );

        await _targetCache.addTargetData(cached);
      });
    }

    if (_queryDataByTarget[targetId] == null) {
      _queryDataByTarget[targetId] = cached;
      _targetIdByTarget[target] = targetId;
    }
    return cached;
  }

  /// Returns the [TargetData] as seen by the [LocalStore], including updates that may have not yet been
  /// persisted to the [TargetCache].
  @visibleForTesting
  Future<TargetData> getTargetData(Target target) async {
    final int targetId = _targetIdByTarget[target];
    if (targetId != null) {
      return _queryDataByTarget[targetId];
    }
    return _targetCache.getTargetData(target);
  }

  /// Unpin all the documents associated with the given target.
  ///
  /// Releasing a non-existing target is an error.
  Future<void> releaseTarget(int targetId) {
    return _persistence.runTransaction('Release target', () async {
      final TargetData targetData = _queryDataByTarget[targetId];
      hardAssert(targetData != null, 'Tried to release nonexistent target: $targetId');

      // References for documents sent via Watch are automatically removed when we delete a query's target data from the
      // reference delegate. Since this does not remove references for locally mutated documents, we have to remove the
      // target associations for these documents manually.
      final ImmutableSortedSet<DocumentKey> removedReferences = _localViewReferences.removeReferencesForId(targetId);
      for (DocumentKey key in removedReferences) {
        await _persistence.referenceDelegate.removeReference(key);
      }

      // Note: This also updates the query cache
      await _persistence.referenceDelegate.removeTarget(targetData);
      _queryDataByTarget.remove(targetId);
      _targetIdByTarget.remove(targetData.target);
    });
  }

  /// Runs the specified query against the local store and returns the results, potentially taking
  /// advantage of query data from previous executions (such as the set of remote keys).
  ///
  /// Set [usePreviousResults] to true in order to use results from previous executions can be used to optimize
  /// this query execution.
  Future<QueryResult> executeQuery(Query query, bool usePreviousResults) async {
    final TargetData targetData = await getTargetData(query.toTarget());
    SnapshotVersion lastLimboFreeSnapshotVersion = SnapshotVersion.none;
    ImmutableSortedSet<DocumentKey> remoteKeys = DocumentKey.emptyKeySet;

    if (targetData != null) {
      lastLimboFreeSnapshotVersion = targetData.lastLimboFreeSnapshotVersion;
      remoteKeys = await _targetCache.getMatchingKeysForTargetId(targetData.targetId);
    }

    final ImmutableSortedMap<DocumentKey, Document> documents = await _queryEngine.getDocumentsMatchingQuery(
      query,
      usePreviousResults ? lastLimboFreeSnapshotVersion : SnapshotVersion.none,
      usePreviousResults ? remoteKeys : DocumentKey.emptyKeySet,
    );
    return QueryResult(documents, remoteKeys);
  }

  /// Returns the keys of the documents that are associated with the given target id in the remote table.
  Future<ImmutableSortedSet<DocumentKey>> getRemoteDocumentKeys(int targetId) {
    return _targetCache.getMatchingKeysForTargetId(targetId);
  }

  Future<void> _applyWriteToRemoteDocuments(MutationBatchResult batchResult) async {
    final MutationBatch batch = batchResult.batch;
    final Set<DocumentKey> docKeys = batch.keys;
    for (DocumentKey docKey in docKeys) {
      final MaybeDocument remoteDoc = await _remoteDocuments.get(docKey);
      MaybeDocument doc = remoteDoc;
      final SnapshotVersion ackVersion = batchResult.docVersions[docKey];
      hardAssert(ackVersion != null, 'docVersions should contain every doc in the write.');

      if (doc == null || doc.version.compareTo(ackVersion) < 0) {
        doc = batch.applyToRemoteDocument(docKey, doc, batchResult);
        if (doc == null) {
          hardAssert(remoteDoc == null, 'Mutation batch $batch applied to document $remoteDoc resulted in null.');
        } else {
          await _remoteDocuments.add(doc, batchResult.commitVersion);
        }
      }
    }

    await _mutationQueue.removeMutationBatch(batch);
  }

  Future<LruGarbageCollectorResults> collectGarbage(LruGarbageCollector garbageCollector) {
    return _persistence.runTransactionAndReturn(
      'Collect garbage',
      () => garbageCollector.collect(_queryDataByTarget.keys.toSet()),
    );
  }
}
