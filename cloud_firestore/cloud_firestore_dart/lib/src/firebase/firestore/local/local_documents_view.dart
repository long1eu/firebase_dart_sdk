// File created by
// Lung Razvan <long1eu>
// on 20/09/2018
import 'dart:async';
import 'dart:collection';
import 'dart:math';

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
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/field_mask.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/overlay.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/patch_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/no_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
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
  const LocalDocumentsView({
    required this.remoteDocumentCache,
    required this.mutationQueue,
    required this.documentOverlayCache,
    required this.indexManager,
  });

  final RemoteDocumentCache remoteDocumentCache;
  final MutationQueue mutationQueue;
  final DocumentOverlayCache documentOverlayCache;
  final IndexManager indexManager;

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
    for (MapEntry<DocumentKey, MaybeDocument?> entry in docs.entries) {
      final DocumentKey key = entry.key;
      final MaybeDocument? doc = entry.value;
      final Overlay? overlay = overlays[key];

      // Recalculate an overlay if the document's existence state is changed due to a remote event. This is because
      // document existence state can change if some patch mutation's preconditions are met (also when there is no
      // overlay yet: a patch whose precondition did not match before the change may match now).
      //
      // DEVIATION FROM UPSTREAM (set overlay of a merge): upstream only recalculates when the overlay is missing or a
      // patch. A merge or update on top of a document without remote version is stored as a set overlay; when the
      // document then arrives from the backend, that set would hide the remote fields the pending writes do not
      // touch, so set and delete overlays are recalculated as well.
      if (existenceStateChanged.contains(key)) {
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
  Future<Map<DocumentKey, OverlayedDocument>> _recalculateAndSaveOverlays(
    Map<DocumentKey, MaybeDocument?> docs,
  ) async {
    if (docs.isEmpty) {
      return <DocumentKey, OverlayedDocument>{};
    }
    final List<MutationBatch> batches = await mutationQueue
        .getAllMutationBatchesAffectingDocumentKeys(docs.keys);

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
          context,
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

    if (overlays.isEmpty) {
      // The remote document cache already matched the documents against the query.
      return remoteDocuments;
    }

    // As documents might match the query because of their overlay we need to include documents for all overlays in
    // the initial document set. A patch overlay can make a cached document match the query even if the cached version
    // does not (yet), so those are read from the cache; set and delete overlays do not need a base document.
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
    // matched by the remote document cache.
    final Timestamp now = Timestamp.now();
    ImmutableSortedMap<DocumentKey, Document> results = remoteDocuments;
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
