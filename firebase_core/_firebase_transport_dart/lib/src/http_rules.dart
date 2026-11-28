import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:_firebase_transport_dart/src/hosts.dart' show canonicalHost;
import 'package:http/http.dart' as http;

/// A response read with a cap on its body.
final class CappedResponse {
  /// A response with [statusCode], [headers] and [body].
  const CappedResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
    this.truncated = false,
  });

  /// The HTTP status.
  final int statusCode;

  /// The response headers as the client gave them (the clients of `package:http` give lowercase
  /// names).
  final Map<String, String> headers;

  /// The body bytes, at most the cap they were read with.
  final Uint8List body;

  /// True when the body was cut at its cap: `errorCap` in [sendCapped], `cap` in [readCapped].
  final bool truncated;

  /// True for a 2xx status.
  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

/// Why a request failed below HTTP.
enum TransportFailure {
  /// The client failed to send the request or to read its response.
  network,

  /// The request was aborted: its `cancel` future completed, or the client reported an abort.
  cancelled,

  /// The server answered with a redirect, which is never followed or returned.
  redirected,
}

/// A failure of the transport, with nothing of the request's URL in it.
///
/// The client's exception object and its stack trace are not kept: only its type name in
/// [causeType] and, for an `http.ClientException`, its message in [detail] with the request URL,
/// its query, its query values and its header values redacted.
final class TransportException implements Exception {
  /// A failure of kind [failure].
  const TransportException(this.failure, {this.causeType, this.detail});

  /// What failed.
  final TransportFailure failure;

  /// The runtime type name of the client's exception. Under dart2js it may be a minified name.
  final String? causeType;

  /// An `http.ClientException`'s message, redacted and sanitized; null for any other cause.
  ///
  /// It can still name the host (a failed lookup) or quote text the server sent, such as a
  /// response header value in a browser's message.
  final String? detail;

  @override
  String toString() => 'TransportException: ${failure.name}';
}

/// A 2xx body longer than its cap.
final class CapExceededException implements Exception {
  /// The body was longer than [cap] bytes.
  const CapExceededException(this.cap);

  /// The cap in bytes.
  final int cap;

  @override
  String toString() =>
      'CapExceededException: the body is longer than $cap bytes';
}

/// Sends the request [build] makes and reads its body with caps.
///
/// [build] receives the future that aborts the request and must give it to `http.AbortableRequest`
/// (or another `http.Abortable` request); a request without it cannot be aborted.
/// Redirects are not followed: a 3xx answer, or a response from another origin than the request,
/// aborts and throws [TransportException] with [TransportFailure.redirected], and its body is not
/// read. A 2xx body past [successCap] aborts and throws [CapExceededException]. A non-2xx body is
/// cut at [errorCap] and returned with [CappedResponse.truncated] true. Past [deadline], measured
/// from the call to the end of the body, it aborts and throws [TimeoutException]. When [cancel]
/// completes, it aborts and throws [TransportException] with [TransportFailure.cancelled]. Every
/// exception of the client becomes a [TransportException]. The first failure wins.
Future<CappedResponse> sendCapped(
  http.Client client,
  http.BaseRequest Function(Future<void> abort) build, {
  required int successCap,
  required int errorCap,
  required Duration deadline,
  Future<void>? cancel,
}) async {
  final Completer<void> abort = Completer<void>();
  final http.BaseRequest request = build(abort.future)..followRedirects = false;
  final _CappedReader reader = _CappedReader(
    abort,
    request,
    successCap: successCap,
    errorCap: errorCap,
  );
  final Timer timer = Timer(deadline, () {
    reader.fail(
      TimeoutException('The request took longer than its deadline', deadline),
    );
  });
  final _CancelHook hook = _CancelHook.watch(cancel, reader.onCancel);
  try {
    unawaited(
      Future<http.StreamedResponse>.sync(
        () => client.send(request),
      ).then(reader.start).catchError(reader.failClient),
    );
    return await reader.result.future;
  } finally {
    timer.cancel();
    hook.clear();
  }
}

/// Sends the request [build] makes and returns its response with a watched body stream.
///
/// [build] receives the future that aborts the request and must give it to `http.AbortableRequest`
/// (or another `http.Abortable` request). Waits for the response headers at most
/// [headersDeadline]; past it, aborts and throws [TimeoutException]. Redirects are refused as in
/// [sendCapped]. The returned response has the status, headers, request and other fields of the
/// client's response, and a single-subscription body stream that aborts the request when its
/// subscription is cancelled or when [cancel] completes (it then ends with a [TransportException]
/// with [TransportFailure.cancelled]). With [idleTimeout], the body stream ends with a
/// [TimeoutException] and aborts when no bytes arrive for that long; the idle timer starts when the
/// body is listened to, restarts on every chunk and stops while the subscription is paused. It
/// checks no status and applies no cap. Every exception of the client, before the headers or from
/// the body stream, becomes a [TransportException].
///
/// The response's `request` is the request [build] made, with its headers: a product must not
/// print it, since the headers carry tokens.
Future<http.StreamedResponse> sendStreaming(
  http.Client client,
  http.BaseRequest Function(Future<void> abort) build, {
  required Duration headersDeadline,
  Duration? idleTimeout,
  Future<void>? cancel,
}) async {
  final Completer<void> abort = Completer<void>();
  final http.BaseRequest request = build(abort.future)..followRedirects = false;
  final _StreamingSend send = _StreamingSend(abort, request, idleTimeout);
  final Timer timer = Timer(headersDeadline, () {
    send.fail(
      TimeoutException(
        'The response headers took longer than their deadline',
        headersDeadline,
      ),
    );
  });
  final _CancelHook hook = _CancelHook.watch(cancel, send.onCancel);
  send.hook = hook;
  try {
    unawaited(
      Future<http.StreamedResponse>.sync(
        () => client.send(request),
      ).then(send.start).catchError(send.failClient),
    );
    return await send.result.future;
  } finally {
    timer.cancel();
    if (!send.hasBody) {
      hook.clear();
    }
  }
}

/// Reads the body of [response] up to [cap] bytes, within [deadline].
///
/// A longer body is cut: the subscription is cancelled at once and the result has
/// [CappedResponse.truncated] true; it never throws for size. A [TransportException], a
/// [TimeoutException] or a [CapExceededException] from the body stream (the stream [sendStreaming]
/// returns) is thrown unchanged; any other stream error completes the future with a
/// [TransportException]. Past [deadline] the subscription is cancelled and [TimeoutException] is
/// thrown.
Future<CappedResponse> readCapped(
  http.StreamedResponse response, {
  required int cap,
  required Duration deadline,
}) async {
  final _LimitedReader reader = _LimitedReader(response, cap);
  final Timer timer = Timer(deadline, () {
    reader.fail(
      TimeoutException(
        'Reading the body took longer than its deadline',
        deadline,
      ),
    );
  });
  try {
    reader.start();
    return await reader.result.future;
  } finally {
    timer.cancel();
  }
}

/// The UTF-8 bytes of server text kept: 1 KiB.
const int _serverTextCap = 1024;

/// [text] with control characters (C0, DEL and C1) removed, cut to at most 1 KiB of UTF-8 at a
/// character boundary.
String sanitizeServerText(String text) {
  final StringBuffer buffer = StringBuffer();
  int bytes = 0;
  for (final int rune in text.runes) {
    if (_isControl(rune)) {
      continue;
    }
    final int size = _utf8Length(rune);
    if (bytes + size > _serverTextCap) {
      break;
    }
    bytes += size;
    buffer.writeCharCode(rune);
  }
  return buffer.toString();
}

/// Decodes [bytes] as UTF-8, replacing malformed sequences.
String decodeUtf8Lenient(Uint8List bytes) =>
    utf8.decode(bytes, allowMalformed: true);

bool _isControl(int rune) => rune < 0x20 || (rune >= 0x7f && rune <= 0x9f);

String _withoutControls(String text) =>
    String.fromCharCodes(text.runes.where((int rune) => !_isControl(rune)));

int _utf8Length(int rune) {
  if (rune < 0x80) {
    return 1;
  }
  if (rune < 0x800) {
    return 2;
  }
  return rune < 0x10000 ? 3 : 4;
}

/// The listener on a caller's `cancel` future. [clear] drops the callback, so a long-lived
/// `cancel` future does not keep a finished call alive.
final class _CancelHook {
  _CancelHook._(this._onCancel);

  /// Calls [onCancel] when [cancel] completes, with a value or an error, until [clear].
  factory _CancelHook.watch(Future<void>? cancel, void Function() onCancel) {
    final _CancelHook hook = _CancelHook._(onCancel);
    if (cancel != null) {
      unawaited(
        cancel.then(
          (_) => hook._fire(),
          onError: (Object _, StackTrace _) => hook._fire(),
        ),
      );
    }
    return hook;
  }

  void Function()? _onCancel;

  void _fire() {
    final void Function()? onCancel = _onCancel;
    _onCancel = null;
    onCancel?.call();
  }

  void clear() {
    _onCancel = null;
  }
}

/// True when [response] is a redirect: a 3xx status, or a response URL of another origin than
/// [requestUrl] (a client that followed the redirect despite `followRedirects = false`).
bool _isRedirect(http.BaseResponse response, Uri requestUrl) {
  if (response.statusCode >= 300 && response.statusCode < 400) {
    return true;
  }
  return response is http.BaseResponseWithUrl &&
      !_sameOrigin(response.url, requestUrl);
}

/// Same scheme, host and port. Hosts are compared by [canonicalHost]; an internationalized name
/// is compared as given, so its Unicode and its punycode spellings are different origins. An IPv4
/// address is compared as given too, so a non-canonical spelling such as `127.1` is another origin
/// than `127.0.0.1` (the check fails closed, as `redirected`).
bool _sameOrigin(Uri a, Uri b) =>
    a.scheme.toLowerCase() == b.scheme.toLowerCase() &&
    canonicalHost(a.host) == canonicalHost(b.host) &&
    a.port == b.port;

/// Stops listening to a body that is abandoned.
///
/// The failure that made the body abandoned was already reported; the cancel's own future can only
/// fail with the client's exception, which may print the URL, and carries nothing new. So its error
/// is dropped on purpose.
void _cancelQuietly(StreamSubscription<List<int>> subscription) {
  subscription.cancel().ignore();
}

/// Listens to a body that is not read and stops at once, so its connection is released; no byte
/// of it is read.
void _discard(Stream<List<int>> body) {
  _cancelQuietly(body.listen(null, onError: (Object _) {}));
}

/// The [TransportException] for [error], an exception of the client or of its body stream.
///
/// [error] is not kept. The URL of [request] (when known), its header values and the exception's
/// own URL are redacted from the message of an `http.ClientException`.
TransportException _transportFailure(Object error, http.BaseRequest? request) {
  final TransportFailure failure = error is http.RequestAbortedException
      ? TransportFailure.cancelled
      : TransportFailure.network;
  return TransportException(
    failure,
    causeType: error.runtimeType.toString(),
    detail: error is http.ClientException
        ? _redactedDetail(error, request)
        : null,
  );
}

/// The message of [error] with every secret of [request] and of the exception's URL replaced by
/// `<redacted>`, then sanitized.
///
/// The secrets are the URLs, their query strings, each query value of four characters or more and
/// each request header value of four characters or more, as written and percent-decoded. Control
/// characters are removed from the message and from the secrets before matching, so they cannot
/// split a secret so that it escapes the match.
///
/// The message is cut at its first `. [` (after the control characters are removed) before
/// anything else: `dart:io`'s "Content size exceeds specified contentLength. N bytes written while
/// expected M. [<chunk>]" quotes up to 1 KiB of the request body, which can hold a token.
String _redactedDetail(http.ClientException error, http.BaseRequest? request) {
  final Set<String> secrets = <String>{};
  for (final Uri? url in <Uri?>[request?.url, error.uri]) {
    if (url != null) {
      _addUrlSecrets(secrets, url);
    }
  }
  for (final String value in request?.headers.values ?? const <String>[]) {
    _addForms(secrets, value, 4);
  }
  final String message = _withoutQuotedBody(_withoutControls(error.message));
  return sanitizeServerText(_redact(message, secrets));
}

/// [message] up to its first `. [`, keeping the full stop; the whole [message] when it has none.
String _withoutQuotedBody(String message) {
  final int start = message.indexOf('. [');
  return start < 0 ? message : message.substring(0, start + 1);
}

void _addUrlSecrets(Set<String> secrets, Uri url) {
  _addForms(secrets, url.toString(), 1);
  final String query = url.query;
  if (query.isEmpty) {
    return;
  }
  _addForms(secrets, query, 1);
  for (final String pair in query.split('&')) {
    final int equals = pair.indexOf('=');
    _addForms(secrets, equals < 0 ? pair : pair.substring(equals + 1), 4);
  }
}

/// Adds [text] as written and percent-decoded, without control characters, to [secrets]; each
/// form only when it has at least [minLength] characters.
void _addForms(Set<String> secrets, String text, int minLength) {
  final List<String> forms = <String>[text];
  try {
    forms
      ..add(Uri.decodeFull(text))
      ..add(Uri.decodeQueryComponent(text));
  } on ArgumentError {
    // Malformed percent-encoding: only the forms decoded so far can appear.
  } on FormatException {
    // Percent-encoding of bytes that are not UTF-8: only the forms decoded so far can appear.
  }
  for (final String form in forms) {
    final String plain = _withoutControls(form);
    if (plain.length >= minLength) {
      secrets.add(plain);
    }
  }
}

/// [text] with each run of code units covered by an occurrence of any of [secrets] replaced by one
/// `<redacted>`. Every occurrence of every secret is covered, also where occurrences overlap.
String _redact(String text, Set<String> secrets) {
  final List<bool> covered = List<bool>.filled(text.length, false);
  for (final String secret in secrets) {
    int start = text.indexOf(secret);
    while (start >= 0) {
      covered.fillRange(start, start + secret.length, true);
      start = text.indexOf(secret, start + 1);
    }
  }
  final StringBuffer buffer = StringBuffer();
  for (int index = 0; index < text.length; index++) {
    if (!covered[index]) {
      buffer.writeCharCode(text.codeUnitAt(index));
    } else if (index == 0 || !covered[index - 1]) {
      buffer.write('<redacted>');
    }
  }
  return buffer.toString();
}

/// The [CappedResponse] of [response] with the bytes in [builder].
CappedResponse _cappedOf(
  http.StreamedResponse response,
  BytesBuilder builder, {
  required bool truncated,
}) {
  return CappedResponse(
    statusCode: response.statusCode,
    headers: response.headers,
    body: builder.takeBytes(),
    truncated: truncated,
  );
}

/// Reads one response body against the caps of [sendCapped] and completes [result] once.
final class _CappedReader {
  _CappedReader(
    this._abort,
    this._request, {
    required this.successCap,
    required this.errorCap,
  });

  final Completer<void> _abort;
  final http.BaseRequest _request;
  final int successCap;
  final int errorCap;
  final Completer<CappedResponse> result = Completer<CappedResponse>();
  final BytesBuilder _builder = BytesBuilder();
  StreamSubscription<List<int>>? _subscription;
  http.StreamedResponse? _response;

  void start(http.StreamedResponse response) {
    if (result.isCompleted) {
      _discard(response.stream);
      return;
    }
    if (_isRedirect(response, _request.url)) {
      fail(const TransportException(TransportFailure.redirected));
      _discard(response.stream);
      return;
    }
    _response = response;
    _subscription = response.stream.listen(
      _onChunk,
      onError: failClient,
      onDone: () => _complete(truncated: false),
      cancelOnError: true,
    );
  }

  /// The `cancel` future completed.
  void onCancel() {
    fail(const TransportException(TransportFailure.cancelled));
  }

  bool get _success {
    final int status = _response!.statusCode;
    return status >= 200 && status < 300;
  }

  void _onChunk(List<int> chunk) {
    if (result.isCompleted) {
      return;
    }
    final int cap = _success ? successCap : errorCap;
    final int room = cap - _builder.length;
    if (chunk.length <= room) {
      _builder.add(chunk);
      return;
    }
    if (_success) {
      fail(CapExceededException(successCap));
      return;
    }
    _builder.add(chunk.sublist(0, room));
    _stop();
    _complete(truncated: true);
  }

  void _complete({required bool truncated}) {
    if (result.isCompleted) {
      return;
    }
    result.complete(_cappedOf(_response!, _builder, truncated: truncated));
  }

  /// An exception of the client or of the body stream, as a [TransportException]. The client's
  /// stack trace is not kept: it can reference the client's exception.
  void failClient(Object error, StackTrace _) {
    _subscription = null;
    fail(_transportFailure(error, _request));
  }

  /// Completes [result] with [error] unless it is already complete, then aborts the request. The
  /// first failure wins: the deadline's timeout is recorded before the abort, so the failure the
  /// abort causes later is ignored.
  void fail(Object error) {
    if (!result.isCompleted) {
      result.completeError(error, StackTrace.current);
    }
    _stop();
  }

  void _stop() {
    if (!_abort.isCompleted) {
      _abort.complete();
    }
    final StreamSubscription<List<int>>? subscription = _subscription;
    _subscription = null;
    if (subscription != null) {
      _cancelQuietly(subscription);
    }
  }
}

/// The headers phase of [sendStreaming]: completes [result] once, then hands the body to a
/// [_StreamingBody].
final class _StreamingSend {
  _StreamingSend(this._abort, this._request, this._idleTimeout);

  final Completer<void> _abort;
  final http.BaseRequest _request;
  final Duration? _idleTimeout;
  final Completer<http.StreamedResponse> result =
      Completer<http.StreamedResponse>();

  /// The listener on the `cancel` future; the body clears it when it ends.
  _CancelHook? hook;
  _StreamingBody? _body;

  /// True once the response was returned with its body.
  bool get hasBody => _body != null;

  void start(http.StreamedResponse response) {
    if (result.isCompleted) {
      _discard(response.stream);
      return;
    }
    if (_isRedirect(response, _request.url)) {
      fail(const TransportException(TransportFailure.redirected));
      _discard(response.stream);
      return;
    }
    final _StreamingBody body = _StreamingBody(
      response.stream,
      _abort,
      _request,
      _idleTimeout,
      onEnd: () => hook?.clear(),
    );
    _body = body;
    result.complete(_withBody(response, body.stream));
  }

  /// The `cancel` future completed: fails the headers phase, or ends the body.
  void onCancel() {
    final _StreamingBody? body = _body;
    if (body != null) {
      body.onCancel();
      return;
    }
    fail(const TransportException(TransportFailure.cancelled));
  }

  /// An exception of the client before the headers, as a [TransportException]. The client's stack
  /// trace is not kept: it can reference the client's exception.
  void failClient(Object error, StackTrace _) {
    fail(_transportFailure(error, _request));
  }

  /// Completes [result] with [error] unless it is complete, then aborts the request.
  void fail(Object error) {
    if (result.isCompleted) {
      return;
    }
    result.completeError(error, StackTrace.current);
    if (!_abort.isCompleted) {
      _abort.complete();
    }
  }

  static http.StreamedResponse _withBody(
    http.StreamedResponse response,
    Stream<List<int>> stream,
  ) {
    if (response case final http.BaseResponseWithUrl withUrl) {
      return _StreamedResponseWithUrl(
        stream,
        response.statusCode,
        url: withUrl.url,
        contentLength: response.contentLength,
        request: response.request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    }
    return http.StreamedResponse(
      stream,
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }
}

/// A [http.StreamedResponse] that keeps the URL of the client's response.
final class _StreamedResponseWithUrl extends http.StreamedResponse
    implements http.BaseResponseWithUrl {
  _StreamedResponseWithUrl(
    super.stream,
    super.statusCode, {
    required this.url,
    super.contentLength,
    super.request,
    super.headers,
    super.isRedirect,
    super.persistentConnection,
    super.reasonPhrase,
  });

  @override
  final Uri url;
}

/// The body stream [sendStreaming] returns: wraps the client's body with the abort, the cancel
/// signal and the idle timer.
final class _StreamingBody {
  _StreamingBody(
    this._source,
    this._abort,
    this._request,
    this._idleTimeout, {
    required void Function() onEnd,
  }) : _onEnd = onEnd;

  final Stream<List<int>> _source;
  final Completer<void> _abort;
  final http.BaseRequest _request;
  final Duration? _idleTimeout;
  final void Function() _onEnd;
  late final StreamController<List<int>> _controller =
      StreamController<List<int>>(
        onListen: _onListen,
        onPause: _onPause,
        onResume: _onResume,
        onCancel: _onCancel,
      );
  StreamSubscription<List<int>>? _subscription;
  Timer? _idle;
  bool _listened = false;
  bool _done = false;

  Stream<List<int>> get stream => _controller.stream;

  /// The `cancel` future of [sendStreaming] completed.
  void onCancel() {
    _finish(const TransportException(TransportFailure.cancelled));
  }

  void _onListen() {
    if (_done) {
      return;
    }
    _listened = true;
    _subscription = _source.listen(
      _onData,
      onError: _onSourceError,
      onDone: _onSourceDone,
      cancelOnError: true,
    );
    _restartIdle();
  }

  void _onData(List<int> chunk) {
    _restartIdle();
    _controller.add(chunk);
  }

  /// The client's stack trace is not kept: it can reference the client's exception.
  void _onSourceError(Object error, StackTrace _) {
    _subscription = null;
    _finish(_transportFailure(error, _request));
  }

  void _onSourceDone() {
    _subscription = null;
    _markDone();
    unawaited(_controller.close());
  }

  void _onPause() {
    _subscription?.pause();
    _idle?.cancel();
  }

  void _onResume() {
    _subscription?.resume();
    _restartIdle();
  }

  /// The listener cancelled its subscription: aborts the request unless the body had ended.
  Future<void> _onCancel() async {
    final bool ended = _done;
    _markDone();
    if (!ended) {
      _abortRequest();
    }
    final StreamSubscription<List<int>>? subscription = _subscription;
    _subscription = null;
    if (subscription == null) {
      return;
    }
    try {
      await subscription.cancel();
    } on Object catch (error) {
      throw _transportFailure(error, _request);
    }
  }

  void _restartIdle() {
    final Duration? idleTimeout = _idleTimeout;
    _idle?.cancel();
    if (idleTimeout == null || _done) {
      return;
    }
    _idle = Timer(idleTimeout, () {
      _finish(
        TimeoutException('No bytes arrived for the idle timeout', idleTimeout),
      );
    });
  }

  /// Ends the body with [error] unless it has ended: aborts the request and stops the source (or
  /// listens to it and stops at once, when nobody listened yet, so its connection is released).
  void _finish(Object error) {
    if (_done) {
      return;
    }
    _markDone();
    _abortRequest();
    final StreamSubscription<List<int>>? subscription = _subscription;
    _subscription = null;
    if (subscription != null) {
      _cancelQuietly(subscription);
    } else if (!_listened) {
      _discard(_source);
    }
    _controller.addError(error, StackTrace.current);
    unawaited(_controller.close());
  }

  void _markDone() {
    _done = true;
    _idle?.cancel();
    _onEnd();
  }

  void _abortRequest() {
    if (!_abort.isCompleted) {
      _abort.complete();
    }
  }
}

/// Reads one body for [readCapped] and completes [result] once.
final class _LimitedReader {
  _LimitedReader(this._response, this._cap);

  final http.StreamedResponse _response;
  final int _cap;
  final Completer<CappedResponse> result = Completer<CappedResponse>();
  final BytesBuilder _builder = BytesBuilder();
  StreamSubscription<List<int>>? _subscription;

  void start() {
    _subscription = _response.stream.listen(
      _onChunk,
      onError: _onError,
      onDone: () => _complete(truncated: false),
      cancelOnError: true,
    );
  }

  void _onChunk(List<int> chunk) {
    if (result.isCompleted) {
      return;
    }
    final int room = _cap - _builder.length;
    if (chunk.length <= room) {
      _builder.add(chunk);
      return;
    }
    _builder.add(chunk.sublist(0, room));
    _stop();
    _complete(truncated: true);
  }

  /// The failures of this package (from a [sendStreaming] body) pass through unchanged; anything
  /// else is the client's and becomes a [TransportException]. The stream's stack trace is not kept:
  /// it can reference the client's exception.
  void _onError(Object error, StackTrace _) {
    _subscription = null;
    final bool ours =
        error is TransportException ||
        error is TimeoutException ||
        error is CapExceededException;
    fail(ours ? error : _transportFailure(error, _response.request));
  }

  void _complete({required bool truncated}) {
    if (result.isCompleted) {
      return;
    }
    result.complete(_cappedOf(_response, _builder, truncated: truncated));
  }

  /// Completes [result] with [error] unless it is complete, and stops reading.
  void fail(Object error) {
    if (!result.isCompleted) {
      result.completeError(error, StackTrace.current);
    }
    _stop();
  }

  void _stop() {
    final StreamSubscription<List<int>>? subscription = _subscription;
    _subscription = null;
    if (subscription != null) {
      _cancelQuietly(subscription);
    }
  }
}
