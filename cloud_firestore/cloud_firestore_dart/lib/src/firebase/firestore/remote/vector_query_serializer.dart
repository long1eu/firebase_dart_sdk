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

import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/distance_measure.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/vector_query.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as proto_v1;
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;

/// Encoding of vector (nearest-neighbour) queries and decoding of their results.
extension VectorQuerySerializer on RemoteSerializer {
  /// Encodes [vectorQuery] on top of the base [query] as a structured query
  /// with a `find_nearest` stage. As for aggregations, only the explicit sort
  /// orders are sent (the ordering of `find_nearest` supersedes them).
  proto.Target_QueryTarget encodeVectorQueryTarget(
    Query query,
    VectorQuery vectorQuery,
  ) {
    final proto.Target_QueryTarget target = encodeQueryTarget(
      query.toTarget(),
    ).clone();
    final List<proto.StructuredQuery_Order> orders =
        target.structuredQuery.orderBy;
    final int explicitCount = query.explicitSortOrder.length;
    if (orders.length > explicitCount) {
      orders.removeRange(explicitCount, orders.length);
    }

    final proto.StructuredQuery_FindNearest findNearest =
        proto.StructuredQuery_FindNearest()
          ..vectorField = (proto.StructuredQuery_FieldReference()
            ..fieldPath = vectorQuery.vectorField.canonicalString)
          ..queryVector = encodeValue(
            VectorFieldValue.fromList(vectorQuery.queryVector.toArray()),
          )
          ..distanceMeasure = _encodeDistanceMeasure(
            vectorQuery.distanceMeasure,
          )
          ..limit = (proto.Int32Value()..value = vectorQuery.limit);
    final String? resultField = vectorQuery.distanceResultField;
    if (resultField != null) {
      findNearest.distanceResultField = resultField;
    }
    final double? threshold = vectorQuery.distanceThreshold;
    if (threshold != null) {
      findNearest.distanceThreshold = proto.DoubleValue()..value = threshold;
    }
    target.structuredQuery.findNearest = findNearest;
    return target..freeze();
  }

  proto.StructuredQuery_FindNearest_DistanceMeasure _encodeDistanceMeasure(
    DistanceMeasure measure,
  ) {
    switch (measure) {
      case DistanceMeasure.euclidean:
        return proto.StructuredQuery_FindNearest_DistanceMeasure.EUCLIDEAN;
      case DistanceMeasure.cosine:
        return proto.StructuredQuery_FindNearest_DistanceMeasure.COSINE;
      case DistanceMeasure.dotProduct:
        return proto.StructuredQuery_FindNearest_DistanceMeasure.DOT_PRODUCT;
    }
  }

  /// Decodes a document returned by a vector query.
  Document decodeVectorQueryDocument(proto_v1.Document document) {
    final DocumentKey key = decodeKey(document.name);
    final SnapshotVersion version = decodeVersion(document.updateTime);
    return Document.fromProto(
      key,
      version,
      DocumentState.synced,
      document,
      decodeValue,
    );
  }
}
