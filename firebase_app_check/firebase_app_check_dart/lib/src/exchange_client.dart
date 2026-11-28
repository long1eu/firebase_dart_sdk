import 'dart:async';
import 'dart:convert';

import 'package:_firebase_transport_dart/_firebase_transport_dart.dart';
import 'package:firebase_app_check_dart/src/app_check_token.dart';
import 'package:firebase_app_check_dart/src/clocks.dart';
import 'package:firebase_app_check_dart/src/exception.dart';
import 'package:firebase_app_check_dart/src/ttl.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

final RegExp _apiKeyPattern = RegExp(r'^A[A-Za-z0-9_-]{38}$');
final RegExp _appIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9:._-]{0,127}$');
final RegExp _projectIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$');
final RegExp _serverStatusPattern = RegExp(r'^[A-Z_]{1,64}$');

/// The cap on a 2xx body, and the bytes kept of any other body.
const int _bodyCap = 16384;

/// The deadline of one exchange, from the send to the end of the body. With the 8 s of the seam
/// and the 10 s of the callers it is one set that changes together.
const Duration _exchangeDeadline = Duration(seconds: 7);

/// Sends the debug-token exchange: one HTTPS POST that trades a debug token for an App Check
/// token.
///
/// The debug token travels only in the body of that request and the API key only in its
/// `X-Goog-Api-Key` header, both only to the origin given to the constructor. Neither appears in
/// an exception.
@internal
final class ExchangeClient {
  /// A client that posts to [origin] for the app of [projectId] and [appId], with [apiKey].
  ///
  /// [origin] must pass `checkOrigin`. An empty [projectId], [appId] or [apiKey] is accepted here
  /// and refused by [exchange]; a malformed one is an [ArgumentError], as in [checkOptions].
  /// [client] is not closed by this class. Completing [closed] aborts a request in flight.
  ExchangeClient({
    required http.Client client,
    required Uri origin,
    required String projectId,
    required String appId,
    required String apiKey,
    required Clocks clocks,
    required Future<void> closed,
  }) : _client = client,
       _origin = checkOrigin(origin),
       _projectId = projectId,
       _appId = appId,
       _apiKey = apiKey,
       _clocks = clocks,
       _closed = closed {
    _checkWellFormed(apiKey: apiKey, appId: appId, projectId: projectId);
    closed.whenComplete(() => _isClosed = true).ignore();
  }

  final http.Client _client;
  final Uri _origin;
  final String _projectId;
  final String _appId;
  final String _apiKey;
  final Clocks _clocks;
  final Future<void> _closed;
  bool _isClosed = false;

  /// Throws an [ArgumentError] when `apiKey`, `appId` or `projectId` of [options] is present but
  /// malformed. The error names the option and never its value. A missing or empty option passes:
  /// [exchange] refuses it.
  static void checkOptions(FirebaseOptions options) {
    _checkWellFormed(
      apiKey: options.apiKey,
      appId: options.appId,
      projectId: options.projectId ?? '',
    );
  }

  /// Exchanges [debugToken] for a session token, or with [limitedUse] for a limited-use token.
  ///
  /// The result is issued at the readings both clocks gave before the request was sent, so a token
  /// is never believed to live longer than it does.
  ///
  /// Throws a [StateError] before any request when an option is missing or empty. Throws a
  /// [FirebaseAppCheckException] without `retryAfter`: `fetch-network-error`, `fetch-timeout`,
  /// `fetch-status-error`, `fetch-parse-error`, or `app-check-closed` when the close signal
  /// completed before or during the request.
  Future<SessionToken> exchange({
    required String debugToken,
    required bool limitedUse,
  }) async {
    _checkPresent();
    if (_isClosed) {
      throw appCheckClosed();
    }
    final DateTime issuedWall = _clocks.wallNow();
    final Duration issuedMono = _clocks.monoNow();
    final CappedResponse response = await _send(debugToken, limitedUse);
    if (response.statusCode != 200) {
      throw _statusError(response, debugToken);
    }
    final ({String token, Duration ttl}) answer = _parseAnswer(response.body);
    return SessionToken(
      token: answer.token,
      issuedWall: issuedWall,
      issuedMono: issuedMono,
      ttl: answer.ttl,
    );
  }

  void _checkPresent() {
    final String? missing = _apiKey.isEmpty
        ? 'apiKey'
        : _appId.isEmpty
        ? 'appId'
        : _projectId.isEmpty
        ? 'projectId'
        : null;
    if (missing != null) {
      throw StateError(
        'FirebaseOptions.$missing is missing; the App Check debug provider '
        'needs it.',
      );
    }
  }

  Future<CappedResponse> _send(String debugToken, bool limitedUse) async {
    final Uri url = _origin.replace(
      pathSegments: <String>[
        'v1',
        'projects',
        _projectId,
        'apps',
        '$_appId:exchangeDebugToken',
      ],
    );
    final List<int> body = utf8.encode(
      jsonEncode(<String, Object>{
        'debug_token': debugToken,
        if (limitedUse) 'limited_use': true,
      }),
    );
    try {
      return await sendCapped(
        _client,
        (Future<void> abort) =>
            http.AbortableRequest('POST', url, abortTrigger: abort)
              ..headers['Content-Type'] = 'application/json'
              ..headers[FirebaseHeaders.apiKey] = _apiKey
              ..bodyBytes = body,
        successCap: _bodyCap,
        errorCap: _bodyCap,
        deadline: _exchangeDeadline,
        cancel: _closed,
      );
    } on TransportException catch (error) {
      // The transport's exception is not kept as a cause: none of its types may reach a caller.
      throw _transportError(error.failure);
    } on TimeoutException {
      throw fetchTimeout();
    } on CapExceededException {
      throw fetchParseError(ParseProblem.oversizedBody);
    }
  }

  FirebaseAppCheckException _transportError(TransportFailure failure) {
    switch (failure) {
      case TransportFailure.network:
      case TransportFailure.redirected:
        return fetchNetworkError();
      case TransportFailure.cancelled:
        // An abort the close signal did not cause (a client that reports one by itself) is a
        // failure of the network like any other.
        return _isClosed ? appCheckClosed() : fetchNetworkError();
    }
  }

  /// The `fetch-status-error` for [response], whose body is read leniently: a body of another
  /// shape than `{"error": {"status", "message"}}` gives nulls.
  FirebaseAppCheckException _statusError(
    CappedResponse response,
    String debugToken,
  ) {
    final Object? error = _errorObject(response.body);
    final Object? status = error is Map ? error['status'] : null;
    final Object? message = error is Map ? error['message'] : null;
    return fetchStatusError(
      httpStatus: response.statusCode,
      serverStatus: status is String && _serverStatusPattern.hasMatch(status)
          ? status
          : null,
      serverMessage: message is String
          ? _redactedMessage(message, debugToken)
          : null,
    );
  }

  static Object? _errorObject(List<int> body) {
    try {
      final Object? decoded = decodeGuardedBytes(body);
      return decoded is Map ? decoded['error'] : null;
    } on FormatException {
      // Not JSON (or cut at the cap): the status alone is reported.
      return null;
    }
  }

  /// [message] with control characters removed, every occurrence of [debugToken] (ignoring case)
  /// replaced by `<redacted>`, cut to 1 KiB.
  ///
  /// The control characters go first so that none of them can split an echoed token and make it
  /// escape the match; the cut comes last so that it cannot leave the start of a token.
  static String _redactedMessage(String message, String debugToken) {
    final String plain = String.fromCharCodes(
      message.runes.where(
        (int rune) => !(rune < 0x20 || (rune >= 0x7f && rune <= 0x9f)),
      ),
    );
    final RegExp echoed = RegExp(
      RegExp.escape(debugToken),
      caseSensitive: false,
    );
    return sanitizeServerText(plain.replaceAll(echoed, '<redacted>'));
  }

  static ({String token, Duration ttl}) _parseAnswer(List<int> body) {
    final Object? decoded;
    try {
      decoded = decodeGuardedBytes(body);
    } on FormatException {
      throw fetchParseError(ParseProblem.notJson);
    }
    final Map<Object?, Object?> fields = decoded is Map
        ? decoded
        : const <Object?, Object?>{};
    final Object? token = fields['token'];
    if (token is! String) {
      throw fetchParseError(ParseProblem.noToken);
    }
    if (!isTokenText(token)) {
      throw fetchParseError(ParseProblem.invalidToken);
    }
    final Duration? ttl = parseTtl(fields['ttl']);
    if (ttl == null) {
      throw fetchParseError(ParseProblem.invalidTtl);
    }
    return (token: token, ttl: ttl);
  }

  static void _checkWellFormed({
    required String apiKey,
    required String appId,
    required String projectId,
  }) {
    if (apiKey.isNotEmpty && !_apiKeyPattern.hasMatch(apiKey)) {
      throw ArgumentError(
        'is not a Firebase API key: "A" and 38 letters, digits, "_" or "-"',
        'FirebaseOptions.apiKey',
      );
    }
    if (appId.isNotEmpty &&
        !(_appIdPattern.hasMatch(appId) && appId.contains(':'))) {
      throw ArgumentError(
        'is not a Firebase app id of the form 1:<number>:<platform>:<hash>',
        'FirebaseOptions.appId',
      );
    }
    if (projectId.isNotEmpty && !_projectIdPattern.hasMatch(projectId)) {
      throw ArgumentError(
        'is not a project id: 1 to 128 letters, digits, ".", "_", ":" or "-"',
        'FirebaseOptions.projectId',
      );
    }
  }

  @override
  String toString() => 'ExchangeClient(${_origin.host})';
}
