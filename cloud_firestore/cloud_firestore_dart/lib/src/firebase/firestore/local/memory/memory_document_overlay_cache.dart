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
import 'dart:collection';

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/document_overlay_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/overlay.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';

/// In-memory [DocumentOverlayCache] of one user.
class MemoryDocumentOverlayCache implements DocumentOverlayCache {
  /// The overlays, sorted by document key.
  ImmutableSortedMap<DocumentKey, Overlay> _overlays =
      ImmutableSortedMap<DocumentKey, Overlay>.emptyMap(DocumentKey.comparator);

  final Map<int, Set<DocumentKey>> _overlayByBatchId =
      <int, Set<DocumentKey>>{};

  @override
  Future<Overlay?> getOverlay(DocumentKey key) async => _overlays[key];

  @override
  Future<Map<DocumentKey, Overlay>> getOverlays(
    Iterable<DocumentKey> keys,
  ) async {
    final Map<DocumentKey, Overlay> result = <DocumentKey, Overlay>{};
    for (DocumentKey key in keys) {
      final Overlay? overlay = _overlays[key];
      if (overlay != null) {
        result[key] = overlay;
      }
    }
    return result;
  }

  void _saveOverlay(int largestBatchId, Mutation mutation) {
    // Remove the association of the overlay to its batch id.
    final Overlay? existing = _overlays[mutation.key];
    if (existing != null) {
      _overlayByBatchId[existing.largestBatchId]!.remove(mutation.key);
    }

    _overlays = _overlays.insert(
      mutation.key,
      Overlay(largestBatchId, mutation),
    );

    // Create the associate of this overlay to the given largestBatchId.
    _overlayByBatchId
        .putIfAbsent(largestBatchId, () => <DocumentKey>{})
        .add(mutation.key);
  }

  @override
  Future<void> saveOverlays(
    int largestBatchId,
    Map<DocumentKey, Mutation> overlays,
  ) async {
    for (MapEntry<DocumentKey, Mutation> entry in overlays.entries) {
      _saveOverlay(largestBatchId, entry.value);
    }
  }

  @override
  Future<void> removeOverlaysForBatchId(int batchId) async {
    final Set<DocumentKey>? keys = _overlayByBatchId.remove(batchId);
    if (keys != null) {
      for (DocumentKey key in keys) {
        _overlays = _overlays.remove(key);
      }
    }
  }

  @override
  Future<void> removeOverlays(Iterable<DocumentKey> keys) async {
    for (DocumentKey key in keys) {
      final Overlay? existing = _overlays[key];
      if (existing != null) {
        _overlayByBatchId[existing.largestBatchId]!.remove(key);
        _overlays = _overlays.remove(key);
      }
    }
  }

  @override
  Future<Map<DocumentKey, Overlay>> getOverlaysForCollection(
    ResourcePath collection,
    int sinceBatchId,
  ) async {
    final Map<DocumentKey, Overlay> result = <DocumentKey, Overlay>{};

    final int immediateChildrenPathLength = collection.length + 1;
    final DocumentKey prefix = DocumentKey.fromPath(
      collection.appendSegment(''),
    );
    final Iterator<MapEntry<DocumentKey, Overlay>> iterator = _overlays
        .iteratorFrom(prefix);

    while (iterator.moveNext()) {
      final Overlay overlay = iterator.current.value;
      final DocumentKey key = overlay.key;
      if (!collection.isPrefixOf(key.path)) {
        break;
      }
      // Documents from sub-collections
      if (key.path.length != immediateChildrenPathLength) {
        continue;
      }

      if (overlay.largestBatchId > sinceBatchId) {
        result[overlay.key] = overlay;
      }
    }

    return result;
  }

  @override
  Future<Map<DocumentKey, Overlay>> getOverlaysForCollectionGroup(
    String collectionGroup,
    int sinceBatchId,
    int count,
  ) async {
    // NOTE: As upstream, this is only needed by the index backfiller, which does not run for memory persistence; it
    // is implemented so that the overlay cache test cases run against both caches.
    final SplayTreeMap<int, Map<DocumentKey, Overlay>> batchIdToOverlays =
        SplayTreeMap<int, Map<DocumentKey, Overlay>>();

    for (MapEntry<DocumentKey, Overlay> entry in _overlays) {
      final Overlay overlay = entry.value;
      final ResourcePath path = overlay.key.path;
      if (path.segments[path.length - 2] != collectionGroup) {
        continue;
      }
      if (overlay.largestBatchId > sinceBatchId) {
        batchIdToOverlays.putIfAbsent(
          overlay.largestBatchId,
          () => <DocumentKey, Overlay>{},
        )[overlay.key] = overlay;
      }
    }

    final Map<DocumentKey, Overlay> result = <DocumentKey, Overlay>{};
    for (Map<DocumentKey, Overlay> overlays in batchIdToOverlays.values) {
      result.addAll(overlays);
      if (result.length >= count) {
        break;
      }
    }

    return result;
  }
}
