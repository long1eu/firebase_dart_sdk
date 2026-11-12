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

part of 'datastore.dart';

/// Runs aggregation queries (`RunAggregationQuery`).
extension DatastoreAggregation on Datastore {
  /// Runs [aggregateFields] over the documents matching [query] on the server.
  ///
  /// The result is keyed by the client-side alias of each field.
  Future<Map<String, FieldValue>> runAggregateQuery(
      Query query, List<AggregateField> aggregateFields) async {
    final proto.Target_QueryTarget target =
        _serializer.encodeAggregateQueryTarget(query);
    final Map<String, String> aliasMap = <String, String>{};
    final proto.StructuredAggregationQuery aggregationQuery = _serializer
        .encodeStructuredAggregationQuery(target, aggregateFields, aliasMap);

    final proto.RunAggregationQueryRequest request =
        proto.RunAggregationQueryRequest()
          ..parent = target.parent
          ..structuredAggregationQuery = aggregationQuery;

    final ResponseStream<proto.RunAggregationQueryResponse> call =
        _client.runAggregationQuery(request);
    final proto.RunAggregationQueryResponse response;
    try {
      response = await call.first;
    } on StateError {
      throw FirestoreError(
          'No responses received', FirestoreErrorCode.unimplemented);
    } finally {
      // The first response carries the whole result.
      call.cancel().ignore();
    }

    return _serializer.decodeAggregationResult(
        response.result.aggregateFields, aliasMap);
  }
}
