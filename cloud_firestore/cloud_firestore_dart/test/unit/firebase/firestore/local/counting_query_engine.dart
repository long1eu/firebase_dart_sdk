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
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_documents_view.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_context.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/index_manager.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/document_overlay_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/mutation_queue.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/remote_document_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_engine.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/overlay.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/patch_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/set_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';

/// The kind of mutation of an overlay that was read.
enum OverlayType { patch, set, delete }

/// A test-only [QueryEngine] that forwards all API calls and exposes the number of documents and mutations read.
class CountingQueryEngine implements QueryEngine {
  CountingQueryEngine(this.subject);

  /// The query engine that is used as the backing implementation.
  final QueryEngine subject;

  int mutationsReadByQuery = 0;
  int mutationsReadByKey = 0;
  int documentsReadByQuery = 0;
  int documentsReadByKey = 0;
  int overlaysReadByCollection = 0;
  int overlaysReadByKey = 0;

  /// The type of every overlay that was read since the last [resetCounts].
  final Map<DocumentKey, OverlayType> overlayTypes =
      <DocumentKey, OverlayType>{};

  void _recordOverlays(Iterable<Overlay> overlays) {
    for (final Overlay overlay in overlays) {
      final Mutation mutation = overlay.mutation;
      overlayTypes[overlay.key] = mutation is PatchMutation
          ? OverlayType.patch
          : mutation is SetMutation
          ? OverlayType.set
          : OverlayType.delete;
    }
  }

  void resetCounts() {
    overlaysReadByCollection = 0;
    overlaysReadByKey = 0;
    overlayTypes.clear();
    mutationsReadByQuery = 0;
    mutationsReadByKey = 0;
    documentsReadByQuery = 0;
    documentsReadByKey = 0;
  }

  @override
  bool get indexAutoCreationEnabled => subject.indexAutoCreationEnabled;

  @override
  set indexAutoCreationEnabled(bool value) =>
      subject.indexAutoCreationEnabled = value;

  @override
  void setLocalDocumentsView(LocalDocumentsView localDocuments) {
    subject.setLocalDocumentsView(
      LocalDocumentsView(
        remoteDocumentCache: _CountingRemoteDocumentCache(
          localDocuments.remoteDocumentCache,
          this,
        ),
        mutationQueue: _CountingMutationQueue(
          localDocuments.mutationQueue,
          this,
        ),
        documentOverlayCache: _CountingDocumentOverlayCache(
          localDocuments.documentOverlayCache,
          this,
        ),
        indexManager: localDocuments.indexManager,
      ),
    );
  }

  @override
  Future<ImmutableSortedMap<DocumentKey, Document>> getDocumentsMatchingQuery(
    Query query,
    SnapshotVersion lastLimboFreeSnapshotVersion,
    ImmutableSortedSet<DocumentKey> remoteKeys,
  ) {
    return subject.getDocumentsMatchingQuery(
      query,
      lastLimboFreeSnapshotVersion,
      remoteKeys,
    );
  }

  @override
  void handleDocumentChange(
    MaybeDocument oldDocument,
    MaybeDocument newDocument,
  ) {
    subject.handleDocumentChange(oldDocument, newDocument);
  }
}

class _CountingRemoteDocumentCache implements RemoteDocumentCache {
  _CountingRemoteDocumentCache(this._subject, this._counter);

  final RemoteDocumentCache _subject;
  final CountingQueryEngine _counter;

  @override
  set indexManager(IndexManager indexManager) =>
      _subject.indexManager = indexManager;

  @override
  Future<void> add(MaybeDocument maybeDocument, SnapshotVersion readTime) =>
      _subject.add(maybeDocument, readTime);

  @override
  Future<void> remove(DocumentKey documentKey) => _subject.remove(documentKey);

  @override
  Future<void> removeAll(Iterable<DocumentKey> documentKeys) =>
      _subject.removeAll(documentKeys);

  @override
  Future<MaybeDocument?> get(DocumentKey documentKey) async {
    final MaybeDocument? result = await _subject.get(documentKey);
    _counter.documentsReadByKey += result != null ? 1 : 0;
    return result;
  }

  @override
  Future<Map<DocumentKey, MaybeDocument?>> getAll(
    Iterable<DocumentKey> documentKeys,
  ) async {
    final Map<DocumentKey, MaybeDocument?> result = await _subject.getAll(
      documentKeys,
    );
    _counter.documentsReadByKey += result.length;
    return result;
  }

  @override
  Future<Map<DocumentKey, ReadDocument>> getAllForCollectionGroup(
    String collectionGroup,
    IndexOffset offset,
    int limit,
  ) async {
    final Map<DocumentKey, ReadDocument> result = await _subject
        .getAllForCollectionGroup(collectionGroup, offset, limit);
    _counter.documentsReadByQuery += result.length;
    return result;
  }

  @override
  Future<ImmutableSortedMap<DocumentKey, Document>>
  getAllDocumentsMatchingQuery(
    Query query,
    IndexOffset offset, {
    Set<DocumentKey> mutatedKeys = const <DocumentKey>{},
    QueryContext? context,
  }) async {
    final ImmutableSortedMap<DocumentKey, Document> result = await _subject
        .getAllDocumentsMatchingQuery(
          query,
          offset,
          mutatedKeys: mutatedKeys,
          context: context,
        );
    _counter.documentsReadByQuery += result.length;
    return result;
  }
}

class _CountingDocumentOverlayCache implements DocumentOverlayCache {
  _CountingDocumentOverlayCache(this._subject, this._counter);

  final DocumentOverlayCache _subject;
  final CountingQueryEngine _counter;

  @override
  Future<Overlay?> getOverlay(DocumentKey key) async {
    final Overlay? result = await _subject.getOverlay(key);
    _counter.overlaysReadByKey += result != null ? 1 : 0;
    if (result != null) {
      _counter._recordOverlays(<Overlay>[result]);
    }
    return result;
  }

  @override
  Future<Map<DocumentKey, Overlay>> getOverlays(
    Iterable<DocumentKey> keys,
  ) async {
    final Map<DocumentKey, Overlay> result = await _subject.getOverlays(keys);
    _counter.overlaysReadByKey += result.length;
    _counter._recordOverlays(result.values);
    return result;
  }

  @override
  Future<void> saveOverlays(
    int largestBatchId,
    Map<DocumentKey, Mutation> overlays,
  ) => _subject.saveOverlays(largestBatchId, overlays);

  @override
  Future<void> removeOverlaysForBatchId(int batchId) =>
      _subject.removeOverlaysForBatchId(batchId);

  @override
  Future<void> removeOverlays(Iterable<DocumentKey> keys) =>
      _subject.removeOverlays(keys);

  @override
  Future<Map<DocumentKey, Overlay>> getOverlaysForCollection(
    ResourcePath collection,
    int sinceBatchId,
  ) async {
    final Map<DocumentKey, Overlay> result = await _subject
        .getOverlaysForCollection(collection, sinceBatchId);
    _counter.overlaysReadByCollection += result.length;
    _counter._recordOverlays(result.values);
    return result;
  }

  @override
  Future<Map<DocumentKey, Overlay>> getOverlaysForCollectionGroup(
    String collectionGroup,
    int sinceBatchId,
    int count,
  ) async {
    final Map<DocumentKey, Overlay> result = await _subject
        .getOverlaysForCollectionGroup(collectionGroup, sinceBatchId, count);
    _counter.overlaysReadByCollection += result.length;
    _counter._recordOverlays(result.values);
    return result;
  }
}

class _CountingMutationQueue implements MutationQueue {
  _CountingMutationQueue(this._subject, this._counter);

  final MutationQueue _subject;
  final CountingQueryEngine _counter;

  @override
  Future<void> start() => _subject.start();

  @override
  Future<bool> isEmpty() => _subject.isEmpty();

  @override
  Future<int> getHighestUnacknowledgedBatchId() =>
      _subject.getHighestUnacknowledgedBatchId();

  @override
  Future<void> acknowledgeBatch(MutationBatch batch, Uint8List streamToken) =>
      _subject.acknowledgeBatch(batch, streamToken);

  @override
  Uint8List get lastStreamToken => _subject.lastStreamToken;

  @override
  Future<void> setLastStreamToken(Uint8List streamToken) =>
      _subject.setLastStreamToken(streamToken);

  @override
  Future<MutationBatch> addMutationBatch(
    Timestamp localWriteTime,
    List<Mutation> baseMutations,
    List<Mutation> mutations,
  ) => _subject.addMutationBatch(localWriteTime, baseMutations, mutations);

  @override
  Future<MutationBatch?> lookupMutationBatch(int batchId) =>
      _subject.lookupMutationBatch(batchId);

  @override
  Future<MutationBatch?> getNextMutationBatchAfterBatchId(int batchId) =>
      _subject.getNextMutationBatchAfterBatchId(batchId);

  @override
  Future<List<MutationBatch>> getAllMutationBatches() async {
    final List<MutationBatch> result = await _subject.getAllMutationBatches();
    _counter.mutationsReadByKey += result.length;
    return result;
  }

  @override
  Future<List<MutationBatch>> getAllMutationBatchesAffectingDocumentKey(
    DocumentKey documentKey,
  ) async {
    final List<MutationBatch> result = await _subject
        .getAllMutationBatchesAffectingDocumentKey(documentKey);
    _counter.mutationsReadByKey += result.length;
    return result;
  }

  @override
  Future<List<MutationBatch>> getAllMutationBatchesAffectingDocumentKeys(
    Iterable<DocumentKey> documentKeys,
  ) async {
    final List<MutationBatch> result = await _subject
        .getAllMutationBatchesAffectingDocumentKeys(documentKeys);
    _counter.mutationsReadByKey += result.length;
    return result;
  }

  @override
  Future<List<MutationBatch>> getAllMutationBatchesAffectingQuery(
    Query query,
  ) async {
    final List<MutationBatch> result = await _subject
        .getAllMutationBatchesAffectingQuery(query);
    _counter.mutationsReadByQuery += result.length;
    return result;
  }

  @override
  Future<void> removeMutationBatch(MutationBatch batch) =>
      _subject.removeMutationBatch(batch);

  @override
  Future<void> performConsistencyCheck() => _subject.performConsistencyCheck();
}
