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

part of 'datastore.dart';

/// Runs vector (nearest-neighbour) queries (`RunQuery` with `find_nearest`).
extension DatastoreVectorQuery on Datastore {
  /// Runs [vectorQuery] over [query] on the server and returns the documents
  /// in the order the server produced them (nearest first).
  Future<List<Document>> runVectorQuery(
    Query query,
    VectorQuery vectorQuery,
  ) async {
    final proto.Target_QueryTarget target = _serializer.encodeVectorQueryTarget(
      query,
      vectorQuery,
    );
    final proto.RunQueryRequest request = proto.RunQueryRequest()
      ..parent = target.parent
      ..structuredQuery = target.structuredQuery;

    final ResponseStream<proto.RunQueryResponse> call = _client.runQuery(
      request,
    );
    final List<Document> result = <Document>[];
    // Read to the end; a response that fails to decode does not reset the call, see [CallReleaser].
    await _client.callReleaser.forEach(call, call.cancel, (
      proto.RunQueryResponse response,
    ) {
      if (response.hasDocument()) {
        result.add(_serializer.decodeVectorQueryDocument(response.document));
      }
    });
    return result;
  }
}
