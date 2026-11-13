// File created by
// Lung Razvan <long1eu>
// on 02/12/2019

part of 'datastore.dart';

/// Helper class that wraps the gRPC calls and invalidates the auth token when a unary call fails with
/// [StatusCode.unauthenticated]. The listen and write streams invalidate it themselves, only while they are not
/// healthy (see [BaseStream]), as upstream does.
class FirestoreClient {
  @visibleForTesting
  FirestoreClient(
    FirestoreTransport transport,
    this._optionsProvider, {
    CallReleaser? callReleaser,
  }) : _transport = transport,
       callReleaser = callReleaser ?? CallReleaser();

  /// Lets go of the calls this client is done with, see [CallReleaser].
  final CallReleaser callReleaser;

  final ChannelOptionsProvider _optionsProvider;
  final FirestoreTransport _transport;
  bool _terminated = false;

  /// Fails a request made after [shutdown], like `DatastoreImpl.verifyInitialized()` of the JS SDK.
  void _verifyNotTerminated() {
    if (_terminated) {
      throw FirestoreError(
        'The client has already been terminated.',
        FirestoreErrorCode.failedPrecondition,
      );
    }
  }

  /// Gets multiple documents.
  ///
  /// Documents returned by this method are not guaranteed to be returned in the
  /// same order that they were requested.
  ResponseStream<proto.BatchGetDocumentsResponse> batchGetDocuments(
    proto.BatchGetDocumentsRequest request, {
    CallOptions? options,
  }) {
    _verifyNotTerminated();
    final ResponseStream<proto.BatchGetDocumentsResponse> call = _transport
        .startCall(
          FirestoreRpc.batchGetDocuments,
          Stream<proto.BatchGetDocumentsRequest>.value(request),
          options: options,
        );
    return ResponseStream<proto.BatchGetDocumentsResponse>(
      call,
      _buildStream(call),
    );
  }

  /// Runs a query. The server streams the matching documents back.
  ResponseStream<proto.RunQueryResponse> runQuery(
    proto.RunQueryRequest request, {
    CallOptions? options,
  }) {
    _verifyNotTerminated();
    final ResponseStream<proto.RunQueryResponse> call = _transport.startCall(
      FirestoreRpc.runQuery,
      Stream<proto.RunQueryRequest>.value(request),
      options: options,
    );
    return ResponseStream<proto.RunQueryResponse>(call, _buildStream(call));
  }

  /// Runs an aggregation query. The server streams the result back.
  ResponseStream<proto.RunAggregationQueryResponse> runAggregationQuery(
    proto.RunAggregationQueryRequest request, {
    CallOptions? options,
  }) {
    _verifyNotTerminated();
    final ResponseStream<proto.RunAggregationQueryResponse> call = _transport
        .startCall(
          FirestoreRpc.runAggregationQuery,
          Stream<proto.RunAggregationQueryRequest>.value(request),
          options: options,
        );
    return ResponseStream<proto.RunAggregationQueryResponse>(
      call,
      _buildStream(call),
    );
  }

  /// Executes a pipeline query. The server streams the results back.
  ResponseStream<proto.ExecutePipelineResponse> executePipeline(
    proto.ExecutePipelineRequest request, {
    CallOptions? options,
  }) {
    _verifyNotTerminated();
    final ResponseStream<proto.ExecutePipelineResponse> call = _transport
        .startCall(
          FirestoreRpc.executePipeline,
          Stream<proto.ExecutePipelineRequest>.value(request),
          options: options,
        );
    return ResponseStream<proto.ExecutePipelineResponse>(
      call,
      _buildStream(call),
    );
  }

  /// Starts a transaction on the backend.
  ResponseFuture<proto.BeginTransactionResponse> beginTransaction(
    proto.BeginTransactionRequest request, {
    CallOptions? options,
  }) {
    _verifyNotTerminated();
    final ResponseStream<proto.BeginTransactionResponse> call = _transport
        .startCall(
          FirestoreRpc.beginTransaction,
          Stream<proto.BeginTransactionRequest>.value(request),
          options: options,
        );
    return _buildFuture<proto.BeginTransactionResponse>(call);
  }

  /// Rolls a transaction back, which releases it on the backend.
  ResponseFuture<Empty> rollback(
    proto.RollbackRequest request, {
    CallOptions? options,
  }) {
    _verifyNotTerminated();
    final ResponseStream<Empty> call = _transport.startCall(
      FirestoreRpc.rollback,
      Stream<proto.RollbackRequest>.value(request),
      options: options,
    );
    return _buildFuture<Empty>(call);
  }

  /// Commits a transaction, while optionally updating documents.
  ResponseFuture<proto.CommitResponse> commit(
    proto.CommitRequest request, {
    CallOptions? options,
  }) {
    _verifyNotTerminated();
    final ResponseStream<proto.CommitResponse> call = _transport.startCall(
      FirestoreRpc.commit,
      Stream<proto.CommitRequest>.value(request),
      options: options,
    );
    return _buildFuture<proto.CommitResponse>(call);
  }

  /// Listens to changes.
  ///
  /// The call is returned right away without waiting for the channel to be
  /// ready: gRPC buffers the requests until it is connected, and a failed
  /// connection is reported as an error on the response stream (which lets the
  /// stream back off and the online state tracker count the failure).
  Future<ResponseStream<proto.ListenResponse>> listen(
    Stream<proto.ListenRequest> request,
  ) async {
    final ResponseStream<proto.ListenResponse> call = _transport.startCall(
      FirestoreRpc.listen,
      request,
    );
    return ResponseStream<proto.ListenResponse>(
      call,
      _buildStream(call, invalidateToken: false),
    );
  }

  /// Streams batches of document updates and deletes, in order.
  Future<ResponseStream<proto.WriteResponse>> write(
    Stream<proto.WriteRequest> request,
  ) async {
    final ResponseStream<proto.WriteResponse> call = _transport.startCall(
      FirestoreRpc.write,
      request,
    );
    return ResponseStream<proto.WriteResponse>(
      call,
      _buildStream(call, invalidateToken: false),
    );
  }

  /// Terminates this connection.
  ///
  /// All open calls are terminated immediately, and no further calls may be made on this connection.
  Future<void> shutdown() {
    _terminated = true;
    callReleaser.cancelAll();
    return _transport.shutdown();
  }

  /// Invalidates the token of the credentials and App Check providers, so that
  /// the next call gets a fresh one.
  void invalidateToken() => _optionsProvider.invalidateToken();

  Stream<R> _buildStream<R>(Stream<R> response, {bool invalidateToken = true}) {
    return response
        .transform(
          DoStreamTransformer<R>(
            onError: (Object error, StackTrace stackTrace) {
              if (invalidateToken &&
                  error is GrpcError &&
                  error.code == StatusCode.unauthenticated) {
                Log.d(
                  'FirestoreClient',
                  'Received status ${error.code}. Invalidating the token.',
                );
                _optionsProvider.invalidateToken();
              }
            },
          ),
        )
        // TODO(long1eu): OnErrorResumeStreamTransformer doesn't provide the stacktrace
        .transform(
          OnErrorResumeStreamTransformer<R>(
            (dynamic error, [StackTrace? stackTrace]) => Stream<R>.error(
              error is GrpcError
                  ? FirestoreError(
                      error.message ?? '',
                      FirestoreErrorCode.fromValue(error),
                    )
                  : FirestoreError(
                      error.toString(),
                      FirestoreErrorCode.unknown,
                    ),
              stackTrace,
            ),
          ),
        );
  }

  ResponseFuture<R> _buildFuture<R>(ResponseStream<R> call) {
    final Future<R> future =
        _buildStream(call) //
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
