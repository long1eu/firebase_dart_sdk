// File created by
// Lung Razvan <long1eu>
// on 01/12/2019

part of 'datastore.dart';

abstract class BaseStream<Req extends GeneratedMessage,
    Res extends GeneratedMessage> extends DelegatingStream<StreamEvent> {
  BaseStream(
    StreamController<StreamEvent> eventsController,
    TaskScheduler scheduler,
    TaskId idleTaskId,
    TaskId connectionTaskId,
  )   : _backoff = ExponentialBackoff(scheduler, connectionTaskId),
        _eventsController = eventsController,
        _scheduler = scheduler,
        _idleTimerId = idleTaskId,
        super(eventsController.stream);

  final ExponentialBackoff _backoff;
  final StreamController<StreamEvent> _eventsController;
  final TaskScheduler _scheduler;
  final TaskId _idleTimerId;

  State _state = State.initial;
  TimerTask? _idleTimer;

  ResponseStream<Res>? _writeResponse;
  StreamSubscription<Res>? _responseSub;
  StreamController<Req>? _requestsController;

  /// Incremented whenever a call is opened or closed. A start() that finds a
  /// different value after an await knows its call is stale.
  int _generation = 0;

  /// Completes when the close in flight (if any) has finished tearing down.
  Future<void>? _closeFuture;

  bool get isStarted =>
      _state == State.starting ||
      _state == State.open ||
      _state == State.backoff;

  bool get isOpen => _state == State.open;

  @mustCallSuper
  Future<void> start() async {
    // A close that is still releasing its call must finish first, otherwise it
    // would reset the state of this new call.
    while (_closeFuture != null) {
      await _closeFuture;
    }

    assert(_requestsController == null, 'Last stream is still active');
    assert(_responseSub == null, 'Last subscription is still active');
    assert(_idleTimer == null, 'Idle timer still set');

    if (_state == State.error) {
      _performBackoff();
      return;
    }

    assert(_state == State.initial, 'Already started');
    _changeState(State.starting);
    final int generation = ++_generation;
    // Not a broadcast controller: gRPC only starts listening to the requests
    // once the connection is up, anything written before must be buffered.
    final StreamController<Req> requestsController = StreamController<Req>();
    _requestsController = requestsController;
    final ResponseStream<Res> writeResponse =
        await _buildCall(requestsController.stream);

    // The stream might have been stopped while the call was being built (for
    // example when the network was toggled). In that case the call is stale and
    // must not be opened, as its requests controller was already torn down.
    if (_generation != generation ||
        _state != State.starting ||
        _requestsController != requestsController) {
      await writeResponse.cancel();
      return;
    }
    _writeResponse = writeResponse;

    _responseSub = writeResponse.listen(_onData,
        onError: _onError, onDone: _onDone, cancelOnError: false);
    // A call that fails before the headers arrive completes this future with
    // the error. It is reported through the response stream instead.
    unawaited(writeResponse.headers.then(_onHeaders, onError: (Object _) {}));
    _changeState(State.open);
  }

  Future<void> stop() async {
    if (isStarted) {
      return _close(State.initial, const GrpcError.ok());
    }
  }

  void tearDown() {}

  void inhibitBackoff() {
    assert(!isStarted, 'Can inhibit backoff only after in a stopped state');
    _changeState(State.initial);
    _backoff.reset();
  }

  void writeRequest(Req request) {
    if (Log.isDebugEnabled) {
      Log.d('$runtimeType',
          '($hashCode) Stream sending: ${describeForLog(request)}');
    }
    _cancelIdleCheck();
    final StreamController<Req>? requestsController = _requestsController;
    if (requestsController == null) {
      // The stream was torn down in the meantime. The request will be sent
      // again when the stream restarts.
      Log.d('$runtimeType',
          '($hashCode) Dropping request, the stream is not active.');
      return;
    }
    requestsController.add(request);
  }

  /// Marks this stream as idle. If no further actions are performed on the
  /// stream for one minute, the stream will automatically close itself and
  /// emit a [CloseEvent] with [GrpcError.ok]. The stream will then be in a
  /// ![isStarted] state, requiring the caller to start the stream again before
  /// further use.
  ///
  /// Only streams that are in state [State.open] can be marked idle, as all
  /// other states imply pending network operations.
  void markIdle() {
    // Starts the idle timer if we are in state [State.open] and are not yet
    // already running a timer (in which case the previous idle timeout still
    // applies).
    if (isOpen && _idleTimer == null) {
      _idleTimer =
          _scheduler.add(_idleTimerId, idleTimeout, _handleIdleCloseTimer);
    }
  }

  /// Called when GRPC closes the stream, which should always be due to some error.
  @visibleForTesting
  Future<void> handleServerClose(GrpcError status) async {
    assert(isStarted, 'Can\'t handle server close on non-started stream!');

    // In theory the stream could close cleanly, however, in our current model we never expect this to happen because
    // if we stop a stream ourselves, this callback will never be called. To  prevent cases where we retry without a
    // backoff accidentally, we set the stream to error in  all cases.
    await _close(State.error, status);
  }

  @visibleForTesting
  void addEvent(StreamEvent event) {
    _eventsController.add(event);
  }

  Future<ResponseStream<Res>> _buildCall(Stream<Req> requests);

  @mustCallSuper
  void _onData(Res response) {
    if (_state != State.closing) {
      if (Log.isDebugEnabled) {
        Log.d('$runtimeType',
            '($hashCode) Stream received: ${describeForLog(response)}');
      }
    }
  }

  void _onHeaders(Map<String, String> headers) {
    if (Log.isDebugEnabled) {
      final Iterable<MapEntry<String, String>> entries = headers.entries.where(
          (MapEntry<String, String> entry) =>
              whiteListedHeaders.contains(entry.key.toLowerCase()));

      final Map<String, String> values =
          Map<String, String>.fromEntries(entries);
      if (values.isNotEmpty) {
        Log.d('$runtimeType', '($hashCode) Stream received headers: $values');
      }
    }
  }

  void _onError(Object error, StackTrace stackTrace) {
    if (_state != State.closing) {
      // FirestoreClient converts gRPC errors into FirestoreErrors, restore the
      // original status here so the stream can classify it.
      final Object err = error is FirestoreError
          ? GrpcError.custom(error.code.value, error.message)
          : error;
      if (err is GrpcError) {
        if (err.code == StatusCode.ok) {
          Log.d('$runtimeType', '($hashCode) Stream closed.');
        } else {
          Log.d('$runtimeType', '($hashCode) Stream closed with status: $err.');
        }

        handleServerClose(err);
      } else {
        Log.d('$runtimeType',
            '($hashCode) Stream closed with status: ${StatusCode.unknown} $error.');
        handleServerClose(GrpcError.unknown(error.toString()));
      }
    }
  }

  /// The response stream finished without an error event. Streams are only
  /// ever stopped by this class (which cancels the subscription first, so this
  /// callback is not reached), hence a clean finish is the server hanging up.
  /// Treat it as an error-state close so the stream backs off and restarts,
  /// like the Java client (whose onClose always calls handleServerClose).
  ///
  /// PORTING NOTE: the status is reported as UNAVAILABLE rather than OK so the
  /// stream owner does not mistake it for a requested stop (its OK path
  /// asserts that the stream is no longer needed).
  void _onDone() {
    if (_state == State.closing || !isOpen) {
      return;
    }
    Log.d('$runtimeType', '($hashCode) Stream closed by the server.');
    handleServerClose(
        const GrpcError.unavailable('Stream closed by the server'));
  }

  void _performBackoff() {
    assert(
        _state == State.error, 'Should only perform backoff in an error state');
    _changeState(State.backoff);
    _backoff.backoffAndRun(_restart);
  }

  Future<void> _restart() async {
    assert(_state == State.backoff,
        'State should still be backoff but was $_state');
    // Momentarily set state to Initial as start() expects it.
    _changeState(State.initial);
    await start();
    assert(isStarted, 'Stream should have started');
  }

  Future<void> _close(State state, GrpcError grpcError) async {
    assert(isStarted, 'Only started streams should be closed.');
    assert(state == State.error || grpcError.code == StatusCode.ok,
        'Can\'t provide an error when not in an error state.');

    if (state != State.error) {
      Log.d('$runtimeType', '($hashCode) Performing stream teardown');
      tearDown();
    }

    _changeState(State.closing);

    // Cancel any outstanding timers (they're guaranteed not to execute).
    _cancelIdleCheck();
    _backoff.cancel();

    final int code = grpcError.code;
    if (code == StatusCode.ok) {
      // If this is an intentional close ensure we don't delay our next
      // connection attempt.
      _backoff.reset();
    } else if (code == StatusCode.resourceExhausted) {
      Log.d('$runtimeType',
          '($hashCode) Using maximum backoff delay to prevent overloading the backend.');
      _backoff.resetToMax();
    } else if (code == StatusCode.unauthenticated) {
      // 'unauthenticated' error means the token was rejected. Force refreshing
      // was done by the FirestoreClient
      Log.d('$runtimeType',
          '($hashCode) Unauthenticated trying to refresh the token.');
    }

    if (grpcError.code == StatusCode.ok) {
      Log.d('$runtimeType', '($hashCode) Closing stream client-side');
    }

    // Detach the call synchronously: from here on a new call can be opened
    // (once this close completes) without this close touching its fields.
    final StreamController<Req>? requestsController = _requestsController;
    final StreamSubscription<Res>? responseSub = _responseSub;
    final ResponseStream<Res>? writeResponse = _writeResponse;
    _requestsController = null;
    _responseSub = null;
    _writeResponse = null;
    _generation++;

    final Completer<void> closing = Completer<void>();
    _closeFuture = closing.future;
    try {
      // these are null only when called from tests
      // Not awaited: the future of a buffering controller only completes once
      // gRPC consumed the requests, which never happens if it never connected.
      unawaited(requestsController?.close());
      await responseSub?.cancel();
      await writeResponse?.cancel();
    } finally {
      _closeFuture = null;
      closing.complete();
    }

    // This state must be assigned before emitting [CloseEvent] to allow the
    // callback to inhibit backoff or otherwise manipulate the state in its
    // non-started state.
    _changeState(state);

    // Notify the listener that the stream closed.
    addEvent(CloseEvent(grpcError));
  }

  void _cancelIdleCheck() {
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  /// Called by the idle timer when the stream should close due to inactivity.
  Future<void> _handleIdleCloseTimer() async {
    if (isOpen) {
      // When timing out an idle stream there's no reason to force the stream
      // into backoff when it restarts so set the stream state to initial
      // instead of error.
      return _close(State.initial, const GrpcError.ok());
    }
  }

  void _changeState(State state) {
    _state = state;
    if (state == State.open) {
      addEvent(const OpenEvent());
    }
  }

  /// The time a stream stays open after it is marked idle (one minute, as on
  /// Android).
  static const Duration idleTimeout = Duration(minutes: 1);

  static final Set<String> whiteListedHeaders = <String>{
    'date',
    'x-google-backends',
    'x-google-netmon-label',
    'x-google-service',
    'x-google-gfe-request-trace'
  };
}

enum State { initial, starting, open, error, backoff, closing }

abstract class StreamEvent {
  const StreamEvent();
}

class OpenEvent extends StreamEvent {
  const OpenEvent();
}

class CloseEvent extends StreamEvent {
  const CloseEvent(this.error);

  final GrpcError error;
}
