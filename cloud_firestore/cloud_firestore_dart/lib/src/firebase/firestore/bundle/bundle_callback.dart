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

// Ported from the Firestore Android SDK (com.google.firebase.firestore.bundle).

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_metadata.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/named_query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';

/// Interface implemented by components that can apply changes from a bundle to local storage.
abstract class BundleCallback {
  /// Applies the documents from a bundle to the 'ground-state' (remote) documents.
  ///
  /// Local documents are re-calculated if there are remaining mutations in the queue.
  ///
  /// [readTimes] holds the read time of each document in the bundle (from its bundled document metadata); documents
  /// without an entry use their version as read time.
  Future<ImmutableSortedMap<DocumentKey, MaybeDocument>> applyBundledDocuments(
    ImmutableSortedMap<DocumentKey, MaybeDocument> documents,
    String bundleId, {
    Map<DocumentKey, SnapshotVersion>? readTimes,
  });

  /// Saves the given [NamedQuery] to local persistence.
  Future<void> saveNamedQuery(
    NamedQuery namedQuery,
    ImmutableSortedSet<DocumentKey> documentKeys,
  );

  /// Saves the given [BundleMetadata] to local persistence.
  Future<void> saveBundle(BundleMetadata bundleMetadata);
}
