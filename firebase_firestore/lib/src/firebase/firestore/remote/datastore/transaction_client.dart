// File created by
// Lung Razvan <long1eu>
// on 01/12/2019

part of datastore;

/// Wrapper class for transaction specific gRPC methods
class TransactionClient {
  const TransactionClient(this._client, this._serializer);

  final FirestoreClient _client;
  final RemoteSerializer _serializer;

  Future<List<MutationResult>> commit(List<Mutation> mutations) async {
    final proto.CommitRequest builder = proto.CommitRequest() //
      ..database = _databaseName
      ..writes.addAll(mutations.map(_serializer.encodeMutation));

    final proto.CommitResponse response = await _client.commit(builder);
    final SnapshotVersion commitVersion = _serializer.decodeVersion(response.commitTime);
    return response.writeResults
        .map((proto.WriteResult result) => _serializer.decodeMutationResult(result, commitVersion))
        .toList();
  }

  Future<List<MaybeDocument>> lookup(List<DocumentKey> keys) async {
    final proto.BatchGetDocumentsRequest builder = proto.BatchGetDocumentsRequest() //
      ..database = _databaseName
      ..documents.addAll(keys.map(_serializer.encodeKey));

    return _client
        .batchGetDocuments(builder)
        .map(_serializer.decodeMaybeDocument)
        .where((MaybeDocument doc) => keys.contains(doc.key))
        .toList();
  }

  String get _databaseName => _serializer.databaseName;
}
