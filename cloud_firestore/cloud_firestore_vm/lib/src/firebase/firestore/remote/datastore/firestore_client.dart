// File created by
// Lung Razvan <long1eu>
// on 02/12/2019

part of datastore;

/// Helper class that wraps the gRPC calls and invalidates the auth token when [StatusCode.unauthenticated] is received
/// for both the [Future]s and the [Stream]s.
class FirestoreClient extends Client {
  @visibleForTesting
  FirestoreClient(ClientChannelBase channel, this._optionsProvider)
      : _channel = channel,
        _state = BehaviorSubject<ConnectionState>(),
        super(channel, options: _optionsProvider.callOptions);

  final BehaviorSubject<ConnectionState> _state;
  final ChannelOptionsProvider _optionsProvider;
  final ClientChannelBase _channel;

  void onStateChanged(ConnectionState state) {
    Log.d('FirestoreClient', state.toString());
    _state.add(state);
  }

  /// Gets multiple documents.
  ///
  /// Documents returned by this method are not guaranteed to be returned in the
  /// same order that they were requested.
  ResponseStream<proto.BatchGetDocumentsResponse> batchGetDocuments(
    proto.BatchGetDocumentsRequest request, {
    CallOptions? options,
  }) {
    final grpc.ResponseStream<proto.BatchGetDocumentsResponse> call =
        $createStreamingCall(_batchGetDocuments,
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
    final grpc.ResponseStream<proto.RunQueryResponse> call =
        $createStreamingCall(
            _runQuery, Stream<proto.RunQueryRequest>.value(request),
            options: options);
    return ResponseStream<proto.RunQueryResponse>(call, _buildStream(call));
  }

  /// Runs an aggregation query. The server streams the result back.
  ResponseStream<proto.RunAggregationQueryResponse> runAggregationQuery(
    proto.RunAggregationQueryRequest request, {
    CallOptions? options,
  }) {
    final grpc.ResponseStream<proto.RunAggregationQueryResponse> call =
        $createStreamingCall(_runAggregationQuery,
            Stream<proto.RunAggregationQueryRequest>.value(request),
            options: options);
    return ResponseStream<proto.RunAggregationQueryResponse>(
        call, _buildStream(call));
  }

  /// Commits a transaction, while optionally updating documents.
  ResponseFuture<proto.CommitResponse> commit(proto.CommitRequest request,
      {CallOptions? options}) {
    final grpc.ResponseStream<proto.CommitResponse> call = $createStreamingCall(
        _commit, Stream<proto.CommitRequest>.value(request),
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
    final grpc.ResponseStream<proto.ListenResponse> call =
        $createStreamingCall(_listen, request);
    return ResponseStream<proto.ListenResponse>(call, _buildStream(call));
  }

  /// Streams batches of document updates and deletes, in order.
  Future<ResponseStream<proto.WriteResponse>> write(
      Stream<proto.WriteRequest> request) async {
    final grpc.ResponseStream<proto.WriteResponse> call =
        $createStreamingCall(_write, request);
    return ResponseStream<proto.WriteResponse>(call, _buildStream(call));
  }

  /// Terminates this connection.
  ///
  /// All open calls are terminated immediately, and no further calls may be made on this connection.
  Future<void> shutdown() => _channel.terminate();

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

  ResponseFuture<R> _buildFuture<R>(grpc.ResponseStream<R> call) {
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

  static final ClientMethod<proto.BatchGetDocumentsRequest,
          proto.BatchGetDocumentsResponse> _batchGetDocuments =
      ClientMethod<proto.BatchGetDocumentsRequest,
          proto.BatchGetDocumentsResponse>(
    '/google.firestore.v1.Firestore/BatchGetDocuments',
    (proto.BatchGetDocumentsRequest value) => value.writeToBuffer(),
    proto.BatchGetDocumentsResponse.fromBuffer,
  );

  static final ClientMethod<proto.RunQueryRequest, proto.RunQueryResponse>
      _runQuery =
      ClientMethod<proto.RunQueryRequest, proto.RunQueryResponse>(
    '/google.firestore.v1.Firestore/RunQuery',
    (proto.RunQueryRequest value) => value.writeToBuffer(),
    proto.RunQueryResponse.fromBuffer,
  );

  static final ClientMethod<proto.RunAggregationQueryRequest,
          proto.RunAggregationQueryResponse> _runAggregationQuery =
      ClientMethod<proto.RunAggregationQueryRequest,
          proto.RunAggregationQueryResponse>(
    '/google.firestore.v1.Firestore/RunAggregationQuery',
    (proto.RunAggregationQueryRequest value) => value.writeToBuffer(),
    proto.RunAggregationQueryResponse.fromBuffer,
  );

  static final ClientMethod<proto.CommitRequest, proto.CommitResponse> _commit =
      ClientMethod<proto.CommitRequest, proto.CommitResponse>(
    '/google.firestore.v1.Firestore/Commit',
    (proto.CommitRequest value) => value.writeToBuffer(),
    proto.CommitResponse.fromBuffer,
  );

  static final ClientMethod<proto.ListenRequest, proto.ListenResponse> _listen =
      ClientMethod<proto.ListenRequest, proto.ListenResponse>(
    '/google.firestore.v1.Firestore/Listen',
    (proto.ListenRequest value) => value.writeToBuffer(),
    proto.ListenResponse.fromBuffer,
  );

  static final ClientMethod<proto.WriteRequest, proto.WriteResponse> _write =
      ClientMethod<proto.WriteRequest, proto.WriteResponse>(
    '/google.firestore.v1.Firestore/Write',
    (proto.WriteRequest value) => value.writeToBuffer(),
    proto.WriteResponse.fromBuffer,
  );
}

/// A gRPC response producing a stream of values.
class ResponseStream<R> extends DelegatingStream<R> implements Response {
  ResponseStream(this._response, Stream<R> response) : super(response);

  final Response _response;

  @override
  Future<Map<String, String>> get headers => _response.headers;

  @override
  Future<Map<String, String>> get trailers => _response.trailers;

  @override
  Future<void> cancel() => _response.cancel();
}

/// A gRPC response producing a single value.
class ResponseFuture<R> extends DelegatingFuture<R> implements Response {
  ResponseFuture(this._response, Future<R> future) : super(future);

  final Response _response;

  @override
  Future<Map<String, String>> get headers => _response.headers;

  @override
  Future<Map<String, String>> get trailers => _response.trailers;

  @override
  Future<void> cancel() => _response.cancel();
}
