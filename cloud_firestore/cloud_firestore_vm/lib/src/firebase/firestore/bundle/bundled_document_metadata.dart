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

import 'package:cloud_firestore_vm/src/firebase/firestore/bundle/bundle_element.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/snapshot_version.dart';
import 'package:collection/collection.dart';

/// Metadata describing a Firestore document saved in the bundle.
class BundledDocumentMetadata implements BundleElement {
  const BundledDocumentMetadata(
    this.key,
    this.readTime,
    this.exists,
    this.queries,
  );

  /// The document key of a bundled document.
  final DocumentKey key;

  /// The snapshot version of the document data bundled.
  final SnapshotVersion readTime;

  /// Whether the document exists.
  final bool exists;

  /// The names of the queries in this bundle that this document matches to.
  final List<String> queries;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BundledDocumentMetadata &&
          runtimeType == other.runtimeType &&
          key == other.key &&
          readTime == other.readTime &&
          exists == other.exists &&
          const ListEquality<String>().equals(queries, other.queries);

  @override
  int get hashCode =>
      key.hashCode ^
      readTime.hashCode ^
      exists.hashCode ^
      const ListEquality<String>().hash(queries);

  @override
  String toString() =>
      'BundledDocumentMetadata{key: $key, readTime: $readTime, exists: $exists, queries: $queries}';
}
