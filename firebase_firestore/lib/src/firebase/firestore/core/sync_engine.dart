// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'dart:async';

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_database_collection/firebase_database_collection.dart';
import 'package:firebase_firestore/src/firebase/firestore/auth/user.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/limbo_document_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/listent_sequence.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/online_state.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query_view.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/target_id_generator.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/transaction.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/view.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/view_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/view_snapshot.dart';
import 'package:firebase_firestore/src/firebase/firestore/firebase_firestore_error.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/local_store.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/local_view_changes.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/local_write_result.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_data.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_purpose.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/reference_set.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/maybe_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation_batch_result.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/no_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/snapshot_version.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/remote_event.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/remote_store.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/target_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/async_queue.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/util.dart';
import 'package:grpc/grpc.dart';
import 'package:meta/meta.dart';

/// [SyncEngine] is the central controller in the client SDK architecture. It is
/// the glue code between the [EventManager], [LocalStore], and [RemoteStore].
/// Some of [SyncEngine]'s responsibilities include:
///
/// <ol>
/// <li>Coordinating client requests and remote events between the
/// [EventManager] and the local and remote data stores.
/// <li>Managing a [View] object for each query, providing the unified view
/// between the local and remote data stores.
/// <li>Notifying the [RemoteStore] when the LocalStore has new mutations in its
/// queue that need sending to the backend.
/// </ol>
///
/// * The [SyncEngine]’s methods should only ever be called by methods running
/// on our own worker dispatch queue.
class SyncEngine implements RemoteStoreCallback {
  static const String _tag = 'SyncEngine';

  /// The local store, used to persist mutations and cached documents.
  final LocalStore _localStore;

  /// The remote store for sending writes, watches, etc. to the backend.
  final RemoteStore _remoteStore;

  /// [QueryViews] for all active queries, indexed by query.
  final Map<Query, QueryView> _queryViewsByQuery;

  /// [QueryViews] for all active queries, indexed by target ID.
  final Map<int, QueryView> _queryViewsByTarget;

  /// When a document is in limbo, we create a special listen to resolve it.
  /// This maps the [DocumentKey] of each limbo document to the target id of the
  /// listen resolving it.
  final Map<DocumentKey, int> _limboTargetsByKey;

  /// Basically the inverse of [_limboTargetsByKey], a map of target id to a
  /// [_LimboResolution] (which includes the DocumentKey as well as whether we've
  /// received a document for the target).
  final Map<int, _LimboResolution> _limboResolutionsByTarget;

  /// Used to track any documents that are currently in limbo.
  final ReferenceSet _limboDocumentRefs;

  /// Stores user completion blocks, indexed by user and batch id.
  final Map<User, Map<int, Completer<void>>> _mutationUserCallbacks;

  /// Used for creating the target ids for the listens used to resolve limbo
  /// documents.
  final TargetIdGenerator _targetIdGenerator;

  User _currentUser;

  SyncEngineCallback callback;

  SyncEngine(this._localStore, this._remoteStore, this._currentUser)
      : _queryViewsByQuery = <Query, QueryView>{},
        _queryViewsByTarget = <int, QueryView>{},
        _limboTargetsByKey = <DocumentKey, int>{},
        _limboResolutionsByTarget = <int, _LimboResolution>{},
        _limboDocumentRefs = ReferenceSet(),
        _mutationUserCallbacks = <User, Map<int, Completer<void>>>{},
        _targetIdGenerator = TargetIdGenerator.getSyncEngineGenerator(0);

  void _assertCallback(String method) {
    Assert.hardAssert(
        callback != null, 'Trying to call $method before setting callback');
  }

  /// Initiates a new listen. The [LocalStore] will be queried for initial data
  /// and the listen will be sent to the [RemoteStore] to get remote data. The
  /// registered [SyncEngineCallback] will be notified of resulting view
  /// snapshots and/or listen errors.
  ///
  /// Returns the target ID assigned to the query.
  Future<int> listen(Query query) async {
    _assertCallback('listen');
    Assert.hardAssert(!_queryViewsByQuery.containsKey(query),
        'We already listen to query: $query');

    final QueryData queryData = await _localStore.allocateQuery(query);
    final ImmutableSortedMap<DocumentKey, Document> docs =
        await _localStore.executeQuery(query);
    final ImmutableSortedSet<DocumentKey> remoteKeys =
        await _localStore.getRemoteDocumentKeys(queryData.targetId);

    final View view = View(query, remoteKeys);
    final DocumentChanges viewDocChanges = view.computeDocChanges(docs);
    final ViewChange viewChange = view.applyChanges(viewDocChanges);
    Assert.hardAssert(view.limboDocuments.isEmpty,
        'View returned limbo docs before target ack from the server');

    final QueryView queryView = QueryView(query, queryData.targetId, view);
    _queryViewsByQuery[query] = queryView;
    _queryViewsByTarget[queryData.targetId] = queryView;
    callback.onViewSnapshots(<ViewSnapshot>[viewChange.snapshot]);

    _remoteStore.listen(queryData);
    return queryData.targetId;
  }

  /// Stops listening to a query previously listened to via listen. */
  void stopListening(Query query) {
    _assertCallback('stopListening');

    final QueryView queryView = _queryViewsByQuery[query];
    Assert.hardAssert(
        queryView != null, 'Trying to stop listening to a query not found');

    _localStore.releaseQuery(query);
    _remoteStore.stopListening(queryView.targetId);
    _removeAndCleanup(queryView);
  }

  /// Initiates the write of local mutation batch which involves adding the
  /// writes to the mutation queue, notifying the remote store about new
  /// mutations, and raising events for any changes this write caused. The
  /// provided task will be resolved once the write has been acked/rejected by
  /// the backend (or failed locally for any other reason).
  Future<void> writeMutations(
      List<Mutation> mutations, Completer<void> userTask) async {
    _assertCallback('writeMutations');

    final LocalWriteResult result = await _localStore.writeLocally(mutations);
    addUserCallback(result.batchId, userTask);

    await _emitNewSnapshot(result.changes, /*remoteEvent:*/ null);
    _remoteStore.fillWritePipeline();
  }

  /*private*/
  void addUserCallback(int batchId, Completer<void> userTask) {
    Map<int, Completer<void>> userTasks = _mutationUserCallbacks[_currentUser];
    if (userTasks == null) {
      userTasks = <int, Completer<void>>{};
      _mutationUserCallbacks[_currentUser] = userTasks;
    }
    userTasks[batchId] = userTask;
  }

  /// Takes an [updateFunction] in which a set of reads and writes can be
  /// performed atomically. In the [updateFunction], the client can read and
  /// write values using the supplied transaction object. After the
  /// [updateFunction], all changes will be committed. If some other client has
  /// changed any of the data referenced, then the [updateFunction] will be
  /// called again. If the [updateFunction] still fails after the given number
  /// of retries, then the transaction will be rejected.
  ///
  /// * The transaction object passed to the [updateFunction] contains methods
  /// for accessing documents and collections. Unlike other datastore access,
  /// data accessed with the transaction will not reflect local changes that
  /// have not been committed. For this reason, it is required that all reads
  /// are performed before any writes. Transactions must be performed while
  /// online.
  ///
  /// * The [Future] returned is resolved when the transaction is fully
  /// committed.
  Future<TResult> transaction<TResult>(AsyncQueue asyncQueue,
      Future<TResult> Function(Transaction) updateFunction, int retries) async {
    Assert.hardAssert(
        retries >= 0, 'Got negative number of retries for transaction.');
    final Transaction transaction = _remoteStore.createTransaction();
    try {
      final TResult result = await updateFunction(transaction);
      await transaction.commit();
      return result;
    } catch (e) {
      // TODO: Only retry on real transaction failures.
      if (retries == 0) {
        final Error e = FirebaseFirestoreError(
            'Transaction failed all retries.',
            FirebaseFirestoreErrorCode.aborted);
        return Future<TResult>.error(e);
      }
      return this.transaction(asyncQueue, updateFunction, retries - 1);
    }
  }

  /// Called by [FirestoreClient] to notify us of a new remote event.
  @override
  Future<void> handleRemoteEvent(RemoteEvent event) async {
    _assertCallback('handleRemoteEvent');

    // Update `receivedDocument` as appropriate for any limbo targets.
    for (MapEntry<int, TargetChange> entry in event.targetChanges.entries) {
      final int targetId = entry.key;
      final TargetChange targetChange = entry.value;
      final _LimboResolution limboResolution =
          _limboResolutionsByTarget[targetId];
      if (limboResolution != null) {
        // Since this is a limbo resolution lookup, it's for a single document
        // and it could be added, modified, or removed, but not a combination.
        Assert.hardAssert(
            targetChange.addedDocuments.length +
                    targetChange.modifiedDocuments.length +
                    targetChange.removedDocuments.length <=
                1,
            'Limbo resolution for single document contains multiple changes.');
        if (targetChange.addedDocuments.isNotEmpty) {
          limboResolution.receivedDocument = true;
        } else if (targetChange.modifiedDocuments.isNotEmpty) {
          Assert.hardAssert(limboResolution.receivedDocument,
              'Received change for limbo target document without add.');
        } else if (targetChange.removedDocuments.isNotEmpty) {
          Assert.hardAssert(limboResolution.receivedDocument,
              'Received remove for limbo target document without add.');
          limboResolution.receivedDocument = false;
        } else {
          // This was probably just a CURRENT targetChange or similar.
        }
      }
    }

    final ImmutableSortedMap<DocumentKey, MaybeDocument> changes =
        await _localStore.applyRemoteEvent(event);
    await _emitNewSnapshot(changes, event);
  }

  /// Applies an [OnlineState] change to the sync engine and notifies any views
  /// of the change.
  @override
  void handleOnlineStateChange(OnlineState onlineState) {
    final List<ViewSnapshot> newViewSnapshots = <ViewSnapshot>[];
    for (MapEntry<Query, QueryView> entry in _queryViewsByQuery.entries) {
      final View view = entry.value.view;
      final ViewChange viewChange = view.applyOnlineStateChange(onlineState);
      Assert.hardAssert(viewChange.limboChanges.isEmpty,
          'OnlineState should not affect limbo documents.');
      if (viewChange.snapshot != null) {
        newViewSnapshots.add(viewChange.snapshot);
      }
    }
    callback.onViewSnapshots(newViewSnapshots);
  }

  @override
  ImmutableSortedSet<DocumentKey> getRemoteKeysForTarget(int targetId) {
    final _LimboResolution limboResolution =
        _limboResolutionsByTarget[targetId];
    if (limboResolution != null && limboResolution.receivedDocument) {
      return DocumentKey.emptyKeySet.insert(limboResolution.key);
    } else {
      final QueryView queryView = _queryViewsByTarget[targetId];
      return queryView != null
          ? queryView.view.syncedDocuments
          : DocumentKey.emptyKeySet;
    }
  }

  /// Called by FirestoreClient to notify us of a rejected listen.
  @override
  Future<void> handleRejectedListen(int targetId, GrpcError error) async {
    _assertCallback('handleRejectedListen');

    final _LimboResolution limboResolution =
        _limboResolutionsByTarget[targetId];
    final DocumentKey limboKey =
        limboResolution != null ? limboResolution.key : null;
    if (limboKey != null) {
      // Since this query failed, we won't want to manually unlisten to it.
      // So go ahead and remove it from bookkeeping.
      _limboTargetsByKey.remove(limboKey);
      _limboResolutionsByTarget.remove(targetId);

      // TODO: Retry on transient errors?

      // It's a limbo doc. Create a synthetic event saying it was deleted. This
      // is kind of a hack. Ideally, we would have a method in the local store
      // to purge a document. However, it would be tricky to keep all of the
      // local store's invariants with another method.
      final Map<DocumentKey, MaybeDocument> documentUpdates =
          <DocumentKey, MaybeDocument>{
        limboKey: NoDocument(limboKey, SnapshotVersion.none)
      };
      final Set<DocumentKey> limboDocuments =
          Set<DocumentKey>.from(<DocumentKey>[limboKey]);
      final RemoteEvent event = RemoteEvent(
        SnapshotVersion.none,
        /* targetChanges: */ <int, TargetChange>{},
        /* targetMismatches: */ Set<int>(),
        documentUpdates,
        limboDocuments,
      );
      await handleRemoteEvent(event);
    } else {
      final QueryView queryView = _queryViewsByTarget[targetId];
      Assert.hardAssert(queryView != null, 'Unknown target: $targetId');
      _localStore.releaseQuery(queryView.query);
      _removeAndCleanup(queryView);
      callback.onError(queryView.query, error);
    }
  }

  @override
  Future<void> handleSuccessfulWrite(
      MutationBatchResult mutationBatchResult) async {
    _assertCallback('handleSuccessfulWrite');

    // The local store may or may not be able to apply the write result and
    // raise events immediately (depending on whether the watcher is caught up),
    // so we raise user callbacks first so that they consistently happen before
    // listen events.
    _notifyUser(mutationBatchResult.batch.batchId, /*status:*/ null);

    final ImmutableSortedMap<DocumentKey, MaybeDocument> changes =
        await _localStore.acknowledgeBatch(mutationBatchResult);

    await _emitNewSnapshot(changes, /*remoteEvent:*/ null);
  }

  @override
  Future<void> handleRejectedWrite(int batchId, GrpcError status) async {
    _assertCallback('handleRejectedWrite');

    // The local store may or may not be able to apply the write result and
    // raise events immediately (depending on whether the watcher is caught up),
    // so we raise user callbacks first so that they consistently happen before
    // listen events.
    _notifyUser(batchId, status);

    final ImmutableSortedMap<DocumentKey, MaybeDocument> changes =
        await _localStore.rejectBatch(batchId);
    await _emitNewSnapshot(changes, /*remoteEvent:*/ null);
  }

  /// Resolves the task corresponding to this write result.
  void _notifyUser(int batchId, GrpcError status) {
    final Map<int, Completer<void>> userTasks =
        _mutationUserCallbacks[_currentUser];

    // NOTE: Mutations restored from persistence won't have task completion
    // sources, so it's okay for this (or the task below) to be null.
    if (userTasks != null) {
      final int boxedBatchId = batchId;
      final Completer<void> userTask = userTasks[boxedBatchId];
      if (userTask != null) {
        if (status != null) {
          userTask.completeError(Util.exceptionFromStatus(status));
        } else {
          userTask.complete(null);
        }
        userTasks.remove(boxedBatchId);
      }
    }
  }

  void _removeAndCleanup(QueryView view) {
    _queryViewsByQuery.remove(view.query);
    _queryViewsByTarget.remove(view.targetId);

    final ImmutableSortedSet<DocumentKey> limboKeys =
        _limboDocumentRefs.referencesForId(view.targetId);
    _limboDocumentRefs.removeReferencesForId(view.targetId);
    for (DocumentKey key in limboKeys) {
      if (!_limboDocumentRefs.containsKey(key)) {
        // We removed the last reference for this key.
        _removeLimboTarget(key);
      }
    }
  }

  void _removeLimboTarget(DocumentKey key) {
    // It's possible that the target already got removed because the query
    // failed. In that case, the key won't exist in [limboTargetsByKey]. Only do
    // the cleanup if we still have the target.
    final int targetId = _limboTargetsByKey[key];
    if (targetId != null) {
      _remoteStore.stopListening(targetId);
      _limboTargetsByKey.remove(key);
      _limboResolutionsByTarget.remove(targetId);
    }
  }

  /// Computes a new snapshot from the changes and calls the registered callback
  /// with the new snapshot.
  Future<void> _emitNewSnapshot(
      ImmutableSortedMap<DocumentKey, MaybeDocument> changes,
      RemoteEvent remoteEvent) async {
    final List<ViewSnapshot> newSnapshots = <ViewSnapshot>[];
    final List<LocalViewChanges> documentChangesInAllViews =
        <LocalViewChanges>[];

    for (MapEntry<Query, QueryView> entry in _queryViewsByQuery.entries) {
      final QueryView queryView = entry.value;
      final View view = queryView.view;
      DocumentChanges viewDocChanges = view.computeDocChanges(changes);
      if (viewDocChanges.needsRefill) {
        // The query has a limit and some docs were removed/updated, so we need
        // to re-run the query against the local store to make sure we didn't
        // lose any good docs that had been past the limit.
        final ImmutableSortedMap<DocumentKey, Document> docs =
            await _localStore.executeQuery(queryView.query);
        viewDocChanges = view.computeDocChanges(docs, viewDocChanges);
      }
      final TargetChange targetChange = remoteEvent == null
          ? null
          : remoteEvent.targetChanges[queryView.targetId];
      final ViewChange viewChange =
          queryView.view.applyChanges(viewDocChanges, targetChange);
      _updateTrackedLimboDocuments(viewChange.limboChanges, queryView.targetId);

      if (viewChange.snapshot != null) {
        newSnapshots.add(viewChange.snapshot);
        final LocalViewChanges docChanges = LocalViewChanges.fromViewSnapshot(
          queryView.targetId,
          viewChange.snapshot,
        );
        documentChangesInAllViews.add(docChanges);
      }
    }
    callback.onViewSnapshots(newSnapshots);
    _localStore.notifyLocalViewChanges(documentChangesInAllViews);
  }

  /// Updates the limbo document state for the given targetId.
  void _updateTrackedLimboDocuments(
      List<LimboDocumentChange> limboChanges, int targetId) {
    for (LimboDocumentChange limboChange in limboChanges) {
      switch (limboChange.type) {
        case LimboDocumentChangeType.added:
          _limboDocumentRefs.addReference(limboChange.key, targetId);
          _trackLimboChange(limboChange);
          break;
        case LimboDocumentChangeType.removed:
          Log.d(_tag, 'Document no longer in limbo: ${limboChange.key}');
          final DocumentKey limboDocKey = limboChange.key;
          _limboDocumentRefs.removeReference(limboDocKey, targetId);
          if (!_limboDocumentRefs.containsKey(limboDocKey)) {
            // We removed the last reference for this key
            _removeLimboTarget(limboDocKey);
          }
          break;
        default:
          throw Assert.fail('Unknown limbo change type: ${limboChange.type}');
      }
    }
  }

  void _trackLimboChange(LimboDocumentChange change) {
    final DocumentKey key = change.key;
    if (!_limboTargetsByKey.containsKey(key)) {
      Log.d(_tag, 'New document in limbo: $key');
      final int limboTargetId = _targetIdGenerator.nextId();
      final Query query = Query.atPath(key.path);
      final QueryData queryData = QueryData.init(
        query,
        limboTargetId,
        ListenSequence.INVALID,
        QueryPurpose.limboResolution,
      );
      _limboResolutionsByTarget[limboTargetId] = _LimboResolution(key);
      _remoteStore.listen(queryData);
      _limboTargetsByKey[key] = limboTargetId;
    }
  }

  @visibleForTesting
  Map<DocumentKey, int> getCurrentLimboDocuments() {
    // Make a defensive copy as the Map continues to be modified.
    return Map<DocumentKey, int>.from(_limboTargetsByKey);
  }

  Future<void> handleCredentialChange(User user) async {
    final bool userChanged = _currentUser != user;
    _currentUser = user;

    if (userChanged) {
      // Notify local store and emit any resulting events from swapping out the
      // mutation queue.
      final ImmutableSortedMap<DocumentKey, MaybeDocument> changes =
          await _localStore.handleUserChange(user);
      await _emitNewSnapshot(changes, /*remoteEvent:*/ null);
    }

    // Notify remote store so it can restart its streams.
    await _remoteStore.handleCredentialChange();
  }
}

/// Tracks a limbo resolution.
class _LimboResolution {
  final DocumentKey key;

  /// Set to true once we've received a document. This is used in
  /// [SyncEngine.getRemoteKeysForTarget] and ultimately used by
  /// [WatchChangeAggregator] to decide whether it needs to manufacture a delete
  /// event for the target once the target is CURRENT.
  bool receivedDocument;

  _LimboResolution(this.key);
}

/// A callback used to handle events from the SyncEngine
abstract class SyncEngineCallback {
  void onViewSnapshots(List<ViewSnapshot> snapshotList);

  void onError(Query query, GrpcError error);
}
