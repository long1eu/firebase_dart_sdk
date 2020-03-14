// File created by
// Lung Razvan <long1eu>
// on 02/12/2019

part of datastore;

class WriteStream extends BaseStream<proto.WriteRequest, proto.WriteResponse> {
  factory WriteStream({
    @required FirestoreClient client,
    @required TaskScheduler scheduler,
    @required RemoteSerializer serializer,
  }) {
    // ignore: close_sinks
    final StreamController<StreamEvent> controller =
        StreamController<StreamEvent>.broadcast();
    return WriteStream.test(client, scheduler, serializer, controller);
  }

  @visibleForTesting
  WriteStream.test(
    FirestoreClient client,
    TaskScheduler scheduler,
    RemoteSerializer serializer,
    StreamController<StreamEvent> eventsController,
  )   : assert(client != null),
        assert(serializer != null),
        _client = client,
        _serializer = serializer,
        super(
          eventsController,
          scheduler,
          TaskId.writeStreamIdle,
          TaskId.writeStreamConnectionBackoff,
        );

  final FirestoreClient _client;
  final RemoteSerializer _serializer;

  /// Last received stream token from the server.
  ///
  /// Used to acknowledge which responses the client has processed. Stream
  /// tokens are opaque checkpoint markers whose only real value is their
  /// inclusion in the next request. [BaseStream] implementations manage
  /// propagating of this value from responses to the next request.
  ///
  /// NOTE: A null streamToken is not allowed: use the empty array for the unset
  /// value.
  Uint8List lastStreamToken = emptyStreamToken;

  /// Tracks whether or not a handshake has been successfully exchanged and the
  /// stream is ready to accept mutations.
  bool handshakeComplete = false;

  @override
  Future<ResponseStream<proto.WriteResponse>> _buildCall(
      Stream<proto.WriteRequest> requests) {
    return _client.write(requests);
  }

  @override
  Future<void> start() {
    handshakeComplete = false;
    return super.start();
  }

  @override
  void _onData(proto.WriteResponse response) {
    super._onData(response);
    if (_state != State.closing) {
      lastStreamToken = Uint8List.fromList(response.streamToken);

      if (!handshakeComplete) {
        // The first response is the handshake response
        handshakeComplete = true;

        addEvent(const HandshakeCompleteEvent());
      } else {
        // A successful first write response means the stream is healthy.
        //
        // Note, that we could consider a successful handshake healthy, however,
        // the write itself might be causing an error we want to back off from.
        _backoff.reset();

        final SnapshotVersion commitVersion =
            _serializer.decodeVersion(response.commitTime);
        final List<MutationResult> results = response.writeResults
            .map((proto.WriteResult proto) =>
                _serializer.decodeMutationResult(proto, commitVersion))
            .toList();

        addEvent(OnWriteResponse(commitVersion, results));
      }
    }
  }

  @override
  void tearDown() {
    if (handshakeComplete) {
      // Send an empty write request to the backend to indicate imminent stream
      // closure. This allows the backend to clean up resources.
      writeMutations(<Mutation>[]);
    }
  }

  /// Sends an initial streamToken to the server, performing the handshake
  /// required. Subsequent [writeMutations] calls should wait until
  /// [HandshakeCompleteEvent] is emitted.
  void writeHandshake() {
    assert(isOpen, 'Writing handshake requires an opened stream');
    assert(!handshakeComplete, 'Handshake already completed');

    // TODO(long1eu): Support stream resumption. We intentionally do not set the
    //  stream token on the handshake, ignoring any stream token we might have.
    writeRequest(proto.WriteRequest()..database = _serializer.databaseName);
  }

  /// Sends a list of mutations to the Firestore backend to apply
  void writeMutations(List<Mutation> mutations) {
    assert(isOpen, 'Writing mutations requires an opened stream');
    assert(handshakeComplete,
        'Handshake must be complete before writing mutations');

    final proto.WriteRequest request = proto.WriteRequest.create()
      ..streamToken = lastStreamToken
      ..writes.addAll(mutations.map(_serializer.encodeMutation))
      ..freeze();
    writeRequest(request);
  }

  /// The empty stream token.
  static final Uint8List emptyStreamToken = Uint8List.fromList(<int>[0]);
}

class HandshakeCompleteEvent extends StreamEvent {
  const HandshakeCompleteEvent();
}

class OnWriteResponse extends StreamEvent {
  const OnWriteResponse(this.version, this.results);

  final SnapshotVersion version;
  final List<MutationResult> results;
}
