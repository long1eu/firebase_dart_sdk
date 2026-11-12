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

import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/overlay.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';

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
      int largestBatchId, Map<DocumentKey, Mutation> overlays);

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
      ResourcePath collection, int sinceBatchId);

  /// Returns [count] overlays with a batch id higher than [sinceBatchId] for the provided [collectionGroup], processed
  /// by ascending batch id. The method always returns all overlays for a batch even if [count] is exceeded.
  Future<Map<DocumentKey, Overlay>> getOverlaysForCollectionGroup(
      String collectionGroup, int sinceBatchId, int count);
}
