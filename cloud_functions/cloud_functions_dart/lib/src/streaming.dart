/// Streaming callables (§5.10): one request with `Accept: text/event-stream`, its answer read as
/// server-sent events, a JSON answer or a non-2xx answer.
library;

import 'dart:async';

import 'package:_firebase_transport_dart/_firebase_transport_dart.dart';
import 'package:cloud_functions_dart/src/exception.dart';
import 'package:cloud_functions_dart/src/https_callable.dart';
import 'package:cloud_functions_dart/src/request.dart';
import 'package:cloud_functions_dart/src/response.dart';
import 'package:cloud_functions_dart/src/serializer.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

/// The largest stream event, and the largest JSON answer: 32 MiB.
const int _eventCap = 32 * 1024 * 1024;

/// The largest stream: 1 GiB.
const int _streamCap = 1024 * 1024 * 1024;

/// The largest non-2xx body read: 1 MiB.
const int _errorCap = 1024 * 1024;

const String _invalidEventMessage =
    'The server sent an event that is not valid JSON.';
const String _endedEarlyMessage =
    'The stream ended before the function returned a result.';

/// One stream of [HttpsCallable.stream]: a single-subscription controller whose listen sends the
/// request.
///
/// Pause and resume are forwarded to the body subscription, so the idle timer of `sendStreaming`
/// stops while the listener is paused; a cancel aborts the request. It has no timer of its own.
@internal
final class CallableStream {
  /// A stream that sends [_request] when listened to, aborted by [abortTrigger].
  CallableStream(this._request, Future<void>? abortTrigger)
    : _abortTrigger = abortTrigger {
    _watchTrigger(abortTrigger);
  }

  final CallRequest _request;
  final Future<void>? _abortTrigger;
  late final StreamController<CallableStreamEvent> _controller =
      StreamController<CallableStreamEvent>(
        onListen: _onListen,
        onPause: () => _bodySubscription?.pause(),
        onResume: () => _bodySubscription?.resume(),
        onCancel: _onCancel,
      );
  InFlightCall? _call;
  StreamSubscription<List<int>>? _bodySubscription;
  bool _triggered = false;
  bool _finished = false;
  int _statusCode = 0;

  /// The stream handed to the caller.
  Stream<CallableStreamEvent> get stream => _controller.stream;

  String get _idleMessage =>
      'The stream sent nothing for ${describeDuration(_request.timeout)}.';

  /// Notes a trigger that completes before the listen, so the listen sends nothing (§5.3). After
  /// the listen, the in-flight call watches the trigger itself.
  void _watchTrigger(Future<void>? trigger) {
    if (trigger == null) {
      return;
    }
    void fire() {
      _triggered = true;
    }

    unawaited(
      trigger.then<void>(
        (_) => fire(),
        onError: (Object _, StackTrace _) => fire(),
      ),
    );
  }

  void _onListen() {
    if (_triggered) {
      _finish(error: cancelledError(closed: false));
      return;
    }
    final InFlightCall call;
    try {
      call = _request.functions.startCall(_abortTrigger);
    } on StateError {
      _finish(error: cancelledError(closed: true));
      return;
    }
    _call = call;
    unawaited(call.aborted.then((_) => _onAborted(call)));
    unawaited(_run(call));
  }

  /// A cancel or a close ends the stream at once, whatever phase it is in, so `close` never waits
  /// for a pending token wait or for a paused listener. A deadline ends it through the failure
  /// that recorded it.
  void _onAborted(InFlightCall call) {
    final AbortReason? reason = call.reason;
    if (reason == null || reason == AbortReason.deadline) {
      return;
    }
    _finish(error: cancelledError(closed: reason == AbortReason.closed));
  }

  /// The listener cancelled: abort the request; nothing more reaches the listener.
  void _onCancel() {
    _call?.abort(AbortReason.cancelled);
    _finish();
  }

  Future<void> _run(InFlightCall call) async {
    try {
      final RequestTokens tokens = await _request.tokensFor(call);
      if (_finished) {
        return;
      }
      final http.StreamedResponse response = await _send(tokens, call);
      if (_finished) {
        _discard(response);
        return;
      }
      await _readResponse(response, tokens);
    } on Object catch (error) {
      _fail(error, deadlineMessage: _request.callDeadlineMessage);
    }
  }

  /// `sendStreaming` with the call's time left as the headers deadline and the timeout as the
  /// idle timeout; its [TimeoutException] becomes "No response arrived within `<t>`.".
  Future<http.StreamedResponse> _send(
    RequestTokens tokens,
    InFlightCall call,
  ) async {
    final Duration headersDeadline = _request.timeLeft(call);
    try {
      return await sendStreaming(
        _request.functions.httpClient,
        (Future<void> abort) => buildCallableRequest(
          url: _request.url,
          body: _request.body,
          tokens: tokens,
          abort: abort,
          streaming: true,
        ),
        headersDeadline: headersDeadline,
        idleTimeout: _request.timeout,
        cancel: call.aborted,
      );
    } on TimeoutException {
      throw deadlineError(
        'No response arrived within ${describeDuration(_request.timeout)}.',
      );
    }
  }

  /// Status first (§5.10 rule 2), then a JSON answer (rule 3), else server-sent events (rule 4).
  Future<void> _readResponse(
    http.StreamedResponse response,
    RequestTokens tokens,
  ) async {
    _statusCode = response.statusCode;
    final bool success = _statusCode >= 200 && _statusCode < 300;
    if (!success) {
      final CappedResponse capped = await _readWhole(response, _errorCap);
      _request.afterResponse(capped, tokens);
      _finishWithValue(capped);
      return;
    }
    if (_isJson(response.headers['content-type'])) {
      final CappedResponse capped = await _readWhole(response, _eventCap);
      if (capped.truncated) {
        throw internalError(tooLargeMessage, httpStatus: _statusCode);
      }
      _finishWithValue(capped);
      return;
    }
    _listenToEvents(response);
  }

  /// [readCapped] within the timeout; its [TimeoutException] is the idle message's.
  Future<CappedResponse> _readWhole(
    http.StreamedResponse response,
    int cap,
  ) async {
    try {
      return await readCapped(response, cap: cap, deadline: _request.timeout);
    } on TimeoutException {
      throw deadlineError(_idleMessage);
    }
  }

  /// One [CallableResult] from a body read whole, or the error of the unary rules (§5.7).
  void _finishWithValue(CappedResponse capped) {
    if (_finished) {
      return;
    }
    final Object? value = valueOfResponse(
      capped.statusCode,
      capped.body,
      truncated: capped.truncated,
    );
    _finish(event: CallableResult(value));
  }

  void _listenToEvents(http.StreamedResponse response) {
    final SseDecoder decoder = SseDecoder(
      maxEventBytes: _eventCap,
      maxStreamBytes: _streamCap,
    );
    final StreamSubscription<List<int>> subscription = response.stream.listen(
      (List<int> chunk) => _onItems(decoder.add(chunk), atEnd: false),
      onError: (Object error, StackTrace _) =>
          _fail(error, deadlineMessage: _idleMessage),
      onDone: () {
        _bodySubscription = null;
        _onItems(decoder.close(), atEnd: true);
        _finish(
          error: internalError(_endedEarlyMessage, httpStatus: _statusCode),
        );
      },
      cancelOnError: true,
    );
    _bodySubscription = subscription;
    if (_controller.isPaused) {
      subscription.pause();
    }
  }

  void _onItems(List<SseItem> items, {required bool atEnd}) {
    for (final SseItem item in items) {
      if (_finished) {
        return;
      }
      switch (item) {
        case SseEvent(:final String data):
          _onEvent(data);
        case SseMalformed():
          _finish(
            error: internalError(
              atEnd ? _endedEarlyMessage : _invalidEventMessage,
              httpStatus: _statusCode,
            ),
          );
        case SseEventTooLarge():
          _finish(
            error: internalError(tooLargeMessage, httpStatus: _statusCode),
          );
        case SseStreamTooLarge():
          _finish(
            error: internalError(
              'The stream is larger than 1 GiB.',
              httpStatus: _statusCode,
            ),
          );
      }
    }
  }

  /// §5.10 rules 4a-4e, in JS's key order: `result`, `message`, `error`; any other object is
  /// ignored.
  void _onEvent(String data) {
    final Map<Object?, Object?> object;
    try {
      object = _eventObject(data);
    } on FirebaseFunctionsException catch (error) {
      _finish(error: error);
      return;
    }
    try {
      if (object.containsKey('result')) {
        _finish(
          event: CallableResult(decodeOrThrow(object['result'], _statusCode)),
        );
      } else if (object.containsKey('message')) {
        _controller.add(
          CallableMessage(decodeOrThrow(object['message'], _statusCode)),
        );
      } else if (object.containsKey('error')) {
        _finish(error: _errorOfFrame(object));
      }
    } on FirebaseFunctionsException catch (error) {
      _finish(error: error);
    }
  }

  Map<Object?, Object?> _eventObject(String data) {
    if (exceedsJsonDepth(data.codeUnits, maxDepth: maxValueDepth)) {
      throw internalError(tooDeepMessage, httpStatus: _statusCode);
    }
    final Object? decoded;
    try {
      decoded = decodeGuardedText(data, maxDepth: maxValueDepth);
    } on FormatException {
      throw internalError(_invalidEventMessage, httpStatus: _statusCode);
    }
    if (decoded is! Map<Object?, Object?>) {
      throw internalError(_invalidEventMessage, httpStatus: _statusCode);
    }
    return decoded;
  }

  /// §5.10 rule 4d: the envelope rule, where a missing or non-string status is `internal` and a
  /// status `OK` is `internal` with its details kept.
  FirebaseFunctionsException _errorOfFrame(Map<Object?, Object?> object) {
    final Object? error = object['error'];
    if (error is Map<Object?, Object?> && error['status'] == 'OK') {
      final Object? details = error.containsKey('details')
          ? decodeOrThrow(error['details'], _statusCode)
          : null;
      return internalError(
        'The server sent an error event with status OK.',
        httpStatus: _statusCode,
        details: details,
      );
    }
    return envelopeError(object, _statusCode, inStream: true);
  }

  /// Ends the stream with the exception of [error], a failure of the token wait, the send or the
  /// body; an error that is not such a failure (a [StateError] of a deleted app) is emitted as is.
  void _fail(Object error, {required String deadlineMessage}) {
    if (_finished) {
      return;
    }
    final FirebaseFunctionsException? mapped = exceptionOfFailure(
      error,
      closed: _call?.reason == AbortReason.closed,
      deadlineMessage: deadlineMessage,
    );
    _finish(error: mapped ?? error);
  }

  /// Emits [event] or [error] (at most one), then done; stops reading the body, which aborts the
  /// request when the body has not ended, and settles the call. Later calls do nothing.
  void _finish({CallableStreamEvent? event, Object? error}) {
    if (_finished) {
      return;
    }
    _finished = true;
    if (event != null) {
      _controller.add(event);
    }
    if (error != null) {
      _controller.addError(error);
    }
    unawaited(_controller.close());
    _stopBody();
    _call?.settle();
  }

  /// The body's cancel future can fail only with the client's exception, which may print the
  /// request URL and was already reported or is moot once the stream ended, so it is dropped.
  void _stopBody() {
    final StreamSubscription<List<int>>? subscription = _bodySubscription;
    _bodySubscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel().catchError((Object _) {}));
    }
  }

  /// Releases the connection of a response that arrived after the stream ended.
  void _discard(http.StreamedResponse response) {
    unawaited(response.stream.listen(null).cancel().catchError((Object _) {}));
  }
}

/// True when [contentType]'s media type is `application/json` (parameters ignored).
bool _isJson(String? contentType) {
  if (contentType == null) {
    return false;
  }
  final String mediaType = contentType.split(';').first.trim().toLowerCase();
  return mediaType == 'application/json';
}
