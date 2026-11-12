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

import 'package:cloud_firestore_dart/src/firebase/firestore/distance_measure.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart'
    as core;
import 'package:cloud_firestore_dart/src/firebase/firestore/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query_document_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/vector_query_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/vector_value.dart';
import 'package:meta/meta.dart';

/// The maximum number of nearest neighbours a vector query may request.
const int maxVectorQueryLimit = 1000;

/// The maximum number of dimensions of a query vector.
const int maxVectorQueryDimensions = 2048;

/// A query that finds the documents whose vector field is closest to a given
/// query vector. Create one with [Query.findNearest].
///
/// Vector queries are always executed on the server: they fail with an
/// `unavailable` error when the client is offline. Results are ordered by
/// distance, nearest first.
class VectorQuery {
  /// Validates the arguments and creates the query.
  @internal
  VectorQuery(
    this.query,
    this.vectorField,
    this.queryVector,
    this.limit,
    this.distanceMeasure, {
    this.distanceResultField,
    this.distanceThreshold,
  }) {
    if (limit <= 0 || limit > maxVectorQueryLimit) {
      throw ArgumentError(
          'Invalid vector query: limit must be a positive integer of no more than $maxVectorQueryLimit, but was $limit.');
    }
    if (queryVector.length == 0) {
      throw ArgumentError(
          'Invalid vector query: the query vector must not be empty.');
    }
    if (queryVector.length > maxVectorQueryDimensions) {
      throw ArgumentError(
          'Invalid vector query: the query vector must have no more than $maxVectorQueryDimensions dimensions, but had ${queryVector.length}.');
    }
    final String? resultField = distanceResultField;
    if (resultField != null && resultField.isEmpty) {
      throw ArgumentError(
          'Invalid vector query: distanceResultField must not be empty.');
    }
    final double? threshold = distanceThreshold;
    if (threshold != null && threshold.isNaN) {
      throw ArgumentError(
          'Invalid vector query: distanceThreshold must not be NaN.');
    }
  }

  /// The query whose results are searched.
  final Query<Object?> query;

  /// The field holding the vectors to search.
  final core.FieldPath vectorField;

  /// The vector to find the nearest neighbours of.
  final VectorValue queryVector;

  /// The maximum number of results, between 1 and [maxVectorQueryLimit].
  final int limit;

  /// How the distance between vectors is measured.
  final DistanceMeasure distanceMeasure;

  /// If set, the computed distance is written to this field of each result.
  final String? distanceResultField;

  /// If set, only documents within this distance (or similarity, for
  /// [DistanceMeasure.dotProduct] and [DistanceMeasure.cosine]) are returned.
  final double? distanceThreshold;

  /// Executes the query on the server and returns the nearest documents.
  Future<VectorQuerySnapshot> get() async {
    final List<Document> docs =
        await query.firestore.client.runVectorQuery(query.query, this);
    return VectorQuerySnapshot(
        this,
        docs
            .map((Document doc) => QueryDocumentSnapshot.fromDocument(
                query.firestore, doc,
                fromCache: false, hasPendingWrites: false))
            .toList(growable: false));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VectorQuery &&
          query == other.query &&
          vectorField == other.vectorField &&
          queryVector == other.queryVector &&
          limit == other.limit &&
          distanceMeasure == other.distanceMeasure &&
          distanceResultField == other.distanceResultField &&
          distanceThreshold == other.distanceThreshold;

  @override
  int get hashCode => Object.hash(query, vectorField, queryVector, limit,
      distanceMeasure, distanceResultField, distanceThreshold);
}
