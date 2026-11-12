// File created by
// Lung Razvan <long1eu>
// on 23/09/2018

import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_callback.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_metadata.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/named_query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/target.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/target_id_generator.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/default_query_engine.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_documents_view.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_view_changes.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_write_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/index_manager.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/bundle_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/document_overlay_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/mutation_queue.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/query_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/remote_document_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_engine.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_purpose.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/reference_set.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_collections.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/field_mask.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/patch_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/no_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_event.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/target_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:firebase_app_dart/internal.dart';

import 'package:meta/meta.dart';

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
class LocalStore implements BundleCallback {
  /// Creates a local store on top of [persistence] for [initialUser]. Queries are executed by [queryEngine], which
  /// defaults to a [DefaultQueryEngine].
  factory LocalStore(
    Persistence persistence,
    User initialUser, {
    QueryEngine? queryEngine,
  }) {
    hardAssert(
      persistence.started,
      'LocalStore was passed an unstarted persistence implementation',
    );

    final QueryCache queryCache = persistence.queryCache;
    final TargetIdGenerator targetIdGenerator = TargetIdGenerator.forQueryCache(
      queryCache.highestTargetId,
    );
    final MutationQueue mutationQueue = persistence.getMutationQueue(
      initialUser,
    );
    final RemoteDocumentCache remoteDocuments = persistence.remoteDocumentCache;
    final DocumentOverlayCache documentOverlayCache = persistence
        .getDocumentOverlayCache(initialUser);
    final IndexManager indexManager = persistence.getIndexManager(initialUser);
    final LocalDocumentsView localDocuments = LocalDocumentsView(
      remoteDocumentCache: remoteDocuments,
      mutationQueue: mutationQueue,
      documentOverlayCache: documentOverlayCache,
      indexManager: indexManager,
    );
    remoteDocuments.indexManager = indexManager;
    final QueryEngine engine = (queryEngine ?? DefaultQueryEngine())
      ..setLocalDocumentsView(localDocuments);

    final ReferenceSet localViewReferences = ReferenceSet();
    persistence.referenceDelegate.inMemoryPins = localViewReferences;

    return LocalStore._(
      persistence,
      queryCache,
      targetIdGenerator,
      mutationQueue,
      remoteDocuments,
      documentOverlayCache,
      indexManager,
      localDocuments,
      engine,
      localViewReferences,
      <int, QueryData>{},
      <Target, int>{},
      persistence.bundleCache,
    );
  }

  LocalStore._(
    this._persistence,
    this._queryCache,
    this._targetIdGenerator,
    this._mutationQueue,
    this._remoteDocuments,
    this._documentOverlayCache,
    this._indexManager,
    this._localDocuments,
    this._queryEngine,
    this._localViewReferences,
    this._targetIds,
    this._targetIdByTarget,
    this._bundleCache,
  );

  /// The maximum time to leave a resume token buffered without writing it out.
  ///
  /// This value is arbitrary: it's long enough to avoid several writes (possibly indefinitely if updates come more
  /// frequently than this) but short enough that restarting after crashing will still have a pretty recent resume
  /// token.
  static final int _resultTokenMaxAgeSeconds = const Duration(
    minutes: 5,
  ).inSeconds;

  /// Manages our in-memory or durable persistence.
  final Persistence _persistence;

  /// The set of all mutations that have been sent but not yet been applied to the backend.
  MutationQueue _mutationQueue;

  /// The last known state of all referenced documents according to the backend.
  final RemoteDocumentCache _remoteDocuments;

  /// The overlays that can be used to short circuit applying all mutations from the mutation queue.
  DocumentOverlayCache _documentOverlayCache;

  /// Manages the list of active field and collection indices of the current user.
  IndexManager _indexManager;

  /// The current state of all referenced documents, reflecting local changes.
  LocalDocumentsView _localDocuments;

  /// Performs queries over the [_localDocuments] (and potentially maintains
  /// indexes).
  QueryEngine _queryEngine;

  /// The set of document references maintained by any local views.
  final ReferenceSet _localViewReferences;

  /// Maps a query to the data about that query.
  final QueryCache _queryCache;

  /// Maps a targetId to data about its query.
  final Map<int, QueryData> _targetIds;

  /// Maps a target to its targetId.
  final Map<Target, int> _targetIdByTarget;

  /// Holds information about the bundles loaded into the SDK.
  final BundleCache _bundleCache;

  /// Used to generate targetIds for queries tracked locally.
  final TargetIdGenerator _targetIdGenerator;

  Future<void> start() async {
    await _persistence.overlayMigrationManager.run();
    await startIndexManager();
    await startMutationQueue();
  }

  Future<void> startIndexManager() {
    return _persistence.runTransaction(
      'Start IndexManager',
      _indexManager.start,
    );
  }

  /// The index manager of the current user. It is replaced when the user changes.
  IndexManager get indexManagerForCurrentUser => _indexManager;

  /// The local documents view of the current user. It is replaced when the user changes.
  LocalDocumentsView get localDocumentsForCurrentUser => _localDocuments;

  /// Returns all configured field indexes.
  List<FieldIndex> getFieldIndexes() => _indexManager.getFieldIndexes();

  /// Makes [newFieldIndexes] the configured field indexes: the indexes that are not in the list are deleted with
  /// their entries, the ones that are new are added (and filled by the index backfiller), the others are kept.
  Future<void> configureFieldIndexes(List<FieldIndex> newFieldIndexes) {
    return _persistence.runTransaction('Configure indexes', () async {
      final SplayTreeSet<FieldIndex> existing = SplayTreeSet<FieldIndex>(
        FieldIndex.semanticCompare,
      )..addAll(_indexManager.getFieldIndexes());
      final SplayTreeSet<FieldIndex> wanted = SplayTreeSet<FieldIndex>(
        FieldIndex.semanticCompare,
      )..addAll(newFieldIndexes);
      for (final FieldIndex index in existing) {
        if (!wanted.contains(index)) {
          await _indexManager.deleteFieldIndex(index);
        }
      }
      for (final FieldIndex index in wanted) {
        if (!existing.contains(index)) {
          await _indexManager.addFieldIndex(index);
        }
      }
    });
  }

  /// Removes all field indexes and their entries.
  Future<void> deleteAllFieldIndexes() {
    return _persistence.runTransaction(
      'Delete All Indexes',
      _indexManager.deleteAllFieldIndexes,
    );
  }

  /// Lets the query engine create field indexes for the queries it would have served faster with one.
  // ignore: avoid_setters_without_getters
  set indexAutoCreationEnabled(bool isEnabled) {
    _queryEngine.indexAutoCreationEnabled = isEnabled;
  }

  Future<void> startMutationQueue() {
    return _persistence.runTransaction(
      'Start MutationQueue',
      _mutationQueue.start,
    );
  }

  // PORTING NOTE: no shutdown for [LocalStore] or persistence components on Android.
  Future<ImmutableSortedMap<DocumentKey, MaybeDocument>> handleUserChange(
    User user,
  ) async {
    // Swap out the mutation queue, grabbing the pending mutation batches before and after.
    final List<MutationBatch> oldBatches = await _mutationQueue
        .getAllMutationBatches();

    _mutationQueue = _persistence.getMutationQueue(user);
    _documentOverlayCache = _persistence.getDocumentOverlayCache(user);
    _indexManager = _persistence.getIndexManager(user);
    await startIndexManager();
    _remoteDocuments.indexManager = _indexManager;
    await startMutationQueue();

    final List<MutationBatch> newBatches = await _mutationQueue
        .getAllMutationBatches();

    // Recreate our LocalDocumentsView using the new MutationQueue.
    _localDocuments = LocalDocumentsView(
      remoteDocumentCache: _remoteDocuments,
      mutationQueue: _mutationQueue,
      documentOverlayCache: _documentOverlayCache,
      indexManager: _indexManager,
    );
    _queryEngine.setLocalDocumentsView(_localDocuments);

    // Union the old/new changed keys.
    ImmutableSortedSet<DocumentKey> changedKeys = DocumentKey.emptyKeySet;
    for (List<MutationBatch> batches in <List<MutationBatch>>[
      oldBatches,
      newBatches,
    ]) {
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
    return _persistence.runTransactionAndReturn('Locally write mutations', () async {
      // Figure out which keys do not have a remote version in the cache, this is needed to create the right overlay
      // mutation: if no remote version presents, we do not need to create overlays as patch mutations.
      final Map<DocumentKey, MaybeDocument?> remoteDocs = await _remoteDocuments
          .getAll(keys);
      final Set<DocumentKey> docsWithoutRemoteVersion = <DocumentKey>{
        for (MapEntry<DocumentKey, MaybeDocument?> entry in remoteDocs.entries)
          if (entry.value == null) entry.key,
      };

      // Load and apply all existing mutations. This lets us compute the
      // current base state for all non-idempotent transforms before applying
      // any additional user-provided writes.
      final Map<DocumentKey, OverlayedDocument> overlayedDocuments =
          await _localDocuments.getOverlayedDocuments(remoteDocs);

      // For non-idempotent mutations (such as `FieldValue.increment()`), we
      // record the base state in a separate patch mutation. This is later
      // used to guarantee consistent values and prevents flicker even if the
      // backend sends us an update that already includes our transform.
      final List<Mutation> baseMutations = <Mutation>[];
      for (Mutation mutation in mutations) {
        final ObjectValue? baseValue = mutation.extractTransformBaseValue(
          overlayedDocuments[mutation.key]!.document,
        );
        if (baseValue != null) {
          // NOTE: The base state should only be applied if there's some existing
          // document to override, so use a Precondition of exists=true
          baseMutations.add(
            PatchMutation(
              mutation.key,
              baseValue,
              baseValue.fieldMask,
              Precondition(exists: true),
            ),
          );
        }
      }

      final MutationBatch batch = await _mutationQueue.addMutationBatch(
        localWriteTime,
        baseMutations,
        mutations,
      );
      // Apply the new batch on top of the current local view and save the resulting overlays.
      ImmutableSortedMap<DocumentKey, MaybeDocument> changedDocuments =
          DocumentCollections.emptyMaybeDocumentMap();
      final Map<DocumentKey, Mutation> overlays = <DocumentKey, Mutation>{};
      for (DocumentKey key in keys) {
        final OverlayedDocument overlayed = overlayedDocuments[key]!;
        final (MaybeDocument? document, FieldMask? mutatedFields) = batch
            .applyToLocalViewWithMask(
              key,
              overlayed.document,
              overlayed.mutatedFields,
            );
        // Set mutatedFields to null if the document is only from local mutations, this creates a Set (or Delete)
        // mutation, instead of trying to create a patch mutation as the overlay (unless no mutation applied).
        final bool hasLocalMutations =
            mutatedFields == null ||
            mutatedFields.mask.isNotEmpty ||
            (document is Document && document.hasLocalMutations);
        final Mutation? overlay = Mutation.calculateOverlayMutation(
          document,
          hasLocalMutations && docsWithoutRemoteVersion.contains(key)
              ? null
              : mutatedFields,
        );
        if (overlay != null) {
          overlays[key] = overlay;
        }
        changedDocuments = changedDocuments.insert(
          key,
          document ??
              NoDocument(
                key,
                SnapshotVersion.none,
                hasCommittedMutations: false,
              ),
        );
      }
      await _documentOverlayCache.saveOverlays(batch.batchId, overlays);
      return LocalWriteResult(batch.batchId, changedDocuments);
    });
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
  Future<ImmutableSortedMap<DocumentKey, MaybeDocument>> acknowledgeBatch(
    MutationBatchResult batchResult,
  ) {
    return _persistence.runTransactionAndReturn<
      ImmutableSortedMap<DocumentKey, MaybeDocument>
    >('Acknowledge batch', () async {
      final MutationBatch batch = batchResult.batch;
      await _mutationQueue.acknowledgeBatch(batch, batchResult.streamToken);
      await _applyWriteToRemoteDocuments(batchResult);
      await _mutationQueue.performConsistencyCheck();

      await _documentOverlayCache.removeOverlaysForBatchId(batch.batchId);
      await _localDocuments.recalculateAndSaveOverlays(
        _getKeysWithTransformResults(batchResult),
      );

      return _localDocuments.getDocuments(batch.keys);
    });
  }

  /// Removes mutations from the [MutationQueue] for the specified batch. LocalDocuments will be recalculated.
  Future<ImmutableSortedMap<DocumentKey, MaybeDocument>> rejectBatch(
    int batchId,
  ) {
    // TODO(long1eu): Call queryEngine.handleDocumentChange() appropriately.
    return _persistence.runTransactionAndReturn<
      ImmutableSortedMap<DocumentKey, MaybeDocument>
    >('Reject batch', () async {
      final MutationBatch? foundBatch = await _mutationQueue
          .lookupMutationBatch(batchId);
      hardAssert(foundBatch != null, 'Attempt to reject nonexistent batch!');
      final MutationBatch toReject = foundBatch!;

      await _mutationQueue.removeMutationBatch(toReject);
      await _mutationQueue.performConsistencyCheck();

      await _documentOverlayCache.removeOverlaysForBatchId(batchId);
      await _localDocuments.recalculateAndSaveOverlays(toReject.keys);

      return _localDocuments.getDocuments(toReject.keys);
    });
  }

  /// Returns the keys of the documents whose mutations in the acknowledged batch had transform results: their
  /// overlays hold the local estimates of the transforms and are recalculated on top of the server values.
  static Set<DocumentKey> _getKeysWithTransformResults(
    MutationBatchResult batchResult,
  ) {
    final Set<DocumentKey> result = <DocumentKey>{};
    for (int i = 0; i < batchResult.mutationResults.length; ++i) {
      if (batchResult.mutationResults[i].transformResults.isNotEmpty) {
        result.add(batchResult.batch.mutations[i].key);
      }
    }
    return result;
  }

  /// Returns the last recorded stream token for the current user.
  Uint8List get lastStreamToken => _mutationQueue.lastStreamToken;

  /// Sets the stream token for the current user without acknowledging any mutation batch. This is usually only useful
  /// after a stream handshake or in response to an error that requires clearing the stream token.
  ///
  /// Use [WriteStream.emptyStreamToken] to clear the current value.
  Future<void> setLastStreamToken(Uint8List streamToken) async {
    await _persistence.runTransaction(
      'Set stream token',
      () => _mutationQueue.setLastStreamToken(streamToken),
    );
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
  Future<ImmutableSortedMap<DocumentKey, MaybeDocument>> applyRemoteEvent(
    RemoteEvent remoteEvent,
  ) {
    // TODO(long1eu): Call queryEngine.handleDocumentChange() appropriately.
    return _persistence.runTransactionAndReturn<
      ImmutableSortedMap<DocumentKey, MaybeDocument>
    >('Apply remote event', () async {
      final int sequenceNumber =
          _persistence.referenceDelegate.currentSequenceNumber;

      final Map<int, TargetChange> targetChanges = remoteEvent.targetChanges;
      for (MapEntry<int, TargetChange> entry in targetChanges.entries) {
        final int targetId = entry.key;
        final TargetChange change = entry.value;

        // Do not ref/unref unassigned targetIds - it may lead to leaks.
        final QueryData? existingQueryData = _targetIds[targetId];
        if (existingQueryData == null) {
          continue;
        }
        final QueryData queryData = existingQueryData;

        await _queryCache.removeMatchingKeys(change.removedDocuments, targetId);
        await _queryCache.addMatchingKeys(change.addedDocuments, targetId);

        QueryData newQueryData = queryData.copyWith(
          snapshotVersion: queryData.snapshotVersion,
          resumeToken: queryData.resumeToken,
          sequenceNumber: sequenceNumber,
        );
        final bool isMismatch = remoteEvent.targetMismatches.containsKey(
          targetId,
        );
        if (isMismatch) {
          // An existence filter mismatch invalidates the target: forget its resume token so that the next listen
          // (also after a restart) gets a full update. The previous results can no longer be trusted either.
          newQueryData = newQueryData
              .copyWith(
                snapshotVersion: SnapshotVersion.none,
                resumeToken: Uint8List(0),
                sequenceNumber: sequenceNumber,
              )
              .withLastLimboFreeSnapshotVersion(SnapshotVersion.none);
        } else if (change.resumeToken.isNotEmpty) {
          // Update the resume token if the change includes one.
          newQueryData = newQueryData.copyWith(
            snapshotVersion: remoteEvent.snapshotVersion,
            resumeToken: change.resumeToken,
            sequenceNumber: sequenceNumber,
          );
        }

        _targetIds[targetId] = newQueryData;

        // Update the query data if there are target changes (or if sufficient time has passed since the last update).
        // A cleared resume token is always persisted, otherwise the stale token would be used again after a restart.
        if (isMismatch ||
            _shouldPersistQueryData(queryData, newQueryData, change)) {
          await _queryCache.updateQueryData(newQueryData);
        }
      }

      final Map<DocumentKey, MaybeDocument> changedDocs =
          <DocumentKey, MaybeDocument>{};
      final Map<DocumentKey, MaybeDocument> documentUpdates =
          remoteEvent.documentUpdates;
      final Set<DocumentKey> limboDocuments =
          remoteEvent.resolvedLimboDocuments;
      // Each loop iteration only affects its "own" doc, so it's safe to get all the remote documents in advance in a
      // single call.
      final Map<DocumentKey, MaybeDocument?> existingDocs =
          await _remoteDocuments.getAll(documentUpdates.keys);
      final Set<DocumentKey> existenceChangedKeys = <DocumentKey>{};
      for (MapEntry<DocumentKey, MaybeDocument> entry
          in documentUpdates.entries) {
        final DocumentKey key = entry.key;
        final MaybeDocument doc = entry.value;
        final MaybeDocument? existingDoc = existingDocs[key];
        // Check if see if there is a existence state change for this document.
        if ((doc is Document) != (existingDoc is Document)) {
          existenceChangedKeys.add(key);
        }

        // Note: The order of the steps below is important, since we want to ensure that rejected limbo resolutions
        // (which fabricate NoDocuments with SnapshotVersion.none) never add documents to cache.
        if (doc is NoDocument && doc.version == SnapshotVersion.none) {
          // NoDocuments with SnapshotVersion.none are used in manufactured events. We remove these documents from
          // cache since we lost access.
          await _remoteDocuments.remove(doc.key);
          changedDocs[key] = doc;
        } else if (existingDoc == null ||
            doc.version.compareTo(existingDoc.version) > 0 ||
            (doc.version.compareTo(existingDoc.version) == 0 &&
                existingDoc.hasPendingWrites)) {
          hardAssert(
            remoteEvent.snapshotVersion != SnapshotVersion.none,
            'Cannot add a document when the remote version is zero',
          );
          await _remoteDocuments.add(doc, remoteEvent.snapshotVersion);
          changedDocs[key] = doc;
        } else {
          Log.d(
            'LocalStore',
            'Ignoring outdated watch update for $key. Current version: ${existingDoc.version}  Watch version: '
                '${doc.version}',
          );
        }

        if (limboDocuments.contains(key)) {
          await _persistence.referenceDelegate.updateLimboDocument(key);
        }
      }

      // HACK: The only reason we allow snapshot version none is so that we can synthesize remote events when we get
      // permission denied errors while trying to resolve the state of a locally cached document that is in limbo.
      final SnapshotVersion lastRemoteVersion =
          _queryCache.lastRemoteSnapshotVersion;
      final SnapshotVersion remoteVersion = remoteEvent.snapshotVersion;
      if (remoteVersion != SnapshotVersion.none) {
        hardAssertLazy(
          remoteVersion.compareTo(lastRemoteVersion) >= 0,
          () =>
              'Watch stream reverted to previous snapshot?? ($remoteVersion < $lastRemoteVersion)',
        );
        await _queryCache.setLastRemoteSnapshotVersion(remoteVersion);
      }

      return _localDocuments.getLocalViewOfDocuments(
        changedDocs,
        existenceChangedKeys,
      );
    });
  }

  /// Returns true if the [newQueryData] should be persisted during an update of an active target. [QueryData] should
  /// always be persisted when a target is being released and should not call this function.
  ///
  /// While the target is active, [QueryData] updates can be omitted when nothing about the target has changed except
  /// metadata like the resume token or snapshot version. Occasionally it's worth the extra write to prevent these
  /// values from getting too stale after a crash, but this doesn't have to be too frequent.
  static bool _shouldPersistQueryData(
    QueryData oldQueryData,
    QueryData newQueryData,
    TargetChange? change,
  ) {
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

    // Update the query cache if sufficient time has passed since the last persisted last limbo free snapshot version.
    final int newLimboFreeSeconds =
        newQueryData.lastLimboFreeSnapshotVersion.timestamp.seconds;
    final int oldLimboFreeSeconds =
        oldQueryData.lastLimboFreeSnapshotVersion.timestamp.seconds;
    final int limboFreeTimeDelta = newLimboFreeSeconds - oldLimboFreeSeconds;
    if (limboFreeTimeDelta >= _resultTokenMaxAgeSeconds) {
      return true;
    }

    // Otherwise if the only thing that has changed about a target is its resume token it's not worth persisting. Note
    // that the [RemoteStore] keeps an in-memory view of the currently active targets which includes the current resume
    // token, so stream failure or user changes will still use an up-to-date resume token regardless of what we do here.
    if (change == null) {
      return false;
    }
    final int changes =
        change.addedDocuments.length +
        change.modifiedDocuments.length +
        change.removedDocuments.length;
    return changes > 0;
  }

  /// Notify the local store of the changed views to locally pin / unpin documents.
  Future<void> notifyLocalViewChanges(
    List<LocalViewChanges> viewChanges,
  ) async {
    await _persistence.runTransaction('notifyLocalViewChanges', () async {
      for (LocalViewChanges viewChange in viewChanges) {
        if (!_targetIds.containsKey(viewChange.targetId)) {
          // The target was released while the view change was in flight: pinning documents for it would never be
          // undone.
          continue;
        }
        _localViewReferences.addReferences(
          viewChange.added,
          viewChange.targetId,
        );
        final ImmutableSortedSet<DocumentKey> removed = viewChange.removed;
        for (DocumentKey key in removed) {
          await _persistence.referenceDelegate.removeReference(key);
        }
        _localViewReferences.removeReferences(removed, viewChange.targetId);

        if (!viewChange.fromCache) {
          final QueryData queryData = _targetIds[viewChange.targetId]!;

          // Advance the last limbo free snapshot version
          final SnapshotVersion lastLimboFreeSnapshotVersion =
              queryData.snapshotVersion;
          final QueryData updatedQueryData = queryData
              .withLastLimboFreeSnapshotVersion(lastLimboFreeSnapshotVersion);
          _targetIds[viewChange.targetId] = updatedQueryData;

          if (_shouldPersistQueryData(queryData, updatedQueryData, null)) {
            await _queryCache.updateQueryData(updatedQueryData);
          }
        }
      }
    });
  }

  /// Returns the mutation batch after the passed in [batchId] in the mutation queue or null if empty.
  ///
  /// [afterBatchId] The batch to search after, or -1 for the first mutation in the queue.
  ///
  /// Returns the next mutation or null if there wasn't one.
  Future<MutationBatch?> getNextMutationBatch(int afterBatchId) {
    return _mutationQueue.getNextMutationBatchAfterBatchId(afterBatchId);
  }

  /// Returns the highest batch id of the current user's mutation queue (the newest batch that was not yet acknowledged
  /// or rejected), or [MutationBatch.unknown] if there are no pending writes.
  Future<int> getHighestUnacknowledgedBatchId() {
    return _mutationQueue.getHighestUnacknowledgedBatchId();
  }

  /// Returns the current value of a document with a given key, or null if not found.
  Future<MaybeDocument?> readDocument(DocumentKey key) async {
    return _localDocuments.getDocument(key);
  }

  /// Assigns the given target an internal id so that its results can be pinned so they don't get GC'd. A target must
  /// be allocated in the local store before the store can be used to manage its view.
  ///
  /// Allocating an already allocated target will return the existing [QueryData] for that target.
  Future<QueryData> allocateTarget(Target target) async {
    late int targetId;
    late QueryData cached;
    final QueryData? existing = await _queryCache.getQueryData(target);

    if (existing != null) {
      // This target has been listened to previously, so reuse the previous targetId.
      // TODO(long1eu): freshen last accessed date?
      cached = existing;
      targetId = cached.targetId;
    } else {
      await _persistence.runTransaction('Allocate target', () async {
        targetId = _targetIdGenerator.nextId;
        cached = QueryData(
          target,
          targetId,
          _persistence.referenceDelegate.currentSequenceNumber,
          QueryPurpose.listen,
        );

        await _queryCache.addQueryData(cached);
      });
    }

    // Several queries may map to the same target (e.g. a limit query and a mirroring limitToLast query), in which case
    // the target is already active and its in-memory data must not be replaced.
    final QueryData? active = _targetIds[targetId];
    if (active != null) {
      return active;
    }
    _targetIds[targetId] = cached;
    _targetIdByTarget[target] = targetId;
    return cached;
  }

  /// Returns the [QueryData] as seen by the [LocalStore], including updates that may have not yet been persisted to
  /// the [QueryCache].
  @visibleForTesting
  Future<QueryData?> getQueryData(Target target) async {
    final int? targetId = _targetIdByTarget[target];
    if (targetId != null) {
      return _targetIds[targetId];
    }
    return _queryCache.getQueryData(target);
  }

  /// Unpin all the documents associated with the given target.
  ///
  /// Releasing a non-existing target is an error.
  Future<void> releaseTarget(int targetId) {
    return _persistence.runTransaction('Release target', () async {
      final QueryData? cachedQueryData = _targetIds[targetId];
      hardAssertLazy(
        cachedQueryData != null,
        () => 'Tried to release nonexistent target: $targetId',
      );
      final QueryData queryData = cachedQueryData!;

      // References for documents sent via Watch are automatically removed when we delete a query's target data from the
      // reference delegate. Since this does not remove references for locally mutated documents, we have to remove the
      // target associations for these documents manually.
      final ImmutableSortedSet<DocumentKey> removedReferences =
          _localViewReferences.removeReferencesForId(queryData.targetId);
      for (DocumentKey key in removedReferences) {
        await _persistence.referenceDelegate.removeReference(key);
      }
      // Note: This also updates the query cache with the in-memory query data (resume token, last limbo free snapshot
      // version) that may not have been persisted yet.
      await _persistence.referenceDelegate.removeTarget(queryData);
      _targetIds.remove(queryData.targetId);
      _targetIdByTarget.remove(queryData.target);
    });
  }

  /// Runs the specified query against the local store and returns the results, potentially taking advantage of query
  /// data from previous executions (such as the set of remote keys).
  ///
  /// [usePreviousResults] is whether results from previous executions can be used to optimize this query execution.
  Future<QueryResult> executeQuery(Query query, bool usePreviousResults) async {
    final QueryData? queryData = await getQueryData(query.toTarget());
    SnapshotVersion lastLimboFreeSnapshotVersion = SnapshotVersion.none;
    ImmutableSortedSet<DocumentKey> remoteKeys = DocumentKey.emptyKeySet;

    if (queryData != null) {
      lastLimboFreeSnapshotVersion = queryData.lastLimboFreeSnapshotVersion;
      remoteKeys = await _queryCache.getMatchingKeysForTargetId(
        queryData.targetId,
      );
    }

    final ImmutableSortedMap<DocumentKey, Document> documents =
        await _queryEngine.getDocumentsMatchingQuery(
          query,
          usePreviousResults
              ? lastLimboFreeSnapshotVersion
              : SnapshotVersion.none,
          usePreviousResults ? remoteKeys : DocumentKey.emptyKeySet,
        );
    return QueryResult(documents, remoteKeys);
  }

  /// Returns the keys of the documents that are associated with the given target id in the remote table.
  Future<ImmutableSortedSet<DocumentKey>> getRemoteDocumentKeys(int targetId) {
    return _queryCache.getMatchingKeysForTargetId(targetId);
  }

  Future<void> _applyWriteToRemoteDocuments(
    MutationBatchResult batchResult,
  ) async {
    final MutationBatch batch = batchResult.batch;
    final Set<DocumentKey> docKeys = batch.keys;
    for (DocumentKey docKey in docKeys) {
      final MaybeDocument? remoteDoc = await _remoteDocuments.get(docKey);
      MaybeDocument? doc = remoteDoc;
      final SnapshotVersion? ackVersion = batchResult.docVersions[docKey];
      hardAssert(
        ackVersion != null,
        'docVersions should contain every doc in the write.',
      );

      if (doc == null || doc.version.compareTo(ackVersion!) < 0) {
        doc = batch.applyToRemoteDocument(docKey, doc, batchResult);
        if (doc == null) {
          hardAssertLazy(
            remoteDoc == null,
            () =>
                'Mutation batch $batch applied to document $remoteDoc resulted in null.',
          );
        } else {
          await _remoteDocuments.add(doc, batchResult.commitVersion);
        }
      }
    }

    await _mutationQueue.removeMutationBatch(batch);
  }

  Future<LruGarbageCollectorResults> collectGarbage(
    LruGarbageCollector garbageCollector,
  ) {
    return _persistence.runTransactionAndReturn(
      'Collect garbage',
      () => garbageCollector.collect(_targetIds.keys.toSet()),
    );
  }

  /// Returns whether the given bundle has already been loaded and its create time is newer or equal to the currently
  /// loading bundle.
  Future<bool> hasNewerBundle(BundleMetadata bundleMetadata) {
    return _persistence.runTransactionAndReturn<bool>(
      'Has newer bundle',
      () async {
        final BundleMetadata? cachedMetadata = await _bundleCache
            .getBundleMetadata(bundleMetadata.bundleId);
        return cachedMetadata != null &&
            cachedMetadata.createTime.compareTo(bundleMetadata.createTime) >= 0;
      },
    );
  }

  @override
  Future<void> saveBundle(BundleMetadata bundleMetadata) {
    return _persistence.runTransaction(
      'Save bundle',
      () => _bundleCache.saveBundleMetadata(bundleMetadata),
    );
  }

  @override
  Future<ImmutableSortedMap<DocumentKey, MaybeDocument>> applyBundledDocuments(
    ImmutableSortedMap<DocumentKey, MaybeDocument> documents,
    String bundleId, {
    Map<DocumentKey, SnapshotVersion>? readTimes,
  }) async {
    // Allocates a target to hold all document keys from the bundle, such that they will not get garbage collected right
    // away.
    final QueryData umbrellaQueryData = await allocateTarget(
      _newUmbrellaQuery(bundleId).toTarget(),
    );

    return _persistence.runTransactionAndReturn<
      ImmutableSortedMap<DocumentKey, MaybeDocument>
    >('Apply bundle documents', () async {
      ImmutableSortedSet<DocumentKey> documentKeys = DocumentKey.emptyKeySet;
      final Map<DocumentKey, MaybeDocument> documentMap =
          <DocumentKey, MaybeDocument>{};

      for (final MapEntry<DocumentKey, MaybeDocument> entry in documents) {
        final DocumentKey documentKey = entry.key;
        final MaybeDocument document = entry.value;

        if (document is Document) {
          documentKeys = documentKeys.insert(documentKey);
        }
        documentMap[documentKey] = document;
      }

      await _queryCache.removeMatchingKeysForTargetId(
        umbrellaQueryData.targetId,
      );
      await _queryCache.addMatchingKeys(
        documentKeys,
        umbrellaQueryData.targetId,
      );

      final Set<DocumentKey> existenceChangedKeys = <DocumentKey>{};
      final Map<DocumentKey, MaybeDocument> changedDocs =
          await _populateBundledDocumentChanges(
            documentMap,
            readTimes,
            existenceChangedKeys,
          );
      return _localDocuments.getLocalViewOfDocuments(
        changedDocs,
        existenceChangedKeys,
      );
    });
  }

  /// Populates the remote document cache with the documents from a bundle. Returns the document changes resulting from
  /// applying those documents.
  ///
  /// Each document is stored with its read time from [readTimes] (the bundle's document metadata, as the Android SDK
  /// does since the MutableDocument refactor), or with its version if there is none.
  Future<Map<DocumentKey, MaybeDocument>> _populateBundledDocumentChanges(
    Map<DocumentKey, MaybeDocument> documents,
    Map<DocumentKey, SnapshotVersion>? readTimes,
    Set<DocumentKey> existenceChangedKeys,
  ) async {
    final Map<DocumentKey, MaybeDocument> changedDocs =
        <DocumentKey, MaybeDocument>{};

    // Each loop iteration only affects its 'own' doc, so it's safe to get all the remote documents in advance in a
    // single call.
    final Map<DocumentKey, MaybeDocument?> existingDocs = await _remoteDocuments
        .getAll(documents.keys);

    for (final MapEntry<DocumentKey, MaybeDocument> entry
        in documents.entries) {
      final DocumentKey key = entry.key;
      final MaybeDocument doc = entry.value;
      final MaybeDocument? existingDoc = existingDocs[key];
      if ((doc is Document) != (existingDoc is Document)) {
        existenceChangedKeys.add(key);
      }

      // Note: The order of the steps below is important, since we want to ensure that rejected limbo resolutions (which
      // fabricate NoDocuments with SnapshotVersion.none) never add documents to cache.
      if (doc is NoDocument && doc.version == SnapshotVersion.none) {
        // NoDocuments with SnapshotVersion.none are used in manufactured events. We remove these documents from cache
        // since we lost access.
        await _remoteDocuments.remove(doc.key);
        changedDocs[key] = doc;
      } else if (existingDoc == null ||
          doc.version.compareTo(existingDoc.version) > 0 ||
          (doc.version.compareTo(existingDoc.version) == 0 &&
              existingDoc.hasPendingWrites)) {
        hardAssert(
          doc.version != SnapshotVersion.none,
          'Cannot add a document when the remote version is zero',
        );
        await _remoteDocuments.add(doc, readTimes?[key] ?? doc.version);
        changedDocs[key] = doc;
      } else {
        Log.d(
          'LocalStore',
          'Ignoring outdated bundle document for $key. Current version: ${existingDoc.version}  Bundle version: '
              '${doc.version}',
        );
      }
    }
    return changedDocs;
  }

  @override
  Future<void> saveNamedQuery(
    NamedQuery namedQuery,
    ImmutableSortedSet<DocumentKey> documentKeys,
  ) async {
    // Allocate a target for the named query such that it can be resumed from associated read time if users use it to
    // listen.
    // NOTE: this also means if no corresponding target exists, the new target will remain active and will not get
    // collected, unless users happen to unlisten the query somehow.
    final QueryData existingQueryData = await allocateTarget(
      namedQuery.bundledQuery.toQuery().toTarget(),
    );
    final int targetId = existingQueryData.targetId;

    await _persistence.runTransaction('Saved named query', () async {
      // Only update the matching documents if it is newer than what the SDK already has
      if (namedQuery.readTime.compareTo(existingQueryData.snapshotVersion) >
          0) {
        // Update existing target data because the query from the bundle is newer.
        final QueryData newQueryData = existingQueryData.copyWith(
          snapshotVersion: namedQuery.readTime,
          resumeToken: Uint8List(0),
          sequenceNumber: existingQueryData.sequenceNumber,
        );
        _targetIds[targetId] = newQueryData;

        await _queryCache.updateQueryData(newQueryData);
        await _queryCache.removeMatchingKeysForTargetId(targetId);
        await _queryCache.addMatchingKeys(documentKeys, targetId);
      }

      await _bundleCache.saveNamedQuery(namedQuery);
    });
  }

  /// Returns the [NamedQuery] associated with [queryName] or null if not found.
  Future<NamedQuery?> getNamedQuery(String queryName) {
    return _persistence.runTransactionAndReturn<NamedQuery?>(
      'Get named query',
      () => _bundleCache.getNamedQuery(queryName),
    );
  }

  /// Creates a new query using the given bundle name, which will be used to hold the keys of all documents from the
  /// bundle in query-document mappings. This ensures that the loaded documents do not get garbage collected right away.
  static Query _newUmbrellaQuery(String bundleName) {
    // It is OK that the path used for the query is not valid, because this will not be read and queried.
    return Query(ResourcePath.fromString('__bundle__/docs/$bundleName'));
  }
}
