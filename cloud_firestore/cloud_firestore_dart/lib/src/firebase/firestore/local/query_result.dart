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

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';

/// The result of executing a query against the local store.
class QueryResult {
  const QueryResult(this.documents, this.remoteKeys);

  /// The documents that match the query.
  final ImmutableSortedMap<DocumentKey, Document> documents;

  /// The keys of the documents that matched the query's target at the last remote snapshot.
  final ImmutableSortedSet<DocumentKey> remoteKeys;
}
