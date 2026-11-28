import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// A response read with a cap on its body.
final class CappedResponse {
  /// A response with [statusCode], [headers] (lowercase names) and [body].
  const CappedResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
    this.truncated = false,
  });

  /// The HTTP status.
  final int statusCode;

  /// The response headers, names in lowercase.
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
/// The client's exception object is not kept: only its type name in [causeType] and, for an
/// `http.ClientException`, its message with the URL redacted in [detail].
final class TransportException implements Exception {
  /// A failure of kind [failure].
  const TransportException(this.failure, {this.causeType, this.detail});

  /// What failed.
  final TransportFailure failure;

  /// The runtime type name of the client's exception.
  final String? causeType;

  /// An `http.ClientException`'s message, redacted and sanitized; null for any other cause.
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
/// [build] receives the future that aborts the request and must give it to `http.AbortableRequest`.
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
    request.url,
    successCap: successCap,
    errorCap: errorCap,
  );
  final Timer timer = Timer(deadline, () {
    reader.fail(
      TimeoutException('The request took longer than its deadline', deadline),
      StackTrace.current,
    );
  });
  _watchCancel(cancel, reader.onCancel);
  try {
    unawaited(
      Future<http.StreamedResponse>.sync(
        () => client.send(request),
      ).then(reader.start, onError: reader.failClient),
    );
    return await reader.result.future;
  } finally {
    timer.cancel();
    reader.close();
  }
}

/// Sends the request [build] makes and returns its response with a watched body stream.
///
/// [build] receives the future that aborts the request and must give it to `http.AbortableRequest`.
/// Waits for the response headers at most [headersDeadline]; past it, aborts and throws
/// [TimeoutException]. Redirects are refused as in [sendCapped]. The returned response has the
/// status, headers and other fields of the client's response and a single-subscription body stream
/// that aborts the request when its subscription is cancelled or when [cancel] completes (it then
/// ends with a [TransportException] with [TransportFailure.cancelled]). With [idleTimeout], the
/// body stream ends with a [TimeoutException] and aborts when no bytes arrive for that long; the
/// idle timer starts when the body is listened to, restarts on every chunk and stops while the
/// subscription is paused. It checks no status and applies no cap. Every exception of the client,
/// before the headers or from the body stream, becomes a [TransportException].
Future<http.StreamedResponse> sendStreaming(
  http.Client client,
  http.BaseRequest Function(Future<void> abort) build, {
  required Duration headersDeadline,
  Duration? idleTimeout,
  Future<void>? cancel,
}) async {
  final Completer<void> abort = Completer<void>();
  final http.BaseRequest request = build(abort.future)..followRedirects = false;
  final _StreamingSend send = _StreamingSend(abort, request.url, idleTimeout);
  final Timer timer = Timer(headersDeadline, () {
    send.fail(
      TimeoutException(
        'The response headers took longer than their deadline',
        headersDeadline,
      ),
      StackTrace.current,
    );
  });
  _watchCancel(cancel, send.onCancel);
  try {
    unawaited(
      Future<http.StreamedResponse>.sync(
        () => client.send(request),
      ).then(send.start, onError: send.failClient),
    );
    return await send.result.future;
  } finally {
    timer.cancel();
  }
}

/// Reads the body of [response] up to [cap] bytes, within [deadline].
///
/// A longer body is cut: the subscription is cancelled at once and the result has
/// [CappedResponse.truncated] true; it never throws for size. A stream error completes the future
/// with a [TransportException]. Past [deadline] the subscription is cancelled and
/// [TimeoutException] is thrown.
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
      StackTrace.current,
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

int _utf8Length(int rune) {
  if (rune < 0x80) {
    return 1;
  }
  if (rune < 0x800) {
    return 2;
  }
  return rune < 0x10000 ? 3 : 4;
}

/// Calls [onCancel] when [cancel] completes, with a value or an error.
void _watchCancel(Future<void>? cancel, void Function() onCancel) {
  if (cancel == null) {
    return;
  }
  unawaited(
    cancel.then(
      (_) => onCancel(),
      onError: (Object _, StackTrace _) => onCancel(),
    ),
  );
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

bool _sameOrigin(Uri a, Uri b) =>
    a.scheme.toLowerCase() == b.scheme.toLowerCase() &&
    a.host.toLowerCase() == b.host.toLowerCase() &&
    a.port == b.port;

/// Stops listening to a body that is abandoned.
///
/// The failure that made the body abandoned was already reported; the cancel's own future can only
/// fail with the client's exception, which may print the URL, and carries nothing new. So its error
/// is dropped on purpose.
void _cancelQuietly(StreamSubscription<List<int>> subscription) {
  subscription.cancel().ignore();
}

/// Listens to the body of a response that is not returned and stops at once, so its connection is
/// released; no byte of it is read.
void _discard(http.StreamedResponse response) {
  _cancelQuietly(response.stream.listen(null, onError: (Object _) {}));
}

/// The [TransportException] for [error], an exception of the client or of its body stream.
///
/// [error] is not kept. [url] (the request URL, when known) and the exception's own URL are
/// redacted from the message of an `http.ClientException`.
TransportException _transportFailure(Object error, Uri? url) {
  final TransportFailure failure = error is http.RequestAbortedException
      ? TransportFailure.cancelled
      : TransportFailure.network;
  return TransportException(
    failure,
    causeType: error.runtimeType.toString(),
    detail: error is http.ClientException ? _redactedDetail(error, url) : null,
  );
}

/// The message of [error] with the URLs, their query strings and each query value of four
/// characters or more replaced by `<redacted>`, as written and percent-decoded, then sanitized.
///
/// Control characters are removed before the replacement too, so they cannot split a URL so that it
/// escapes the match.
String _redactedDetail(http.ClientException error, Uri? url) {
  final Set<String> secrets = <String>{};
  for (final Uri? each in <Uri?>[url, error.uri]) {
    if (each != null) {
      _addUrlSecrets(secrets, each);
    }
  }
  final List<String> longestFirst = secrets.toList()
    ..sort((String a, String b) => b.length.compareTo(a.length));
  final String plain = String.fromCharCodes(
    error.message.runes.where((int rune) => !_isControl(rune)),
  );
  return sanitizeServerText(_replaceEach(plain, longestFirst));
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

/// Adds [text] as written and percent-decoded to [secrets], each form only when it has at least
/// [minLength] characters.
void _addForms(Set<String> secrets, String text, int minLength) {
  final List<String> forms = <String>[text];
  try {
    forms
      ..add(Uri.decodeFull(text))
      ..add(Uri.decodeQueryComponent(text));
  } on ArgumentError {
    // Malformed percent-encoding: only the written form can appear.
  } on FormatException {
    // Percent-encoding of bytes that are not UTF-8: only the written form can appear.
  }
  for (final String form in forms) {
    if (form.length >= minLength) {
      secrets.add(form);
    }
  }
}

/// [text] with every occurrence of each of [longestFirst] replaced by `<redacted>`, in one pass; at
/// each position the longest match wins.
String _replaceEach(String text, List<String> longestFirst) {
  final StringBuffer buffer = StringBuffer();
  int index = 0;
  while (index < text.length) {
    final String? match = _matchAt(text, index, longestFirst);
    if (match == null) {
      buffer.writeCharCode(text.codeUnitAt(index));
      index++;
    } else {
      buffer.write('<redacted>');
      index += match.length;
    }
  }
  return buffer.toString();
}

String? _matchAt(String text, int index, List<String> longestFirst) {
  for (final String candidate in longestFirst) {
    if (text.startsWith(candidate, index)) {
      return candidate;
    }
  }
  return null;
}

/// Reads one response body against the caps of [sendCapped] and completes [result] once.
final class _CappedReader {
  _CappedReader(
    this._abort,
    this._url, {
    required this.successCap,
    required this.errorCap,
  });

  final Completer<void> _abort;
  final Uri _url;
  final int successCap;
  final int errorCap;
  final Completer<CappedResponse> result = Completer<CappedResponse>();
  final BytesBuilder _builder = BytesBuilder(copy: false);
  StreamSubscription<List<int>>? _subscription;
  http.StreamedResponse? _response;
  bool _closed = false;

  void start(http.StreamedResponse response) {
    if (result.isCompleted) {
      _discard(response);
      return;
    }
    if (_isRedirect(response, _url)) {
      fail(const TransportException(TransportFailure.redirected));
      _discard(response);
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

  /// The `cancel` future completed: aborts unless [sendCapped] has returned.
  void onCancel() {
    if (!_closed) {
      fail(const TransportException(TransportFailure.cancelled));
    }
  }

  /// [sendCapped] has returned; a later cancel does nothing.
  void close() {
    _closed = true;
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
      fail(CapExceededException(successCap), StackTrace.current);
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
    final http.StreamedResponse response = _response!;
    result.complete(
      CappedResponse(
        statusCode: response.statusCode,
        headers: response.headers,
        body: _builder.takeBytes(),
        truncated: truncated,
      ),
    );
  }

  /// An exception of the client or of the body stream, as a [TransportException].
  void failClient(Object error, StackTrace stackTrace) {
    _subscription = null;
    fail(_transportFailure(error, _url), stackTrace);
  }

  /// Completes [result] with [error] unless it is already complete, then aborts the request. The
  /// first failure wins: the deadline's timeout is recorded before the abort, so the failure the
  /// abort causes later is ignored.
  void fail(Object error, [StackTrace? stackTrace]) {
    if (!result.isCompleted) {
      result.completeError(error, stackTrace ?? StackTrace.current);
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
  _StreamingSend(this._abort, this._url, this._idleTimeout);

  final Completer<void> _abort;
  final Uri _url;
  final Duration? _idleTimeout;
  final Completer<http.StreamedResponse> result =
      Completer<http.StreamedResponse>();
  _StreamingBody? _body;

  void start(http.StreamedResponse response) {
    if (result.isCompleted) {
      _discard(response);
      return;
    }
    if (_isRedirect(response, _url)) {
      fail(const TransportException(TransportFailure.redirected));
      _discard(response);
      return;
    }
    final _StreamingBody body = _StreamingBody(
      response.stream,
      _abort,
      _url,
      _idleTimeout,
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

  /// An exception of the client before the headers, as a [TransportException].
  void failClient(Object error, StackTrace stackTrace) {
    fail(_transportFailure(error, _url), stackTrace);
  }

  /// Completes [result] with [error] unless it is complete, then aborts the request.
  void fail(Object error, [StackTrace? stackTrace]) {
    if (result.isCompleted) {
      return;
    }
    result.completeError(error, stackTrace ?? StackTrace.current);
    if (!_abort.isCompleted) {
      _abort.complete();
    }
  }

  static http.StreamedResponse _withBody(
    http.StreamedResponse response,
    Stream<List<int>> stream,
  ) {
    if (response is http.BaseResponseWithUrl) {
      return _StreamedResponseWithUrl(
        stream,
        response.statusCode,
        url: (response as http.BaseResponseWithUrl).url,
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
  _StreamingBody(this._source, this._abort, this._url, this._idleTimeout);

  final Stream<List<int>> _source;
  final Completer<void> _abort;
  final Uri _url;
  final Duration? _idleTimeout;
  late final StreamController<List<int>> _controller =
      StreamController<List<int>>(
        onListen: _onListen,
        onPause: _onPause,
        onResume: _onResume,
        onCancel: _onCancel,
      );
  StreamSubscription<List<int>>? _subscription;
  Timer? _idle;
  bool _done = false;

  Stream<List<int>> get stream => _controller.stream;

  /// The `cancel` future of [sendStreaming] completed.
  void onCancel() {
    _finish(
      const TransportException(TransportFailure.cancelled),
      StackTrace.current,
    );
  }

  void _onListen() {
    if (_done) {
      return;
    }
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

  void _onSourceError(Object error, StackTrace stackTrace) {
    _subscription = null;
    _finish(_transportFailure(error, _url), stackTrace);
  }

  void _onSourceDone() {
    _subscription = null;
    _done = true;
    _idle?.cancel();
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
    _done = true;
    _idle?.cancel();
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
      throw _transportFailure(error, _url);
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
        StackTrace.current,
      );
    });
  }

  /// Ends the body with [error] unless it has ended: aborts the request and stops the source.
  void _finish(Object error, StackTrace stackTrace) {
    if (_done) {
      return;
    }
    _done = true;
    _idle?.cancel();
    _abortRequest();
    final StreamSubscription<List<int>>? subscription = _subscription;
    _subscription = null;
    if (subscription != null) {
      _cancelQuietly(subscription);
    }
    _controller.addError(error, stackTrace);
    unawaited(_controller.close());
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
  final BytesBuilder _builder = BytesBuilder(copy: false);
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

  void _onError(Object error, StackTrace stackTrace) {
    _subscription = null;
    fail(_transportFailure(error, _response.request?.url), stackTrace);
  }

  void _complete({required bool truncated}) {
    if (result.isCompleted) {
      return;
    }
    result.complete(
      CappedResponse(
        statusCode: _response.statusCode,
        headers: _response.headers,
        body: _builder.takeBytes(),
        truncated: truncated,
      ),
    );
  }

  /// Completes [result] with [error] unless it is complete, and stops reading.
  void fail(Object error, StackTrace stackTrace) {
    if (!result.isCompleted) {
      result.completeError(error, stackTrace);
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
