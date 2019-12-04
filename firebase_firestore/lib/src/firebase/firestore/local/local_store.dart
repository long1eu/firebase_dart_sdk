// File created by
// Lung Razvan <long1eu>
// on 23/09/2018

import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_database_collection/firebase_database_collection.dart';
import 'package:firebase_firestore/src/firebase/firestore/auth/user.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/target_id_generator.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/local_documents_view.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/local_view_changes.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/local_write_result.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/mutation_queue.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/persistence.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_cache.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_data.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_engine.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_purpose.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/reference_set.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/remote_document_cache.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/simple_query_engine.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/maybe_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation_batch_result.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/snapshot_version.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/remote_event.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/remote_store.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/target_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';
import 'package:firebase_firestore/src/firebase/timestamp.dart';

import 'lru_garbage_collector.dart';

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
  factory LocalStore(Persistence persistence, User initialUser) {
    hardAssert(persistence.started, 'LocalStore was passed an unstarted persistence implementation');

    final QueryCache queryCache = persistence.queryCache;
    final TargetIdGenerator targetIdGenerator = TargetIdGenerator.forQueryCache(queryCache.highestTargetId);
    final MutationQueue mutationQueue = persistence.getMutationQueue(initialUser);
    final RemoteDocumentCache remoteDocuments = persistence.remoteDocumentCache;
    final LocalDocumentsView localDocuments = LocalDocumentsView(remoteDocuments, mutationQueue);
    // TODO(long1eu): Use IndexedQueryEngine as appropriate.
    final SimpleQueryEngine queryEngine = SimpleQueryEngine(localDocuments);

    final ReferenceSet localViewReferences = ReferenceSet();
    persistence.referenceDelegate.inMemoryPins = localViewReferences;

    return LocalStore._(
      persistence,
      queryCache,
      targetIdGenerator,
      mutationQueue,
      remoteDocuments,
      localDocuments,
      queryEngine,
      localViewReferences,
      <int, QueryData>{},
    );
  }

  LocalStore._(
    this._persistence,
    this._queryCache,
    this._targetIdGenerator,
    this._mutationQueue,
    this._remoteDocuments,
    this._localDocuments,
    this._queryEngine,
    this._localViewReferences,
    this._targetIds,
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

  /// Performs queries over the [_localDocuments] (and potentially maintains indexes).
  QueryEngine _queryEngine;

  /// The set of document references maintained by any local views.
  final ReferenceSet _localViewReferences;

  /// Maps a query to the data about that query.
  final QueryCache _queryCache;

  /// Maps a targetId to data about its query.
  final Map<int, QueryData> _targetIds;

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
    _localDocuments = LocalDocumentsView(_remoteDocuments, _mutationQueue);
    // TODO(long1eu): Use IndexedQueryEngine as appropriate.
    _queryEngine = SimpleQueryEngine(_localDocuments);

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

    final MutationBatch batch = await _persistence.runTransactionAndReturn(
        'Locally write mutations', () => _mutationQueue.addMutationBatch(localWriteTime, mutations));

    final Set<DocumentKey> keys = batch.keys;
    final ImmutableSortedMap<DocumentKey, MaybeDocument> changedDocuments = await _localDocuments.getDocuments(keys);

    return LocalWriteResult(batch.batchId, changedDocuments);
  }

  /// Acknowledges the given batch.
  ///
  /// On the happy path when a batch is acknowledged, the local store will
  ///   * remove the batch from the mutation queue;
  ///   * apply the changes to the remote document cache;
  ///   * recalculate the latency compensated view implied by those changes (there may be mutations in the queue that
  ///   affect the documents but haven't been acknowledged yet); and
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
    return _queryCache.lastRemoteSnapshotVersion;
  }

  /// Updates the 'ground-state' (remote) documents. We assume that the remote event reflects any write batches that
  /// have been acknowledged or rejected (i.e. we do not re-apply local mutations to updates from this event).
  ///
  /// [LocalDocuments] are re-calculated if there are remaining mutations in the queue.
  Future<ImmutableSortedMap<DocumentKey, MaybeDocument>> applyRemoteEvent(RemoteEvent remoteEvent) {
    // TODO(long1eu): Call queryEngine.handleDocumentChange() appropriately.
    return _persistence.runTransactionAndReturn<ImmutableSortedMap<DocumentKey, MaybeDocument>>('Apply remote event',
        () async {
      final int sequenceNumber = _persistence.referenceDelegate.currentSequenceNumber;
      final Set<DocumentKey> authoritativeUpdates = <DocumentKey>{};

      final Map<int, TargetChange> targetChanges = remoteEvent.targetChanges;
      for (MapEntry<int, TargetChange> entry in targetChanges.entries) {
        final int targetId = entry.key;
        final TargetChange change = entry.value;

        // Do not ref/unref unassigned targetIds - it may lead to leaks.
        QueryData queryData = _targetIds[targetId];
        if (queryData == null) {
          continue;
        }

        // When a global snapshot contains updates (either add or modify) we can completely trust these updates as
        // authoritative and blindly apply them to our cache (as a defensive measure to promote self-healing in the
        // unfortunate case that our cache is ever somehow corrupted / out-of-sync).
        //
        // If the document is only updated while removing it from a target then watch isn't obligated to send the
        // absolute latest version: it can send the first version that caused the document not to match.
        change.addedDocuments.forEach(authoritativeUpdates.add);
        change.modifiedDocuments.forEach(authoritativeUpdates.add);

        await _queryCache.removeMatchingKeys(change.removedDocuments, targetId);
        await _queryCache.addMatchingKeys(change.addedDocuments, targetId);

        // Update the resume token if the change includes one. Don't clear any preexisting value.
        final Uint8List resumeToken = change.resumeToken;
        if (resumeToken.isNotEmpty) {
          final QueryData oldQueryData = queryData;
          queryData = queryData.copyWith(
            snapshotVersion: remoteEvent.snapshotVersion,
            resumeToken: resumeToken,
            sequenceNumber: sequenceNumber,
          );
          _targetIds[targetId] = queryData;

          if (_shouldPersistQueryData(oldQueryData, queryData, change)) {
            await _queryCache.updateQueryData(queryData);
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

        // If a document update isn't authoritative, make sure we don't apply an old document version to the remote
        // cache. We make an exception for SnapshotVersion.MIN which can happen for manufactured events (e.g. in the
        // case of a limbo document resolution failing).
        if (existingDoc == null ||
            doc.version == SnapshotVersion.none ||
            (authoritativeUpdates.contains(doc.key) && !existingDoc.hasPendingWrites) ||
            doc.version.compareTo(existingDoc.version) >= 0) {
          await _remoteDocuments.add(doc);
          changedDocs[key] = doc;
        } else {
          Log.d(
              'LocalStore',
              'Ignoring outdated watch update for $key. Current version: ${existingDoc.version}  Watch version: '
                  '${doc.version}');
        }

        if (limboDocuments.contains(key)) {
          await _persistence.referenceDelegate.updateLimboDocument(key);
        }
      }

      // HACK: The only reason we allow snapshot version none is so that we can synthesize remote events when we get
      // permission denied errors while trying to resolve the state of a locally cached document that is in limbo.
      final SnapshotVersion lastRemoteVersion = _queryCache.lastRemoteSnapshotVersion;
      final SnapshotVersion remoteVersion = remoteEvent.snapshotVersion;
      if (remoteVersion != SnapshotVersion.none) {
        hardAssert(remoteVersion.compareTo(lastRemoteVersion) >= 0,
            'Watch stream reverted to previous snapshot?? ($remoteVersion < $lastRemoteVersion)');
        await _queryCache.setLastRemoteSnapshotVersion(remoteVersion);
      }

      return _localDocuments.getLocalViewOfDocuments(changedDocs);
    });
  }

  /// Returns true if the [newQueryData] should be persisted during an update of an active target. [QueryData] should
  /// always be persisted when a target is being released and should not call this function.
  ///
  /// While the target is active, [QueryData] updates can be omitted when nothing about the target has changed except
  /// metadata like the resume token or snapshot version. Occasionally it's worth the extra write to prevent these
  /// values from getting too stale after a crash, but this doesn't have to be too frequent.
  static bool _shouldPersistQueryData(QueryData oldQueryData, QueryData newQueryData, TargetChange change) {
    // Avoid clearing any existing value
    if (newQueryData.resumeToken.isEmpty) {
      return false;
    }

    // Any resume token is interesting if there isn't one already.
    if (oldQueryData.resumeToken.isEmpty) {
      return true;
    }

    // Don't allow resume token changes to be buffered indefinitely. This allows us to be reasonably up-to-date after a
    // crash and avoids needing to loop over all active queries on shutdown. Especially in the browser we may not get
    // time to do anything interesting while the current tab is closing.
    final int newSeconds = newQueryData.snapshotVersion.timestamp.seconds;
    final int oldSeconds = oldQueryData.snapshotVersion.timestamp.seconds;
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
        _localViewReferences.addReferences(viewChange.added, viewChange.targetId);
        final ImmutableSortedSet<DocumentKey> removed = viewChange.removed;
        for (DocumentKey key in removed) {
          await _persistence.referenceDelegate.removeReference(key);
        }
        _localViewReferences.removeReferences(removed, viewChange.targetId);
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
  Future<QueryData> allocateQuery(Query query) async {
    int targetId;
    QueryData cached = await _queryCache.getQueryData(query);

    if (cached != null) {
      // This query has been listened to previously, so reuse the previous targetId.
      // TODO(long1eu): freshen last accessed date?
      targetId = cached.targetId;
    } else {
      await _persistence.runTransaction('Allocate query', () async {
        targetId = _targetIdGenerator.nextId;
        cached = QueryData.init(
          query,
          targetId,
          _persistence.referenceDelegate.currentSequenceNumber,
          QueryPurpose.listen,
        );

        await _queryCache.addQueryData(cached);
      });
    }

    // Sanity check to ensure that even when resuming a query it's not currently active.
    hardAssert(_targetIds[targetId] == null, 'Tried to allocate an already allocated query: $query');
    _targetIds[targetId] = cached;
    return cached;
  }

  /// Unpin all the documents associated with the given query.
  Future<void> releaseQuery(Query query) async {
    await _persistence.runTransaction('Release query', () async {
      QueryData queryData = await _queryCache.getQueryData(query);
      hardAssert(queryData != null, 'Tried to release nonexistent query: $query');

      final int targetId = queryData.targetId;
      final QueryData cachedQueryData = _targetIds[targetId];
      if (cachedQueryData.snapshotVersion.compareTo(queryData.snapshotVersion) > 0) {
        // If we've been avoiding persisting the [resumeToken] (see [shouldPersistQueryData] for conditions and
        // rationale) we need to persist the token now because there will no longer be an in-memory version to fall back
        // on.
        queryData = cachedQueryData;
        await _queryCache.updateQueryData(queryData);
      }

      // References for documents sent via Watch are automatically removed when we delete a query's target data from the
      // reference delegate. Since this does not remove references for locally mutated documents, we have to remove the
      // target associations for these documents manually.
      final ImmutableSortedSet<DocumentKey> removedReferences =
          _localViewReferences.removeReferencesForId(queryData.targetId);
      for (DocumentKey key in removedReferences) {
        await _persistence.referenceDelegate.removeReference(key);
      }
      await _persistence.referenceDelegate.removeTarget(queryData);
      _targetIds.remove(queryData.targetId);
    });
  }

  /// Runs the given query against all the documents in the local store and returns the results.
  Future<ImmutableSortedMap<DocumentKey, Document>> executeQuery(Query query) {
    return _queryEngine.getDocumentsMatchingQuery(query);
  }

  /// Returns the keys of the documents that are associated with the given target id in the remote table.
  Future<ImmutableSortedSet<DocumentKey>> getRemoteDocumentKeys(int targetId) {
    return _queryCache.getMatchingKeysForTargetId(targetId);
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
          await _remoteDocuments.add(doc);
        }
      }
    }

    await _mutationQueue.removeMutationBatch(batch);
  }

  Future<LruGarbageCollectorResults> collectGarbage(LruGarbageCollector garbageCollector) {
    return _persistence.runTransaction('Collect garbage', () => garbageCollector.collect(_targetIds.keys.toSet()));
  }
}
