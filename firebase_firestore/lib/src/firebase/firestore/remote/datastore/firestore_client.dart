// File created by
// Lung Razvan <long1eu>
// on 02/12/2019

part of datastore;

/// Helper class that wraps the gRPC calls and invalidates the auth token when [StatusCode.unauthenticated] is received
/// for both the [Future]s and the [Stream]s.
class FirestoreClient extends Client {
  @visibleForTesting
  FirestoreClient(ClientChannel channel, this._optionsProvider)
      : assert(channel != null),
        assert(_optionsProvider != null),
        _channel = channel,
        _state = BehaviorSubject<ConnectionState>(),
        super(channel, options: _optionsProvider.callOptions);

  final BehaviorSubject<ConnectionState> _state;
  final ChannelOptionsProvider _optionsProvider;
  final ClientChannel _channel;

  void onStateChanged(ConnectionState state) {
    Log.d('FirestoreClient', state.toString());
    _state.add(state);
  }

  /// Gets multiple documents.
  ///
  /// Documents returned by this method are not guaranteed to be returned in the same order that they were requested.
  ResponseStream<proto.BatchGetDocumentsResponse> batchGetDocuments(proto.BatchGetDocumentsRequest request,
      {CallOptions options}) {
    final ClientCall<proto.BatchGetDocumentsRequest, proto.BatchGetDocumentsResponse> call =
        $createCall(_batchGetDocuments, Stream<proto.BatchGetDocumentsRequest>.value(request), options: options);
    return ResponseStream<proto.BatchGetDocumentsResponse>(call, _buildStream(call));
  }

  /// Commits a transaction, while optionally updating documents.
  ResponseFuture<proto.CommitResponse> commit(proto.CommitRequest request, {CallOptions options}) {
    final ClientCall<proto.CommitRequest, proto.CommitResponse> call =
        $createCall(_commit, Stream<proto.CommitRequest>.value(request), options: options);
    return _buildFuture<proto.CommitResponse>(call);
  }

  /// Listens to changes.
  Future<ResponseStream<proto.ListenResponse>> listen(Stream<proto.ListenRequest> request) async {
    final ClientCall<proto.ListenRequest, proto.ListenResponse> call = $createCall(_listen, request);

    if (_state.value == ConnectionState.ready) {
      return ResponseStream<proto.ListenResponse>(call, _buildStream(call));
    } else {
      return _state
          .where((ConnectionState state) => state == ConnectionState.ready)
          .mapTo(ResponseStream<proto.ListenResponse>(call, _buildStream(call)))
          .first;
    }
  }

  /// Streams batches of document updates and deletes, in order.
  Future<ResponseStream<proto.WriteResponse>> write(Stream<proto.WriteRequest> request) async {
    final ClientCall<proto.WriteRequest, proto.WriteResponse> call = $createCall(_write, request);

    if (_state.value == ConnectionState.ready) {
      return ResponseStream<proto.WriteResponse>(call, _buildStream(call));
    } else {
      return _state
          .where((ConnectionState state) => state == ConnectionState.ready)
          .mapTo(ResponseStream<proto.WriteResponse>(call, _buildStream(call)))
          .first;
    }
  }

  /// Terminates this connection.
  ///
  /// All open calls are terminated immediately, and no further calls may be made on this connection.
  Future<void> shutdown() => _channel.terminate();

  Stream<R> _buildStream<R>(ClientCall<dynamic, R> call) {
    return call.response.transform(DoStreamTransformer<R>(
      onError: (dynamic error, [StackTrace stackTrace]) {
        if (error is GrpcError && error.code == StatusCode.unauthenticated) {
          Log.d('FirestoreClient', 'Received status ${error.code}. Invalidating the token.');
          _optionsProvider.invalidateToken();
        }
      },
    ))
        // TODO(long1eu): OnErrorResumeStreamTransformer doesn't provide the stacktrace
        .transform(OnErrorResumeStreamTransformer<R>((dynamic error, [StackTrace stackTrace]) => Stream<R>.error(
            error is GrpcError
                ? FirebaseFirestoreError(error.message, FirebaseFirestoreErrorCode.values[error.code])
                : FirebaseFirestoreError(error.toString(), FirebaseFirestoreErrorCode.unknown),
            stackTrace)));
  }

  Future<R> _buildFuture<R>(ClientCall<dynamic, R> call) {
    final Future<R> future = _buildStream(call) //
        .fold(null, _ensureOnlyOneResponse)
        .then(_ensureOneResponse);

    return ResponseFuture<R>(call, future);
  }

  static R _ensureOnlyOneResponse<R>(R previous, R element) {
    if (previous != null) {
      throw GrpcError.unimplemented('More than one response received');
    }
    return element;
  }

  static R _ensureOneResponse<R>(R value) {
    if (value == null) {
      throw GrpcError.unimplemented('No responses received');
    }
    return value;
  }

  static final ClientMethod<proto.BatchGetDocumentsRequest, proto.BatchGetDocumentsResponse> _batchGetDocuments =
      ClientMethod<proto.BatchGetDocumentsRequest, proto.BatchGetDocumentsResponse>(
    '/google.firestore.v1.Firestore/BatchGetDocuments',
    (proto.BatchGetDocumentsRequest value) => value.writeToBuffer(),
    (List<int> value) => proto.BatchGetDocumentsResponse.fromBuffer(value),
  );

  static final ClientMethod<proto.CommitRequest, proto.CommitResponse> _commit =
      ClientMethod<proto.CommitRequest, proto.CommitResponse>(
    '/google.firestore.v1.Firestore/Commit',
    (proto.CommitRequest value) => value.writeToBuffer(),
    (List<int> value) => proto.CommitResponse.fromBuffer(value),
  );

  static final ClientMethod<proto.ListenRequest, proto.ListenResponse> _listen =
      ClientMethod<proto.ListenRequest, proto.ListenResponse>(
    '/google.firestore.v1.Firestore/Listen',
    (proto.ListenRequest value) => value.writeToBuffer(),
    (List<int> value) => proto.ListenResponse.fromBuffer(value),
  );

  static final ClientMethod<proto.WriteRequest, proto.WriteResponse> _write =
      ClientMethod<proto.WriteRequest, proto.WriteResponse>(
    '/google.firestore.v1.Firestore/Write',
    (proto.WriteRequest value) => value.writeToBuffer(),
    (List<int> value) => proto.WriteResponse.fromBuffer(value),
  );
}

/// A gRPC response producing a stream of values.
class ResponseStream<R> extends DelegatingStream<R> with _ResponseMixin<dynamic, R> {
  ResponseStream(this._call, Stream<R> response) : super(response);

  @override
  final ClientCall<dynamic, R> _call;

  @override
  Future<Map<String, String>> get headers => _call.headers;

  @override
  Future<Map<String, String>> get trailers => _call.trailers;

  @override
  Future<void> cancel() => _call.cancel();
}

/// A gRPC response producing a single value.
class ResponseFuture<R> extends DelegatingFuture<R> with _ResponseMixin<dynamic, R> {
  ResponseFuture(this._call, Future<R> future) : super(future);

  @override
  final ClientCall<dynamic, R> _call;
}

mixin _ResponseMixin<Q, R> implements Response {
  ClientCall<Q, R> get _call;

  @override
  Future<Map<String, String>> get headers => _call.headers;

  @override
  Future<Map<String, String>> get trailers => _call.trailers;

  @override
  Future<void> cancel() => _call.cancel();
}
