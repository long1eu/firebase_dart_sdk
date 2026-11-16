// Copyright 2024 Google LLC
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

import 'package:cloud_firestore_dart/src/firebase/firestore/query_document_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/vector_query.dart';

/// The results of a [VectorQuery], nearest document first.
///
/// Vector queries are always served by the backend, so a snapshot is never
/// from the cache and never has pending writes.
///
/// The snapshot is an [Iterable] of its documents:
///
/// ```dart
/// final VectorQuerySnapshot snapshot = await firestore
///     .collection('items')
///     .findNearest('embedding', <double>[0.1, 0.2], 3, DistanceMeasure.euclidean)
///     .get();
/// final List<String> ids = <String>[for (final doc in snapshot) doc.id];
/// ```
///
/// The documents are untyped: a converter of the query is not applied.
class VectorQuerySnapshot<T> extends Iterable<QueryDocumentSnapshot<T>> {
  /// Implementation detail of the SDK; not part of the supported API.
  VectorQuerySnapshot._(this.query, List<QueryDocumentSnapshot<T>> docs)
    : docs = List<QueryDocumentSnapshot<T>>.unmodifiable(docs);

  /// The query that produced this snapshot.
  final VectorQuery<T> query;

  /// The documents, ordered by distance (nearest first).
  final List<QueryDocumentSnapshot<T>> docs;

  @override
  Iterator<QueryDocumentSnapshot<T>> get iterator => docs.iterator;

  @override
  int get length => docs.length;

  /// The number of documents (same as [length]).
  int get size => docs.length;
}

/// Members of [VectorQuerySnapshot] for the SDK itself. Not exported by the public libraries.
extension VectorQuerySnapshotInternal<T> on VectorQuerySnapshot<T> {
  /// The snapshot of [query] with the documents [docs], nearest first.
  static VectorQuerySnapshot<T> create<T>(
    VectorQuery<T> query,
    List<QueryDocumentSnapshot<T>> docs,
  ) => VectorQuerySnapshot<T>._(query, docs);
}
