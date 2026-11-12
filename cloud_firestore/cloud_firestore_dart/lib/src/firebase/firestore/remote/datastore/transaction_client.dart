// File created by
// Lung Razvan <long1eu>
// on 01/12/2019

part of 'datastore.dart';

/// Wrapper class for transaction specific gRPC methods
class TransactionClient {
  const TransactionClient(this._client, this._serializer);

  final FirestoreClient _client;
  final RemoteSerializer _serializer;

  String get _databaseName => _serializer.databaseName;

  Future<List<MutationResult>> commit(List<Mutation> mutations) async {
    final proto.CommitRequest builder =
        proto.CommitRequest() //
          ..database = _databaseName
          ..writes.addAll(mutations.map(_serializer.encodeMutation));

    final proto.CommitResponse response = await _client.commit(builder);
    final SnapshotVersion commitVersion = _serializer.decodeVersion(
      response.commitTime,
    );
    return response.writeResults
        .map(
          (proto.WriteResult result) =>
              _serializer.decodeMutationResult(result, commitVersion),
        )
        .toList();
  }

  Future<List<MaybeDocument>> lookup(List<DocumentKey> keys) async {
    final proto.BatchGetDocumentsRequest builder =
        proto.BatchGetDocumentsRequest() //
          ..database = _databaseName
          ..documents.addAll(keys.map(_serializer.encodeKey));

    // The backend may keep the stream open after it has sent a response for
    // every requested document ("logical termination"), so complete as soon as
    // all the documents arrived instead of waiting for the stream to close.
    final Completer<List<MaybeDocument>> completer =
        Completer<List<MaybeDocument>>();
    final Map<DocumentKey, MaybeDocument> documents =
        <DocumentKey, MaybeDocument>{};
    // The backend answers once per distinct document, even if a key is repeated.
    final int expectedCount = keys.toSet().length;
    final ResponseStream<proto.BatchGetDocumentsResponse> call = _client
        .batchGetDocuments(builder);
    late final StreamSubscription<proto.BatchGetDocumentsResponse> subscription;

    // The call is not cancelled once the last document arrived, see [CallReleaser].
    void finish() => _client.callReleaser.release(subscription, call.cancel);

    subscription = call.listen(
      (proto.BatchGetDocumentsResponse response) {
        if (completer.isCompleted) {
          return;
        }
        final MaybeDocument doc = _serializer.decodeMaybeDocument(response);
        documents[doc.key] = doc;
        if (documents.length == expectedCount) {
          completer.complete(<MaybeDocument>[
            for (DocumentKey key in keys)
              if (documents.containsKey(key)) documents[key]!,
          ]);
          finish();
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
      onDone: () {
        if (!completer.isCompleted) {
          // The server closed the stream early: report what was received (in
          // key order) instead of an empty result.
          completer.complete(<MaybeDocument>[
            for (DocumentKey key in keys)
              if (documents.containsKey(key)) documents[key]!,
          ]);
        }
      },
      cancelOnError: true,
    );
    return completer.future;
  }
}
