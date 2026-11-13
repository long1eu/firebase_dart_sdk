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

  /// Starts a read-only transaction on the backend and returns its id. Its reads see the database as it was at one
  /// point in time: at [readTime] when given, otherwise at the time the transaction starts.
  Future<Uint8List> beginReadOnlyTransaction({
    SnapshotVersion? readTime,
  }) async {
    final proto.TransactionOptions_ReadOnly readOnly =
        proto.TransactionOptions_ReadOnly();
    if (readTime != null) {
      readOnly.readTime = _serializer.encodeVersion(readTime);
    }
    final proto.BeginTransactionResponse response = await _client
        .beginTransaction(
          proto.BeginTransactionRequest()
            ..database = _databaseName
            ..options = (proto.TransactionOptions()..readOnly = readOnly),
        );
    return Uint8List.fromList(response.transaction);
  }

  /// Releases the transaction with the id [transaction] on the backend.
  Future<void> rollback(Uint8List transaction) async {
    await _client.rollback(
      proto.RollbackRequest()
        ..database = _databaseName
        ..transaction = transaction,
    );
  }

  /// Runs [query] on the backend inside the transaction with the id [transaction] and returns the matching
  /// documents in the order the backend produced them.
  Future<List<Document>> runQuery(Query query, Uint8List transaction) async {
    final proto.Target_QueryTarget target = _serializer.encodeQueryTarget(
      query.toTarget(),
    );
    final proto.RunQueryRequest request = proto.RunQueryRequest()
      ..parent = target.parent
      ..structuredQuery = target.structuredQuery
      ..transaction = transaction;

    final List<Document> result = <Document>[];
    final ResponseStream<proto.RunQueryResponse> call = _client.runQuery(
      request,
    );
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

  /// Runs [aggregateFields] over the documents matching [query] on the backend, inside the transaction with the id
  /// [transaction]. The result is keyed by the client-side alias of each field.
  Future<Map<String, FieldValue>> runAggregateQuery(
    Query query,
    List<AggregateField> aggregateFields,
    Uint8List transaction,
  ) async {
    final proto.Target_QueryTarget target = _serializer
        .encodeAggregateQueryTarget(query);
    final Map<String, String> aliasMap = <String, String>{};
    final proto.RunAggregationQueryRequest request =
        proto.RunAggregationQueryRequest()
          ..parent = target.parent
          ..structuredAggregationQuery = _serializer
              .encodeStructuredAggregationQuery(
                target,
                aggregateFields,
                aliasMap,
              )
          ..transaction = transaction;

    final ResponseStream<proto.RunAggregationQueryResponse> call = _client
        .runAggregationQuery(request);
    final proto.RunAggregationQueryResponse response;
    try {
      // The first response carries the whole result; the call is not cancelled, see [CallReleaser].
      response = await _client.callReleaser.first(call, call.cancel);
    } on StateError {
      throw FirestoreError(
        'No responses received',
        FirestoreErrorCode.unimplemented,
      );
    }
    return _serializer.decodeAggregationResult(
      response.result.aggregateFields,
      aliasMap,
    );
  }

  /// Executes the pipeline of [request] on the backend inside the transaction with the id [transaction] and collects
  /// every response of the stream.
  Future<List<proto.ExecutePipelineResponse>> executePipeline(
    proto.ExecutePipelineRequest request,
    Uint8List transaction,
  ) {
    return _client.executePipeline(request..transaction = transaction).toList();
  }

  /// Reads the documents with the given [keys] from the backend. With [transaction] (the id of a read-only
  /// transaction) they are read as of the snapshot of that transaction.
  Future<List<MaybeDocument>> lookup(
    List<DocumentKey> keys, {
    Uint8List? transaction,
  }) async {
    final proto.BatchGetDocumentsRequest builder =
        proto.BatchGetDocumentsRequest() //
          ..database = _databaseName
          ..documents.addAll(keys.map(_serializer.encodeKey));
    if (transaction != null) {
      builder.transaction = transaction;
    }

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
