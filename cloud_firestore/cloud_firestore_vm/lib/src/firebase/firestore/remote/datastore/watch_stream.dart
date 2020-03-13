// File created by
// Lung Razvan <long1eu>
// on 02/12/2019

part of datastore;

class WatchStream
    extends BaseStream<proto.ListenRequest, proto.ListenResponse> {
  factory WatchStream({
    @required FirestoreClient client,
    @required AsyncQueue workerQueue,
    @required RemoteSerializer serializer,
  }) {
    // ignore: close_sinks
    final StreamController<StreamEvent> controller =
        StreamController<StreamEvent>.broadcast();
    return WatchStream.test(client, serializer, controller, workerQueue);
  }

  @visibleForTesting
  WatchStream.test(
    FirestoreClient client,
    RemoteSerializer serializer,
    StreamController<StreamEvent> eventsController,
    AsyncQueue workerQueue,
  )   : assert(client != null),
        assert(serializer != null),
        _client = client,
        _serializer = serializer,
        super(eventsController, workerQueue, TimerId.listenStreamIdle,
            TimerId.listenStreamConnectionBackoff);

  final FirestoreClient _client;
  final RemoteSerializer _serializer;

  @override
  Future<ResponseStream<proto.ListenResponse>> _buildCall(
      Stream<proto.ListenRequest> requests) async {
    return _client.listen(requests);
  }

  /// Registers interest in the results of the given query.
  ///
  /// If the query includes a [resumeToken] it will be included in the request.
  /// Results that affect the query will be streamed back as [WatchChange]
  /// messages that reference the [targetId] included in query.
  void watchQuery(QueryData queryData) {
    hardAssert(isOpen, 'Watching queries requires an open stream');

    final proto.ListenRequest request = proto.ListenRequest.create()
      ..database = _serializer.databaseName
      ..addTarget = _serializer.encodeTarget(queryData)
      ..labels.addAll(_serializer.encodeListenRequestLabels(queryData));
    writeRequest(request);
  }

  /// Unregisters interest in the results of the query associated with the given
  /// target id.
  void unwatchTarget(int targetId) {
    hardAssert(isOpen, 'Unwatching targets requires an open stream');

    final proto.ListenRequest request = proto.ListenRequest.create()
      ..database = _serializer.databaseName
      ..removeTarget = targetId
      ..freeze();
    writeRequest(request);
  }

  @override
  void _onData(proto.ListenResponse response) {
    super._onData(response);
    // A successful response means the stream is healthy
    _backoff.reset();

    final WatchChange watchChange = _serializer.decodeWatchChange(response);
    final SnapshotVersion snapshotVersion =
        _serializer.decodeVersionFromListenResponse(response);

    addEvent(OnWatchChange(snapshotVersion, watchChange));
  }
}

class OnWatchChange extends StreamEvent {
  const OnWatchChange(this.snapshotVersion, this.watchChange);

  final SnapshotVersion snapshotVersion;
  final WatchChange watchChange;
}
