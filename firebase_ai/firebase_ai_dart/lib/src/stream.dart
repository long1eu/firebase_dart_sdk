import 'dart:async';
import 'dart:typed_data';

import 'package:_firebase_transport_dart/_firebase_transport_dart.dart';
import 'package:firebase_ai_dart/src/aggregate.dart';
import 'package:firebase_ai_dart/src/errors.dart';
import 'package:firebase_ai_dart/src/exception.dart';
import 'package:firebase_ai_dart/src/request.dart';
import 'package:firebase_ai_dart/src/response.dart';
import 'package:http/http.dart' as http;

/// The cap on one SSE event (its current line plus its data so far): 64 MiB.
const int maxSseEventBytes = 64 * 1024 * 1024;

/// The cap on one stream (all bytes given to the decoder): 256 MiB.
const int maxSseStreamBytes = 256 * 1024 * 1024;

/// Sends one streaming request and returns its chunks, one per SSE event, in order.
///
/// The returned stream is single-subscription, and nothing is sent until it is listened to.
/// [call] was started when the caller's method was called: its deadline covers the time before
/// the stream is listened to, the token wait and the wait for the response headers. After the
/// headers, [idleTimeout] gives two bounds, both reported as `deadline-exceeded`: no bytes for
/// that long (a dead transport), and no event for that long (so a keep-alive comment cannot keep
/// a stalled stream open). Both stop while the subscription is paused; null disables both.
///
/// [body] is sent as JSON to [url] with POST. Each event's data is decoded with the depth guard
/// and given to [decode]; every event that decodes is emitted.
///
/// The stream ends with a `FirebaseAIException` and aborts the request:
/// - the one `errorFromResponse` builds with [errorContext] for a non-2xx answer, and the one
///   `errorFromEvent` builds for an event with a top-level `error` key;
/// - `parse-failed` for a malformed body, event data that is not a JSON object, or JSON nested
///   too deep; `response-too-large` past [maxSseEventBytes] or [maxSseStreamBytes];
/// - `ai-closed`, `cancelled` or `deadline-exceeded` when [call] ended early, and the failures of
///   the token step and of the transport, as for a unary request.
///
/// A failure after at least one chunk carries the aggregate of the emitted chunks as its
/// `response`. Cancelling the subscription aborts the request and is not an error.
///
/// Throws, before it returns, an [ArgumentError] when [idleTimeout] is negative, and what
/// `jsonEncode` throws for [body].
Stream<GenerateContentResponse> sendStream(
  AiRequestContext context,
  AiCall call, {
  required Uri url,
  required Map<String, Object?> body,
  required Duration? idleTimeout,
  required ErrorContext errorContext,
  required GenerateContentResponse Function(Map<String, Object?> json) decode,
}) {
  if (idleTimeout != null && idleTimeout.isNegative) {
    throw ArgumentError.value(
      idleTimeout,
      'idleTimeout',
      'must not be negative',
    );
  }
  return _StreamSend(
    context,
    call,
    url: url,
    body: encodeBody(body),
    idleTimeout: idleTimeout,
    errorContext: errorContext,
    decode: decode,
  ).stream;
}

/// One streaming request, from the listen to the end of its body.
final class _StreamSend {
  _StreamSend(
    this._context,
    this._call, {
    required Uri url,
    required Uint8List body,
    required Duration? idleTimeout,
    required ErrorContext errorContext,
    required GenerateContentResponse Function(Map<String, Object?> json) decode,
  }) : _url = url,
       _requestBody = body,
       _idleTimeout = idleTimeout,
       _errorContext = errorContext,
       _decode = decode;

  final AiRequestContext _context;
  final AiCall _call;
  final Uri _url;
  final Uint8List _requestBody;
  final Duration? _idleTimeout;
  final ErrorContext _errorContext;
  final GenerateContentResponse Function(Map<String, Object?> json) _decode;

  final SseDecoder _decoder = SseDecoder(
    maxEventBytes: maxSseEventBytes,
    maxStreamBytes: maxSseStreamBytes,
  );
  final List<GenerateContentResponse> _emitted = <GenerateContentResponse>[];
  late final StreamController<GenerateContentResponse> _controller =
      StreamController<GenerateContentResponse>(
        onListen: () => unawaited(_run()),
        onPause: _onPause,
        onResume: _onResume,
        onCancel: _onCancel,
      );
  StreamSubscription<List<int>>? _body;
  Timer? _eventTimer;
  bool _readingBody = false;
  bool _done = false;

  Stream<GenerateContentResponse> get stream => _controller.stream;

  /// The token step, the send and the status check; then the body is listened to.
  Future<void> _run() async {
    try {
      final RequestTokens tokens = await fetchTokens(_context, _call, _url);
      final http.StreamedResponse response = await sendStreaming(
        _context.client,
        (Future<void> abort) =>
            postRequest(_context, _url, _requestBody, tokens, abort),
        headersDeadline: _call.takeTimeLeft(),
        idleTimeout: _idleTimeout,
        cancel: _call.whenEnded,
      );
      _context.headers.afterAnswer(response.statusCode, tokens);
      if (_done) {
        // The listener cancelled as the headers arrived; the request is already aborted.
        return;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final CappedResponse answer = await readCapped(
          response,
          cap: maxErrorBodyBytes,
          deadline: _call.takeTimeLeft(),
        );
        throw errorFromResponse(
          answer,
          _errorContext,
          appCheckOutcome: tokens.appCheck.name,
        );
      }
      _listenTo(response.stream);
    } on Object catch (error) {
      _fail(failureOf(_context, _call, error));
    }
  }

  /// Starts reading a success body. The call's deadline ends here; the two idle bounds take over.
  ///
  /// When the call ended as the headers arrived, the body gives the `cancelled` of that end at
  /// once, and [_onBodyError] reports the recorded end.
  void _listenTo(Stream<List<int>> body) {
    _call.stopDeadline();
    _readingBody = true;
    final StreamSubscription<List<int>> subscription = _body = body.listen(
      _onBytes,
      onError: _onBodyError,
      onDone: _onBodyDone,
    );
    if (_controller.isPaused) {
      subscription.pause();
    } else {
      _restartEventTimer();
    }
  }

  void _onBytes(List<int> chunk) {
    for (final SseItem item in _decoder.add(chunk)) {
      if (_done) {
        return;
      }
      _onItem(item);
    }
  }

  void _onItem(SseItem item) {
    switch (item) {
      case SseEvent(:final String data):
        _restartEventTimer();
        _onEvent(data);
      case SseMalformed() || SseEventTooLarge() || SseStreamTooLarge():
        _fail(errorFromFailure(item));
    }
  }

  /// Emits the chunk of one event, or fails the stream on data that is not a response.
  void _onEvent(String data) {
    final Object? json;
    try {
      json = decodeGuardedText(data, maxDepth: maxAiJsonDepth);
    } on FormatException catch (error) {
      _fail(errorFromFailure(error));
      return;
    }
    if (json is! Map<String, Object?>) {
      _fail(notAnObjectError());
      return;
    }
    if (json.containsKey('error')) {
      _fail(errorFromEvent(json, _errorContext));
      return;
    }
    final GenerateContentResponse chunk;
    try {
      chunk = _decode(json);
    } on Object catch (error) {
      _fail(error);
      return;
    }
    _emitted.add(chunk);
    _controller.add(chunk);
  }

  /// A failure of the transport, the no-bytes bound, or the `cancelled` that follows an early end
  /// of the call (the abort trigger, `close()` or the event timer).
  void _onBodyError(Object error, StackTrace _) {
    _fail(failureOf(_context, _call, error));
  }

  void _onBodyDone() {
    for (final SseItem item in _decoder.close()) {
      _onItem(item);
    }
    if (_done) {
      return;
    }
    _done = true;
    _release();
    unawaited(_controller.close());
  }

  void _onPause() {
    _body?.pause();
    _eventTimer?.cancel();
  }

  void _onResume() {
    _body?.resume();
    if (_readingBody) {
      _restartEventTimer();
    }
  }

  /// The listener cancelled: the request is aborted and nothing more is emitted.
  void _onCancel() {
    if (_done) {
      return;
    }
    _done = true;
    _abort();
    _release();
  }

  /// Restarts the event timer: it runs from the listen to the body and from each decoded event,
  /// never from a comment line, and ends the call when it fires.
  void _restartEventTimer() {
    _eventTimer?.cancel();
    final Duration? idleTimeout = _idleTimeout;
    if (idleTimeout == null || _done) {
      return;
    }
    _eventTimer = Timer(idleTimeout, () => _call.end(CallEnd.eventTimer));
  }

  /// Ends the stream with [error], carrying the aggregate of the chunks emitted so far, and aborts
  /// the request.
  void _fail(Object error) {
    if (_done) {
      return;
    }
    _done = true;
    _abort();
    _release();
    _controller.addError(_withPartial(error));
    unawaited(_controller.close());
  }

  Object _withPartial(Object error) {
    if (error is! FirebaseAIException || _emitted.isEmpty) {
      return error;
    }
    return error.withResponse(aggregateResponses(_emitted));
  }

  /// Completes the `cancel` future of the send, which aborts the request in any phase, and stops
  /// listening to the body. The cancel's own error can only repeat the abort, so it is dropped.
  void _abort() {
    _call.end(CallEnd.stopped);
    _body?.cancel().ignore();
    _body = null;
  }

  void _release() {
    _eventTimer?.cancel();
    _call.dispose();
  }
}
