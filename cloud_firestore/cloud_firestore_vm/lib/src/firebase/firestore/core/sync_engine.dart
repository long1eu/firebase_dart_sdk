// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'dart:async';

import 'package:_firebase_database_collection_vm/_firebase_database_collection_vm.dart';
import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/aggregate_field.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/bundle/bundle_element.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/bundle/bundle_loader.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/bundle/bundle_metadata.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/bundle/bundle_reader.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/event_manager.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/firestore_client.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/limbo_document_change.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/listent_sequence.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/online_state.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/target_id_generator.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/view.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/view_change.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/view_snapshot.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/load_bundle_task.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/load_bundle_task_progress.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/local_view_changes.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/local_write_result.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/query_purpose.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/reference_set.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation_batch_result.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/no_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/remote_event.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/remote_store.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/target_change.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/util.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/vector_query.dart';
import 'package:grpc/grpc.dart';
import 'package:meta/meta.dart';

/// [SyncEngine] is the central controller in the client SDK architecture. It is the glue code between the
/// [EventManager], [LocalStore], and [RemoteStore]. Some of [SyncEngine]'s responsibilities include:
///
/// Coordinating client requests and remote events between the [EventManager] and the local and remote data stores.
/// Managing a [View] object for each query, providing the unified view between the local and remote data stores.
/// Notifying the [RemoteStore] when the [LocalStore] has new mutations in its queue that need sending to the backend.
///
/// The [SyncEngine]’s methods should only ever be called by methods running on our own worker dispatch queue.
class SyncEngine implements RemoteStoreCallback {
  SyncEngine(
    this._localStore,
    this._remoteStore,
    this._currentUser, {
    int maxConcurrentLimboResolutions = _defaultMaxConcurrentLimboResolutions,
  })  : _maxConcurrentLimboResolutions = maxConcurrentLimboResolutions,
        _queryViewsByQuery = <Query, QueryView>{},
        _queriesByTarget = <int, List<Query>>{},
        _enqueuedLimboResolutions = <DocumentKey>{},
        _activeLimboTargetsByKey = <DocumentKey, int>{},
        _activeLimboResolutionsByTarget = <int, _LimboResolution>{},
        _limboDocumentRefs = ReferenceSet(),
        _mutationUserCallbacks = <User, Map<int, Completer<void>>>{},
        _pendingWritesCallbacks = <int, List<Completer<void>>>{},
        _targetIdGenerator = TargetIdGenerator.forSyncEngine();

  static const String _tag = 'SyncEngine';

  /// The maximum number of concurrently active limbo resolution listens.
  static const int _defaultMaxConcurrentLimboResolutions = 100;

  /// The local store, used to persist mutations and cached documents.
  final LocalStore _localStore;

  /// The remote store for sending writes, watches, etc. to the backend.
  final RemoteStore _remoteStore;

  /// [QueryViews] for all active queries, indexed by query.
  final Map<Query, QueryView> _queryViewsByQuery;

  /// Queries mapped to active targets, indexed by target id. Several queries may map to the same target (e.g. a limit
  /// query and a mirroring limitToLast query).
  final Map<int, List<Query>> _queriesByTarget;

  /// When a document is in limbo, we create a special listen to resolve it. This maps the [DocumentKey] of each limbo
  /// document to the target id of the listen resolving it.
  final Map<DocumentKey, int> _activeLimboTargetsByKey;

  /// The maximum number of limbo resolution listens that may be active at the same time.
  final int _maxConcurrentLimboResolutions;

  /// The keys of documents that are in limbo for which we haven't yet started a limbo resolution query. A (linked)
  /// set that keeps the insertion order: the resolutions are started in the order they were enqueued.
  final Set<DocumentKey> _enqueuedLimboResolutions;

  /// Basically the inverse of [_activeLimboTargetsByKey], a map of target id to a [_LimboResolution] (which includes the
  /// DocumentKey as well as whether we've received a document for the target).
  final Map<int, _LimboResolution> _activeLimboResolutionsByTarget;

  /// Used to track any documents that are currently in limbo.
  final ReferenceSet _limboDocumentRefs;

  /// Stores user completion blocks, indexed by user and batch id.
  final Map<User, Map<int, Completer<void>>> _mutationUserCallbacks;

  /// Stores user callbacks waiting for all pending writes to be acknowledged, indexed by the batch id of the last
  /// write that was pending when they were registered.
  final Map<int, List<Completer<void>>> _pendingWritesCallbacks;

  /// Used for creating the target ids for the listens used to resolve limbo documents.
  final TargetIdGenerator _targetIdGenerator;

  User _currentUser;

  SyncEngineCallback? _syncEngineListener;

  SyncEngineCallback get _listener => _syncEngineListener!;

  set syncEngineListener(SyncEngineCallback callback) {
    _syncEngineListener = callback;
  }

  void _assertCallback(String method) {
    hardAssertLazy(_syncEngineListener != null,
        () => 'Trying to call $method before setting callback');
  }

  /// Initiates a new listen.
  ///
  /// The [LocalStore] will be queried for initial data and the listen will be
  /// sent to the [RemoteStore] to get remote data. The registered
  /// [SyncEngineCallback] will be notified of resulting view snapshots and/or
  /// listen errors.
  ///
  /// If [shouldListenToRemote] is false the query is only listened locally,
  /// the listen is not sent to the [RemoteStore] (see
  /// [listenToRemoteStore]).
  ///
  /// Returns the target ID assigned to the query.
  Future<int> listen(Query query, {bool shouldListenToRemote = true}) async {
    _assertCallback('listen');
    hardAssertLazy(!_queryViewsByQuery.containsKey(query),
        () => 'We already listen to query: $query');

    final QueryData queryData = await _localStore.allocateTarget(query.toTarget());

    // The view has to exist before the remote store sends the listen request: the request carries the number of
    // documents the client already has for the target (expected count), which is read from the view.
    final ViewSnapshot viewSnapshot =
        await initializeViewAndComputeSnapshot(query, queryData);
    await _listener.onViewSnapshots(<ViewSnapshot>[viewSnapshot]);

    if (shouldListenToRemote) {
      _listenToRemote(queryData);
    }
    return queryData.targetId;
  }

  Future<ViewSnapshot> initializeViewAndComputeSnapshot(
      Query query, QueryData queryData) async {
    final ImmutableSortedMap<DocumentKey, Document> docs =
        await _localStore.executeQuery(query);
    final ImmutableSortedSet<DocumentKey> remoteKeys =
        await _localStore.getRemoteDocumentKeys(queryData.targetId);

    final View view = View(query, remoteKeys);
    final ViewDocumentChanges viewDocChanges = view.computeDocChanges(docs);

    // The initial snapshot carries the resume token of the target so that an empty result of a target that has been
    // synced before can be raised from the cache. If there are already queries mapped to the target, the sync state of
    // those queries is applied to the new query as well.
    bool targetIsCurrent = false;
    final List<Query>? mirrorQueries = _queriesByTarget[queryData.targetId];
    if (mirrorQueries != null && mirrorQueries.isNotEmpty) {
      final QueryView? mirrorView = _queryViewsByQuery[mirrorQueries.first];
      targetIsCurrent = mirrorView != null &&
          mirrorView.view.syncState == ViewSnapshotSyncState.synced;
    }
    final TargetChange synthesizedCurrentChange =
        TargetChange.createSynthesizedTargetChangeForCurrentChange(
            targetIsCurrent, queryData.resumeToken);
    final ViewChange viewChange =
        view.applyChanges(viewDocChanges, synthesizedCurrentChange);
    hardAssert(view.limboDocuments.isEmpty,
        'View returned limbo docs before target ack from the server');

    final QueryView queryView =
        QueryView(query, queryData.targetId, view, queryData);
    _queryViewsByQuery[query] = queryView;
    // Most likely there will only be one query mapping to a target.
    _queriesByTarget
        .putIfAbsent(queryData.targetId, () => <Query>[])
        .add(query);
    return viewChange.snapshot!;
  }

  /// Sends the listen of a query that is already listened locally to the
  /// [RemoteStore]. Used when a listener that needs the backend is added to a
  /// query that so far only listened to the cache.
  Future<void> listenToRemoteStore(Query query) async {
    _assertCallback('listenToRemoteStore');
    final QueryView? queryView = _queryViewsByQuery[query];
    hardAssert(queryView != null, 'This is the first listen to query: $query');

    _listenToRemote(queryView!.queryData);
  }

  /// Sends the listen to the [RemoteStore] without waiting for it: starting the watch stream needs the network
  /// (credentials, connection), which must not hold up the operations that are queued behind this one, like writes
  /// with a local cache. The remote store registers the target synchronously; a failure to start the stream is
  /// reported by the stream itself.
  void _listenToRemote(QueryData queryData) {
    unawaited(_remoteStore.listen(queryData).catchError(
        (Object error, StackTrace stackTrace) {
      Zone.current.handleUncaughtError(error, stackTrace);
    }));
  }

  /// Stops listening to a query previously listened to via listen. The target
  /// is only removed from the [RemoteStore] if [shouldUnlistenToRemote] is
  /// true.
  Future<void> stopListening(Query query,
      {bool shouldUnlistenToRemote = true}) async {
    _assertCallback('stopListening');

    final QueryView? queryView = _queryViewsByQuery[query];
    hardAssert(
        queryView != null, 'Trying to stop listening to a query not found');

    _queryViewsByQuery.remove(query);

    final int targetId = queryView!.targetId;
    final List<Query> targetQueries = _queriesByTarget[targetId]!;
    targetQueries.remove(query);

    if (targetQueries.isEmpty) {
      await _localStore.releaseTarget(targetId);
      if (shouldUnlistenToRemote) {
        await _remoteStore.stopListening(targetId);
      }
      await _removeAndCleanupTarget(targetId, null);
    }
  }

  /// Stops listening to a query from the backend, while it keeps listening to
  /// the cache. Used when the last listener that needs the backend is removed
  /// from a query that still has cache only listeners.
  Future<void> stopListeningToRemoteStore(Query query) async {
    _assertCallback('stopListeningToRemoteStore');
    final QueryView? queryView = _queryViewsByQuery[query];
    hardAssert(
        queryView != null, 'Trying to stop listening to a query not found');

    await _remoteStore.stopListening(queryView!.targetId);
  }

  /// Initiates the write of local mutation batch which involves adding the writes to the mutation queue, notifying the
  /// remote store about new mutations, and raising events for any changes this write caused.
  ///
  /// The provided Future will be resolved once the write has been acked/rejected by the backend (or failed locally for
  /// any other reason).
  Future<void> writeMutations(
      List<Mutation> mutations, Completer<void> userTask) async {
    _assertCallback('writeMutations');

    final LocalWriteResult result = await _localStore.writeLocally(mutations);
    _addUserCallback(result.batchId, userTask);

    await _emitNewSnapsAndNotifyLocalStore(
        result.changes, /*remoteEvent:*/ null);
    await _remoteStore.fillWritePipeline();
  }

  void _addUserCallback(int batchId, Completer<void> userTask) {
    Map<int, Completer<void>>? userTasks = _mutationUserCallbacks[_currentUser];
    if (userTasks == null) {
      userTasks = <int, Completer<void>>{};
      _mutationUserCallbacks[_currentUser] = userTasks;
    }
    userTasks[batchId] = userTask;
  }

  /// Runs an aggregation over [query] on the server.
  Future<Map<String, FieldValue>> runAggregateQuery(
      Query query, List<AggregateField> aggregateFields) {
    return _remoteStore.runAggregateQuery(query, aggregateFields);
  }

  /// Runs a vector query over [query] on the server.
  Future<List<Document>> runVectorQuery(Query query, VectorQuery vectorQuery) {
    return _remoteStore.runVectorQuery(query, vectorQuery);
  }

  /// Called by [FirestoreClient] to notify us of a new remote event.
  @override
  Future<void> handleRemoteEvent(RemoteEvent event) async {
    _assertCallback('handleRemoteEvent');

    // Update `receivedDocument` as appropriate for any limbo targets.
    for (MapEntry<int, TargetChange> entry in event.targetChanges.entries) {
      final int targetId = entry.key;
      final TargetChange targetChange = entry.value;
      final _LimboResolution? limboResolution =
          _activeLimboResolutionsByTarget[targetId];
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
          hardAssert(limboResolution.receivedDocument,
              'Received change for limbo target document without add.');
        } else if (targetChange.removedDocuments.isNotEmpty) {
          hardAssert(limboResolution.receivedDocument,
              'Received remove for limbo target document without add.');
          limboResolution.receivedDocument = false;
        } else {
          // This was probably just a CURRENT targetChange or similar.
        }
      }
    }

    final ImmutableSortedMap<DocumentKey, MaybeDocument> changes =
        await _localStore.applyRemoteEvent(event);
    await _emitNewSnapsAndNotifyLocalStore(changes, event);
  }

  /// Applies an [OnlineState] change to the sync engine and notifies any views
  /// of the change.
  @override
  Future<void> handleOnlineStateChange(OnlineState onlineState) async {
    final List<ViewSnapshot> newViewSnapshots = <ViewSnapshot>[];
    for (MapEntry<Query, QueryView> entry in _queryViewsByQuery.entries) {
      final View view = entry.value.view;
      final ViewChange viewChange = view.applyOnlineStateChange(onlineState);
      hardAssert(viewChange.limboChanges.isEmpty,
          'OnlineState should not affect limbo documents.');
      final ViewSnapshot? snapshot = viewChange.snapshot;
      if (snapshot != null) {
        newViewSnapshots.add(snapshot);
      }
    }
    await _listener.onViewSnapshots(newViewSnapshots);
    _listener.handleOnlineStateChange(onlineState);
  }

  // TODO(long1eu): implement getRemoteKeysForTarget
  @override
  ImmutableSortedSet<DocumentKey> Function(int targetId)
      get getRemoteKeysForTarget {
    return (int targetId) {
      final _LimboResolution? limboResolution =
          _activeLimboResolutionsByTarget[targetId];
      if (limboResolution != null && limboResolution.receivedDocument) {
        return DocumentKey.emptyKeySet.insert(limboResolution.key);
      } else {
        ImmutableSortedSet<DocumentKey> remoteKeys = DocumentKey.emptyKeySet;
        final List<Query>? targetQueries = _queriesByTarget[targetId];
        if (targetQueries != null) {
          for (Query query in targetQueries) {
            final QueryView? queryView = _queryViewsByQuery[query];
            if (queryView != null) {
              for (DocumentKey key in queryView.view.syncedDocuments) {
                remoteKeys = remoteKeys.insert(key);
              }
            }
          }
        }
        return remoteKeys;
      }
    };
  }

  /// Called by FirestoreClient to notify us of a rejected listen.
  @override
  Future<void> handleRejectedListen(int targetId, GrpcError error) async {
    _assertCallback('handleRejectedListen');

    final _LimboResolution? limboResolution =
        _activeLimboResolutionsByTarget[targetId];
    final DocumentKey? limboKey =
        limboResolution != null ? limboResolution.key : null;
    if (limboKey != null) {
      // Since this query failed, we won't want to manually unlisten to it. So go ahead and remove it from bookkeeping.
      _activeLimboTargetsByKey.remove(limboKey);
      _activeLimboResolutionsByTarget.remove(targetId);
      await _pumpEnqueuedLimboResolutions();

      // TODO(long1eu): Retry on transient errors?

      // It's a limbo doc. Create a synthetic event saying it was deleted. This is kind of a hack. Ideally, we would
      // have a method in the local store to purge a document. However, it would be tricky to keep all of the local
      // store's invariants with another method.
      final Map<DocumentKey, MaybeDocument> documentUpdates =
          <DocumentKey, MaybeDocument>{
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
      hardAssertLazy(_queriesByTarget.containsKey(targetId),
          () => 'Unknown target: $targetId');
      await _localStore.releaseTarget(targetId);
      await _removeAndCleanupTarget(targetId, error);
    }
  }

  @override
  Future<void> handleSuccessfulWrite(
      MutationBatchResult mutationBatchResult) async {
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

    final ImmutableSortedMap<DocumentKey, MaybeDocument> changes =
        await _localStore.rejectBatch(batchId);

    if (changes.isNotEmpty) {
      _logErrorIfInteresting(status, 'Write failed at ${changes.minKey!.path}');
    }

    // The local store may or may not be able to apply the write result and raise events immediately (depending on
    // whether the watcher is caught up), so we raise user callbacks first so that they consistently happen before
    // listen events.
    _notifyUser(batchId, status);

    _resolvePendingWriteTasks(batchId);

    await _emitNewSnapsAndNotifyLocalStore(changes, /*remoteEvent:*/ null);
  }

  /// Takes a snapshot of the current mutation queue and completes [userTask] when all those mutations are either
  /// accepted or rejected by the server.
  Future<void> registerPendingWritesTask(Completer<void> userTask) async {
    if (!_remoteStore.canUseNetwork) {
      Log.d(
          _tag,
          'The network is disabled. The task returned by \'waitForPendingWrites()\' will not complete until the '
          'network is enabled.');
    }

    final int largestPendingBatchId =
        await _localStore.getHighestUnacknowledgedBatchId();

    if (largestPendingBatchId == MutationBatch.unknown) {
      // Complete the task right away if there is no pending writes at the moment.
      userTask.complete();
      return;
    }

    (_pendingWritesCallbacks[largestPendingBatchId] ??= <Completer<void>>[])
        .add(userTask);
  }

  /// Resolves tasks waiting for this batch id to get acknowledged by the server, if there are any.
  void _resolvePendingWriteTasks(int batchId) {
    final List<Completer<void>>? tasks =
        _pendingWritesCallbacks.remove(batchId);
    if (tasks != null) {
      for (Completer<void> task in tasks) {
        task.complete();
      }
    }
  }

  void _failOutstandingPendingWritesAwaitingTasks() {
    final List<Completer<void>> tasks = <Completer<void>>[
      for (List<Completer<void>> list in _pendingWritesCallbacks.values) ...list
    ];
    _pendingWritesCallbacks.clear();
    for (Completer<void> task in tasks) {
      task.completeError(FirestoreError(
          '\'waitForPendingWrites\' task is cancelled due to User change.',
          FirestoreErrorCode.cancelled));
    }
  }

  /// Resolves the task corresponding to this write result.
  void _notifyUser(int batchId, GrpcError? status) {
    final Map<int, Completer<void>>? userTasks =
        _mutationUserCallbacks[_currentUser];

    // NOTE: Mutations restored from persistence won't have task completion
    // sources, so it's okay for this (or the task below) to be null.
    if (userTasks != null) {
      final int boxedBatchId = batchId;
      final Completer<void>? userTask = userTasks[boxedBatchId];
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

  /// Removes the bookkeeping of all the queries mapped to [targetId]. If [error] is not null, it is raised for each of
  /// those queries.
  Future<void> _removeAndCleanupTarget(int targetId, GrpcError? error) async {
    for (Query query in _queriesByTarget[targetId] ?? const <Query>[]) {
      _queryViewsByQuery.remove(query);
      if (error != null) {
        _listener.onError(query, error);
        _logErrorIfInteresting(error, 'Listen for $query failed');
      }
    }
    _queriesByTarget.remove(targetId);

    final ImmutableSortedSet<DocumentKey> limboKeys =
        _limboDocumentRefs.referencesForId(targetId);
    _limboDocumentRefs.removeReferencesForId(targetId);
    for (DocumentKey key in limboKeys) {
      if (!_limboDocumentRefs.containsKey(key)) {
        // We removed the last reference for this key.
        await _removeLimboTarget(key);
      }
    }
  }

  Future<void> _removeLimboTarget(DocumentKey key) async {
    _enqueuedLimboResolutions.remove(key);
    // It's possible that the target already got removed because the query failed. In that case, the key won't exist in
    // limboTargetsByKey. Only do the cleanup if we still have the target.
    final int? targetId = _activeLimboTargetsByKey[key];
    if (targetId != null) {
      // Remove the bookkeeping before awaiting, so that a document re-entering limbo meanwhile is resolved.
      _activeLimboTargetsByKey.remove(key);
      _activeLimboResolutionsByTarget.remove(targetId);
      await _remoteStore.stopListening(targetId);
      await _pumpEnqueuedLimboResolutions();
    }
  }

  /// Computes a new snapshot from the changes and calls the registered callback with the new snapshot.
  Future<void> _emitNewSnapsAndNotifyLocalStore(
    ImmutableSortedMap<DocumentKey, MaybeDocument> changes,
    RemoteEvent? remoteEvent) async {
    final List<ViewSnapshot> newSnapshots = <ViewSnapshot>[];
    final List<LocalViewChanges> documentChangesInAllViews =
        <LocalViewChanges>[];

    // Iterate over a copy: the awaits below let listen/stopListening change the map.
    for (final QueryView queryView in _queryViewsByQuery.values.toList()) {
      if (!identical(_queryViewsByQuery[queryView.query], queryView)) {
        // The query stopped listening while we were emitting.
        continue;
      }
      final View view = queryView.view;
      ViewDocumentChanges viewDocChanges = view.computeDocChanges(changes);
      if (viewDocChanges.needsRefill) {
        // The query has a limit and some docs were removed/updated, so we need to re-run the query against the local
        // store to make sure we didn't lose any good docs that had been past the limit.
        final ImmutableSortedMap<DocumentKey, Document> docs =
            await _localStore.executeQuery(queryView.query);
        viewDocChanges = view.computeDocChanges(docs, viewDocChanges);
        if (!identical(_queryViewsByQuery[queryView.query], queryView)) {
          continue;
        }
      }
      final TargetChange? targetChange = remoteEvent == null
          ? null
          : remoteEvent.targetChanges[queryView.targetId];
      final bool targetIsPendingReset = remoteEvent != null &&
          remoteEvent.targetMismatches.containsKey(queryView.targetId);
      final ViewChange viewChange = queryView.view
          .applyChanges(viewDocChanges, targetChange, targetIsPendingReset);
      await _updateTrackedLimboDocuments(
          viewChange.limboChanges, queryView.targetId);

      final ViewSnapshot? snapshot = viewChange.snapshot;
      if (snapshot != null) {
        newSnapshots.add(snapshot);
        final LocalViewChanges docChanges = LocalViewChanges.fromViewSnapshot(
          queryView.targetId,
          snapshot,
        );
        documentChangesInAllViews.add(docChanges);
      }
    }

    await _listener.onViewSnapshots(newSnapshots);
    await _localStore.notifyLocalViewChanges(documentChangesInAllViews);
  }

  /// Updates the limbo document state for the given targetId.
  Future<void> _updateTrackedLimboDocuments(
      List<LimboDocumentChange> limboChanges, int targetId) async {
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
    if (!_activeLimboTargetsByKey.containsKey(key) &&
        !_enqueuedLimboResolutions.contains(key)) {
      Log.d(_tag, 'New document in limbo: $key');
      _enqueuedLimboResolutions.add(key);
      await _pumpEnqueuedLimboResolutions();
    }
  }

  /// Starts listens for documents in limbo that are enqueued for resolution, subject to a maximum number of
  /// concurrent resolutions.
  ///
  /// Without bounding the number of concurrent resolutions, the server can fail with 'resource exhausted' errors which
  /// can lead to the 'Cannot allocate more' target ID exhaustion.
  Future<void> _pumpEnqueuedLimboResolutions() async {
    while (_enqueuedLimboResolutions.isNotEmpty &&
        _activeLimboTargetsByKey.length < _maxConcurrentLimboResolutions) {
      final DocumentKey key = _enqueuedLimboResolutions.first;
      _enqueuedLimboResolutions.remove(key);
      final int limboTargetId = _targetIdGenerator.nextId;
      _activeLimboResolutionsByTarget[limboTargetId] = _LimboResolution(key);
      _activeLimboTargetsByKey[key] = limboTargetId;
      await _remoteStore.listen(QueryData(
        Query(key.path).toTarget(),
        limboTargetId,
        ListenSequence.invalid,
        QueryPurpose.limboResolution,
      ));
    }
  }

  /// Returns the documents that are in limbo with an active target (a resolution in progress).
  @visibleForTesting
  Map<DocumentKey, int> getActiveLimboDocumentResolutions() {
    // Make a defensive copy as the Map continues to be modified.
    return Map<DocumentKey, int>.from(_activeLimboTargetsByKey);
  }

  /// Returns the documents that are in limbo and enqueued for resolution, without an active target.
  @visibleForTesting
  List<DocumentKey> getEnqueuedLimboDocumentResolutions() {
    // Make a defensive copy as the Set continues to be modified.
    return List<DocumentKey>.from(_enqueuedLimboResolutions);
  }

  Future<void> handleCredentialChange(User user) async {
    final bool userChanged = _currentUser != user;

    if (userChanged) {
      // Fails tasks waiting for pending writes requested by the previous user.
      _failOutstandingPendingWritesAwaitingTasks();
      // Notify local store and emit any resulting events from swapping out the mutation queue.
      final ImmutableSortedMap<DocumentKey, MaybeDocument> changes =
          await _localStore.handleUserChange(user);
      // Switch the user only once the local store switched its mutation queue, so both agree on the current user.
      _currentUser = user;
      await _emitNewSnapsAndNotifyLocalStore(changes, /*remoteEvent:*/ null);
    }

    // Notify remote store so it can restart its streams.
    await _remoteStore.handleCredentialChange();
  }

  /// Loads the bundle read by [bundleReader] into the local store and reports the progress to [resultTask].
  Future<void> loadBundle(
      BundleReader bundleReader, LoadBundleTask resultTask) async {
    try {
      final BundleMetadata bundleMetadata =
          await bundleReader.getBundleMetadata();
      final bool hasNewerBundle =
          await _localStore.hasNewerBundle(bundleMetadata);
      if (hasNewerBundle) {
        resultTask.setResult(LoadBundleTaskProgress.forSuccess(bundleMetadata));
        return;
      }

      LoadBundleTaskProgress? progress =
          LoadBundleTaskProgress.forInitial(bundleMetadata);
      resultTask.updateProgress(progress);

      final BundleLoader bundleLoader =
          BundleLoader(_localStore, bundleMetadata);

      int currentBytesRead = 0;
      BundleElement? bundleElement;
      while ((bundleElement = await bundleReader.getNextElement()) != null) {
        final int oldBytesRead = currentBytesRead;
        currentBytesRead = bundleReader.bytesRead;
        progress = bundleLoader.addElement(
            bundleElement!, currentBytesRead - oldBytesRead);
        if (progress != null) {
          resultTask.updateProgress(progress);
        }
      }

      // The loader also saves the bundle metadata, so that loading the same bundle again is skipped.
      final ImmutableSortedMap<DocumentKey, MaybeDocument> changes =
          await bundleLoader.applyChanges();

      // TODO(b/160876443): This currently raises snapshots with `fromCache=false` if users already listen to some
      // queries and bundles has newer version.
      await _emitNewSnapsAndNotifyLocalStore(changes, /*remoteEvent:*/ null);

      resultTask.setResult(LoadBundleTaskProgress.forSuccess(bundleMetadata));
    } catch (e, stackTrace) {
      Log.w('Firestore', 'Loading bundle failed : $e');
      resultTask.setException(FirestoreError(
        'Bundle failed to load',
        FirestoreErrorCode.invalidArgument,
        e,
        stackTrace,
      ));
    } finally {
      try {
        await bundleReader.close();
      } catch (e) {
        Log.w(_tag, 'Exception while closing bundle: $e');
      }
    }
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

    if (code == StatusCode.failedPrecondition &&
        description.contains('requires an index')) {
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
  const QueryView(this.query, this.targetId, this.view, this.queryData);

  final Query query;

  /// The target data of the query, used to listen to the backend after the query
  /// has been listened to locally only.
  final QueryData queryData;
  final int targetId;
  final View view;
}
