// File created by
// Lung Razvan <long1eu>
// on 20/09/2018
import 'dart:async';

import 'package:_firebase_database_collection_vm/_firebase_database_collection_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/mutation_queue.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/remote_document_cache.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_collections.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/no_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/snapshot_version.dart';

/// A readonly view of the local state of all documents we're tracking (i.e. we have a cached version in
/// [remoteDocumentCache] or local mutations for the document). The view is computed by applying the mutations in the
/// [MutationQueue] to the [RemoteDocumentCache].
// TODO(long1eu): Turn this into the UnifiedDocumentCache / whatever.
class LocalDocumentsView {
  const LocalDocumentsView(this.remoteDocumentCache, this.mutationQueue);

  final RemoteDocumentCache remoteDocumentCache;
  final MutationQueue mutationQueue;

  /// Returns the the local view of the document identified by [key]. If we don't have any cached state it returns null
  Future<MaybeDocument> getDocument(DocumentKey key) async {
    final List<MutationBatch> batches =
        await mutationQueue.getAllMutationBatchesAffectingDocumentKey(key);
    return _getDocument(key, batches);
  }

  // Internal version of [getDocument] that allows reusing batches.
  Future<MaybeDocument> _getDocument(
      DocumentKey key, List<MutationBatch> inBatches) async {
    MaybeDocument document = await remoteDocumentCache.get(key);

    for (MutationBatch batch in inBatches) {
      document = batch.applyToLocalView(key, document);
    }

    return document;
  }

  // Returns the view of the given [docs] as they would appear after applying all mutations in the given [batches].
  Map<DocumentKey, MaybeDocument> _applyLocalMutationsToDocuments(
      Map<DocumentKey, MaybeDocument> docs, List<MutationBatch> batches) {
    return docs.map((DocumentKey key, MaybeDocument value) {
      return MapEntry<DocumentKey, MaybeDocument>(
          key,
          batches.fold(
              value,
              (MaybeDocument localView, MutationBatch batch) =>
                  batch.applyToLocalView(key, localView)));
    });
  }

  /// Gets the local view of the documents identified by [keys].
  ///
  /// If we don't have cached state for a document in [keys], a [NoDocument] will be stored for that key in the
  /// resulting set.
  Future<ImmutableSortedMap<DocumentKey, MaybeDocument>> getDocuments(
      Iterable<DocumentKey> keys) async {
    final Map<DocumentKey, MaybeDocument> docs =
        await remoteDocumentCache.getAll(keys);
    return getLocalViewOfDocuments(docs);
  }

  /// Similar to [getDocuments], but creates the local view from the given [baseDocs] without retrieving documents from
  /// the local store.
  Future<ImmutableSortedMap<DocumentKey, MaybeDocument>>
      getLocalViewOfDocuments(Map<DocumentKey, MaybeDocument> baseDocs) async {
    ImmutableSortedMap<DocumentKey, MaybeDocument> results =
        DocumentCollections.emptyMaybeDocumentMap();

    final List<MutationBatch> batches = await mutationQueue
        .getAllMutationBatchesAffectingDocumentKeys(baseDocs.keys);
    final Map<DocumentKey, MaybeDocument> docs =
        _applyLocalMutationsToDocuments(baseDocs, batches);
    for (MapEntry<DocumentKey, MaybeDocument> entry in docs.entries) {
      // TODO(long1eu): Don't conflate missing / deleted.
      final MaybeDocument maybeDoc = entry.value ??
          NoDocument(
            entry.key,
            SnapshotVersion.none,
            hasCommittedMutations: false,
          );

      results = results.insert(entry.key, maybeDoc);
    }
    return results;
  }

  /// Performs a query against the local view of all documents.
  // TODO(long1eu): The Querying implementation here should move 100% to [SimpleQueryEngine]. Instead, we should just
  //  provide a [getCollectionDocuments] method here that return all the documents in a given collection so that
  //  [SimpleQueryEngine] can do that and then filter in memory.
  Future<ImmutableSortedMap<DocumentKey, Document>> getDocumentsMatchingQuery(
      Query query) async {
    final ResourcePath path = query.path;
    final bool isDocumentKey = DocumentKey.isDocumentKey(path);
    if (isDocumentKey) {
      return _getDocumentsMatchingDocumentQuery(path);
    } else {
      return _getDocumentsMatchingCollectionQuery(query);
    }
  }

  /// Performs a simple document lookup for the given path.
  Future<ImmutableSortedMap<DocumentKey, Document>>
      _getDocumentsMatchingDocumentQuery(ResourcePath path) async {
    ImmutableSortedMap<DocumentKey, Document> result =
        DocumentCollections.emptyDocumentMap();
    // Just do a simple document lookup.
    final MaybeDocument doc = await getDocument(DocumentKey.fromPath(path));
    if (doc is Document) {
      result = result.insert(doc.key, doc);
    }
    return result;
  }

  /// Queries the remote documents and overlays mutations.
  Future<ImmutableSortedMap<DocumentKey, Document>>
      _getDocumentsMatchingCollectionQuery(Query query) async {
    ImmutableSortedMap<DocumentKey, Document> results =
        await remoteDocumentCache.getAllDocumentsMatchingQuery(query);

    final List<MutationBatch> matchingBatches =
        await mutationQueue.getAllMutationBatchesAffectingQuery(query);
    for (MutationBatch batch in matchingBatches) {
      for (Mutation mutation in batch.mutations) {
        // Only process documents belonging to the collection.
        if (!query.path.isImmediateParentOf(mutation.key.path)) {
          continue;
        }

        final DocumentKey key = mutation.key;
        final MaybeDocument baseDoc = results[key];
        final MaybeDocument mutatedDoc =
            mutation.applyToLocalView(baseDoc, baseDoc, batch.localWriteTime);
        if (mutatedDoc is Document) {
          results = results.insert(key, mutatedDoc);
        } else {
          results = results.remove(key);
        }
      }
    }

    // Finally, filter out any documents that don't actually match the query.
    for (MapEntry<DocumentKey, Document> docEntry in results) {
      if (!query.matches(docEntry.value)) {
        results = results.remove(docEntry.key);
      }
    }

    return results;
  }
}
