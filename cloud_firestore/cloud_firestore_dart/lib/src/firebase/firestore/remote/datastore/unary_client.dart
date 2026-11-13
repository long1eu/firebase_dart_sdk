// Copyright 2026 Google LLC
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

/// Creates a [Datastore] over [transport], for clients that only make unary
/// calls (Firestore Lite).
///
/// Unlike the [Datastore] factory this does not refer to the transport of the
/// platform, so that a caller that brings a smaller transport (REST without
/// WebChannel on the web) does not keep the full one in its program.
Datastore newUnaryDatastore(
  TaskScheduler scheduler,
  DatabaseInfo databaseInfo,
  CredentialsProvider credentialsProvider,
  FirestoreTransport Function(DatabaseInfo, ChannelOptionsProvider)
  createTransport, {
  AppCheckTokenProvider? appCheckProvider,
}) {
  final ChannelOptionsProvider optionsProvider = ChannelOptionsProvider(
    databaseId: databaseInfo.databaseId,
    credentialsProvider: credentialsProvider,
    appCheckProvider: appCheckProvider,
  );
  return Datastore.test(
    scheduler,
    databaseInfo,
    RemoteSerializer(databaseInfo.databaseId),
    FirestoreClient(
      createTransport(databaseInfo, optionsProvider),
      optionsProvider,
    ),
  );
}

/// Runs queries with one request and one response (`RunQuery`), without a
/// listen target.
extension DatastoreQuery on Datastore {
  /// Runs [query] on the server and returns the documents in the order the
  /// server produced them.
  ///
  /// The query is sent as its [Query.toTarget]: for a limit-to-last query that
  /// is the flipped query, and the caller reverses the result.
  Future<List<Document>> runQuery(Query query) async {
    final proto.Target_QueryTarget target = _serializer.encodeQueryTarget(
      query.toTarget(),
    );
    final proto.RunQueryRequest request = proto.RunQueryRequest()
      ..parent = target.parent
      ..structuredQuery = target.structuredQuery;

    final ResponseStream<proto.RunQueryResponse> call = _client.runQuery(
      request,
    );
    final List<Document> result = <Document>[];
    await for (final proto.RunQueryResponse response in call) {
      // Responses without a document only report progress (the read time).
      if (response.hasDocument()) {
        result.add(_serializer.decodeVectorQueryDocument(response.document));
      }
    }
    return result;
  }
}
