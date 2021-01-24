// File created by
// Lung Razvan <long1eu>
// on 17/01/2021

import 'package:_firebase_database_collection_vm/_firebase_database_collection_vm.dart';
import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/local_documents_view.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/query_engine.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';

/// A query engine that takes advantage of the target document mapping in the TargetCache. Query
/// execution is optimized by only reading the documents that previously matched a query plus any
/// documents that were edited after the query was last listened to.
///
/// There are some cases where this optimization is not guaranteed to produce the same results as
/// full collection scans. In these cases, query processing falls back to full scans. These cases
/// are:
///
/// * Limit queries where a document that matched the query previously no longer matches the query.
/// * Limit queries where a document edit may cause the document to sort below another document
///   that is in the local cache.
/// * Queries that have never been CURRENT or free of limbo documents.
class DefaultQueryEngine implements QueryEngine {
  static const String _kLogTag = 'DefaultQueryEngine';

  LocalDocumentsView _localDocumentsView;

  @override
  set localDocumentsView(LocalDocumentsView localDocuments) {
    _localDocumentsView = localDocuments;
  }

  @override
  Future<ImmutableSortedMap<DocumentKey, Document>> getDocumentsMatchingQuery(
    Query query,
    SnapshotVersion lastLimboFreeSnapshotVersion,
    ImmutableSortedSet<DocumentKey> remoteKeys,
  ) async {
    hardAssert(_localDocumentsView != null, 'setLocalDocumentsView() not called');

    // Queries that match all documents don't benefit from using key-based lookups. It is more
    // efficient to scan all documents in a collection, rather than to perform individual lookups.
    if (query.matchesAllDocuments) {
      return _executeFullCollectionScan(query);
    }

    // Queries that have never seen a snapshot without limbo free documents should also be run as a
    // full collection scan.
    if (lastLimboFreeSnapshotVersion == SnapshotVersion.none) {
      return _executeFullCollectionScan(query);
    }

    final ImmutableSortedMap<DocumentKey, MaybeDocument> documents = await _localDocumentsView.getDocuments(remoteKeys);
    final ImmutableSortedSet<Document> previousResults = _applyQuery(query, documents);

    if ((query.hasLimitToFirst || query.hasLimitToLast) &&
        _needsRefill(query.getLimitType(), previousResults, remoteKeys, lastLimboFreeSnapshotVersion)) {
      return _executeFullCollectionScan(query);
    }

    Log.d(_kLogTag, 'Re-using previous result from $lastLimboFreeSnapshotVersion to execute query: $query');

    // Retrieve all results for documents that were updated since the last limbo-document free
    // remote snapshot.
    ImmutableSortedMap<DocumentKey, Document> updatedResults =
        await _localDocumentsView.getDocumentsMatchingQuery(query, lastLimboFreeSnapshotVersion);

    // We merge `previousResults` into `updateResults`, since `updateResults` is already a
    // ImmutableSortedMap. If a document is contained in both lists, then its contents are the same.
    for (Document result in previousResults) {
      updatedResults = updatedResults.insert(result.key, result);
    }

    return updatedResults;
  }

  /// Applies the query filter and sorting to the provided documents.
  ImmutableSortedSet<Document> _applyQuery(Query query, ImmutableSortedMap<DocumentKey, MaybeDocument> documents) {
    // Sort the documents and re-apply the query filter since previously matching documents do not
    // necessarily still match the query.
    ImmutableSortedSet<Document> queryResults = ImmutableSortedSet<Document>(<Document>[], query.comparator);
    for (MapEntry<DocumentKey, MaybeDocument> entry in documents) {
      final MaybeDocument maybeDoc = entry.value;
      if (maybeDoc is Document && query.matches(maybeDoc)) {
        final Document doc = maybeDoc;
        queryResults = queryResults.insert(doc);
      }
    }
    return queryResults;
  }

  /// Determines if a limit query needs to be refilled from cache, making it ineligible for
  /// index-free execution.
  ///
  /// The [limitType] represents the type of limit query for refill calculation, while [sortedPreviousResults]
  /// are the documents that matched the query when it was last synchronized, sorted by the query's comparator.
  bool _needsRefill(
    QueryLimitType limitType,
    ImmutableSortedSet<Document> sortedPreviousResults,
    ImmutableSortedSet<DocumentKey> remoteKeys,
    SnapshotVersion limboFreeSnapshotVersion,
  ) {
    // The query needs to be refilled if a previously matching document no longer matches.
    if (remoteKeys.length != sortedPreviousResults.length) {
      return true;
    }

    // Limit queries are not eligible for index-free query execution if there is a potential that an
    // older document from cache now sorts before a document that was previously part of the limit.
    // This, however, can only happen if the document at the edge of the limit goes out of limit. If
    // a document that is not the limit boundary sorts differently, the boundary of the limit itself
    // did not change and documents from cache will continue to be "rejected" by this boundary.
    // Therefore, we can ignore any modifications that don't affect the last document.
    final Document documentAtLimitEdge = limitType == QueryLimitType.limitToFirst //
        ? sortedPreviousResults.maxEntry
        : sortedPreviousResults.minEntry;
    if (documentAtLimitEdge == null) {
      // We don't need to refill the query if there were already no documents.
      return false;
    }
    return documentAtLimitEdge.hasPendingWrites || documentAtLimitEdge.version.compareTo(limboFreeSnapshotVersion) > 0;
  }

  @override
  void handleDocumentChange(MaybeDocument oldDocument, MaybeDocument newDocument) {
    // No indexes to update.
  }

  Future<ImmutableSortedMap<DocumentKey, Document>> _executeFullCollectionScan(Query query) {
    Log.d(_kLogTag, 'Using full collection scan to execute query: $query');
    return _localDocumentsView.getDocumentsMatchingQuery(query, SnapshotVersion.none);
  }
}
