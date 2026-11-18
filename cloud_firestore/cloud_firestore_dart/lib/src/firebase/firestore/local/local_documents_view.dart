// File created by
// Lung Razvan <long1eu>
// on 20/09/2018
import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:meta/meta.dart';
import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_documents_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/document_overlay_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/index_manager.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/mutation_queue.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/remote_document_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_context.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_collections.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/field_mask.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/field_transform.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/overlay.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/delete_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/patch_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/server_timestamp_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/set_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/transform_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/no_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';

/// The local view of a document together with the fields that are mutated locally: [FieldMask.empty] if the document
/// has no local mutations, null if a set or delete was applied (the whole document is mutated).
class OverlayedDocument {
  const OverlayedDocument(this.document, this.mutatedFields);

  /// The local view of the document, or null if there is neither a cached version nor a local mutation for it.
  final MaybeDocument? document;

  final FieldMask? mutatedFields;
}

/// A readonly view of the local state of all documents we're tracking (i.e. we have a cached version in
/// [remoteDocumentCache] or local mutations for the document). The view is computed by applying the document overlays
/// in [documentOverlayCache] (the result of the mutations in the [MutationQueue]) to the [RemoteDocumentCache].
class LocalDocumentsView {
  LocalDocumentsView({
    required this.remoteDocumentCache,
    required this.mutationQueue,
    required this.documentOverlayCache,
    required this.indexManager,
  });

  final RemoteDocumentCache remoteDocumentCache;
  final MutationQueue mutationQueue;
  final DocumentOverlayCache documentOverlayCache;
  final IndexManager indexManager;

  /// The pending writes of the documents whose overlays an acknowledgement recalculated, kept for the next
  /// acknowledgement of the same document (see [recalculateAndSaveOverlaysAfterAcknowledgement]).
  final Map<DocumentKey, _PendingWrites> _pendingWrites =
      <DocumentKey, _PendingWrites>{};

  /// The number of overlays that acknowledgements saved from such a summary instead of a replay of the queue.
  @visibleForTesting
  int overlaysSavedFromSummary = 0;

  /// Returns the the local view of the document identified by [key]. If we don't have any cached state it returns
  /// null.
  Future<MaybeDocument?> getDocument(DocumentKey key) async {
    final Overlay? overlay = await documentOverlayCache.getOverlay(key);
    MaybeDocument? document = await _getBaseDocument(key, overlay);
    if (overlay != null) {
      document = overlay.mutation.applyToLocalView(
        document,
        document,
        Timestamp.now(),
      );
    }
    return document;
  }

  /// Gets the local view of the documents identified by [keys].
  ///
  /// If we don't have cached state for a document in [keys], a [NoDocument] will be stored for that key in the
  /// resulting set.
  Future<ImmutableSortedMap<DocumentKey, MaybeDocument>> getDocuments(
    Iterable<DocumentKey> keys,
  ) async {
    final Map<DocumentKey, MaybeDocument?> docs = await remoteDocumentCache
        .getAll(keys);
    return getLocalViewOfDocuments(docs);
  }

  /// Similar to [getDocuments], but creates the local view from the given [baseDocs] without retrieving documents from
  /// the local store.
  ///
  /// [existenceStateChanged] is the set of document keys whose existence state changed (a remote event or bundle
  /// created or deleted them). Their overlays are recalculated, since the preconditions of their pending patches may
  /// hold (or fail) now.
  Future<ImmutableSortedMap<DocumentKey, MaybeDocument>>
  getLocalViewOfDocuments(
    Map<DocumentKey, MaybeDocument?> baseDocs, [
    Set<DocumentKey> existenceStateChanged = const <DocumentKey>{},
  ]) async {
    final Map<DocumentKey, Overlay> overlays = await documentOverlayCache
        .getOverlays(baseDocs.keys);
    final Map<DocumentKey, OverlayedDocument> views = await _computeViews(
      baseDocs,
      overlays,
      existenceStateChanged,
    );

    ImmutableSortedMap<DocumentKey, MaybeDocument> results =
        DocumentCollections.emptyMaybeDocumentMap();
    for (MapEntry<DocumentKey, OverlayedDocument> entry in views.entries) {
      // TODO(long1eu): Don't conflate missing / deleted.
      final MaybeDocument maybeDoc =
          entry.value.document ??
          NoDocument(
            entry.key,
            SnapshotVersion.none,
            hasCommittedMutations: false,
          );
      results = results.insert(entry.key, maybeDoc);
    }
    return results;
  }

  /// Gets the overlayed documents for the given document map, which will include the local view of those documents and
  /// a [FieldMask] indicating which fields are mutated locally, null if overlay is a Set or Delete mutation.
  Future<Map<DocumentKey, OverlayedDocument>> getOverlayedDocuments(
    Map<DocumentKey, MaybeDocument?> docs,
  ) async {
    final Map<DocumentKey, Overlay> overlays = await documentOverlayCache
        .getOverlays(docs.keys);
    return _computeViews(docs, overlays, const <DocumentKey>{});
  }

  /// Computes the local view for the given documents.
  ///
  /// [docs] are the base (remote) versions of the documents, [overlays] the overlays that need to be applied to them
  /// and [existenceStateChanged] the documents whose existence state might have changed, which need their overlays
  /// recalculated from the mutation queue.
  Future<Map<DocumentKey, OverlayedDocument>> _computeViews(
    Map<DocumentKey, MaybeDocument?> docs,
    Map<DocumentKey, Overlay> overlays,
    Set<DocumentKey> existenceStateChanged,
  ) async {
    final Map<DocumentKey, MaybeDocument?> recalculateDocuments =
        <DocumentKey, MaybeDocument?>{};
    final Map<DocumentKey, OverlayedDocument> result =
        <DocumentKey, OverlayedDocument>{};
    final Timestamp now = Timestamp.now();
    final Set<DocumentKey> writtenWhole = await _keysWithPendingSetOrDelete(
      existenceStateChanged,
      overlays,
    );
    for (MapEntry<DocumentKey, MaybeDocument?> entry in docs.entries) {
      final DocumentKey key = entry.key;
      final MaybeDocument? doc = entry.value;
      final Overlay? overlay = overlays[key];

      // Recalculate an overlay if the document's existence state is changed due to a remote event. This is because
      // document existence state can change if some patch mutation's preconditions are met (also when there is no
      // overlay yet: a patch whose precondition did not match before the change may match now).
      //
      // PORTING NOTE (deviation, set overlay of a merge): upstream only recalculates when the overlay is missing or a
      // patch. A merge or update on top of a document without remote version is stored as a set overlay (the
      // `docsWithoutRemoteVersion` of `LocalStore.writeLocally`, as upstream); when the document then arrives from the
      // backend, that set would hide the remote fields the pending writes do not touch, so such a set overlay is
      // recalculated as well. A set or delete overlay that comes from a set or delete among the pending writes of the
      // document is applied as stored, as upstream: the pending writes determine the whole document, and recalculating
      // it would only rebase its server timestamps on the remote document (their previous value), which changes the
      // local view without a visible change and raises an extra `modified` event.
      if (existenceStateChanged.contains(key) && !writtenWhole.contains(key)) {
        recalculateDocuments[key] = doc;
      } else if (overlay != null) {
        final Mutation mutation = overlay.mutation;
        result[key] = OverlayedDocument(
          mutation.applyToLocalView(doc, doc, now),
          mutation is PatchMutation ? mutation.mask : null,
        );
      } else {
        // Using empty to indicate there is no overlay for the document.
        result[key] = OverlayedDocument(doc, FieldMask.empty);
      }
    }

    result.addAll(await _recalculateAndSaveOverlays(recalculateDocuments));
    return result;
  }

  /// The keys of [existenceStateChanged] whose overlay in [overlays] is a set or a delete and whose pending mutations
  /// contain a set or a delete of the document: their overlay does not depend on the remote document (see the
  /// PORTING NOTE in [_computeViews]).
  Future<Set<DocumentKey>> _keysWithPendingSetOrDelete(
    Set<DocumentKey> existenceStateChanged,
    Map<DocumentKey, Overlay> overlays,
  ) async {
    final Set<DocumentKey> candidates = <DocumentKey>{
      for (final DocumentKey key in existenceStateChanged)
        if (overlays[key]?.mutation case SetMutation() || DeleteMutation()) key,
    };
    if (candidates.isEmpty) {
      return const <DocumentKey>{};
    }
    final List<MutationBatch> batches = await mutationQueue
        .getAllMutationBatchesAffectingDocumentKeys(candidates);
    return <DocumentKey>{
      for (final MutationBatch batch in batches)
        for (final Mutation mutation in batch.mutations)
          if (candidates.contains(mutation.key) &&
              (mutation is SetMutation || mutation is DeleteMutation))
            mutation.key,
    };
  }

  /// Given a collection group, returns the next documents that follow the provided offset, along with an updated batch
  /// id.
  ///
  /// The documents returned by this method are ordered by remote version from the provided offset. If there are no
  /// more remote documents after the provided offset, documents with mutations in order of batch id from the offset
  /// are returned. Since all documents in a batch are returned together, the total number of documents returned can
  /// exceed [count].
  ///
  /// Only supported with SQLite persistence (it is used to backfill the field indexes).
  Future<LocalDocumentsResult> getNextDocuments(
    String collectionGroup,
    IndexOffset offset,
    int count,
  ) async {
    final Map<DocumentKey, ReadDocument> remoteDocs = await remoteDocumentCache
        .getAllForCollectionGroup(collectionGroup, offset, count);
    final Map<DocumentKey, MaybeDocument?> docs = <DocumentKey, MaybeDocument?>{
      for (final MapEntry<DocumentKey, ReadDocument> entry
          in remoteDocs.entries)
        entry.key: entry.value.document,
    };
    final Map<DocumentKey, SnapshotVersion> readTimes =
        <DocumentKey, SnapshotVersion>{
          for (final MapEntry<DocumentKey, ReadDocument> entry
              in remoteDocs.entries)
            entry.key: entry.value.readTime,
        };

    final Map<DocumentKey, Overlay> overlays = count - docs.length > 0
        ? await documentOverlayCache.getOverlaysForCollectionGroup(
            collectionGroup,
            offset.largestBatchId,
            count - docs.length,
          )
        : <DocumentKey, Overlay>{};

    int largestBatchId = FieldIndex.initialLargestBatchId;
    for (final Overlay overlay in overlays.values) {
      if (!docs.containsKey(overlay.key)) {
        docs[overlay.key] = await _getBaseDocument(overlay.key, overlay);
        // The document is processed for its mutation, not for a remote change: like upstream, where the base document
        // of an overlay that was not part of the read-time scan has no read time.
        readTimes[overlay.key] = SnapshotVersion.none;
      }
      // The callsite will use the largest batch ID together with the latest read time to create a new index offset.
      // Since we only process batch IDs if all remote documents have been read, no overlay will increase the overall
      // read time. This is why we only need to special case the batch id.
      largestBatchId = max(largestBatchId, overlay.largestBatchId);
    }

    // Fetch the overlays of the remote documents and add them to the overlay map.
    final List<DocumentKey> missingOverlays = <DocumentKey>[
      for (final DocumentKey key in docs.keys)
        if (!overlays.containsKey(key)) key,
    ];
    overlays.addAll(await documentOverlayCache.getOverlays(missingOverlays));

    final Map<DocumentKey, OverlayedDocument> localDocs = await _computeViews(
      docs,
      overlays,
      const <DocumentKey>{},
    );
    return LocalDocumentsResult(largestBatchId, <DocumentKey, MaybeDocument?>{
      for (final MapEntry<DocumentKey, OverlayedDocument> entry
          in localDocs.entries)
        entry.key: entry.value.document,
    }, readTimes);
  }

  /// Applies the pending mutations to [docs], saves the resulting overlays and returns the local views.
  ///
  /// [batches] are the batches of the mutation queue that affect [docs], read here when not given.
  Future<Map<DocumentKey, OverlayedDocument>> _recalculateAndSaveOverlays(
    Map<DocumentKey, MaybeDocument?> docs, [
    List<MutationBatch>? batches,
  ]) async {
    if (docs.isEmpty) {
      return <DocumentKey, OverlayedDocument>{};
    }
    batches ??= await mutationQueue.getAllMutationBatchesAffectingDocumentKeys(
      docs.keys,
    );

    final Map<DocumentKey, MaybeDocument?> views =
        Map<DocumentKey, MaybeDocument?>.of(docs);
    final Map<DocumentKey, FieldMask?> masks = <DocumentKey, FieldMask?>{};
    // A reverse lookup map from batch id to the documents within that batch.
    final SplayTreeMap<int, Set<DocumentKey>> documentsByBatchId =
        SplayTreeMap<int, Set<DocumentKey>>();

    // Apply mutations from mutation queue to the documents, collecting batch id and field masks along the way.
    for (MutationBatch batch in batches) {
      for (DocumentKey key in batch.keys) {
        if (!views.containsKey(key)) {
          // If this batch has documents not included in passed in `docs`, skip them.
          continue;
        }

        final FieldMask? mask = masks.containsKey(key)
            ? masks[key]
            : FieldMask.empty;
        final (MaybeDocument?, FieldMask?) applied = batch
            .applyToLocalViewWithMask(key, views[key], mask);
        views[key] = applied.$1;
        masks[key] = applied.$2;
        documentsByBatchId
            .putIfAbsent(batch.batchId, () => <DocumentKey>{})
            .add(key);
      }
    }

    final Set<DocumentKey> processed = <DocumentKey>{};
    final Set<DocumentKey> withoutOverlay = <DocumentKey>{};
    // Iterate in descending order of batch ids, skip documents that are already saved.
    for (int batchId in documentsByBatchId.keys.toList().reversed) {
      final Map<DocumentKey, Mutation> overlays = <DocumentKey, Mutation>{};
      for (DocumentKey key in documentsByBatchId[batchId]!) {
        if (processed.add(key)) {
          final Mutation? mutation = Mutation.calculateOverlayMutation(
            views[key],
            masks[key],
          );
          if (mutation != null) {
            overlays[key] = mutation;
          } else {
            withoutOverlay.add(key);
          }
        }
      }
      await documentOverlayCache.saveOverlays(batchId, overlays);
    }

    // PORTING NOTE: upstream keeps the previous overlay of a document whose mutations no longer apply; that overlay
    // would still be applied on the next read.
    final Set<DocumentKey> noMutations = docs.keys.toSet().difference(
      processed,
    );
    await documentOverlayCache.removeOverlays(<DocumentKey>{
      ...withoutOverlay,
      ...noMutations,
    });

    return <DocumentKey, OverlayedDocument>{
      for (MapEntry<DocumentKey, MaybeDocument?> entry in views.entries)
        entry.key: OverlayedDocument(
          entry.value,
          masks.containsKey(entry.key) ? masks[entry.key] : FieldMask.empty,
        ),
    };
  }

  /// Recalculates overlays by reading the documents from remote document cache first, and saves them after they are
  /// calculated.
  Future<void> recalculateAndSaveOverlays(Set<DocumentKey> documentKeys) async {
    if (documentKeys.isEmpty) {
      return;
    }
    final Map<DocumentKey, MaybeDocument?> docs = await remoteDocumentCache
        .getAll(documentKeys);
    await _recalculateAndSaveOverlays(docs);
  }

  /// Recalculates and saves the overlays of [documentKeys] after [batch] was acknowledged and removed from the
  /// mutation queue, like [recalculateAndSaveOverlays]. [documentKeys] are the documents of [batch] that had
  /// transform results. [changesByOtherClients] is [Persistence.changesByOtherClients] in this transaction.
  ///
  /// DEVIATION FROM UPSTREAM (acknowledgements of transforms): upstream applies all remaining batches of each document
  /// to its new remote version, at every acknowledgement. Draining U pending writes with a transform on one document
  /// then costs O(U²) (10,000 writes with a `serverTimestamp`: 77 ms per acknowledgement, 8 minutes in all). Here the
  /// batches read for a document are also summarised, per suffix of the queue, into the value that each written field
  /// ends with ([_PendingWrites]); the next acknowledgement of that document, if it is of the first of those batches,
  /// takes the summary of the batches after it and applies that to the new remote version instead, in time
  /// proportional to the number of fields written. The summary is only made when it gives exactly the document that
  /// applying the batches gives (see [_PendingWrites.of]); otherwise, and when the remote version is not a [Document],
  /// the batches are applied as upstream does.
  ///
  /// The summary is right only while the batches of the document in the queue are the ones it was made from, less the
  /// acknowledged ones: it is dropped when this client writes the document ([forgetPendingWrites] from
  /// `writeLocally`) or a batch of it is rejected, it is not used when another client changed the storage since
  /// ([changesByOtherClients]), and only for an acknowledgement of the batch it expects next (the batches are
  /// acknowledged in order; a transaction that rolled back an acknowledgement leaves a summary that expects a later
  /// batch, so it is not used either).
  Future<void> recalculateAndSaveOverlaysAfterAcknowledgement(
    MutationBatch batch,
    Set<DocumentKey> documentKeys,
    int changesByOtherClients,
  ) async {
    // The other documents of the batch: their overlays are not recalculated, but the batch left their queue.
    for (final DocumentKey key in batch.keys) {
      if (!documentKeys.contains(key)) {
        final _PendingWrites? pending = _pendingWrites.remove(key);
        if (pending != null &&
            pending.expects(batch.batchId, changesByOtherClients)) {
          pending.next++;
          if (!pending.isDone) {
            _pendingWrites[key] = pending;
          }
        }
      }
    }
    if (documentKeys.isEmpty) {
      return;
    }

    final Map<DocumentKey, MaybeDocument?> docs = await remoteDocumentCache
        .getAll(documentKeys);
    final Map<DocumentKey, MaybeDocument?> recalculate =
        <DocumentKey, MaybeDocument?>{};
    for (final MapEntry<DocumentKey, MaybeDocument?> entry in docs.entries) {
      final DocumentKey key = entry.key;
      final MaybeDocument? doc = entry.value;
      final _PendingWrites? pending = _pendingWrites.remove(key);
      if (pending != null &&
          doc is Document &&
          pending.expects(batch.batchId, changesByOtherClients)) {
        pending.next++;
        if (!pending.isDone) {
          await _saveOverlayOfPendingWrites(doc, pending);
          overlaysSavedFromSummary++;
          _pendingWrites[key] = pending;
          continue;
        }
      }
      recalculate[key] = doc;
    }
    if (recalculate.isEmpty) {
      return;
    }

    final List<MutationBatch> batches = await mutationQueue
        .getAllMutationBatchesAffectingDocumentKeys(recalculate.keys);
    await _recalculateAndSaveOverlays(recalculate, batches);
    for (final DocumentKey key in recalculate.keys) {
      final _PendingWrites? pending = _PendingWrites.of(
        key,
        batches,
        changesByOtherClients,
      );
      if (pending != null) {
        _pendingWrites[key] = pending;
      }
    }
  }

  /// Drops what [recalculateAndSaveOverlaysAfterAcknowledgement] keeps about the pending writes of [keys]: their
  /// batches in the mutation queue changed other than by an acknowledgement.
  void forgetPendingWrites(Iterable<DocumentKey> keys) {
    for (final DocumentKey key in keys) {
      _pendingWrites.remove(key);
    }
  }

  /// Saves the overlay of [remoteDocument] that the remaining batches of [pending] give, as
  /// [_recalculateAndSaveOverlays] would save it after applying those batches to [remoteDocument].
  Future<void> _saveOverlayOfPendingWrites(
    Document remoteDocument,
    _PendingWrites pending,
  ) async {
    final Map<FieldPath, _FieldWrite> writes = pending.writes;
    final ObjectValue remoteData = remoteDocument.data;
    ObjectValue data = remoteData;
    for (final MapEntry<FieldPath, _FieldWrite> entry in writes.entries) {
      data = data.set(
        entry.key,
        entry.value.valueOn(remoteData.get(entry.key)),
      );
    }
    // As every patch that applies (see [PatchMutation.applyToLocalView] and [Mutation.applyToLocalViewWithMask]).
    final Document view = Document(
      remoteDocument.key,
      SnapshotVersion.none,
      DocumentState.localMutations,
      data,
    );
    final Mutation? overlay = Mutation.calculateOverlayMutation(
      view,
      FieldMask(writes.keys.toSet()),
    );
    if (overlay != null) {
      await documentOverlayCache.saveOverlays(
        pending.lastBatchId,
        <DocumentKey, Mutation>{remoteDocument.key: overlay},
      );
    } else {
      await documentOverlayCache.removeOverlays(<DocumentKey>{
        remoteDocument.key,
      });
    }
  }

  /// Performs a query against the local view of all documents.
  ///
  /// [offset] is the read time and document key to start scanning the remote documents at (exclusive);
  /// [IndexOffset.none] considers all of them. Documents with local mutations are always included.
  Future<ImmutableSortedMap<DocumentKey, Document>> getDocumentsMatchingQuery(
    Query query,
    IndexOffset offset, [
    QueryContext? context,
  ]) async {
    final ResourcePath path = query.path;
    if (query.isDocumentQuery) {
      return _getDocumentsMatchingDocumentQuery(path);
    } else if (query.isCollectionGroupQuery) {
      return _getDocumentsMatchingCollectionGroupQuery(query, offset, context);
    } else {
      return _getDocumentsMatchingCollectionQuery(query, offset, context);
    }
  }

  /// Performs a simple document lookup for the given path.
  Future<ImmutableSortedMap<DocumentKey, Document>>
  _getDocumentsMatchingDocumentQuery(ResourcePath path) async {
    ImmutableSortedMap<DocumentKey, Document> result =
        DocumentCollections.emptyDocumentMap();
    // Just do a simple document lookup.
    final MaybeDocument? doc = await getDocument(DocumentKey.fromPath(path));
    if (doc is Document) {
      result = result.insert(doc.key, doc);
    }
    return result;
  }

  Future<ImmutableSortedMap<DocumentKey, Document>>
  _getDocumentsMatchingCollectionGroupQuery(
    Query query,
    IndexOffset offset,
    QueryContext? context,
  ) async {
    hardAssert(
      query.path.isEmpty,
      'Currently we only support collection group queries at the root.',
    );
    final String collectionId = query.collectionGroup!;
    ImmutableSortedMap<DocumentKey, Document> results =
        DocumentCollections.emptyDocumentMap();
    final List<ResourcePath> parents = await indexManager.getCollectionParents(
      collectionId,
    );

    // Perform a collection query against each parent that contains the
    // collectionId and aggregate the results.
    for (ResourcePath parent in parents) {
      final Query collectionQuery = query.asCollectionQueryAtPath(
        parent.appendSegment(collectionId),
      );
      final ImmutableSortedMap<DocumentKey, Document> collectionResults =
          await _getDocumentsMatchingCollectionQuery(
            collectionQuery,
            offset,
            context,
          );
      for (MapEntry<DocumentKey, Document> docEntry in collectionResults) {
        results = results.insert(docEntry.key, docEntry.value);
      }
    }
    return results;
  }

  /// Queries the remote documents and applies the overlays of the collection.
  Future<ImmutableSortedMap<DocumentKey, Document>>
  _getDocumentsMatchingCollectionQuery(
    Query query,
    IndexOffset offset,
    QueryContext? context,
  ) async {
    // With an offset that comes from a field index only the overlays of the batches after the offset are read: the
    // documents of the earlier batches are in the index with their overlay applied.
    final bool overlaysSinceBatch =
        offset.largestBatchId != FieldIndex.initialLargestBatchId;
    final Map<DocumentKey, Overlay> overlays = await documentOverlayCache
        .getOverlaysForCollection(query.path, offset.largestBatchId);

    // PORTING NOTE: upstream filters the remote documents by the query here as well. With only the newer overlays at
    // hand that misses a document that was read after the offset and matches the query (or stops matching it) through
    // an overlay of an earlier batch, until the next backfill. The port reads all the documents after the offset in
    // that case and looks their overlays up by key.
    final ImmutableSortedMap<DocumentKey, Document> remoteDocuments =
        await remoteDocumentCache.getAllDocumentsMatchingQuery(
          overlaysSinceBatch ? Query(query.path) : query,
          offset,
          mutatedKeys: overlays.keys.toSet(),
          context: context,
        );
    if (overlaysSinceBatch) {
      final List<DocumentKey> withoutOverlay = <DocumentKey>[
        for (final MapEntry<DocumentKey, Document> entry in remoteDocuments)
          if (!overlays.containsKey(entry.key)) entry.key,
      ];
      if (withoutOverlay.isNotEmpty) {
        overlays.addAll(await documentOverlayCache.getOverlays(withoutOverlay));
      }
    }

    // The documents without an overlay are results as they are. They were read without the filters of the query
    // when the overlays of the earlier batches had to be looked up.
    ImmutableSortedMap<DocumentKey, Document> matching = remoteDocuments;
    if (overlaysSinceBatch) {
      for (final MapEntry<DocumentKey, Document> entry in remoteDocuments) {
        if (!overlays.containsKey(entry.key) && !query.matches(entry.value)) {
          matching = matching.remove(entry.key);
        }
      }
    }

    if (overlays.isEmpty) {
      return matching;
    }

    // As documents might match the query because of their overlay we need to include documents for all overlays in
    // the initial document set. The remote document cache returned the cached documents with an overlay that were read
    // after the offset; a patch overlay of a document that is not among them (it was read before the offset or is
    // cached as deleted) needs its base read by key. Set and delete overlays do not need a base document.
    final List<DocumentKey> missingPatchBases = <DocumentKey>[
      for (Overlay overlay in overlays.values)
        if (overlay.mutation is PatchMutation &&
            !remoteDocuments.containsKey(overlay.key))
          overlay.key,
    ];
    final Map<DocumentKey, MaybeDocument?> patchBases =
        missingPatchBases.isEmpty
        ? const <DocumentKey, MaybeDocument?>{}
        : await remoteDocumentCache.getAll(missingPatchBases);

    // Apply the overlays and match against the query. Only the documents with an overlay are touched: the others were
    // matched above.
    final Timestamp now = Timestamp.now();
    ImmutableSortedMap<DocumentKey, Document> results = matching;
    for (Overlay overlay in overlays.values) {
      final DocumentKey key = overlay.key;
      final MaybeDocument? base = remoteDocuments[key] ?? patchBases[key];
      final MaybeDocument? doc = overlay.mutation.applyToLocalView(
        base,
        base,
        now,
      );
      if (doc is Document && query.matches(doc)) {
        results = results.insert(key, doc);
      } else {
        results = results.remove(key);
      }
    }

    return results;
  }

  /// Returns a base document that can be used to apply [overlay].
  Future<MaybeDocument?> _getBaseDocument(
    DocumentKey key,
    Overlay? overlay,
  ) async {
    // A set or delete overlay replaces the whole document: there is no need to read the remote version (712e5b8).
    return (overlay == null || overlay.mutation is PatchMutation)
        ? remoteDocumentCache.get(key)
        : null;
  }
}

/// The pending batches of one document, and for each suffix of them the value that every field they write ends with
/// once they are applied to a [Document] (see [LocalDocumentsView.recalculateAndSaveOverlaysAfterAcknowledgement]).
class _PendingWrites {
  _PendingWrites._(this.batchIds, this._suffixes, this.changesByOtherClients);

  /// The ids of the batches that write the document, in order.
  final List<int> batchIds;

  /// What batches `i` to the last one write, by index `i`: the fields they write and the value each field ends with.
  final List<Map<FieldPath, _FieldWrite>> _suffixes;

  /// [Persistence.changesByOtherClients] when the batches were read.
  final int changesByOtherClients;

  /// The index in [batchIds] of the first batch that is not acknowledged yet.
  int next = 0;

  bool get isDone => next == batchIds.length;

  int get lastBatchId => batchIds.last;

  /// What the batches that are not acknowledged yet write.
  Map<FieldPath, _FieldWrite> get writes => _suffixes[next];

  /// Whether this describes the batches of the document in the queue when [batchId] is acknowledged.
  bool expects(int batchId, int changesByOtherClients) =>
      changesByOtherClients == this.changesByOtherClients &&
      !isDone &&
      batchIds[next] == batchId;

  /// Summarises the batches of [batches] that write [key], or returns null when the summary could differ from
  /// applying them one by one ([MutationBatch.applyToLocalViewWithMask], as [_recalculateAndSaveOverlays] does).
  ///
  /// It is made only when, in every batch, the document has one mutation (and any base mutations), each of them a
  /// [PatchMutation] that holds for any [Document] (no precondition, or `exists: true`) and deletes no field, and no
  /// field path written (by a mask or a transform) is a proper prefix of another one. Then, applied to a [Document]:
  ///
  /// * every mutation applies, the result is a [Document] with local mutations and version
  ///   [SnapshotVersion.none], and the mask is the union of all masks and transform paths;
  /// * by the definitions of [ObjectValue.set] and [ObjectValue.get], setting a path changes neither what another
  ///   path that is not its prefix or below it reads nor, in either order, the result of setting that other path, and
  ///   setting a path twice equals setting it to the second value. So each path ends with the last value written to
  ///   it, and a transform reads the last value written to its path, or the remote value of the path (a transform
  ///   reads the value after the patch of its mutation, or the value before the batch when that is absent, which is
  ///   the same field read when the batch has one mutation of the document);
  /// * a path that is set to a value and transformed later ends with that transform applied to the value, computed
  ///   here as when the batches are applied. A path transformed only by server timestamps since the start ends with
  ///   `ServerTimestampValue(t, remote value)`, `t` the local write time of the last one: [ServerTimestampValue]
  ///   keeps the previous value of a previous server timestamp, so `STV(t2, STV(t1, x)) == STV(t2, x)`. Any other
  ///   transform of a value that depends on the remote document is not summarised (null).
  ///
  /// The suffixes are made from the last batch back; a suffix that no batch before it changes is shared, and the
  /// summary is given up when the copies would cost more than a few entries per batch (when many batches write
  /// different fields).
  static _PendingWrites? of(
    DocumentKey key,
    List<MutationBatch> batches,
    int changesByOtherClients,
  ) {
    final List<MutationBatch> own = <MutationBatch>[
      for (final MutationBatch batch in batches)
        if (batch.keys.contains(key)) batch,
    ];
    if (own.isEmpty) {
      return null;
    }
    final Set<FieldPath> paths = <FieldPath>{};
    final List<Map<FieldPath, _FieldWrite>> effects =
        <Map<FieldPath, _FieldWrite>>[];
    for (final MutationBatch batch in own) {
      final Map<FieldPath, _FieldWrite>? effect = _effectOf(key, batch, paths);
      if (effect == null) {
        return null;
      }
      effects.add(effect);
    }
    for (final FieldPath path in paths) {
      FieldPath parent = path;
      while (parent.length > 1) {
        parent = parent.popLast();
        if (paths.contains(parent)) {
          return null;
        }
      }
    }

    int budget = 16 * own.length + 1024;
    final List<Map<FieldPath, _FieldWrite>> suffixes =
        List<Map<FieldPath, _FieldWrite>>.filled(
          own.length,
          const <FieldPath, _FieldWrite>{},
        );
    Map<FieldPath, _FieldWrite> later = const <FieldPath, _FieldWrite>{};
    for (int i = own.length - 1; i >= 0; i--) {
      Map<FieldPath, _FieldWrite>? suffix;
      for (final MapEntry<FieldPath, _FieldWrite> entry in effects[i].entries) {
        final _FieldWrite? last = later[entry.key];
        final _FieldWrite write = last == null
            ? entry.value
            : last.after(entry.value);
        if (!identical(write, last)) {
          if (suffix == null) {
            budget -= later.length + 1;
            if (budget < 0) {
              return null;
            }
            suffix = Map<FieldPath, _FieldWrite>.of(later);
          }
          suffix[entry.key] = write;
        }
      }
      later = suffix ?? later;
      suffixes[i] = later;
    }
    return _PendingWrites._(
      <int>[for (final MutationBatch batch in own) batch.batchId],
      suffixes,
      changesByOtherClients,
    );
  }

  /// What [batch] writes to the document [key], as a function of the document before the batch (a field that is not
  /// in the result keeps its value), adding the paths it writes to [paths]; null if [of] does not summarise it.
  static Map<FieldPath, _FieldWrite>? _effectOf(
    DocumentKey key,
    MutationBatch batch,
    Set<FieldPath> paths,
  ) {
    final List<Mutation> mutations = <Mutation>[
      for (final Mutation mutation in batch.baseMutations)
        if (mutation.key == key) mutation,
    ];
    final int baseMutations = mutations.length;
    for (final Mutation mutation in batch.mutations) {
      if (mutation.key == key) {
        mutations.add(mutation);
      }
    }
    if (mutations.length != baseMutations + 1) {
      return null;
    }

    final Map<FieldPath, _FieldWrite> effect = <FieldPath, _FieldWrite>{};
    for (final Mutation mutation in mutations) {
      if (mutation is! PatchMutation ||
          mutation.precondition.updateTime != null ||
          mutation.precondition.exists == false) {
        return null;
      }
      final Map<FieldPath, _FieldWrite> patched = <FieldPath, _FieldWrite>{};
      for (final FieldPath path in mutation.mask.mask) {
        final FieldValue? value = path.isEmpty
            ? null
            : mutation.value.get(path);
        if (value == null) {
          return null;
        }
        patched[path] = _FieldWrite.value(value);
        paths.add(path);
      }
      // The transforms all read the patched document, then are set in order.
      final List<(FieldPath, _FieldWrite)> transformed =
          <(FieldPath, _FieldWrite)>[];
      for (final FieldTransform transform in mutation.fieldTransforms) {
        final FieldPath path = transform.fieldPath;
        if (path.isEmpty) {
          return null;
        }
        final _FieldWrite? write = _FieldWrite.transform(
          transform.operation,
          batch.localWriteTime,
          patched[path] ?? effect[path],
        );
        if (write == null) {
          return null;
        }
        transformed.add((path, write));
        paths.add(path);
      }
      effect.addAll(patched);
      for (final (FieldPath path, _FieldWrite write) in transformed) {
        effect[path] = write;
      }
    }
    return effect;
  }
}

/// The value that a field ends with after a run of writes, as a function of its value before them: either [value],
/// or (when [value] is null) a pending server timestamp with the local write time [serverTimestampTime] on top of the
/// value before.
class _FieldWrite {
  const _FieldWrite.value(FieldValue this.value) : serverTimestampTime = null;

  const _FieldWrite.serverTimestamp(Timestamp this.serverTimestampTime)
    : value = null;

  final FieldValue? value;
  final Timestamp? serverTimestampTime;

  /// The value of the field when its value before the writes was [previous].
  FieldValue valueOn(FieldValue? previous) =>
      value ??
      ServerTimestampOperation().applyToLocalView(
        previous,
        serverTimestampTime!,
      );

  /// [operation] at [localWriteTime] applied to the field after the writes [before] (null: none), or null when the
  /// result depends on the value before them other than through a server timestamp.
  static _FieldWrite? transform(
    TransformOperation operation,
    Timestamp localWriteTime,
    _FieldWrite? before,
  ) {
    final FieldValue? value = before?.value;
    if (value != null) {
      return _FieldWrite.value(
        operation.applyToLocalView(value, localWriteTime),
      );
    } else if (operation is ServerTimestampOperation) {
      return _FieldWrite.serverTimestamp(localWriteTime);
    }
    return null;
  }

  /// These writes after [earlier] ones: this object itself when the earlier ones make no difference.
  _FieldWrite after(_FieldWrite earlier) {
    final FieldValue? earlierValue = earlier.value;
    if (value != null || earlierValue == null) {
      return this;
    }
    return _FieldWrite.value(
      ServerTimestampOperation().applyToLocalView(
        earlierValue,
        serverTimestampTime!,
      ),
    );
  }
}
