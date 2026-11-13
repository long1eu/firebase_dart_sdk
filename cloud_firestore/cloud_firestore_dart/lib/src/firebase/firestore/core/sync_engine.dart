// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/aggregate_field.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_element.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_loader.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_metadata.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_reader.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/event_manager.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/firestore_client.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/limbo_document_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/listent_sequence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/online_state.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/target.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/target_id_generator.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/view.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/view_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/view_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/load_bundle_task.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/load_bundle_task_progress.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_view_changes.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_write_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_purpose.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/reference_set.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/shared_client_state.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/no_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_event.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/target_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/grpc_status.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/vector_query.dart';
import 'package:firebase_app_dart/internal.dart';
import 'package:meta/meta.dart';

/// [SyncEngine] is the central controller in the client SDK architecture. It is the glue code between the
/// [EventManager], [LocalStore], and [RemoteStore]. Some of [SyncEngine]'s responsibilities include:
///
/// Coordinating client requests and remote events between the [EventManager] and the local and remote data stores.
/// Managing a [View] object for each query, providing the unified view between the local and remote data stores.
/// Notifying the [RemoteStore] when the [LocalStore] has new mutations in its queue that need sending to the backend.
///
/// The [SyncEngine]’s methods should only ever be called by methods running on our own worker dispatch queue.
///
/// Several clients can share one persistence (the shared client state). One of them is the primary client
/// ([isPrimaryClient]): it is the only one that uses the network, and listens and writes for all of them. The others
/// learn about the results through the [SharedClientState] (the [SharedClientStateSyncer] methods). A client that does
/// not share its persistence is primary, with a [MemorySharedClientState].
class SyncEngine implements RemoteStoreCallback, SharedClientStateSyncer {
  SyncEngine(
    this._localStore,
    this._remoteStore,
    this._currentUser, {
    int maxConcurrentLimboResolutions = _defaultMaxConcurrentLimboResolutions,
    SharedClientState? sharedClientState,
    bool startAsPrimary = true,
  }) : _maxConcurrentLimboResolutions = maxConcurrentLimboResolutions,
       _sharedClientState = sharedClientState ?? MemorySharedClientState(),
       _primaryState = startAsPrimary ? true : null,
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

  /// The commit version of the newest write that the backend has acknowledged in this session. A remote event that
  /// is older does not reflect that write yet (see [_limboDocumentsConfirmedToExist]).
  SnapshotVersion _lastAcknowledgedCommitVersion = SnapshotVersion.none;

  /// Stores user completion blocks, indexed by user and batch id.
  final Map<User, Map<int, Completer<void>>> _mutationUserCallbacks;

  /// Stores user callbacks waiting for all pending writes to be acknowledged, indexed by the batch id of the last
  /// write that was pending when they were registered.
  final Map<int, List<Completer<void>>> _pendingWritesCallbacks;

  /// Used for creating the target ids for the listens used to resolve limbo documents.
  final TargetIdGenerator _targetIdGenerator;

  User _currentUser;

  /// Manages the state shared with the other clients of the persistence.
  final SharedClientState _sharedClientState;

  /// The last online state applied to the views.
  OnlineState _onlineState = OnlineState.unknown;

  SyncEngineCallback? _syncEngineListener;

  SyncEngineCallback get _listener => _syncEngineListener!;

  set syncEngineListener(SyncEngineCallback callback) {
    _syncEngineListener = callback;
  }

  void _assertCallback(String method) {
    hardAssertLazy(
      _syncEngineListener != null,
      () => 'Trying to call $method before setting callback',
    );
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

    final QueryView? existing = _queryViewsByQuery[query];
    if (existing != null) {
      // A primary client may have a view for the query already: it listens to it on behalf of another client. The
      // view is reused.
      _sharedClientState.addLocalQueryTarget(existing.targetId);
      await _listener.onViewSnapshots(<ViewSnapshot>[
        existing.view.computeInitialSnapshot(),
      ]);
      return existing.targetId;
    }

    final QueryData queryData = await _localStore.allocateTarget(
      query.toTarget(),
    );

    // A query that only listens to the cache is not registered as an active watch target.
    final QueryTargetState status = _sharedClientState.addLocalQueryTarget(
      queryData.targetId,
      addToActiveTargetIds: shouldListenToRemote,
    );

    // The view has to exist before the remote store sends the listen request: the request carries the number of
    // documents the client already has for the target (expected count), which is read from the view.
    final ViewSnapshot viewSnapshot = await initializeViewAndComputeSnapshot(
      query,
      queryData,
      current: status == QueryTargetState.current,
    );
    await _listener.onViewSnapshots(<ViewSnapshot>[viewSnapshot]);

    if (_isPrimary && shouldListenToRemote) {
      _listenToRemote(queryData);
    }
    return queryData.targetId;
  }

  /// Creates the view of [query] and returns its first snapshot. [current] is whether another client found the target
  /// to be current already (see [SharedClientState.addLocalQueryTarget]).
  Future<ViewSnapshot> initializeViewAndComputeSnapshot(
    Query query,
    QueryData queryData, {
    bool current = false,
  }) async {
    final QueryResult queryResult = await _localStore.executeQuery(
      query,
      /* usePreviousResults= */ true,
    );

    final View view = View(
      query,
      queryResult.remoteKeys,
      limboResolutionEnabled: _isPrimary,
    );
    final ViewDocumentChanges viewDocChanges = view.computeDocChanges(
      queryResult.documents,
    );

    // The initial snapshot carries the resume token of the target so that an empty result of a target that has been
    // synced before can be raised from the cache. If there are already queries mapped to the target, the sync state of
    // those queries is applied to the new query as well.
    bool targetIsCurrent = current && _onlineState != OnlineState.offline;
    SnapshotVersion? mirrorReadTime;
    final List<Query>? mirrorQueries = _queriesByTarget[queryData.targetId];
    if (mirrorQueries != null && mirrorQueries.isNotEmpty) {
      final QueryView? mirrorView = _queryViewsByQuery[mirrorQueries.first];
      final bool mirrorIsCurrent =
          mirrorView != null &&
          mirrorView.view.syncState == ViewSnapshotSyncState.synced;
      targetIsCurrent = mirrorIsCurrent;
      if (mirrorIsCurrent) {
        mirrorReadTime = mirrorView.view.readTime;
      }
    }
    final TargetChange synthesizedCurrentChange =
        TargetChange.createSynthesizedTargetChangeForCurrentChange(
          targetIsCurrent,
          queryData.resumeToken,
        );
    final ViewChange viewChange = view.applyChanges(
      viewDocChanges,
      synthesizedCurrentChange,
      false,
      mirrorReadTime,
    );

    final QueryView queryView = QueryView(
      query,
      queryData.targetId,
      view,
      queryData,
    );
    _queryViewsByQuery[query] = queryView;
    // Most likely there will only be one query mapping to a target.
    _queriesByTarget
        .putIfAbsent(queryData.targetId, () => <Query>[])
        .add(query);
    // A view that starts out current (another client synced the target) can have limbo documents.
    await _updateTrackedLimboDocuments(
      viewChange.limboChanges,
      queryData.targetId,
    );
    return viewChange.snapshot!;
  }

  /// Sends the listen of a query that is already listened locally to the
  /// [RemoteStore]. Used when a listener that needs the backend is added to a
  /// query that so far only listened to the cache.
  Future<void> listenToRemoteStore(Query query) async {
    _assertCallback('listenToRemoteStore');
    final QueryView? queryView = _queryViewsByQuery[query];
    hardAssert(queryView != null, 'This is the first listen to query: $query');

    _sharedClientState.addLocalQueryTarget(queryView!.targetId);
    if (_isPrimary) {
      _listenToRemote(queryView.queryData);
    }
  }

  /// Sends the listen to the [RemoteStore] without waiting for it: starting the watch stream needs the network
  /// (credentials, connection), which must not hold up the operations that are queued behind this one, like writes
  /// with a local cache. The remote store registers the target synchronously; a failure to start the stream is
  /// reported by the stream itself.
  void _listenToRemote(QueryData queryData) {
    unawaited(
      _remoteStore.listen(queryData).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        Zone.current.handleUncaughtError(error, stackTrace);
      }),
    );
  }

  /// Stops listening to a query previously listened to via listen. The target
  /// is only removed from the [RemoteStore] if [shouldUnlistenToRemote] is
  /// true.
  Future<void> stopListening(
    Query query, {
    bool shouldUnlistenToRemote = true,
  }) async {
    _assertCallback('stopListening');

    final QueryView? queryView = _queryViewsByQuery[query];
    hardAssert(
      queryView != null,
      'Trying to stop listening to a query not found',
    );

    final int targetId = queryView!.targetId;
    final List<Query> targetQueries = _queriesByTarget[targetId]!;

    // Only clean up the query view and the target if this is the only query mapped to the target.
    if (targetQueries.length > 1) {
      _queryViewsByQuery.remove(query);
      targetQueries.remove(query);
      return;
    }

    if (_isPrimary) {
      // The local query target is removed first, to find out whether another client still listens to the target. If
      // one does, the view is kept: this client keeps listening to the target on its behalf.
      _sharedClientState.removeLocalQueryTarget(targetId);
      if (!_sharedClientState.isActiveQueryTarget(targetId)) {
        _queryViewsByQuery.remove(query);
        targetQueries.remove(query);
        await _localStore.releaseTarget(targetId);
        _sharedClientState.clearQueryState(targetId);
        if (shouldUnlistenToRemote) {
          await _remoteStore.stopListening(targetId);
        }
        await _removeAndCleanupTarget(targetId, null);
      }
    } else {
      await _removeAndCleanupTarget(targetId, null);
      await _localStore.releaseTarget(targetId, keepPersistedTargetData: true);
    }
  }

  /// Stops listening to a query from the backend, while it keeps listening to
  /// the cache. Used when the last listener that needs the backend is removed
  /// from a query that still has cache only listeners.
  Future<void> stopListeningToRemoteStore(Query query) async {
    _assertCallback('stopListeningToRemoteStore');
    final QueryView? queryView = _queryViewsByQuery[query];
    hardAssert(
      queryView != null,
      'Trying to stop listening to a query not found',
    );

    if (_isPrimary) {
      if (_queriesByTarget[queryView!.targetId]!.length == 1) {
        _sharedClientState.removeLocalQueryTarget(queryView.targetId);
      }
      await _remoteStore.stopListening(queryView.targetId);
    }
  }

  /// Initiates the write of local mutation batch which involves adding the writes to the mutation queue, notifying the
  /// remote store about new mutations, and raising events for any changes this write caused.
  ///
  /// The provided Future will be resolved once the write has been acked/rejected by the backend (or failed locally for
  /// any other reason).
  Future<void> writeMutations(
    List<Mutation> mutations,
    Completer<void> userTask,
  ) async {
    _assertCallback('writeMutations');

    final LocalWriteResult result;
    try {
      result = await _localStore.writeLocally(mutations);
    } catch (e) {
      if (!isRecoverablePersistenceError(e)) {
        rethrow;
      }
      // As JS: a write that could not be stored fails, and nothing else happens.
      Log.w(_tag, 'Failed to persist write: $e');
      userTask.completeError(
        FirestoreError(
          'Failed to persist write: $e',
          FirestoreErrorCode.unavailable,
        ),
      );
      return;
    }
    _sharedClientState.addPendingMutation(result.batchId);
    _addUserCallback(result.batchId, userTask);

    await _emitNewSnapsAndNotifyLocalStore(
      result.changes,
      /*remoteEvent:*/ null,
    );
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
    Query query,
    List<AggregateField> aggregateFields,
  ) {
    return _remoteStore.runAggregateQuery(query, aggregateFields);
  }

  /// Runs a vector query over [query] on the server.
  Future<List<Document>> runVectorQuery(Query query, VectorQuery vectorQuery) {
    return _remoteStore.runVectorQuery(query, vectorQuery);
  }

  /// Whether this client is the primary client of its cache (always true with a cache only one client can use); null
  /// until the first [applyPrimaryState] of a client that does not start as primary (the JS `_isPrimaryClient`).
  bool? _primaryState;

  bool get _isPrimary => _primaryState == true;

  /// Whether this client is the primary client of its cache, as last told by [applyPrimaryState].
  bool get isPrimaryClient => _isPrimary;

  /// Called when this client becomes or stops being the primary client of its cache (`syncEngineApplyPrimaryState` of
  /// the JS SDK). Only the primary client uses the network; the client starts and stops the LRU garbage collection and
  /// the index backfill.
  ///
  /// A client that becomes primary reconciles the views of every target that any client listens to with the
  /// persisted state (a secondary does not know which documents the backend considers part of a target), creates the
  /// views of the targets of the other clients and listens to all of them. A client that stops being primary drops the
  /// views of the targets that only other clients listen to, stops all its listens, reconciles its own views and
  /// forgets its limbo resolutions.
  Future<void> applyPrimaryState(bool isPrimary) async {
    if (isPrimary && _primaryState != true) {
      Log.d(_tag, 'Became primary');
      final List<QueryData> activeQueries =
          await _synchronizeQueryViewsAndRaiseSnapshots(
            _sharedClientState.getAllActiveQueryTargets().toList(),
            transitionToPrimary: true,
          );
      _primaryState = true;
      await _remoteStore.applyPrimaryState(true);
      activeQueries.forEach(_listenToRemote);
    } else if (!isPrimary && _primaryState != false) {
      Log.d(_tag, 'Is no longer primary');
      final List<int> activeTargets = <int>[];
      for (final int targetId in _queriesByTarget.keys.toList()) {
        if (_sharedClientState.isLocalQueryTarget(targetId)) {
          activeTargets.add(targetId);
        } else {
          await _removeAndCleanupTarget(targetId, null);
          await _localStore.releaseTarget(
            targetId,
            keepPersistedTargetData: true,
          );
        }
        await _remoteStore.stopListening(targetId);
      }

      await _synchronizeQueryViewsAndRaiseSnapshots(
        activeTargets,
        transitionToPrimary: false,
      );
      await _resetLimboDocuments();
      _primaryState = false;
      await _remoteStore.applyPrimaryState(false);
    }
  }

  /// Stops the limbo resolutions of a client that is no longer primary.
  Future<void> _resetLimboDocuments() async {
    for (final int targetId in _activeLimboResolutionsByTarget.keys.toList()) {
      await _remoteStore.stopListening(targetId);
    }
    _limboDocumentRefs.removeAllReferences();
    _activeLimboResolutionsByTarget.clear();
    _activeLimboTargetsByKey.clear();
  }

  /// Reconciles the views of [targets] with the persisted state, raises the snapshots of the changes and returns the
  /// current target data of each target. A client that becomes primary ([transitionToPrimary]) also creates the views
  /// of the targets that only other clients listen to.
  Future<List<QueryData>> _synchronizeQueryViewsAndRaiseSnapshots(
    List<int> targets, {
    required bool transitionToPrimary,
  }) async {
    final List<QueryData> activeQueries = <QueryData>[];
    final List<ViewSnapshot> newViewSnapshots = <ViewSnapshot>[];
    for (final int targetId in targets) {
      final QueryData queryData;
      final List<Query>? queries = _queriesByTarget[targetId];
      if (queries != null && queries.isNotEmpty) {
        // The target data is read again (the resume token and the snapshot version may have changed) and the views
        // are reconciled with the persisted state (their synced documents may be out of date).
        queryData = await _localStore.allocateTarget(queries.first.toTarget());
        for (final Query query in queries.toList()) {
          final QueryView? queryView = _queryViewsByQuery[query];
          hardAssert(queryView != null, 'No query view found for $query');
          final ViewChange viewChange =
              await _synchronizeViewAndComputeSnapshot(queryView!);
          final ViewSnapshot? snapshot = viewChange.snapshot;
          if (snapshot != null) {
            newViewSnapshots.add(snapshot);
          }
        }
      } else {
        hardAssert(
          transitionToPrimary,
          'A secondary client should never have an active view without an active target.',
        );
        // A target that this client never listened to: allocate it and create its view.
        final Target? target = await _localStore.getCachedTarget(targetId);
        hardAssert(target != null, 'Target for id $targetId not found');
        queryData = await _localStore.allocateTarget(target!);
        await initializeViewAndComputeSnapshot(
          _synthesizeTargetToQuery(target),
          queryData,
        );
      }
      activeQueries.add(queryData);
    }
    await _listener.onViewSnapshots(newViewSnapshots);
    return activeQueries;
  }

  /// Reconciles the documents of an existing view with those in persistence.
  Future<ViewChange> _synchronizeViewAndComputeSnapshot(
    QueryView queryView,
  ) async {
    final QueryResult queryResult = await _localStore.executeQuery(
      queryView.query,
      /* usePreviousResults= */ true,
    );
    final ViewChange viewChange = queryView.view.synchronizeWithPersistedState(
      queryResult,
    );
    if (_isPrimary) {
      await _updateTrackedLimboDocuments(
        viewChange.limboChanges,
        queryView.targetId,
      );
    }
    return viewChange;
  }

  /// The failure of a primary-only transaction of a client that lost the primary lease is ignored
  /// (`ignoreIfPrimaryLeaseLoss` of the JS SDK): the primary client does that work.
  void _logPrimaryLeaseLoss() {
    Log.d(_tag, 'Unexpectedly lost the primary lease');
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
          'Limbo resolution for single document contains multiple changes.',
        );
        limboResolution.current = targetChange.current;
        if (targetChange.addedDocuments.isNotEmpty) {
          limboResolution.receivedDocument = true;
        } else if (targetChange.modifiedDocuments.isNotEmpty) {
          hardAssert(
            limboResolution.receivedDocument,
            'Received change for limbo target document without add.',
          );
        } else if (targetChange.removedDocuments.isNotEmpty) {
          hardAssert(
            limboResolution.receivedDocument,
            'Received remove for limbo target document without add.',
          );
          limboResolution.receivedDocument = false;
        } else {
          // This was probably just a CURRENT targetChange or similar.
        }
      }
    }

    final ImmutableSortedMap<DocumentKey, MaybeDocument> changes;
    try {
      changes = await _localStore.applyRemoteEvent(event);
    } on FirestoreError catch (e) {
      if (!isPrimaryLeaseLoss(e)) {
        rethrow;
      }
      _logPrimaryLeaseLoss();
      return;
    }
    await _emitNewSnapsAndNotifyLocalStore(
      changes,
      event,
      await _limboDocumentsConfirmedToExist(event),
    );
  }

  /// The limbo documents that the backend has confirmed to exist as of [event]: their limbo resolution is CURRENT and
  /// has received the document.
  ///
  /// Such a document is in the view of a query but not in the query's target. If that target is CURRENT too, the
  /// backend does not consider the document a result of the query, and the view drops it (see
  /// [View.backendMismatches]) instead of waiting forever for a resolution that will not come.
  ///
  /// That conclusion is only sound when nothing local can explain why the client has a result that the backend does
  /// not have (yet). So the set is empty while
  ///  * there are pending writes (a write to any document can pull another one into a query, for example into a
  ///    limit), or
  ///  * the event is older than the last acknowledged write (Watch has not caught up with it).
  ///
  /// PORTING NOTE: not in the other SDKs, which leave such a document in limbo.
  Future<Set<DocumentKey>> _limboDocumentsConfirmedToExist(
    RemoteEvent event,
  ) async {
    final Set<DocumentKey> confirmed = <DocumentKey>{
      for (final _LimboResolution resolution
          in _activeLimboResolutionsByTarget.values)
        if (resolution.current && resolution.receivedDocument) resolution.key,
    };
    if (confirmed.isEmpty) {
      return confirmed;
    }
    if (event.snapshotVersion.compareTo(_lastAcknowledgedCommitVersion) < 0) {
      return <DocumentKey>{};
    }
    final int pendingBatchId = await _localStore
        .getHighestUnacknowledgedBatchId();
    if (pendingBatchId != MutationBatch.unknown) {
      return <DocumentKey>{};
    }
    return confirmed;
  }

  /// Applies an [OnlineState] change of the remote store to the sync engine and notifies any views of the change.
  @override
  Future<void> handleOnlineStateChange(OnlineState onlineState) =>
      applyOnlineStateChange(onlineState, OnlineStateSource.remoteStore);

  /// Applies an [OnlineState] change to the sync engine and notifies any views of the change.
  ///
  /// A secondary client ignores the online state of its remote store (it may go offline while the primary client
  /// stays online) and only applies the one the primary client shares.
  Future<void> applyOnlineStateChange(
    OnlineState onlineState,
    OnlineStateSource source,
  ) async {
    // Without shared state (a client that shares no state with the other clients of its cache) the remote store is
    // the only source, also for a secondary client.
    final bool fromSharedState = !_isPrimary && _sharedClientState.sharesState;
    if (fromSharedState != (source == OnlineStateSource.sharedClientState)) {
      return;
    }
    final List<ViewSnapshot> newViewSnapshots = <ViewSnapshot>[];
    for (MapEntry<Query, QueryView> entry in _queryViewsByQuery.entries) {
      final View view = entry.value.view;
      final ViewChange viewChange = view.applyOnlineStateChange(onlineState);
      hardAssert(
        viewChange.limboChanges.isEmpty,
        'OnlineState should not affect limbo documents.',
      );
      final ViewSnapshot? snapshot = viewChange.snapshot;
      if (snapshot != null) {
        newViewSnapshots.add(snapshot);
      }
    }
    await _listener.onViewSnapshots(newViewSnapshots);
    _listener.handleOnlineStateChange(onlineState);

    _onlineState = onlineState;
    if (_isPrimary) {
      _sharedClientState.setOnlineState(onlineState);
    }
  }

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
              remoteKeys = remoteKeys.unionWith(queryView.view.syncedDocuments);
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

    _sharedClientState.updateQueryState(
      targetId,
      QueryTargetState.rejected,
      exceptionFromStatus(error),
    );

    final _LimboResolution? limboResolution =
        _activeLimboResolutionsByTarget[targetId];
    final DocumentKey? limboKey = limboResolution != null
        ? limboResolution.key
        : null;
    if (limboKey != null) {
      // Since this query failed, we won't want to manually unlisten to it. So go ahead and remove it from bookkeeping.
      _activeLimboTargetsByKey.remove(limboKey);
      _activeLimboResolutionsByTarget.remove(targetId);

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
            ),
          };
      final Set<DocumentKey> limboDocuments = <DocumentKey>{limboKey};
      final RemoteEvent event = RemoteEvent(
        documentUpdates: documentUpdates,
        resolvedLimboDocuments: limboDocuments,
      );
      try {
        await handleRemoteEvent(event);
      } catch (_) {
        // As JS: the resolution stays active when the event could not be applied, so that the RemoteStore listens to
        // the limbo target again once the persistence works, which brings the rejection back.
        _activeLimboTargetsByKey[limboKey] = targetId;
        _activeLimboResolutionsByTarget[targetId] = limboResolution!;
        rethrow;
      }
      await _pumpEnqueuedLimboResolutions();
    } else {
      hardAssertLazy(
        _queriesByTarget.containsKey(targetId),
        () => 'Unknown target: $targetId',
      );
      await _localStore.releaseTarget(
        targetId,
        keepPersistedTargetData: !_isPrimary,
      );
      await _removeAndCleanupTarget(targetId, error);
    }
  }

  @override
  Future<void> handleSuccessfulWrite(
    MutationBatchResult mutationBatchResult,
  ) async {
    _assertCallback('handleSuccessfulWrite');

    // The acknowledgement is stored first (as JS): when that fails (see isRecoverablePersistenceError), the RemoteStore
    // keeps the result and calls this again once the persistence works, and the user is told only then.
    final ImmutableSortedMap<DocumentKey, MaybeDocument> changes;
    try {
      changes = await _localStore.acknowledgeBatch(mutationBatchResult);
    } on FirestoreError catch (e) {
      if (!isPrimaryLeaseLoss(e)) {
        rethrow;
      }
      // The backend did apply the write: the user is told, the batch stays in the queue for the primary client.
      _notifyAcknowledged(mutationBatchResult);
      _logPrimaryLeaseLoss();
      return;
    }

    // The local store may or may not be able to apply the write result and raise events immediately (depending on
    // whether the watcher is caught up), so we raise user callbacks before the listen events.
    _notifyAcknowledged(mutationBatchResult);

    _sharedClientState.updateMutationState(
      mutationBatchResult.batch.batchId,
      MutationBatchState.acknowledged,
    );
    await _emitNewSnapsAndNotifyLocalStore(changes, /*remoteEvent:*/ null);
  }

  void _notifyAcknowledged(MutationBatchResult mutationBatchResult) {
    _notifyUser(mutationBatchResult.batch.batchId, /*status:*/ null);

    _resolvePendingWriteTasks(mutationBatchResult.batch.batchId);

    if (mutationBatchResult.commitVersion.compareTo(
          _lastAcknowledgedCommitVersion,
        ) >
        0) {
      _lastAcknowledgedCommitVersion = mutationBatchResult.commitVersion;
    }
  }

  @override
  Future<void> handleRejectedWrite(int batchId, GrpcError status) async {
    _assertCallback('handleRejectedWrite');

    final ImmutableSortedMap<DocumentKey, MaybeDocument> changes;
    try {
      changes = await _localStore.rejectBatch(batchId);
    } on FirestoreError catch (e) {
      // As in the JS SDK the user is not told: the batch stays in the queue for the primary client.
      if (!isPrimaryLeaseLoss(e)) {
        rethrow;
      }
      _logPrimaryLeaseLoss();
      return;
    }

    if (changes.isNotEmpty) {
      _logErrorIfInteresting(status, 'Write failed at ${changes.minKey!.path}');
    }

    // The local store may or may not be able to apply the write result and raise events immediately (depending on
    // whether the watcher is caught up), so we raise user callbacks first so that they consistently happen before
    // listen events.
    final FirestoreError error = exceptionFromStatus(status);
    _notifyUser(batchId, error);

    _resolvePendingWriteTasks(batchId);

    _sharedClientState.updateMutationState(
      batchId,
      MutationBatchState.rejected,
      error,
    );
    await _emitNewSnapsAndNotifyLocalStore(changes, /*remoteEvent:*/ null);
  }

  /// Takes a snapshot of the current mutation queue and completes [userTask] when all those mutations are either
  /// accepted or rejected by the server.
  Future<void> registerPendingWritesTask(Completer<void> userTask) async {
    if (!_remoteStore.canUseNetwork) {
      Log.d(
        _tag,
        'The network is disabled. The task returned by \'waitForPendingWrites()\' will not complete until the '
        'network is enabled.',
      );
    }

    final int largestPendingBatchId;
    try {
      largestPendingBatchId = await _localStore
          .getHighestUnacknowledgedBatchId();
    } catch (e) {
      if (!isRecoverablePersistenceError(e)) {
        rethrow;
      }
      userTask.completeError(
        FirestoreError(
          'Initialization of waitForPendingWrites() operation failed: $e',
          FirestoreErrorCode.unavailable,
        ),
      );
      return;
    }

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
    final List<Completer<void>>? tasks = _pendingWritesCallbacks.remove(
      batchId,
    );
    if (tasks != null) {
      for (Completer<void> task in tasks) {
        task.complete();
      }
    }
  }

  void _failOutstandingPendingWritesAwaitingTasks() {
    final List<Completer<void>> tasks = <Completer<void>>[
      for (List<Completer<void>> list in _pendingWritesCallbacks.values)
        ...list,
    ];
    _pendingWritesCallbacks.clear();
    for (Completer<void> task in tasks) {
      task.completeError(
        FirestoreError(
          '\'waitForPendingWrites\' task is cancelled due to User change.',
          FirestoreErrorCode.cancelled,
        ),
      );
    }
  }

  /// Resolves the task corresponding to this write result.
  void _notifyUser(int batchId, FirestoreError? error) {
    final Map<int, Completer<void>>? userTasks =
        _mutationUserCallbacks[_currentUser];

    // NOTE: Mutations restored from persistence won't have task completion
    // sources, so it's okay for this (or the task below) to be null.
    if (userTasks != null) {
      final int boxedBatchId = batchId;
      final Completer<void>? userTask = userTasks[boxedBatchId];
      if (userTask != null) {
        if (error != null) {
          userTask.completeError(error);
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
    _sharedClientState.removeLocalQueryTarget(targetId);
    for (Query query in _queriesByTarget[targetId] ?? const <Query>[]) {
      _queryViewsByQuery.remove(query);
      if (error != null) {
        _listener.onError(query, error);
        _logErrorIfInteresting(error, 'Listen for $query failed');
      }
    }
    _queriesByTarget.remove(targetId);

    if (!_isPrimary) {
      // Only the primary client resolves limbo documents.
      return;
    }
    final ImmutableSortedSet<DocumentKey> limboKeys = _limboDocumentRefs
        .referencesForId(targetId);
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
    RemoteEvent? remoteEvent, [
    Set<DocumentKey> limboDocumentsConfirmedToExist = const <DocumentKey>{},
  ]) async {
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
      final TargetChange? targetChange = remoteEvent == null
          ? null
          : remoteEvent.targetChanges[queryView.targetId];
      final bool targetIsPendingReset =
          remoteEvent != null &&
          remoteEvent.targetMismatches.containsKey(queryView.targetId);

      // Documents that the backend does not consider results of this query are taken out of its view. They go through
      // computeDocChanges like changed documents, which removes them (and refills a limit query).
      ImmutableSortedMap<DocumentKey, MaybeDocument> viewChanges = changes;
      if (remoteEvent != null && !targetIsPendingReset) {
        for (final Document document in view.backendMismatches(
          limboDocumentsConfirmedToExist,
          targetChange,
          changes,
        )) {
          Log.d(
            _tag,
            'Document ${document.key} exists but the backend does not return it for target ${queryView.targetId}: '
            'removing it from the view',
          );
          viewChanges = viewChanges.insert(document.key, document);
        }
      }
      ViewDocumentChanges viewDocChanges = view.computeDocChanges(viewChanges);
      if (viewDocChanges.needsRefill) {
        // The query has a limit and some docs were removed/updated, so we need to re-run the query against the local
        // store to make sure we didn't lose any good docs that had been past the limit.
        final ImmutableSortedMap<DocumentKey, Document> docs =
            (await _localStore.executeQuery(
              queryView.query,
              /* usePreviousResults= */ false,
            )).documents;
        viewDocChanges = view.computeDocChanges(docs, viewDocChanges);
        if (!identical(_queryViewsByQuery[queryView.query], queryView)) {
          continue;
        }
      }
      queryView.view.limboResolutionEnabled = _isPrimary;
      final ViewChange viewChange = queryView.view.applyChanges(
        viewDocChanges,
        targetChange,
        targetIsPendingReset,
        remoteEvent?.snapshotVersion,
      );
      // If there are changes, or this is a global snapshot, tell the other clients the state of the target: it is
      // current if the view is synced, or (without changes) if the target change says so.
      if (_isPrimary && (viewChange.snapshot != null || remoteEvent != null)) {
        final bool isCurrent = viewChange.snapshot != null
            ? !viewChange.snapshot!.isFromCache
            : targetChange?.current ?? false;
        _sharedClientState.updateQueryState(
          queryView.targetId,
          isCurrent ? QueryTargetState.current : QueryTargetState.notCurrent,
        );
      }
      await _updateTrackedLimboDocuments(
        viewChange.limboChanges,
        queryView.targetId,
      );

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
    List<LimboDocumentChange> limboChanges,
    int targetId,
  ) async {
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
      await _remoteStore.listen(
        QueryData(
          Query(key.path).toTarget(),
          limboTargetId,
          ListenSequence.invalid,
          QueryPurpose.limboResolution,
        ),
      );
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

  ///
  /// As in JS, credential changes are retryable operations (see [RemoteStore.enqueueRetryable]): one that fails
  /// because the persistence is not available keeps the network offline and is tried again, and the changes that
  /// follow it wait for it. The returned future completes after the first attempt.
  Future<void> handleCredentialChange(User user) {
    return _remoteStore.enqueueRetryable(
      () => _remoteStore.handleCredentialChange(() => _switchUser(user)),
    );
  }

  Future<void> _switchUser(User user) async {
    final bool userChanged = _currentUser != user;

    if (userChanged) {
      // Fails tasks waiting for pending writes requested by the previous user.
      _failOutstandingPendingWritesAwaitingTasks();
      // Notify local store and emit any resulting events from swapping out the mutation queue.
      final UserChangeResult result = await _localStore
          .handleUserChangeWithBatchIds(user);
      // Switch the user only once the local store switched its mutation queue, so both agree on the current user.
      _currentUser = user;
      _sharedClientState.handleUserChange(
        user,
        result.removedBatchIds,
        result.addedBatchIds,
      );
      await _emitNewSnapsAndNotifyLocalStore(
        result.affectedDocuments,
        /*remoteEvent:*/ null,
      );
    }
  }

  /// Loads the bundle read by [bundleReader] into the local store and reports the progress to [resultTask].
  Future<void> loadBundle(
    BundleReader bundleReader,
    LoadBundleTask resultTask,
  ) async {
    // The collection groups of the loaded documents, for the other clients.
    Set<String> collectionGroups = <String>{};
    try {
      final BundleMetadata bundleMetadata = await bundleReader
          .getBundleMetadata();
      final bool hasNewerBundle = await _localStore.hasNewerBundle(
        bundleMetadata,
      );
      if (hasNewerBundle) {
        resultTask.setResult(
          LoadBundleTaskProgressInternal.forSuccess(bundleMetadata),
        );
        return;
      }

      LoadBundleTaskProgress? progress =
          LoadBundleTaskProgressInternal.forInitial(bundleMetadata);
      resultTask.updateProgress(progress);

      final BundleLoader bundleLoader = BundleLoader(
        _localStore,
        bundleMetadata,
      );

      int currentBytesRead = 0;
      BundleElement? bundleElement;
      while ((bundleElement = await bundleReader.getNextElement()) != null) {
        final int oldBytesRead = currentBytesRead;
        currentBytesRead = bundleReader.bytesRead;
        progress = bundleLoader.addElement(
          bundleElement!,
          currentBytesRead - oldBytesRead,
        );
        if (progress != null) {
          resultTask.updateProgress(progress);
        }
      }

      // The loader also saves the bundle metadata, so that loading the same bundle again is skipped.
      final ImmutableSortedMap<DocumentKey, MaybeDocument> changes =
          await bundleLoader.applyChanges();
      collectionGroups = bundleLoader.collectionGroups;

      // TODO(b/160876443): This currently raises snapshots with `fromCache=false` if users already listen to some
      // queries and bundles has newer version.
      await _emitNewSnapsAndNotifyLocalStore(changes, /*remoteEvent:*/ null);

      resultTask.setResult(
        LoadBundleTaskProgressInternal.forSuccess(bundleMetadata),
      );
    } catch (e, stackTrace) {
      Log.w('Firestore', 'Loading bundle failed : $e');
      resultTask.setException(
        FirestoreError(
          'Bundle failed to load',
          FirestoreErrorCode.invalidArgument,
          e,
          stackTrace,
        ),
      );
    } finally {
      try {
        await bundleReader.close();
      } catch (e) {
        Log.w(_tag, 'Exception while closing bundle: $e');
      }
    }
    _sharedClientState.notifyBundleLoaded(collectionGroups);
  }

  // Multi-client: the [SharedClientStateSyncer] methods, called with the changes of the other clients.

  @override
  Future<void> applyBatchState(
    int batchId,
    MutationBatchState state,
    FirestoreError? error,
  ) async {
    final ImmutableSortedMap<DocumentKey, MaybeDocument>? documents =
        await _localStore.lookupMutationDocuments(batchId);
    if (documents == null) {
      // A client may not have seen the mutation before it was completed and removed from the mutation queue, in which
      // case the affected documents were not cached. The update can be ignored: the mutation was not applied locally
      // (or its documents would be cached), and the resulting changes arrive as remote document updates.
      Log.d(_tag, 'Cannot apply mutation batch with id: $batchId');
      return;
    }

    if (state == MutationBatchState.pending) {
      // The primary client sends the write to the backend. The other clients do not, their network is disabled.
      await _remoteStore.fillWritePipeline();
    } else {
      // Both are no-ops for the batches that other clients wrote.
      _notifyUser(batchId, error);
      _resolvePendingWriteTasks(batchId);
      _localStore.removeCachedMutationBatchMetadata(batchId);
    }

    await _emitNewSnapsAndNotifyLocalStore(documents, /*remoteEvent:*/ null);
  }

  @override
  Future<void> applyTargetState(
    int targetId,
    QueryTargetState state,
    FirestoreError? error,
  ) async {
    if (_isPrimary) {
      // A primary client gets the state of the targets from the backend.
      Log.d(_tag, 'Ignoring unexpected query state notification.');
      return;
    }

    final List<Query>? queries = _queriesByTarget[targetId];
    if (queries == null || queries.isEmpty) {
      return;
    }
    switch (state) {
      case QueryTargetState.current:
      case QueryTargetState.notCurrent:
        final ImmutableSortedMap<DocumentKey, MaybeDocument> changes =
            await _localStore.getNewDocumentChanges(
              _queryCollectionGroup(queries.first),
            );
        final RemoteEvent synthesizedRemoteEvent = RemoteEvent(
          documentUpdates: const <DocumentKey, MaybeDocument>{},
          resolvedLimboDocuments: const <DocumentKey>{},
          targetChanges: <int, TargetChange>{
            targetId:
                TargetChange.createSynthesizedTargetChangeForCurrentChange(
                  state == QueryTargetState.current,
                  Uint8List(0),
                ),
          },
        );
        await _emitNewSnapsAndNotifyLocalStore(changes, synthesizedRemoteEvent);
        break;
      case QueryTargetState.rejected:
        await _localStore.releaseTarget(
          targetId,
          keepPersistedTargetData: true,
        );
        await _removeAndCleanupTarget(
          targetId,
          GrpcError.custom(error!.code.value, error.message),
        );
        break;
    }
  }

  @override
  Future<void> applyActiveTargetsChange(
    List<int> added,
    List<int> removed,
  ) async {
    if (!_isPrimary) {
      return;
    }

    for (final int targetId in added) {
      // The target is already listened to if this client has it and it is registered in the shared state.
      if (_queriesByTarget.containsKey(targetId) &&
          _sharedClientState.isActiveQueryTarget(targetId)) {
        Log.d(_tag, 'Adding an already active target $targetId');
        continue;
      }

      final Target? target = await _localStore.getCachedTarget(targetId);
      hardAssert(
        target != null,
        'Query data for active target $targetId not found',
      );
      final QueryData queryData = await _localStore.allocateTarget(target!);
      await initializeViewAndComputeSnapshot(
        _synthesizeTargetToQuery(target),
        queryData,
      );
      _listenToRemote(queryData);
    }

    for (final int targetId in removed) {
      // The target may be gone already, if the backend rejected it.
      if (!_queriesByTarget.containsKey(targetId)) {
        continue;
      }
      await _localStore.releaseTarget(targetId);
      await _remoteStore.stopListening(targetId);
      await _removeAndCleanupTarget(targetId, null);
    }
  }

  @override
  Future<List<ClientId>> getActiveClients() => _localStore.getActiveClients();

  @override
  Future<void> synchronizeWithChangedDocuments(String collectionGroup) async {
    final ImmutableSortedMap<DocumentKey, MaybeDocument> changes =
        await _localStore.getNewDocumentChanges(collectionGroup);
    await _emitNewSnapsAndNotifyLocalStore(changes, /*remoteEvent:*/ null);
  }

  /// The collection group of the documents of [query]: the collection id of a collection query, the parent
  /// collection of a document query.
  static String _queryCollectionGroup(Query query) {
    final String? collectionGroup = query.collectionGroup;
    if (collectionGroup != null) {
      return collectionGroup;
    }
    final ResourcePath path = query.path;
    return query.isDocumentQuery
        ? path.getSegment(path.length - 2)
        : path.getSegment(path.length - 1);
  }

  /// A query whose target is [target], for a view of a target that another client listens to.
  static Query _synthesizeTargetToQuery(Target target) {
    return Query(
      target.path,
      collectionGroup: target.collectionGroup,
      filters: target.filters,
      explicitSortOrder: target.orderBy,
      limit: target.limit,
      startAt: target.startAt,
      endAt: target.endAt,
    );
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

  /// Whether the limbo target is CURRENT. Together with [receivedDocument] this means that the backend has confirmed
  /// that the document exists.
  bool current = false;
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
