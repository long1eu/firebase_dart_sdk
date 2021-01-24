// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'dart:async';
import 'dart:collection';

import 'package:_firebase_database_collection_vm/_firebase_database_collection_vm.dart';
import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/event_manager.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/firestore_client.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/limbo_document_change.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/listen_sequence.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/online_state.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/target_id_generator.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/transaction_runner.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/view.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/view_change.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/view_snapshot.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/local_view_changes.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/local_write_result.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistence/target_data.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/query_purpose.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/query_result.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/reference_set.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation_batch_result.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/no_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/remote_event.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/remote_store.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/target_change.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/async_task.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/util.dart';
import 'package:grpc/grpc.dart';
import 'package:meta/meta.dart';

/// [SyncEngine] is the central controller in the client SDK architecture. It is the glue code between the
/// [EventManager], [LocalStore], and [RemoteStore]. Some of [SyncEngine]'s responsibilities include:
///
/// * Coordinating client requests and remote events between the [EventManager] and the local and remote data stores.
/// * Managing a [View] object for each query, providing the unified view between the local and remote data stores.
/// * Notifying the [RemoteStore] when the [LocalStore] has new mutations in its queue that need sending to the backend.
///
/// The [SyncEngine]’s methods should only ever be called by methods running on our own worker dispatch queue.
class SyncEngine implements RemoteStoreCallback {
  SyncEngine(
    this._localStore,
    this._remoteStore,
    this._currentUser,
    this._maxConcurrentLimboResolutions,
  )   : _queryViewsByQuery = <Query, QueryView>{},
        _queriesByTarget = <int, List<Query>>{},
        _enqueuedLimboResolutions = Queue<DocumentKey>(),
        _activeLimboTargetsByKey = <DocumentKey, int>{},
        _activeLimboResolutionsByTarget = <int, _LimboResolution>{},
        _limboDocumentRefs = ReferenceSet(),
        _mutationUserCallbacks = <User, Map<int, Completer<void>>>{},
        _targetIdGenerator = TargetIdGenerator.forSyncEngine(),
        _pendingWritesCallbacks = <int, List<Completer<void>>>{};

  static const String _tag = 'SyncEngine';

  /// The local store, used to persist mutations and cached documents.
  final LocalStore _localStore;

  /// The remote store for sending writes, watches, etc. to the backend.
  final RemoteStore _remoteStore;

  /// [QueryView]s for all active queries, indexed by query.
  final Map<Query, QueryView> _queryViewsByQuery;

  /// [Query]s mapped to active targets, indexed by target id.
  final Map<int, List<Query>> _queriesByTarget;
  final int _maxConcurrentLimboResolutions;

  /// The keys of documents that are in limbo for which we haven't yet started a limbo resolution
  /// query.
  final Queue<DocumentKey> _enqueuedLimboResolutions;

  /// Keeps track of the target ID for each document that is in limbo with an active target.
  final Map<DocumentKey, int> _activeLimboTargetsByKey;

  /// Keeps track of the information about an active limbo resolution for each active target ID that
  /// was started for the purpose of limbo resolution.
  final Map<int, _LimboResolution> _activeLimboResolutionsByTarget;

  /// Used to track any documents that are currently in limbo.
  final ReferenceSet _limboDocumentRefs;

  /// Stores user completion blocks, indexed by user and batch id.
  final Map<User, Map<int, Completer<void>>> _mutationUserCallbacks;

  /// Stores user callbacks waiting for all pending writes to be acknowledged.
  final Map<int, List<Completer<void>>> _pendingWritesCallbacks;

  /// Used for creating the target ids for the listens used to resolve limbo documents.
  final TargetIdGenerator _targetIdGenerator;

  User _currentUser;

  SyncEngineCallback _syncEngineListener;

  set syncEngineListener(SyncEngineCallback callback) {
    _syncEngineListener = callback;
  }

  void _assertCallback(String method) {
    hardAssert(_syncEngineListener != null, 'Trying to call $method before setting callback');
  }

  /// Initiates a new listen.
  ///
  /// The [LocalStore] will be queried for initial data and the listen will be
  /// sent to the [RemoteStore] to get remote data. The registered
  /// [SyncEngineCallback] will be notified of resulting view snapshots and/or
  /// listen errors.
  ///
  /// Returns the target ID assigned to the query.
  Future<int> listen(Query query) async {
    _assertCallback('listen');
    hardAssert(!_queryViewsByQuery.containsKey(query), 'We already listen to query: $query');

    final TargetData targetData = await _localStore.allocateTarget(query.toTarget());
    final ViewSnapshot viewSnapshot = await initializeViewAndComputeSnapshot(query, targetData.targetId);
    await _syncEngineListener.onViewSnapshots(<ViewSnapshot>[viewSnapshot]);

    await _remoteStore.listen(targetData);
    return targetData.targetId;
  }

  Future<ViewSnapshot> initializeViewAndComputeSnapshot(Query query, int targetId) async {
    final QueryResult queryResult = await _localStore.executeQuery(query, /* usePreviousResults= */ true);

    ViewSnapshotSyncState currentTargetSyncState = ViewSnapshotSyncState.none;
    TargetChange synthesizedCurrentChange;

    // If there are already queries mapped to the target id, create a synthesized target change to
    // apply the sync state from those queries to the new query.
    if (_queriesByTarget[targetId] != null) {
      final Query mirrorQuery = _queriesByTarget[targetId].first;
      currentTargetSyncState = _queryViewsByQuery[mirrorQuery].view.syncState;
      final bool current = currentTargetSyncState == ViewSnapshotSyncState.synced;
      synthesizedCurrentChange = TargetChange.createSynthesizedTargetChangeForCurrentChange(current);
    }

    // TODO(wuandy): Investigate if we can extract the logic of view change computation and
    // update tracked limbo in one place, and have both emitNewSnapsAndNotifyLocalStore
    // and here to call that.
    final View view = View(query, queryResult.remoteKeys);
    final ViewDocumentChanges viewDocChanges = view.computeDocChanges(queryResult.documents);
    final ViewChange viewChange = view.applyChanges(viewDocChanges, synthesizedCurrentChange);
    await _updateTrackedLimboDocuments(viewChange.limboChanges, targetId);

    final QueryView queryView = QueryView(query, targetId, view);
    _queryViewsByQuery[query] = queryView;

    if (!_queriesByTarget.containsKey(targetId)) {
      _queriesByTarget[targetId] = <Query>[];
    }
    _queriesByTarget[targetId].add(query);

    return viewChange.snapshot;
  }

  /// Stops listening to a query previously listened to via listen.
  Future<void> stopListening(Query query) async {
    _assertCallback('stopListening');

    final QueryView queryView = _queryViewsByQuery[query];
    hardAssert(queryView != null, 'Trying to stop listening to a query not found');

    _queryViewsByQuery.remove(query);

    final int targetId = queryView.targetId;
    final List<Query> targetQueries = _queriesByTarget[targetId] //
      ..remove(query);

    if (targetQueries.isEmpty) {
      await _localStore.releaseTarget(targetId);
      await _remoteStore.stopListening(targetId);
      await _removeAndCleanupTarget(targetId, GrpcError.ok());
    }
  }

  /// Initiates the write of local mutation batch which involves adding the writes to the mutation queue, notifying the
  /// remote store about new mutations, and raising events for any changes this write caused.
  ///
  /// The provided Future will be resolved once the write has been acked/rejected by the backend (or failed locally for
  /// any other reason).
  Future<void> writeMutations(List<Mutation> mutations, Completer<void> userTask) async {
    _assertCallback('writeMutations');

    final LocalWriteResult result = await _localStore.writeLocally(mutations);
    _addUserCallback(result.batchId, userTask);

    await _emitNewSnapsAndNotifyLocalStore(result.changes, /*remoteEvent:*/ null);
    await _remoteStore.fillWritePipeline();
  }

  void _addUserCallback(int batchId, Completer<void> userTask) {
    Map<int, Completer<void>> userTasks = _mutationUserCallbacks[_currentUser];
    if (userTasks == null) {
      userTasks = <int, Completer<void>>{};
      _mutationUserCallbacks[_currentUser] = userTasks;
    }
    userTasks[batchId] = userTask;
  }

  /// Takes an [updateFunction] in which a set of reads and writes can be performed atomically.
  ///
  /// In the [updateFunction], the client can read and write values using the supplied transaction
  /// object. After the [updateFunction], all changes will be committed. If a retryable error occurs
  /// (ex: some other client has changed any of the data referenced), then the [updateFunction] will
  /// be called again after a backoff. If the [updateFunction] still fails after all retries, then the
  /// transaction will be rejected.
  ///
  /// The transaction object passed to the [updateFunction] contains methods for accessing documents
  /// and collections. Unlike other datastore access, data accessed with the transaction will not
  /// reflect local changes that have not been committed. For this reason, it is required that all
  /// reads are performed before any writes. Transactions must be performed while online.
  ///
  /// The Future returned is completed when the transaction is fully committed.
  Future<T> transaction<T>(AsyncQueue asyncQueue, TransactionUpdateFunction<T> updateFunction) async {
    return TransactionRunner<T>(asyncQueue, _remoteStore, updateFunction).run();
  }

  /// Called by [FirestoreClient] to notify us of a new remote event.
  @override
  Future<void> handleRemoteEvent(RemoteEvent event) async {
    _assertCallback('handleRemoteEvent');

    // Update `receivedDocument` as appropriate for any limbo targets.
    for (MapEntry<int, TargetChange> entry in event.targetChanges.entries) {
      final int targetId = entry.key;
      final TargetChange targetChange = entry.value;
      final _LimboResolution limboResolution = _activeLimboResolutionsByTarget[targetId];
      if (limboResolution != null) {
        // Since this is a limbo resolution lookup, it's for a single document and it could be added, modified, or
        // removed, but not a combination.
        hardAssert(
            targetChange.addedDocuments.length +
                    targetChange.modifiedDocuments.length +
                    targetChange.removedDocuments.length <=
                1,
            'Limbo resolution for single document contains multiple changes.');
        if (targetChange.addedDocuments.isNotEmpty) {
          limboResolution.receivedDocument = true;
        } else if (targetChange.modifiedDocuments.isNotEmpty) {
          hardAssert(limboResolution.receivedDocument, 'Received change for limbo target document without add.');
        } else if (targetChange.removedDocuments.isNotEmpty) {
          hardAssert(limboResolution.receivedDocument, 'Received remove for limbo target document without add.');
          limboResolution.receivedDocument = false;
        } else {
          // This was probably just a CURRENT targetChange or similar.
        }
      }
    }

    final ImmutableSortedMap<DocumentKey, MaybeDocument> changes = await _localStore.applyRemoteEvent(event);
    await _emitNewSnapsAndNotifyLocalStore(changes, event);
  }

  /// Applies an [OnlineState] change to the sync engine and notifies any views
  /// of the change.
  @override
  Future<void> handleOnlineStateChange(OnlineState onlineState) async {
    _assertCallback('handleOnlineStateChange');
    final List<ViewSnapshot> newViewSnapshots = <ViewSnapshot>[];
    for (MapEntry<Query, QueryView> entry in _queryViewsByQuery.entries) {
      final View view = entry.value.view;
      final ViewChange viewChange = view.applyOnlineStateChange(onlineState);
      hardAssert(viewChange.limboChanges.isEmpty, 'OnlineState should not affect limbo documents.');
      if (viewChange.snapshot != null) {
        newViewSnapshots.add(viewChange.snapshot);
      }
    }
    await _syncEngineListener.onViewSnapshots(newViewSnapshots);
    _syncEngineListener.handleOnlineStateChange(onlineState);
  }

  @override
  ImmutableSortedSet<DocumentKey> getRemoteKeysForTarget(int targetId) {
    final _LimboResolution limboResolution = _activeLimboResolutionsByTarget[targetId];
    if (limboResolution != null && limboResolution.receivedDocument) {
      return DocumentKey.emptyKeySet.insert(limboResolution.key);
    } else {
      ImmutableSortedSet<DocumentKey> remoteKeys = DocumentKey.emptyKeySet;
      if (_queriesByTarget.containsKey(targetId)) {
        for (Query query in _queriesByTarget[targetId]) {
          if (_queryViewsByQuery.containsKey(query)) {
            remoteKeys = remoteKeys.unionWith(_queryViewsByQuery[query].view.syncedDocuments);
          }
        }
      }

      return remoteKeys;
    }
  }

  /// Called by FirestoreClient to notify us of a rejected listen.
  @override
  Future<void> handleRejectedListen(int targetId, GrpcError error) async {
    _assertCallback('handleRejectedListen');

    final _LimboResolution limboResolution = _activeLimboResolutionsByTarget[targetId];
    final DocumentKey limboKey = limboResolution != null ? limboResolution.key : null;
    if (limboKey != null) {
      // Since this query failed, we won't want to manually unlisten to it. So go ahead and remove it from bookkeeping.
      _activeLimboTargetsByKey.remove(limboKey);
      _activeLimboResolutionsByTarget.remove(targetId);
      await _pumpEnqueuedLimboResolutions();

      // TODO(long1eu): Retry on transient errors?

      // It's a limbo doc. Create a synthetic event saying it was deleted. This is kind of a hack. Ideally, we would
      // have a method in the local store to purge a document. However, it would be tricky to keep all of the local
      // store's invariants with another method.
      final Map<DocumentKey, MaybeDocument> documentUpdates = <DocumentKey, MaybeDocument>{
        limboKey: NoDocument(
          limboKey,
          SnapshotVersion.none,
          hasCommittedMutations: false,
        )
      };
      final Set<DocumentKey> limboDocuments = <DocumentKey>{limboKey};
      final RemoteEvent event = RemoteEvent(
        documentUpdates: documentUpdates,
        resolvedLimboDocuments: limboDocuments,
      );
      await handleRemoteEvent(event);
    } else {
      await _localStore.releaseTarget(targetId);
      await _removeAndCleanupTarget(targetId, error);
    }
  }

  @override
  Future<void> handleSuccessfulWrite(MutationBatchResult mutationBatchResult) async {
    _assertCallback('handleSuccessfulWrite');

    // The local store may or may not be able to apply the write result and raise events immediately (depending on
    // whether the watcher is caught up), so we raise user callbacks first so that they consistently happen before
    // listen events.
    _notifyUser(mutationBatchResult.batch.batchId, /*status:*/ null);

    _resolvePendingWriteTasks(mutationBatchResult.batch.batchId);

    final ImmutableSortedMap<DocumentKey, MaybeDocument> changes =
        await _localStore.acknowledgeBatch(mutationBatchResult);

    await _emitNewSnapsAndNotifyLocalStore(changes, /*remoteEvent:*/ null);
  }

  @override
  Future<void> handleRejectedWrite(int batchId, GrpcError status) async {
    _assertCallback('handleRejectedWrite');

    final ImmutableSortedMap<DocumentKey, MaybeDocument> changes = await _localStore.rejectBatch(batchId);

    if (changes.isNotEmpty) {
      _logErrorIfInteresting(status, 'Write failed at ${changes.minKey.path}');
    }

    // The local store may or may not be able to apply the write result and raise events immediately (depending on
    // whether the watcher is caught up), so we raise user callbacks first so that they consistently happen before
    // listen events.
    _notifyUser(batchId, status);

    _resolvePendingWriteTasks(batchId);

    await _emitNewSnapsAndNotifyLocalStore(changes, /*remoteEvent:*/ null);
  }

  /// Takes a snapshot of current mutation queue, and register a user task which will resolve when
  /// all those mutations are either accepted or rejected by the server.
  Future<void> registerPendingWritesTask(Completer<void> userTask) async {
    if (!_remoteStore.canUseNetwork()) {
      Log.d(_tag,
          'The network is disabled. The task returned by [awaitPendingWrites] will not complete until the network is enabled.');
    }

    final int largestPendingBatchId = await _localStore.getHighestUnacknowledgedBatchId();

    if (largestPendingBatchId == MutationBatch.unknown) {
      // Complete the task right away if there is no pending writes at the moment.
      userTask.complete(null);
      return;
    }

    if (!_pendingWritesCallbacks.containsKey(largestPendingBatchId)) {
      _pendingWritesCallbacks[largestPendingBatchId] = <Completer<void>>[];
    }

    _pendingWritesCallbacks[largestPendingBatchId].add(userTask);
  }

  /// Resolves tasks waiting for this batch id to get acknowledged by server, if there are any.
  void _resolvePendingWriteTasks(int batchId) {
    if (_pendingWritesCallbacks.containsKey(batchId)) {
      for (Completer<void> task in _pendingWritesCallbacks[batchId]) {
        task.complete(null);
      }

      _pendingWritesCallbacks.remove(batchId);
    }
  }

  void _failOutstandingPendingWritesAwaitingTasks() {
    for (MapEntry<int, List<Completer<void>>> entry in _pendingWritesCallbacks.entries) {
      for (Completer<void> task in entry.value) {
        task.completeError(FirestoreError(
            "'waitForPendingWrites' task is cancelled due to User change.", FirestoreErrorCode.cancelled));
      }
    }

    _pendingWritesCallbacks.clear();
  }

  /// Resolves the task corresponding to this write result.
  void _notifyUser(int batchId, GrpcError status) {
    final Map<int, Completer<void>> userTasks = _mutationUserCallbacks[_currentUser];

    // NOTE: Mutations restored from persistence won't have task completion
    // sources, so it's okay for this (or the task below) to be null.
    if (userTasks != null) {
      final int boxedBatchId = batchId;
      final Completer<void> userTask = userTasks[boxedBatchId];
      if (userTask != null) {
        if (status != null) {
          userTask.completeError(exceptionFromStatus(status));
        } else {
          userTask.complete(null);
        }
        userTasks.remove(boxedBatchId);
      }
    }
  }

  Future<void> _removeAndCleanupTarget(int targetId, GrpcError status) async {
    for (Query query in _queriesByTarget[targetId]) {
      _queryViewsByQuery.remove(query);
      if (status.code != StatusCode.ok) {
        _syncEngineListener.onError(query, status);
        _logErrorIfInteresting(status, 'Listen for $query failed');
      }
    }
    _queriesByTarget.remove(targetId);

    final ImmutableSortedSet<DocumentKey> limboKeys = _limboDocumentRefs.referencesForId(targetId);
    _limboDocumentRefs.removeReferencesForId(targetId);
    for (DocumentKey key in limboKeys) {
      if (!_limboDocumentRefs.containsKey(key)) {
        // We removed the last reference for this key.
        await _removeLimboTarget(key);
      }
    }
  }

  Future<void> _removeLimboTarget(DocumentKey key) async {
    // It's possible that the target already got removed because the query failed. In that case, the key won't exist in
    // limboTargetsByKey. Only do the cleanup if we still have the target.
    final int targetId = _activeLimboTargetsByKey[key];
    if (targetId != null) {
      await _remoteStore.stopListening(targetId);
      _activeLimboTargetsByKey.remove(key);
      _activeLimboResolutionsByTarget.remove(targetId);
      await _pumpEnqueuedLimboResolutions();
    }
  }

  /// Computes a new snapshot from the changes and calls the registered callback with the new snapshot.
  Future<void> _emitNewSnapsAndNotifyLocalStore(
    ImmutableSortedMap<DocumentKey, MaybeDocument> changes,
    RemoteEvent remoteEvent,
  ) async {
    final List<ViewSnapshot> newSnapshots = <ViewSnapshot>[];
    final List<LocalViewChanges> documentChangesInAllViews = <LocalViewChanges>[];

    for (MapEntry<Query, QueryView> entry in _queryViewsByQuery.entries) {
      final QueryView queryView = entry.value;
      final View view = queryView.view;
      ViewDocumentChanges viewDocChanges = view.computeDocChanges(changes);
      if (viewDocChanges.needsRefill) {
        // The query has a limit and some docs were removed/updated, so we need to re-run the query against the local
        // store to make sure we didn't lose any good docs that had been past the limit.
        final QueryResult queryResult =
            await _localStore.executeQuery(queryView.query, /* usePreviousResults= */ false);
        viewDocChanges = view.computeDocChanges(queryResult.documents, viewDocChanges);
      }
      final TargetChange targetChange = remoteEvent == null ? null : remoteEvent.targetChanges[queryView.targetId];
      final ViewChange viewChange = queryView.view.applyChanges(viewDocChanges, targetChange);
      await _updateTrackedLimboDocuments(viewChange.limboChanges, queryView.targetId);

      if (viewChange.snapshot != null) {
        newSnapshots.add(viewChange.snapshot);
        final LocalViewChanges docChanges = LocalViewChanges.fromViewSnapshot(
          queryView.targetId,
          viewChange.snapshot,
        );
        documentChangesInAllViews.add(docChanges);
      }
    }

    await _syncEngineListener.onViewSnapshots(newSnapshots);
    await _localStore.notifyLocalViewChanges(documentChangesInAllViews);
  }

  /// Updates the limbo document state for the given targetId.
  Future<void> _updateTrackedLimboDocuments(List<LimboDocumentChange> limboChanges, int targetId) async {
    for (LimboDocumentChange limboChange in limboChanges) {
      switch (limboChange.type) {
        case LimboDocumentChangeType.added:
          _limboDocumentRefs.addReference(limboChange.key, targetId);
          await _trackLimboChange(limboChange);
          break;
        case LimboDocumentChangeType.removed:
          Log.d(_tag, 'Document no longer in limbo: ${limboChange.key}');
          final DocumentKey limboDocKey = limboChange.key;
          _limboDocumentRefs.removeReference(limboDocKey, targetId);
          if (!_limboDocumentRefs.containsKey(limboDocKey)) {
            // We removed the last reference for this key
            await _removeLimboTarget(limboDocKey);
          }
          break;
        default:
          throw fail('Unknown limbo change type: ${limboChange.type}');
      }
    }
  }

  Future<void> _trackLimboChange(LimboDocumentChange change) async {
    final DocumentKey key = change.key;
    if (!_activeLimboTargetsByKey.containsKey(key)) {
      Log.d(_tag, 'New document in limbo: $key');
      _enqueuedLimboResolutions.add(key);
      await _pumpEnqueuedLimboResolutions();
    }
  }

  /// Starts listens for documents in limbo that are enqueued for resolution, subject to a maximum
  /// number of concurrent resolutions.
  ///
  /// <p>Without bounding the number of concurrent resolutions, the server can fail with "resource
  /// exhausted" errors which can lead to pathological client behavior as seen in
  /// https://github.com/firebase/firebase-js-sdk/issues/2683.
  Future<void> _pumpEnqueuedLimboResolutions() async {
    while (_enqueuedLimboResolutions.isNotEmpty && _activeLimboTargetsByKey.length < _maxConcurrentLimboResolutions) {
      final DocumentKey key = _enqueuedLimboResolutions.removeFirst();
      final int limboTargetId = _targetIdGenerator.nextId;
      _activeLimboResolutionsByTarget[limboTargetId] = _LimboResolution(key);
      _activeLimboTargetsByKey[key] = limboTargetId;
      await _remoteStore.listen(
        TargetData(
          Query(key.path).toTarget(),
          limboTargetId,
          ListenSequence.invalid,
          QueryPurpose.limboResolution,
        ),
      );
    }
  }

  @visibleForTesting
  Map<DocumentKey, int> getActiveLimboDocumentResolutions() {
    // Make a defensive copy as the Map continues to be modified.
    return Map<DocumentKey, int>.from(_activeLimboTargetsByKey);
  }

  @visibleForTesting
  Queue<DocumentKey> getEnqueuedLimboDocumentResolutions() {
    // Make a defensive copy as the Queue continues to be modified.
    return Queue<DocumentKey>.from(_enqueuedLimboResolutions);
  }

  Future<void> handleCredentialChange(User user) async {
    final bool userChanged = _currentUser != user;
    _currentUser = user;

    if (userChanged) {
      // Fails tasks waiting for pending writes requested by previous user.
      _failOutstandingPendingWritesAwaitingTasks();
      // Notify local store and emit any resulting events from swapping out the mutation queue.
      final ImmutableSortedMap<DocumentKey, MaybeDocument> changes = await _localStore.handleUserChange(user);
      await _emitNewSnapsAndNotifyLocalStore(changes, /*remoteEvent:*/ null);
    }

    // Notify remote store so it can restart its streams.
    await _remoteStore.handleCredentialChange();
  }

  /// Logs the error as a warnings if it likely represents a developer mistake such as forgetting to create an index or
  /// permission denied.
  void _logErrorIfInteresting(GrpcError error, String contextString) {
    if (_errorIsInteresting(error)) {
      Log.w('Firestore', '$contextString: $error');
    }
  }

  bool _errorIsInteresting(GrpcError error) {
    final int code = error.code;
    final String description = error.message ?? '';

    if (code == StatusCode.failedPrecondition && description.contains('requires an index')) {
      return true;
    } else if (code == StatusCode.permissionDenied) {
      return true;
    }

    return false;
  }
}

/// Tracks a limbo resolution.
class _LimboResolution {
  _LimboResolution(this.key);

  final DocumentKey key;

  /// Set to true once we've received a document. This is used in [SyncEngine.getRemoteKeysForTarget] and ultimately
  /// used by [WatchChangeAggregator] to decide whether it needs to manufacture a delete event for the target once the
  /// target is CURRENT.
  bool receivedDocument = false;
}

/// Interface implemented by EventManager to handle notifications from SyncEngine.
abstract class SyncEngineCallback {
  /// Handles new view snapshots.
  Future<void> onViewSnapshots(List<ViewSnapshot> snapshotList);

  /// Handles the failure of a query.
  void onError(Query query, GrpcError error);

  /// Handles a change in online state.
  void handleOnlineStateChange(OnlineState onlineState);
}

/// QueryView contains all of the info that SyncEngine needs to track for a particular query and
/// view.
class QueryView {
  const QueryView(this.query, this.targetId, this.view);

  final Query query;
  final int targetId;
  final View view;
}
