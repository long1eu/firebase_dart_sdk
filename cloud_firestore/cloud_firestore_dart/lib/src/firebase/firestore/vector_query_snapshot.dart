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
import 'package:meta/meta.dart';

/// The results of a [VectorQuery], nearest document first.
///
/// Vector queries are always served by the backend, so a snapshot is never
/// from the cache and never has pending writes.
class VectorQuerySnapshot extends Iterable<QueryDocumentSnapshot> {
  /// Implementation detail of the SDK; not part of the supported API.
  @internal
  VectorQuerySnapshot(this.query, List<QueryDocumentSnapshot> docs)
    : docs = List<QueryDocumentSnapshot>.unmodifiable(docs);

  /// The query that produced this snapshot.
  final VectorQuery query;

  /// The documents, ordered by distance (nearest first).
  final List<QueryDocumentSnapshot> docs;

  @override
  Iterator<QueryDocumentSnapshot> get iterator => docs.iterator;

  @override
  int get length => docs.length;

  /// The number of documents (same as [length]).
  int get size => docs.length;
}
