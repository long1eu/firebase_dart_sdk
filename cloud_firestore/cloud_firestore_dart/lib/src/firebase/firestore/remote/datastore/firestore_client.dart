// File created by
// Lung Razvan <long1eu>
// on 02/12/2019

part of datastore;

/// Helper class that wraps the gRPC calls and invalidates the auth token when [StatusCode.unauthenticated] is received
/// for both the [Future]s and the [Stream]s.
class FirestoreClient {
  @visibleForTesting
  FirestoreClient(FirestoreTransport transport, this._optionsProvider)
      : _transport = transport;

  final ChannelOptionsProvider _optionsProvider;
  final FirestoreTransport _transport;

  /// Gets multiple documents.
  ///
  /// Documents returned by this method are not guaranteed to be returned in the
  /// same order that they were requested.
  ResponseStream<proto.BatchGetDocumentsResponse> batchGetDocuments(
    proto.BatchGetDocumentsRequest request, {
    CallOptions? options,
  }) {
    final ResponseStream<proto.BatchGetDocumentsResponse> call =
        _transport.startCall(FirestoreRpc.batchGetDocuments,
            Stream<proto.BatchGetDocumentsRequest>.value(request),
            options: options);
    return ResponseStream<proto.BatchGetDocumentsResponse>(
        call, _buildStream(call));
  }

  /// Runs a query. The server streams the matching documents back.
  ResponseStream<proto.RunQueryResponse> runQuery(
    proto.RunQueryRequest request, {
    CallOptions? options,
  }) {
    final ResponseStream<proto.RunQueryResponse> call = _transport.startCall(
        FirestoreRpc.runQuery, Stream<proto.RunQueryRequest>.value(request),
        options: options);
    return ResponseStream<proto.RunQueryResponse>(call, _buildStream(call));
  }

  /// Runs an aggregation query. The server streams the result back.
  ResponseStream<proto.RunAggregationQueryResponse> runAggregationQuery(
    proto.RunAggregationQueryRequest request, {
    CallOptions? options,
  }) {
    final ResponseStream<proto.RunAggregationQueryResponse> call =
        _transport.startCall(FirestoreRpc.runAggregationQuery,
            Stream<proto.RunAggregationQueryRequest>.value(request),
            options: options);
    return ResponseStream<proto.RunAggregationQueryResponse>(
        call, _buildStream(call));
  }

  /// Commits a transaction, while optionally updating documents.
  ResponseFuture<proto.CommitResponse> commit(proto.CommitRequest request,
      {CallOptions? options}) {
    final ResponseStream<proto.CommitResponse> call = _transport.startCall(
        FirestoreRpc.commit, Stream<proto.CommitRequest>.value(request),
        options: options);
    return _buildFuture<proto.CommitResponse>(call);
  }

  /// Listens to changes.
  ///
  /// The call is returned right away without waiting for the channel to be
  /// ready: gRPC buffers the requests until it is connected, and a failed
  /// connection is reported as an error on the response stream (which lets the
  /// stream back off and the online state tracker count the failure).
  Future<ResponseStream<proto.ListenResponse>> listen(
      Stream<proto.ListenRequest> request) async {
    final ResponseStream<proto.ListenResponse> call =
        _transport.startCall(FirestoreRpc.listen, request);
    return ResponseStream<proto.ListenResponse>(call, _buildStream(call));
  }

  /// Streams batches of document updates and deletes, in order.
  Future<ResponseStream<proto.WriteResponse>> write(
      Stream<proto.WriteRequest> request) async {
    final ResponseStream<proto.WriteResponse> call =
        _transport.startCall(FirestoreRpc.write, request);
    return ResponseStream<proto.WriteResponse>(call, _buildStream(call));
  }

  /// Terminates this connection.
  ///
  /// All open calls are terminated immediately, and no further calls may be made on this connection.
  Future<void> shutdown() => _transport.shutdown();

  Stream<R> _buildStream<R>(Stream<R> response) {
    return response.transform(DoStreamTransformer<R>(
      onError: (Object error, StackTrace stackTrace) {
        if (error is GrpcError && error.code == StatusCode.unauthenticated) {
          Log.d('FirestoreClient',
              'Received status ${error.code}. Invalidating the token.');
          _optionsProvider.invalidateToken();
        }
      },
    ))
        // TODO(long1eu): OnErrorResumeStreamTransformer doesn't provide the stacktrace
        .transform(OnErrorResumeStreamTransformer<R>(
            (dynamic error, [StackTrace? stackTrace]) => Stream<R>.error(
                error is GrpcError
                    ? FirestoreError(error.message ?? '',
                        FirestoreErrorCode.fromValue(error))
                    : FirestoreError(
                        error.toString(), FirestoreErrorCode.unknown),
                stackTrace)));
  }

  ResponseFuture<R> _buildFuture<R>(ResponseStream<R> call) {
    final Future<R> future = _buildStream(call) //
        .fold<R?>(null, _ensureOnlyOneResponse)
        .then<R>(_ensureOneResponse);

    return ResponseFuture<R>(call, future);
  }

  static R _ensureOnlyOneResponse<R>(R? previous, R element) {
    if (previous != null) {
      throw const GrpcError.unimplemented('More than one response received');
    }
    return element;
  }

  static R _ensureOneResponse<R>(R? value) {
    if (value == null) {
      throw const GrpcError.unimplemented('No responses received');
    }
    return value;
  }
}
