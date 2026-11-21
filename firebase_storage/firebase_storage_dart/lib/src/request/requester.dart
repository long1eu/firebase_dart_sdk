/// The request layer: headers, tokens, retries with backoff, timeouts and the mapping of error responses, after
/// `implementation/request.ts` and `implementation/backoff.ts` of the JS SDK.
@internal
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import '../errors.dart';
import '../version.dart';

/// The most of an error response's body that is kept in `FirebaseStorageException.serverResponse`.
@internal
const int maxErrorBodyBytes = 16 * 1024;

/// Whether [status] is retried: any 5xx, 408 (request timeout) and 429 (too many requests).
@internal
bool isRetryStatus(int status) =>
    (status >= 500 && status < 600) || status == 408 || status == 429;

/// Thrown by [Requester.send] when the body is longer than its `maxBodyBytes`.
@internal
final class BodyTooLargeException implements Exception {
  /// Creates the exception.
  const BodyTooLargeException();
}

/// One logical request: what to send and how to treat the response. The [Requester] adds the common headers and
/// retries it.
@immutable
@internal
final class StorageRequest {
  /// Creates a request.
  ///
  /// * [successCodes] are the statuses handed back as a success; any other status is either retried (see
  ///   [retryOnStatus]) or turned into an exception by [errorMapper].
  /// * [timeout] is the retry time of the request (a value of `StorageRetryPolicy`).
  /// * [retryOnStatus] retries the retryable statuses (see [isRetryStatus]); when false they go to
  ///   [errorMapper] like any other error. Network errors are retried either way, as in the JS SDK. The chunk
  ///   requests of a resumable upload set it to false and retry by themselves.
  const StorageRequest({
    required this.method,
    required this.url,
    required this.timeout,
    required this.errorMapper,
    this.headers = const <String, String>{},
    this.body,
    this.successCodes = const <int>{200},
    this.retryOnStatus = true,
  });

  /// The HTTP method.
  final String method;

  /// The full URL, query included.
  final Uri url;

  /// The headers of this request; the common ones (version, app id, tokens) are added to them.
  final Map<String, String> headers;

  /// The body, if any.
  final Uint8List? body;

  /// The statuses that are a success.
  final Set<int> successCodes;

  /// The retry time.
  final Duration timeout;

  /// Whether retryable statuses are retried.
  final bool retryOnStatus;

  /// Turns an error response into an exception.
  final StorageErrorMapper errorMapper;
}

/// A complete response with a success status.
@internal
final class StorageResponse {
  /// Creates a response.
  StorageResponse(this.statusCode, this.headers, this.bodyBytes);

  /// The HTTP status.
  final int statusCode;

  /// The headers, with lower-case names.
  final Map<String, String> headers;

  /// The body.
  final Uint8List bodyBytes;

  /// The body as UTF-8 text.
  String get body => utf8.decode(bodyBytes, allowMalformed: true);

  /// The body as a JSON object; throws `FirebaseStorageException` (`unknown`) when it is not one.
  Map<String, Object?> get jsonObject {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      decoded = null;
    }
    if (decoded is Map<String, Object?>) {
      return decoded;
    }
    throw unknownResponse(
      'the response is not a JSON object.',
      httpStatus: statusCode,
    );
  }
}

/// Sends [StorageRequest]s for one `FirebaseStorage`.
///
/// For each logical request it fetches the auth and App Check tokens once, sends the request with the common
/// headers, and retries network errors and retryable statuses with the backoff of the JS SDK until the retry
/// time of the request runs out. A 401 answered to a request with a user token gets one more attempt, right
/// away, with a token fetched with `forceRefresh: true`.
///
/// [send] returns the whole body; [open] hands back the response as soon as its headers arrive, for streamed
/// downloads. Both take an `abortTrigger`: when it completes, the attempt in flight is aborted (with clients
/// that support `http.Abortable`), a backoff wait ends, and the request throws `canceled`.
@internal
class Requester {
  /// Creates a requester that sends through [client] (closed by [close] when [ownsClient]).
  ///
  /// [mockUserToken] replaces the token of the app's auth provider (emulator only). [emulatorHost] is the
  /// `host:port` of the emulator, which may receive tokens over plain HTTP (see [mayCarryTokens]).
  /// [requestTimeout] is an idle timeout: an attempt fails like a network error (so it is retried) when the
  /// client takes no byte of the request body for that long, when no response arrives that long after the body
  /// was sent, or when a response body pauses that long. [clock], [random] and [delay] are for tests.
  Requester({
    required this.app,
    required http.Client client,
    required bool ownsClient,
    required this.requestTimeout,
    String? emulatorHost,
    String? mockUserToken,
    DateTime Function()? clock,
    double Function()? random,
    Future<void> Function(Duration duration)? delay,
  }) : _client = client,
       _ownsClient = ownsClient,
       _emulatorHost = emulatorHost?.toLowerCase(),
       _mockUserToken = mockUserToken,
       _clock = clock ?? DateTime.now,
       random = random ?? _defaultRandom,
       _delay = delay;

  /// The app whose tokens are sent.
  final FirebaseApp app;

  /// A number in `[0, 1)`: the jitter of the backoff.
  final double Function() random;

  /// The idle timeout of an attempt: the longest time without a byte of the request body taken by the client,
  /// without a response once the body was sent, or between two chunks of a response body. Readers of [open]
  /// apply it to the body. On the web, where the body cannot be watched, it bounds the wait from the start of
  /// the attempt to the response.
  final Duration requestTimeout;

  final http.Client _client;
  final bool _ownsClient;
  final String? _emulatorHost;
  final String? _mockUserToken;
  final DateTime Function() _clock;
  final Future<void> Function(Duration duration)? _delay;
  bool _closed = false;

  /// The current time (the injected clock in tests).
  DateTime now() => _clock();

  /// Waits [duration], or less when [abortTrigger] completes first; it returns normally either way.
  ///
  /// Uses the injected delay in tests, otherwise a [Timer] that is cancelled on abort, so that a canceled
  /// operation does not keep the process alive.
  Future<void> wait(Duration duration, {Future<void>? abortTrigger}) {
    final Completer<void> done = Completer<void>();
    void finish() {
      if (!done.isCompleted) {
        done.complete();
      }
    }

    final Future<void> Function(Duration duration)? delay = _delay;
    Timer? timer;
    if (delay == null) {
      timer = Timer(duration, finish);
    } else {
      delay(duration).then((_) => finish(), onError: (Object _) => finish());
    }
    abortTrigger?.then(
      (_) {
        timer?.cancel();
        finish();
      },
      onError: (Object _) {
        timer?.cancel();
        finish();
      },
    );
    return done.future;
  }

  /// Whether a request to [url] may carry the auth and App Check tokens: over HTTPS, to the emulator host, or
  /// to a loopback host. Like `StorageTokenAuthorizer` of the iOS SDK, tokens never travel in clear text to
  /// anybody else.
  bool mayCarryTokens(Uri url) {
    if (url.scheme == 'https') {
      return true;
    }
    final String host = url.host.toLowerCase();
    return url.authority.toLowerCase() == _emulatorHost ||
        host == 'localhost' ||
        host == '::1' ||
        RegExp(r'^127\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(host);
  }

  /// Whether [close] was called.
  bool get isClosed => _closed;

  /// Closes the client when it is owned; later requests throw a [StateError].
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    if (_ownsClient) {
      _client.close();
    }
  }

  /// Sends [request] and returns the complete response once its status is one of the success codes.
  ///
  /// With [maxBodyBytes], reading stops as soon as the body is longer and [BodyTooLargeException] is thrown.
  /// A body cut by a network error is requested again, within the retry time.
  ///
  /// [streamedBody] replaces the body of [request] with one that is read from a stream, opened again for each
  /// attempt (VM only). Off the web, a body is handed to the client in slices of at most [bodySliceSize]
  /// bytes and [onBodyProgress] is called with the number of bytes the client has taken after each slice (from
  /// 0 again on each attempt).
  Future<StorageResponse> send(
    StorageRequest request, {
    Future<void>? abortTrigger,
    int? maxBodyBytes,
    RequestBody? streamedBody,
    void Function(int bytesSent)? onBodyProgress,
  }) {
    final Uint8List? bytes = request.body;
    final RequestBody? body =
        streamedBody ?? (bytes == null ? null : RequestBody.bytes(bytes));
    return _execute(request, abortTrigger, body, onBodyProgress, (
      http.StreamedResponse response,
    ) async {
      final Uint8List bytes = await _readAll(response.stream, maxBodyBytes);
      return StorageResponse(response.statusCode, response.headers, bytes);
    });
  }

  /// Sends [request] and returns the response as soon as its headers arrive with a success status; its body
  /// is not read. Reading it is up to the caller (and so are the errors while reading it).
  Future<http.StreamedResponse> open(
    StorageRequest request, {
    Future<void>? abortTrigger,
  }) {
    final Uint8List? bytes = request.body;
    return _execute(
      request,
      abortTrigger,
      bytes == null ? null : RequestBody.bytes(bytes),
      null,
      (http.StreamedResponse response) async => response,
    );
  }

  Future<T> _execute<T>(
    StorageRequest request,
    Future<void>? abortTrigger,
    RequestBody? body,
    void Function(int bytesSent)? onBodyProgress,
    Future<T> Function(http.StreamedResponse response) onSuccess,
  ) async {
    _checkOpen();
    final _AbortState abort = _AbortState(abortTrigger);
    final DateTime deadline = _clock().add(request.timeout);
    final bool withTokens = mayCarryTokens(request.url);
    String? authToken = withTokens
        ? await _authToken(forceRefresh: false)
        : null;
    final String? appCheckToken = withTokens ? await _appCheckToken() : null;
    bool refreshed = false;
    int waitSeconds = 1;
    while (true) {
      abort.check();
      _checkOpen();
      Object? failure;
      int? failedStatus;
      try {
        final http.StreamedResponse response = await _sendOnce(
          request,
          _headers(request, authToken, appCheckToken),
          abort,
          body,
          onBodyProgress,
        );
        final int status = response.statusCode;
        if (request.successCodes.contains(status)) {
          return await onSuccess(response);
        }
        if (status == 401 &&
            !refreshed &&
            authToken != null &&
            _mockUserToken == null) {
          _discard(response);
          refreshed = true;
          authToken = await _authToken(forceRefresh: true);
          continue;
        }
        if (request.retryOnStatus && isRetryStatus(status)) {
          _discard(response);
          failure = 'HTTP $status';
          failedStatus = status;
        } else {
          throw request.errorMapper(status, await _readErrorBody(response));
        }
      } on http.ClientException catch (e) {
        failure = e;
      } on TimeoutException catch (e) {
        failure = e;
      }
      abort.check();
      _checkOpen();
      final DateTime current = _clock();
      if (!current.isBefore(deadline)) {
        throw retryLimitExceeded(
          httpStatus: failedStatus,
          cause: _describe(failure, request),
        );
      }
      if (waitSeconds < 64) {
        waitSeconds *= 2;
      }
      Duration pause = Duration(
        milliseconds: ((waitSeconds + random()) * 1000).round(),
      );
      final Duration remaining = deadline.difference(current);
      if (pause > remaining) {
        pause = remaining;
      }
      await wait(pause, abortTrigger: abortTrigger);
    }
  }

  Map<String, String> _headers(
    StorageRequest request,
    String? authToken,
    String? appCheckToken,
  ) {
    final String appId = app.options.appId;
    return <String, String>{
      ...request.headers,
      if (appId.isNotEmpty) 'X-Firebase-GMPID': appId,
      if (authToken != null) 'Authorization': 'Firebase $authToken',
      'X-Firebase-Storage-Version': 'dart/$packageVersion',
      'X-Firebase-AppCheck': ?appCheckToken,
    };
  }

  Future<http.StreamedResponse> _sendOnce(
    StorageRequest request,
    Map<String, String> headers,
    _AbortState abort,
    RequestBody? body,
    void Function(int bytesSent)? onBodyProgress,
  ) {
    final Completer<void> attemptAbort = Completer<void>();
    final Completer<http.StreamedResponse> result =
        Completer<http.StreamedResponse>();
    Timer? timer;
    void fail(Object error) {
      timer?.cancel();
      if (!attemptAbort.isCompleted) {
        attemptAbort.complete();
      }
      if (!result.isCompleted) {
        result.completeError(error);
      }
    }

    // The idle timeout: started again whenever the client takes part of the body, and once more when the
    // body ends, for the wait for the response.
    void touch() {
      if (result.isCompleted) {
        return;
      }
      timer?.cancel();
      timer = Timer(requestTimeout, () {
        fail(
          TimeoutException(
            'No progress for $requestTimeout on ${request.method} '
            '${request.url.path}',
            requestTimeout,
          ),
        );
      });
    }

    final http.BaseRequest httpRequest;
    if (body != null && streamsRequestBodies) {
      httpRequest = _StreamingRequest(
        request.method,
        request.url,
        body,
        onActivity: touch,
        onProgress: onBodyProgress,
        abortTrigger: attemptAbort.future,
      );
    } else {
      final http.AbortableRequest plain = http.AbortableRequest(
        request.method,
        request.url,
        abortTrigger: attemptAbort.future,
      );
      if (body != null) {
        plain.bodyBytes =
            body.bytes ??
            (throw UnsupportedError('A streamed request body needs dart:io.'));
      }
      httpRequest = plain;
    }
    httpRequest
      // The REST API never redirects, and a redirect would carry the App Check header to another host.
      ..followRedirects = false
      ..headers.addAll(headers);

    touch();
    abort.onAbort(() => fail(http.RequestAbortedException(request.url)));
    _client
        .send(httpRequest)
        .then(
          (http.StreamedResponse response) {
            timer?.cancel();
            if (result.isCompleted) {
              _discard(response);
            } else {
              result.complete(response);
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            timer?.cancel();
            if (!result.isCompleted) {
              result.completeError(error, stackTrace);
            }
          },
        );
    return result.future;
  }

  Future<Uint8List> _readAll(Stream<List<int>> stream, int? maxBytes) async {
    final BytesBuilder builder = BytesBuilder(copy: false);
    await for (final List<int> chunk in stream.timeout(requestTimeout)) {
      builder.add(chunk);
      if (maxBytes != null && builder.length > maxBytes) {
        throw const BodyTooLargeException();
      }
    }
    return builder.takeBytes();
  }

  /// [failure] for a message: the exception's message with the method and path of the request, never the
  /// query (it can hold an upload id or a download token).
  static String _describe(Object? failure, StorageRequest request) {
    final String target = '${request.method} ${request.url.path}';
    return switch (failure) {
      http.ClientException(:final String message) =>
        '${failure.runtimeType}: $message ($target)',
      TimeoutException() => 'TimeoutException ($target)',
      _ => '$failure ($target)',
    };
  }

  Future<String> _readErrorBody(http.StreamedResponse response) async {
    final BytesBuilder builder = BytesBuilder(copy: false);
    try {
      await for (final List<int> chunk in response.stream.timeout(
        requestTimeout,
      )) {
        builder.add(chunk);
        if (builder.length >= maxErrorBodyBytes) {
          break;
        }
      }
    } on http.ClientException {
      // Keep what arrived: the status is what matters.
    } on TimeoutException {
      // Same.
    }
    Uint8List bytes = builder.takeBytes();
    if (bytes.length > maxErrorBodyBytes) {
      bytes = Uint8List.sublistView(bytes, 0, maxErrorBodyBytes);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  Future<String?> _authToken({required bool forceRefresh}) async {
    final String? mockUserToken = _mockUserToken;
    if (mockUserToken != null) {
      return mockUserToken;
    }
    final AuthTokenProvider provider = app.authProvider;
    if (identical(provider, app)) {
      // The app is its own provider when none was set: nobody can be signed in.
      return null;
    }
    try {
      final GetTokenResult result = await provider.getAccessToken(
        forceRefresh: forceRefresh,
      );
      return result.token.isEmpty ? null : result.token;
    } on FirebaseNoSignedInUserException {
      return null;
    } on FirebaseApiNotAvailableException {
      return null;
    } on Object catch (e, stackTrace) {
      throw tokenFailed(e, stackTrace);
    }
  }

  Future<String?> _appCheckToken() async {
    final AppCheckTokenProvider? provider = app.appCheckProvider;
    if (provider == null) {
      return null;
    }
    try {
      final AppCheckTokenResult result = await provider.getToken(
        forceRefresh: false,
      );
      return result.token.isEmpty ? null : result.token;
    } on Object {
      // Like Firestore: the request goes out without the header and the backend decides.
      return null;
    }
  }

  void _checkOpen() {
    if (_closed) {
      throw StateError('This FirebaseStorage was closed.');
    }
  }

  static void _discard(http.StreamedResponse response) {
    response.stream.listen(null, onError: (Object _) {}).cancel().ignore();
  }

  static double _defaultRandom() => _random.nextDouble();
}

final math.Random _random = math.Random();

/// The largest slice of a request body handed to the client at once: 64 KiB.
@internal
const int bodySliceSize = 64 * 1024;

/// Whether request bodies are streamed to the client slice by slice, which gives upload progress and the idle
/// timeout. Not on the web: `fetch` takes the whole body at once.
@internal
const bool streamsRequestBodies = !bool.fromEnvironment(
  'dart.library.js_interop',
);

/// The body of a request: [length] bytes that [open] produces, from the start, for each attempt.
@internal
final class RequestBody {
  /// A body of [length] bytes read from the streams of [open].
  RequestBody(this.length, this.open) : bytes = null;

  /// A body of [bytes].
  RequestBody.bytes(Uint8List this.bytes)
    : length = bytes.length,
      open = (() => Stream<List<int>>.value(bytes));

  /// The size of the body, sent as `Content-Length`.
  final int length;

  /// Opens the body; called once per attempt.
  final Stream<List<int>> Function() open;

  /// The bytes, for a body in memory.
  final Uint8List? bytes;
}

/// A request whose body is handed to the client one slice at a time, reporting each slice the client took.
///
/// The slices come from an `async*` generator, so a client that applies backpressure (`IOClient` writing to
/// a socket) pulls them only as fast as it sends them.
final class _StreamingRequest extends http.BaseRequest with http.Abortable {
  _StreamingRequest(
    super.method,
    super.url,
    this._body, {
    required this.onActivity,
    this.onProgress,
    this.abortTrigger,
  }) {
    contentLength = _body.length;
  }

  @override
  final Future<void>? abortTrigger;

  final RequestBody _body;

  /// Called when the client takes a slice, and when the body ends.
  final void Function() onActivity;

  /// Called with the bytes taken so far after each slice.
  final void Function(int bytesSent)? onProgress;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(_slices());
  }

  Stream<List<int>> _slices() async* {
    int sent = 0;
    await for (final List<int> event in _body.open()) {
      for (int start = 0; start < event.length; start += bodySliceSize) {
        final int end = math.min(start + bodySliceSize, event.length);
        yield event is Uint8List
            ? Uint8List.sublistView(event, start, end)
            : event.sublist(start, end);
        sent += end - start;
        onActivity();
        onProgress?.call(sent);
      }
    }
    onActivity();
  }
}

/// The `abortTrigger` of a logical request, shared by its attempts and backoff waits.
final class _AbortState {
  _AbortState(Future<void>? trigger) {
    trigger?.then((_) => _abort(), onError: (Object _) => _abort());
  }

  bool _aborted = false;
  final List<void Function()> _listeners = <void Function()>[];

  void _abort() {
    if (_aborted) {
      return;
    }
    _aborted = true;
    final List<void Function()> listeners = List<void Function()>.of(
      _listeners,
    );
    _listeners.clear();
    for (final void Function() listener in listeners) {
      listener();
    }
  }

  /// Throws `canceled` when the trigger fired.
  void check() {
    if (_aborted) {
      throw canceled();
    }
  }

  /// Calls [listener] when the trigger fires (right away when it already did).
  void onAbort(void Function() listener) {
    if (_aborted) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }
}
