// Copyright 2022 Google LLC
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

import 'package:cloud_firestore_vm/src/firebase/firestore/aggregate_field.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_vm/src/proto/google/firestore/v1/index.dart'
    as proto_v1;
import 'package:cloud_firestore_vm/src/proto/index.dart' as proto;

/// Encoding of aggregation queries and decoding of their results.
extension AggregationSerializer on RemoteSerializer {
  /// Encodes the target of an aggregation over [query]. Unlike a listen
  /// target, only the explicit sort orders are sent: the implicit key ordering
  /// is irrelevant to an aggregation.
  proto.Target_QueryTarget encodeAggregateQueryTarget(Query query) {
    final proto.Target_QueryTarget target = encodeQueryTarget(query.toTarget()).clone();
    final List<proto.StructuredQuery_Order> orders =
        target.structuredQuery.orderBy;
    final int explicitCount = query.explicitSortOrder.length;
    if (orders.length > explicitCount) {
      orders.removeRange(explicitCount, orders.length);
    }
    return target..freeze();
  }

  /// Builds the structured aggregation query for [aggregateFields].
  ///
  /// The server only accepts short aliases, so each distinct aggregation is
  /// sent as `aggregate_N` and [aliasMap] receives the mapping from that alias
  /// to the client-side alias. Duplicate aggregations are sent once.
  proto.StructuredAggregationQuery encodeStructuredAggregationQuery(
    proto.Target_QueryTarget encodedQueryTarget,
    List<AggregateField> aggregateFields,
    Map<String, String> aliasMap,
  ) {
    final proto.StructuredAggregationQuery result =
        proto.StructuredAggregationQuery()
          ..structuredQuery = encodedQueryTarget.structuredQuery;

    final Set<String> unique = <String>{};
    int aliasId = 1;
    for (final AggregateField field in aggregateFields) {
      if (!unique.add(field.alias)) {
        continue;
      }
      final String serverAlias = 'aggregate_${aliasId++}';
      aliasMap[serverAlias] = field.alias;

      final proto.StructuredAggregationQuery_Aggregation aggregation =
          proto.StructuredAggregationQuery_Aggregation()..alias = serverAlias;
      final proto.StructuredQuery_FieldReference reference =
          proto.StructuredQuery_FieldReference()..fieldPath = field.fieldPath;
      if (field is CountAggregateField) {
        aggregation.count =
            proto.StructuredAggregationQuery_Aggregation_Count();
      } else if (field is SumAggregateField) {
        aggregation.sum = proto.StructuredAggregationQuery_Aggregation_Sum()
          ..field_1 = reference;
      } else if (field is AverageAggregateField) {
        aggregation.avg = proto.StructuredAggregationQuery_Aggregation_Avg()
          ..field_1 = reference;
      } else {
        throw ArgumentError('Unsupported aggregation: $field');
      }
      result.aggregations.add(aggregation);
    }
    return result;
  }

  /// Decodes the result of an aggregation, mapping the server aliases back to
  /// the client-side aliases using [aliasMap].
  Map<String, FieldValue> decodeAggregationResult(
    Map<String, proto_v1.Value> aggregateFields,
    Map<String, String> aliasMap,
  ) {
    final Map<String, FieldValue> result = <String, FieldValue>{};
    for (final MapEntry<String, proto_v1.Value> entry
        in aggregateFields.entries) {
      final String? clientAlias = aliasMap[entry.key];
      hardAssert(clientAlias != null, '${entry.key} not present in aliasMap');
      result[clientAlias!] = decodeValue(entry.value);
    }
    return result;
  }
}
