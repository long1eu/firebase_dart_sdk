// Copyright 2021 Google LLC
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

import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/overlay.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/set_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';

/// Provides methods to read and write document overlays.
///
/// An overlay is a saved mutation, that gives a local view of a document when applied to the remote version of the
/// document. Each overlay stores the largest batch id that is included in the overlay, which allows us to remove the
/// overlay once all batches leading up to it have been acknowledged. Overlays are kept per user.
abstract class DocumentOverlayCache {
  /// Gets the saved overlay mutation for the given document key. Returns null if there is no overlay for that key.
  Future<Overlay?> getOverlay(DocumentKey key);

  /// Gets the saved overlay mutations for the given document keys. Skips keys for which there are no overlays.
  Future<Map<DocumentKey, Overlay>> getOverlays(Iterable<DocumentKey> keys);

  /// Saves the given document key to mutation map to persistence as overlays. All overlays will have their largest
  /// batch id set to [largestBatchId].
  Future<void> saveOverlays(
    int largestBatchId,
    Map<DocumentKey, Mutation> overlays,
  );

  /// Removes the overlays whose largest batch id equals [batchId].
  Future<void> removeOverlaysForBatchId(int batchId);

  /// Removes the overlays of the given documents.
  ///
  /// PORTING NOTE: not in the Android SDK. Used when recalculating the overlay of a document results in no overlay
  /// (all its pending mutations fail their precondition after a remote change), so that the previous overlay is not
  /// applied any more.
  Future<void> removeOverlays(Iterable<DocumentKey> keys);

  /// Returns all saved overlays for the given [collection] (immediate children only).
  ///
  /// [sinceBatchId] is the batch id after which we are interested in overlays (exclusive).
  Future<Map<DocumentKey, Overlay>> getOverlaysForCollection(
    ResourcePath collection,
    int sinceBatchId,
  );

  /// Returns every overlay of the collection of [query] (immediate children only, of every batch), with the plain set
  /// overlays already applied and matched against [query] (see [CollectionOverlays]).
  ///
  /// NOT IN THE OFFICIAL SDKS: a set overlay does not depend on the remote document, so a cache can build its document
  /// and drop it while it reads, instead of holding every overlay of a large collection of pending writes.
  /// [CollectionOverlays.split] does it after [getOverlaysForCollection].
  Future<CollectionOverlays> getOverlaysForCollectionQuery(
    Query query,
    Timestamp now,
  );

  /// Returns [count] overlays with a batch id higher than [sinceBatchId] for the provided [collectionGroup], processed
  /// by ascending batch id. The method always returns all overlays for a batch even if [count] is exceeded.
  Future<Map<DocumentKey, Overlay>> getOverlaysForCollectionGroup(
    String collectionGroup,
    int sinceBatchId,
    int count,
  );
}

/// The overlays of a collection read for a query ([DocumentOverlayCache.getOverlaysForCollectionQuery]): the plain set
/// overlays (no precondition, no field transforms) as the documents they write, kept when they match the query and
/// reduced to their id when they do not, and every other overlay (patch, delete) as it is.
class CollectionOverlays {
  CollectionOverlays(this.overlays, this.documents, this.hiddenIds);

  /// Applies and matches the plain set overlays among the overlays [all] of the collection of [query].
  factory CollectionOverlays.split(
    Map<DocumentKey, Overlay> all,
    Query query,
    Timestamp now,
  ) {
    final Map<DocumentKey, Overlay> overlays = <DocumentKey, Overlay>{};
    final Map<DocumentKey, Document> documents = <DocumentKey, Document>{};
    final Set<String> hiddenIds = <String>{};
    for (final Overlay overlay in all.values) {
      final Document? document = setDocument(overlay.mutation, now);
      if (document == null) {
        overlays[overlay.key] = overlay;
      } else if (query.matches(document)) {
        documents[document.key] = document;
      } else {
        hiddenIds.add(document.key.path.getLastSegment());
      }
    }
    return CollectionOverlays(overlays, documents, hiddenIds);
  }

  /// The document that the overlay [mutation] writes whatever the remote document is, or null if it depends on it:
  /// [mutation] is a set without precondition and field transforms (an overlay that sets the whole document).
  static Document? setDocument(Mutation mutation, Timestamp now) {
    if (mutation is SetMutation &&
        mutation.precondition.isNone &&
        mutation.fieldTransforms.isEmpty) {
      return mutation.applyToLocalView(null, null, now)! as Document;
    }
    return null;
  }

  /// The overlays that are not plain sets: they are applied to the remote document.
  final Map<DocumentKey, Overlay> overlays;

  /// The documents of the plain set overlays that match the query.
  final Map<DocumentKey, Document> documents;

  /// The ids (last segments of the keys) of the documents whose plain set overlay does not match the query: their
  /// remote document is hidden.
  final Set<String> hiddenIds;

  /// The number of overlays read.
  int get length => overlays.length + documents.length + hiddenIds.length;

  bool get isEmpty => length == 0;

  /// Whether the document [key] of the collection has a plain set overlay, matching the query or not.
  bool hasSetOverlay(DocumentKey key) =>
      documents.containsKey(key) ||
      (hiddenIds.isNotEmpty && hiddenIds.contains(key.path.getLastSegment()));
}
