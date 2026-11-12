// Copyright 2019 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:async';

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:firebase_app_dart/internal.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/target.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_documents_view.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/index_manager.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_engine.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';

/// Firestore queries can be executed in three modes. The Query Engine determines what mode to use based on what data is
/// persisted. The mode only determines the runtime complexity of the query - the result set is equivalent across all
/// implementations.
///
/// The Query engine will use indexed-based execution if a user has configured any index that can be used to execute
/// query. Otherwise, the engine will try to optimize the query by re-using a previously persisted query result. If that
/// is not possible, the query will be executed via a full collection scan.
///
/// Index-based execution is the default when available. The query engine supports partial indexed execution and merges
/// the result from the index lookup with documents that have not yet been indexed. The index evaluation matches the
/// backend's format and as such, the SDK can use indexing for all queries that the backend supports.
///
/// If no index exists, the query engine tries to take advantage of the target document mapping in the TargetCache.
/// These mappings exists for all queries that have been synced with the backend at least once and allow the query
/// engine to only read documents that previously matched a query plus any documents that were edited after the query
/// was last listened to.
///
/// For queries that have never been CURRENT or free of limbo documents, this specific optimization is not guaranteed to
/// produce the same results as full collection scans. So in these cases, query processing falls back to full scans.
///
/// Port of the Android SDK's QueryEngine (072ee4c, "Merge the Index Engines"). The field indexes come from
/// [LocalDocumentsView.indexManager].
class DefaultQueryEngine implements QueryEngine {
  static const String _tag = 'DefaultQueryEngine';

  LocalDocumentsView? _localDocumentsView;

  @override
  void setLocalDocumentsView(LocalDocumentsView localDocuments) {
    _localDocumentsView = localDocuments;
  }

  @override
  Future<ImmutableSortedMap<DocumentKey, Document>> getDocumentsMatchingQuery(
      Query query,
      SnapshotVersion lastLimboFreeSnapshotVersion,
      ImmutableSortedSet<DocumentKey> remoteKeys) async {
    hardAssert(
        _localDocumentsView != null, 'setLocalDocumentsView() not called');

    ImmutableSortedMap<DocumentKey, Document>? result =
        await _performQueryUsingIndex(query);
    if (result != null) {
      return result;
    }

    result = await _performQueryUsingRemoteKeys(
        query, remoteKeys, lastLimboFreeSnapshotVersion);
    if (result != null) {
      return result;
    }

    return _executeFullCollectionScan(query);
  }

  /// Performs an indexed query that evaluates the query based on a collection's persisted index values. Returns null
  /// if an index is not available.
  Future<ImmutableSortedMap<DocumentKey, Document>?> _performQueryUsingIndex(
      Query query) async {
    if (query.matchesAllDocuments) {
      // Don't use indexes for queries that can be executed by scanning the collection.
      return null;
    }

    final LocalDocumentsView localDocumentsView = _localDocumentsView!;
    final IndexManager indexManager = localDocumentsView.indexManager;

    final Target target = query.toTarget();
    final IndexType indexType = indexManager.getIndexType(target);

    if (indexType == IndexType.none) {
      // The target cannot be served from any index.
      return null;
    }

    if (query.hasLimit && indexType == IndexType.partial) {
      // We cannot apply a limit for targets that are served using a partial index. If a partial index will be used to
      // serve the target, the query may return a superset of documents that match the target (for example, if the
      // index doesn't include all the target's filters), or may return the correct set of documents in the wrong order
      // (for example, if the index doesn't include a segment for one of the orderBys). Therefore a limit should not be
      // applied in such cases.
      return _performQueryUsingIndex(query.limitToFirst(Target.noLimit));
    }

    final List<DocumentKey>? keys =
        await indexManager.getDocumentsMatchingTarget(target);
    hardAssert(keys != null,
        'index manager must return results for partial and full indexes.');

    final ImmutableSortedMap<DocumentKey, MaybeDocument> indexedDocuments =
        await localDocumentsView.getDocuments(keys!);
    final IndexOffset offset = indexManager.getMinOffsetForTarget(target);

    final ImmutableSortedSet<Document> previousResults =
        _applyQuery(query, indexedDocuments);
    if (_needsRefill(query, keys.length, previousResults, offset.readTime)) {
      // A limit query whose boundaries change due to local edits can be re-run against the cache by excluding the
      // limit. This ensures that all documents that match the query's filters are included in the result set. The SDK
      // can then apply the limit once all local edits are incorporated.
      return _performQueryUsingIndex(query.limitToFirst(Target.noLimit));
    }

    return _appendRemainingResults(previousResults, query, offset);
  }

  /// Performs a query based on the target's persisted query mapping. Returns null if the mapping is not available or
  /// cannot be used.
  Future<ImmutableSortedMap<DocumentKey, Document>?>
      _performQueryUsingRemoteKeys(
          Query query,
          ImmutableSortedSet<DocumentKey> remoteKeys,
          SnapshotVersion lastLimboFreeSnapshotVersion) async {
    if (query.matchesAllDocuments) {
      // Queries that match all documents don't benefit from using key-based lookups. It is more efficient to scan all
      // documents in a collection, rather than to perform individual lookups.
      return null;
    }

    if (lastLimboFreeSnapshotVersion == SnapshotVersion.none) {
      // Queries that have never seen a snapshot without limbo free documents should be run as a full collection scan.
      return null;
    }

    final ImmutableSortedMap<DocumentKey, MaybeDocument> documents =
        await _localDocumentsView!.getDocuments(remoteKeys);
    final ImmutableSortedSet<Document> previousResults =
        _applyQuery(query, documents);

    if (_needsRefill(query, remoteKeys.length, previousResults,
        lastLimboFreeSnapshotVersion)) {
      return null;
    }

    if (Log.isDebugEnabled) {
      Log.d(_tag,
          'Re-using previous result from $lastLimboFreeSnapshotVersion to execute query: $query');
    }

    return _appendRemainingResults(
        previousResults,
        query,
        IndexOffset.createSuccessor(
            lastLimboFreeSnapshotVersion, FieldIndex.initialLargestBatchId));
  }

  /// Applies the query filter and sorting to the provided documents.
  ImmutableSortedSet<Document> _applyQuery(
      Query query, ImmutableSortedMap<DocumentKey, MaybeDocument> documents) {
    // Sort the documents and re-apply the query filter since previously matching documents do not necessarily still
    // match the query.
    ImmutableSortedSet<Document> queryResults =
        ImmutableSortedSet<Document>(<Document>[], query.comparator);
    for (MapEntry<DocumentKey, MaybeDocument> entry in documents) {
      final MaybeDocument maybeDoc = entry.value;
      if (maybeDoc is Document && query.matches(maybeDoc)) {
        queryResults = queryResults.insert(maybeDoc);
      }
    }
    return queryResults;
  }

  /// Determines if a limit query needs to be refilled from cache, making it ineligible for index-free execution.
  ///
  /// [expectedDocumentCount] is the number of documents keys that matched the query at the last snapshot,
  /// [sortedPreviousResults] the documents that match the query based on the previous result, sorted by the query's
  /// comparator (its size may be different from [expectedDocumentCount] if documents cease to match the query) and
  /// [limboFreeSnapshotVersion] the version of the snapshot when the query was last synchronized.
  bool _needsRefill(
      Query query,
      int expectedDocumentCount,
      ImmutableSortedSet<Document> sortedPreviousResults,
      SnapshotVersion limboFreeSnapshotVersion) {
    if (!query.hasLimit) {
      // Queries without limits do not need to be refilled.
      return false;
    }

    if (expectedDocumentCount != sortedPreviousResults.length) {
      // The query needs to be refilled if a previously matching document no longer matches.
      return true;
    }

    // Limit queries are not eligible for index-free query execution if there is a potential that an older document
    // from cache now sorts before a document that was previously part of the limit. This, however, can only happen if
    // the document at the edge of the limit goes out of limit. If a document that is not the limit boundary sorts
    // differently, the boundary of the limit itself did not change and documents from cache will continue to be
    // "rejected" by this boundary. Therefore, we can ignore any modifications that don't affect the last document.
    final Document? documentAtLimitEdge =
        query.limitType == LimitType.limitToFirst
            ? sortedPreviousResults.maxEntry
            : sortedPreviousResults.minEntry;
    if (documentAtLimitEdge == null) {
      // We don't need to refill the query if there were already no documents.
      return false;
    }
    return documentAtLimitEdge.hasPendingWrites ||
        documentAtLimitEdge.version.compareTo(limboFreeSnapshotVersion) > 0;
  }

  @override
  void handleDocumentChange(
      MaybeDocument oldDocument, MaybeDocument newDocument) {
    // No indexes to update.
  }

  Future<ImmutableSortedMap<DocumentKey, Document>> _executeFullCollectionScan(
      Query query) {
    if (Log.isDebugEnabled) {
      Log.d(_tag, 'Using full collection scan to execute query: $query');
    }
    return _localDocumentsView!
        .getDocumentsMatchingQuery(query, IndexOffset.none);
  }

  /// Combines the results from an indexed execution with the remaining documents that have not yet been indexed.
  Future<ImmutableSortedMap<DocumentKey, Document>> _appendRemainingResults(
      Iterable<Document> indexedResults,
      Query query,
      IndexOffset offset) async {
    // Retrieve all results for documents that were updated since the offset.
    ImmutableSortedMap<DocumentKey, Document> remainingResults =
        await _localDocumentsView!.getDocumentsMatchingQuery(query, offset);
    for (final Document entry in indexedResults) {
      remainingResults = remainingResults.insert(entry.key, entry);
    }
    return remainingResults;
  }
}
