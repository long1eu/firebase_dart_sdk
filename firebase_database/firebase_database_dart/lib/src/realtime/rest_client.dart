/// The read-only REST implementation of [ServerActions] (owner R): reads as the JS
/// `ReadonlyRestClient` does (`rtdb_protocol.md` 10, 6.4); threat model T7, T8, T23.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_database_dart/src/core/connection/listen_hash_provider.dart';
import 'package:firebase_database_dart/src/core/connection/listen_spec.dart';
import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:firebase_database_dart/src/core/util/logger.dart';
import 'package:firebase_database_dart/src/realtime/auth_session.dart';
import 'package:firebase_database_dart/src/realtime/realtime_error.dart';
import 'package:firebase_database_dart/src/realtime/realtime_target.dart';
import 'package:http/http.dart' as http;

/// The most of an error response body that is read (threat model T23).
const int _maxErrorBodyBytes = 16 * 1024;

/// The status of a success body over `maxResponseBytes` (`DatabaseErrorCode.tooBig`).
const String _statusTooBig = 'too_big';

/// The status of a read that failed on an unexpected error (`DatabaseErrorCode.unknown`).
const String _statusUnknown = 'unknown';

/// Reads a database over HTTPS (or HTTP to the emulator); the second implementation of
/// [ServerActions] (JS uses it for `forceRestClient` and crawlers, 10).
///
/// [get] and [listen] send `GET <path>.json?ns=..[&query params]&format=export[&auth=..][&ac=..]`
/// (`ac` only on the web, see below). The
/// query parameters are `ListenSpec.restParams` (the core's
/// `QueryParams.toRestQueryStringParameters()`, `rtdb_seam_changes.md` A.4). A listen is one
/// read: the data goes to [ServerActionsDelegate.onDataUpdate] at the spec's path, then
/// `onComplete` gets `ok`. 401 is `permission_denied`, 404 is null data, other non-2xx are
/// `rest_error:<status>` for a listen and a [ServerActionsException] carrying the status for a
/// get (A.2; 9, 10; JS drops it, ReadonlyRestClient.ts:168). A body that is not JSON reads as
/// null with a warning (ReadonlyRestClient.ts:222-227); so does one nested deeper than
/// `maxJsonDepth` or holding a number that is not finite (threat model rule 4). No answer within
/// `requestTimeout` (to the headers, or between two chunks of the body) and a network failure
/// are `network_error`; a success body over `maxResponseBytes` is `too_big`.
///
/// Deliberate difference from JS: [get] does not call [ServerActionsDelegate.onDataUpdate].
/// `ReadonlyRestClient.ts:158-163` does, with no tag even for a filtered query, which writes the
/// partial result of a limited query over the whole path; Repo applies the result of a get
/// itself.
///
/// Writes and onDisconnect operations complete with the status `read_only` ([statusReadOnly],
/// A.7) on the event loop, never synchronously. URLs come from [RealtimeTarget.restUri]. The ID
/// token goes in `auth=` (the probe measured that `auth=` is the only form the emulator checks
/// rules with: `access_token=` and `Authorization: Bearer` are admin there). The App Check token
/// goes in the `X-Firebase-AppCheck` header where the platform sends headers (the VM), and in
/// the `ac` query value on the web, as JS does from a browser (ReadonlyRestClient.ts:197-199): a
/// custom header there would make every read a CORS preflight (security rule 2 of the brief).
/// Both tokens only when non-empty and where [RealtimeTarget.mayReceiveTokens] allows (T3).
/// Redirects are not followed
/// (a 3xx is `rest_error:3xx`), error bodies are read up to 16 KiB, success bodies up to
/// `maxResponseBytes` (T23). No error message or log line holds a URL query or a token (T7, T8):
/// `ClientException.uri` is dropped and its message is cleaned.
///
/// While [interrupt] holds a reason, reads wait before they are sent; a read already sent is
/// not cancelled.
final class RestClient implements ServerActions {
  /// Creates a client of [target] reading tokens from [tokens] (A.1) and reporting to [delegate];
  /// [logger] gets the warnings of 10 (parse failures, `rest_error`), never a URL query (T7);
  /// null drops them.
  /// [httpClient] defaults to a new `http.Client` that [shutdown] closes; a given one is left
  /// open. [maxResponseBytes] bounds a success body (`ConnectionTimings.maxMessageBytes`),
  /// [requestTimeout] the wait for an answer and every pause in its body
  /// (`ConnectionTimings.requestTimeout`), [maxJsonDepth] the nesting of the data
  /// (`ConnectionTimings.maxJsonDepth`). [useHeaders] says whether App Check travels in a header
  /// (true) or in the `ac` query value (false): pass the same value as to [RealtimeTarget.new].
  // MERGE: T: the factory passes `wsConnectorSendsHeaders` (transport/ws_connector.dart) as
  // [useHeaders], the switch the WebSocket side uses; not imported here.
  RestClient({
    required RealtimeTarget target,
    required RealtimeTokenSource tokens,
    required ServerActionsDelegate delegate,
    DatabaseLogger? logger,
    http.Client? httpClient,
    required int maxResponseBytes,
    required bool useHeaders,
    Duration requestTimeout = const Duration(seconds: 60),
    int maxJsonDepth = 64,
  }) : _target = target,
       _tokens = tokens,
       _delegate = delegate,
       _logger = logger,
       _client = httpClient ?? http.Client(),
       _ownsClient = httpClient == null,
       _maxResponseBytes = maxResponseBytes,
       _requestTimeout = requestTimeout,
       _maxJsonDepth = maxJsonDepth,
       _useHeaders = useHeaders;

  final RealtimeTarget _target;
  final RealtimeTokenSource _tokens;
  final ServerActionsDelegate _delegate;
  final DatabaseLogger? _logger;
  final http.Client _client;
  final bool _ownsClient;
  final int _maxResponseBytes;
  final Duration _requestTimeout;
  final int _maxJsonDepth;
  final bool _useHeaders;

  /// The registered listens by path and query identifier (JS `getListenId_`, keyed by the
  /// identity `ListenSpec` documents).
  final Map<(String, String), _Read> _listens = <(String, String), _Read>{};

  /// Every read not finished yet, listens and gets, for [shutdown].
  final Set<_Read> _reads = <_Read>{};

  final Set<String> _interruptReasons = <String>{};
  Completer<void>? _resumed;
  bool _closed = false;

  /// Nothing to connect; reports nothing (the REST client never calls
  /// [ServerActionsDelegate.onConnect]).
  @override
  void initialize() {}

  /// Closes the HTTP client when this client created it; later reads complete nothing.
  @override
  Future<void> shutdown() async {
    if (_closed) {
      return;
    }
    _closed = true;
    for (final _Read read in _reads.toList()) {
      read.cancel();
    }
    _reads.clear();
    _listens.clear();
    _wakeWaitingReads();
    if (_ownsClient) {
      _client.close();
    }
  }

  /// One read of [spec]; [hashProvider] is not used.
  @override
  void listen(
    ListenSpec spec, {
    required ListenHashProvider hashProvider,
    int? tag,
    required RequestResultCallback onComplete,
  }) {
    if (_closed) {
      return;
    }
    assert(
      spec.isDefault || tag != null,
      'A query that is not the default one is listened to with a tag.',
    );
    final (String, String) key = (spec.path, spec.queryIdentifier);
    if (_listens.containsKey(key)) {
      throw StateError('Already listening to ${spec.path} with this query.');
    }
    final _Read read = _Read();
    _listens[key] = read;
    unawaited(
      _run(spec, read).then((_ReadResult result) {
        _completeListen(spec, key, read, tag, result, onComplete);
      }),
    );
  }

  void _completeListen(
    ListenSpec spec,
    (String, String) key,
    _Read read,
    int? tag,
    _ReadResult result,
    RequestResultCallback onComplete,
  ) {
    if (_closed || !identical(_listens[key], read)) {
      return;
    }
    switch (result) {
      case _ReadData(:final Object? data):
        _delegate.onDataUpdate(spec.path, data, isMerge: false, tag: tag);
        onComplete(statusOk, null);
      case _ReadFailure(:final String status, :final String? reason):
        _listens.remove(key);
        onComplete(status, reason);
      case _ReadDropped():
        break;
    }
  }

  /// Forgets the listen; a read in flight is dropped.
  @override
  void unlisten(ListenSpec spec, {int? tag}) {
    _listens.remove((spec.path, spec.queryIdentifier))?.cancel();
  }

  /// One read of [spec]. A read dropped by [shutdown] never completes.
  @override
  Future<Object?> get(ListenSpec spec) async {
    final _ReadResult result = _closed
        ? const _ReadDropped()
        : await _run(spec, _Read());
    switch (result) {
      case _ReadData(:final Object? data):
        return data;
      case _ReadFailure(:final String status, :final String? reason):
        throw ServerActionsException(status, reason);
      case _ReadDropped():
        return Completer<Object?>().future;
    }
  }

  /// Completes with `read_only`: the REST client is read-only.
  @override
  void put(
    String path,
    Object? data, {
    String? hash,
    RequestResultCallback? onComplete,
  }) {
    _completeReadOnly(onComplete);
  }

  /// Completes with `read_only`: the REST client is read-only.
  @override
  void merge(
    String path,
    Map<String, Object?> data, {
    String? hash,
    RequestResultCallback? onComplete,
  }) {
    _completeReadOnly(onComplete);
  }

  /// Completes with `read_only`.
  @override
  void onDisconnectPut(
    String path,
    Object? data, {
    RequestResultCallback? onComplete,
  }) {
    _completeReadOnly(onComplete);
  }

  /// Completes with `read_only`.
  @override
  void onDisconnectMerge(
    String path,
    Map<String, Object?> data, {
    RequestResultCallback? onComplete,
  }) {
    _completeReadOnly(onComplete);
  }

  /// Completes with `read_only`.
  @override
  void onDisconnectCancel(String path, {RequestResultCallback? onComplete}) {
    _completeReadOnly(onComplete);
  }

  void _completeReadOnly(RequestResultCallback? onComplete) {
    if (onComplete == null || _closed) {
      return;
    }
    scheduleMicrotask(() {
      if (!_closed) {
        onComplete(statusReadOnly, null);
      }
    });
  }

  /// Nothing to do: there are no outstanding writes.
  @override
  void purgeOutstandingWrites() {}

  /// Records [reason]; reads wait while any reason is set.
  @override
  void interrupt(String reason) {
    _interruptReasons.add(reason);
  }

  @override
  void resume(String reason) {
    _interruptReasons.remove(reason);
    if (_interruptReasons.isEmpty) {
      _wakeWaitingReads();
    }
  }

  @override
  bool isInterrupted(String reason) => _interruptReasons.contains(reason);

  void _wakeWaitingReads() {
    final Completer<void>? resumed = _resumed;
    _resumed = null;
    resumed?.complete();
  }

  bool _isDropped(_Read read) => _closed || read.isCancelled;

  /// Runs [read] of [spec] to its end; never throws.
  Future<_ReadResult> _run(ListenSpec spec, _Read read) async {
    _reads.add(read);
    try {
      while (_interruptReasons.isNotEmpty && !_isDropped(read)) {
        await Future.any(<Future<void>>[
          (_resumed ??= Completer<void>()).future,
          read.cancelled,
        ]);
      }
      if (_isDropped(read)) {
        return const _ReadDropped();
      }
      final _ReadResult result = await _fetch(spec, read);
      return _isDropped(read) ? const _ReadDropped() : result;
    } on Object catch (error) {
      // Rule 4 of the threat model: nothing escapes into the application's zone. Only the type
      // is logged: the error's text may hold a URL.
      _log(
        DatabaseLogLevel.error,
        'REST read of ${spec.path} failed: ${error.runtimeType}',
      );
      return _isDropped(read)
          ? const _ReadDropped()
          : const _ReadFailure(_statusUnknown, null);
    } finally {
      _reads.remove(read);
    }
  }

  /// Fetches the tokens (JS: `getToken(false)` on each read, ReadonlyRestClient.ts:189-192),
  /// then sends the request.
  Future<_ReadResult> _fetch(ListenSpec spec, _Read read) async {
    final Future<String?> appCheckToken = _tokens
        .appCheckToken(forceRefresh: false)
        .then(
          (String? token) => token,
          onError: (Object _) {
            _log(
              DatabaseLogLevel.warning,
              'App Check token fetch failed; reading ${spec.path} without App Check',
            );
            return null;
          },
        );
    final String? authToken;
    try {
      authToken = await _tokens.authToken(forceRefresh: false);
    } on Object {
      // The provider's message is not logged (threat model T8).
      _log(
        DatabaseLogLevel.warning,
        'Auth token fetch failed; REST read of ${spec.path} not sent',
      );
      return const _ReadFailure(
        statusNetworkError,
        'The auth token could not be fetched.',
      );
    }
    final _Credentials credentials = _Credentials(
      authToken: _nonEmpty(authToken),
      appCheckToken: _nonEmpty(await appCheckToken),
    );
    if (_isDropped(read)) {
      return const _ReadDropped();
    }
    return _send(spec, read, credentials);
  }

  /// The request of [spec] with [credentials] where the target allows them (T3, T23).
  http.BaseRequest _request(
    ListenSpec spec,
    _Credentials credentials,
    Future<void> abortTrigger,
  ) {
    // Order as JS: query parameters, format, auth, ac (ReadonlyRestClient.ts:189-199).
    final Map<String, String> params = <String, String>{
      ...spec.restParams,
      'format': 'export',
    };
    final bool mayCarry = _target.mayReceiveTokens(
      _target.restUri(spec.path, params),
    );
    if (!mayCarry && credentials.isNotEmpty) {
      _log(
        DatabaseLogLevel.warning,
        'REST read of ${spec.path} sent without credentials: '
        'tokens go only over TLS or to the emulator',
      );
    }
    final String? authToken = mayCarry ? credentials.authToken : null;
    final String? appCheckToken = mayCarry ? credentials.appCheckToken : null;
    if (authToken != null) {
      params['auth'] = authToken;
    }
    if (appCheckToken != null && !_useHeaders) {
      params['ac'] = appCheckToken;
    }
    return http.AbortableRequest(
        'GET',
        _target.restUri(spec.path, params),
        abortTrigger: abortTrigger,
      )
      // A redirect would carry the token in the URL and App Check in a header to another host.
      ..followRedirects = false
      ..headers.addAll(<String, String>{
        if (_useHeaders && appCheckToken != null)
          'X-Firebase-AppCheck': appCheckToken,
      });
  }

  /// Sends the request of [spec] and turns its answer into a result.
  Future<_ReadResult> _send(
    ListenSpec spec,
    _Read read,
    _Credentials credentials,
  ) async {
    final _Attempt attempt = _Attempt(read);
    final http.BaseRequest request = _request(
      spec,
      credentials,
      attempt.aborted,
    );
    _log(
      DatabaseLogLevel.debug,
      credentials.isNotEmpty
          ? 'GET ${spec.path} (contents hidden)'
          : 'GET ${spec.path}',
    );
    try {
      final http.StreamedResponse response = await _sendOnce(request, attempt);
      return await _answer(spec, response, attempt);
    } on TimeoutException {
      return _networkFailure(
        spec,
        'no answer within ${_requestTimeout.inMilliseconds} ms',
      );
    } on _BodyTooLarge {
      _log(
        DatabaseLogLevel.warning,
        'REST read of ${spec.path}: the answer is over $_maxResponseBytes bytes',
      );
      return const _ReadFailure(
        _statusTooBig,
        'The data requested exceeds the maximum size that can be read.',
      );
    } on _Aborted {
      return const _ReadDropped();
    } on http.ClientException catch (error) {
      if (_isDropped(read)) {
        return const _ReadDropped();
      }
      // Never `error.toString()`: it holds the URL with its query (T8).
      final String message = _hideSecrets(
        error.message,
        request.url,
        credentials,
      );
      return _networkFailure(spec, safeServerText(message));
    }
  }

  _ReadResult _networkFailure(ListenSpec spec, String detail) {
    _log(DatabaseLogLevel.warning, 'REST read of ${spec.path} failed: $detail');
    return _ReadFailure(statusNetworkError, 'REST read failed: $detail');
  }

  /// Sends [request]; fails with [TimeoutException] when the headers take longer than the
  /// request timeout and with [_Aborted] when the read is cancelled, whether or not the client
  /// supports `http.Abortable`.
  Future<http.StreamedResponse> _sendOnce(
    http.BaseRequest request,
    _Attempt attempt,
  ) {
    final Completer<http.StreamedResponse> result =
        Completer<http.StreamedResponse>();
    final Timer timer = Timer(_requestTimeout, () {
      if (!result.isCompleted) {
        result.completeError(TimeoutException(null, _requestTimeout));
      }
      attempt.abort();
    });
    unawaited(
      attempt.aborted.then((_) {
        timer.cancel();
        if (!result.isCompleted) {
          result.completeError(const _Aborted());
        }
      }),
    );
    _client
        .send(request)
        .then(
          (http.StreamedResponse response) {
            timer.cancel();
            if (result.isCompleted) {
              _discard(response);
            } else {
              result.complete(response);
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            timer.cancel();
            if (!result.isCompleted) {
              result.completeError(error, stackTrace);
            }
          },
        );
    return result.future;
  }

  /// The result of [response] (ReadonlyRestClient.ts:213-247).
  Future<_ReadResult> _answer(
    ListenSpec spec,
    http.StreamedResponse response,
    _Attempt attempt,
  ) async {
    final int status = response.statusCode;
    if (status >= 200 && status < 300) {
      final int? length = response.contentLength;
      if (length != null && length > _maxResponseBytes) {
        _discard(response);
        throw const _BodyTooLarge();
      }
      final Uint8List body = await _collect(
        response.stream,
        attempt,
        cap: _maxResponseBytes,
        cut: false,
      );
      return _ReadData(_decode(spec.path, body));
    }
    if (status == 404) {
      _discard(response);
      return const _ReadData(null);
    }
    final String? reason = await _errorReason(response, attempt);
    if (status != 401) {
      // 401 and 404 are expected (ReadonlyRestClient.ts:230).
      _log(
        DatabaseLogLevel.warning,
        'REST read of ${spec.path} failed: HTTP $status',
      );
    }
    return _ReadFailure(restListenStatus(status), reason);
  }

  /// The decoded [body], or null with a warning when it is not JSON, nested deeper than the
  /// limit or holding a number that is not finite.
  Object? _decode(String path, Uint8List body) {
    final Object? data;
    try {
      data = jsonDecode(utf8.decode(body));
    } on FormatException {
      _log(
        DatabaseLogLevel.warning,
        'REST read of $path: the answer is not JSON; read as null',
      );
      return null;
    }
    final String? problem = _jsonProblem(data, _maxJsonDepth);
    if (problem != null) {
      _log(
        DatabaseLogLevel.warning,
        'REST read of $path: the answer has $problem; read as null',
      );
      return null;
    }
    return data;
  }

  /// The server's reason in an error body: its `error` field when it is a JSON object with one,
  /// else the text; cut and escaped ([safeServerText]); null when empty or unreadable.
  Future<String?> _errorReason(
    http.StreamedResponse response,
    _Attempt attempt,
  ) async {
    Uint8List bytes;
    try {
      bytes = await _collect(
        response.stream,
        attempt,
        cap: _maxErrorBodyBytes,
        cut: true,
      );
    } on Object {
      // The status is what matters; the reason is only for humans.
      return null;
    }
    if (bytes.length > _maxErrorBodyBytes) {
      bytes = Uint8List.sublistView(bytes, 0, _maxErrorBodyBytes);
    }
    final String text = utf8.decode(bytes, allowMalformed: true).trim();
    if (text.isEmpty) {
      return null;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      decoded = null;
    }
    final String reason = switch (decoded) {
      {'error': final String error} => error,
      _ => text,
    };
    return safeServerText(reason);
  }

  /// Reads [stream] into bytes. Over [cap] bytes it fails with [_BodyTooLarge], or with [cut]
  /// stops and returns what it has (at least [cap] bytes). Fails with [TimeoutException] after a
  /// pause of the request timeout and with [_Aborted] when [attempt] is aborted.
  Future<Uint8List> _collect(
    Stream<List<int>> stream,
    _Attempt attempt, {
    required int cap,
    required bool cut,
  }) {
    final BytesBuilder builder = BytesBuilder(copy: false);
    final Completer<Uint8List> done = Completer<Uint8List>();
    late final StreamSubscription<List<int>> subscription;
    Timer? idle;
    void end(Object? error) {
      if (done.isCompleted) {
        return;
      }
      idle?.cancel();
      unawaited(subscription.cancel());
      if (error == null) {
        done.complete(builder.takeBytes());
      } else {
        done.completeError(error);
      }
    }

    void arm() {
      idle?.cancel();
      idle = Timer(_requestTimeout, () {
        end(TimeoutException(null, _requestTimeout));
        attempt.abort();
      });
    }

    subscription = stream.listen(
      (List<int> chunk) {
        builder.add(chunk);
        if (builder.length <= cap) {
          arm();
        } else {
          end(cut ? null : const _BodyTooLarge());
        }
      },
      onError: (Object error) => end(error),
      onDone: () => end(null),
      cancelOnError: true,
    );
    arm();
    unawaited(attempt.aborted.then((_) => end(const _Aborted())));
    return done.future;
  }

  void _discard(http.StreamedResponse response) {
    unawaited(response.stream.listen(null, onError: (Object _) {}).cancel());
  }

  void _log(DatabaseLogLevel level, String message) {
    _logger?.call(level, message);
  }
}

/// [message] with the URL, its query and the tokens of a request removed (T7, T8).
String _hideSecrets(String message, Uri url, _Credentials credentials) {
  String text = message.replaceAll(url.toString(), '<url hidden>');
  if (url.query.isNotEmpty) {
    text = text.replaceAll(url.query, '<query hidden>');
  }
  for (final String? token in <String?>[
    credentials.authToken,
    credentials.appCheckToken,
  ]) {
    if (token != null) {
      text = text.replaceAll(token, '<token hidden>');
    }
  }
  return text;
}

String? _nonEmpty(String? token) =>
    token == null || token.isEmpty ? null : token;

/// What makes [root] unusable (a nesting deeper than [maxDepth] containers, a number that is
/// not finite), or null. Walks without recursion (threat model rule 4).
String? _jsonProblem(Object? root, int maxDepth) {
  final List<(Object?, int)> stack = <(Object?, int)>[(root, 0)];
  while (stack.isNotEmpty) {
    final (Object? value, int depth) = stack.removeLast();
    switch (value) {
      case final double number when !number.isFinite:
        return 'a number that is not finite';
      case Map<String, Object?>() || List<Object?>() when depth >= maxDepth:
        return 'a nesting deeper than $maxDepth';
      case final Map<String, Object?> map:
        for (final Object? child in map.values) {
          stack.add((child, depth + 1));
        }
      case final List<Object?> list:
        for (final Object? child in list) {
          stack.add((child, depth + 1));
        }
      default:
        break;
    }
  }
  return null;
}

/// The tokens of one read, non-empty or null.
final class _Credentials {
  const _Credentials({required this.authToken, required this.appCheckToken});

  final String? authToken;
  final String? appCheckToken;

  bool get isNotEmpty => authToken != null || appCheckToken != null;

  @override
  String toString() => '_Credentials(contents hidden)';
}

/// One read (a listen or a get), cancelled by [ServerActions.unlisten] or
/// [ServerActions.shutdown].
final class _Read {
  final Completer<void> _cancelled = Completer<void>();

  Future<void> get cancelled => _cancelled.future;

  bool get isCancelled => _cancelled.isCompleted;

  void cancel() {
    if (!_cancelled.isCompleted) {
      _cancelled.complete();
    }
  }
}

/// The HTTP request of one read: aborted by a cancel of the read or a timeout.
final class _Attempt {
  _Attempt(_Read read) {
    unawaited(read.cancelled.then((_) => abort()));
  }

  final Completer<void> _aborted = Completer<void>();

  Future<void> get aborted => _aborted.future;

  void abort() {
    if (!_aborted.isCompleted) {
      _aborted.complete();
    }
  }
}

sealed class _ReadResult {
  const _ReadResult();
}

final class _ReadData extends _ReadResult {
  const _ReadData(this.data);

  final Object? data;
}

final class _ReadFailure extends _ReadResult {
  const _ReadFailure(this.status, this.reason);

  final String status;
  final String? reason;
}

final class _ReadDropped extends _ReadResult {
  const _ReadDropped();
}

/// A success body over `maxResponseBytes`.
final class _BodyTooLarge implements Exception {
  const _BodyTooLarge();
}

/// The read was cancelled while its request was in flight.
final class _Aborted implements Exception {
  const _Aborted();
}
