import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_installations_dart/src/bounded.dart';
import 'package:firebase_installations_dart/src/exception.dart';
import 'package:firebase_installations_dart/src/fid.dart';
import 'package:firebase_installations_dart/src/http_rules.dart';
import 'package:firebase_installations_dart/src/record.dart';
import 'package:firebase_installations_dart/src/version.dart';
import 'package:http/http.dart' as http;

/// The largest 2xx body read: 64 KiB.
const int _successCap = 64 * 1024;

/// The largest error body read: 16 KiB.
const int _errorCap = 16 * 1024;

/// The deadline of one HTTP attempt.
const Duration requestDeadline = Duration(seconds: 10);

/// The wait before the one retry after a 5xx or a transport error.
const Duration _retryDelay = Duration(seconds: 1);

final RegExp _expiresInPattern = RegExp(r'^([0-9]{1,9})s$');

/// The longest token lifetime accepted from the server: 400 days, in seconds.
const int _maxExpiresInSeconds = 400 * 24 * 60 * 60;

/// An installation the server registered.
final class RegisteredInstallation {
  /// The [fid] the server keeps, its [refreshToken] and first auth [token].
  const RegisteredInstallation({
    required this.fid,
    required this.refreshToken,
    required this.token,
  });

  /// The FID the server keeps (it may differ from the one sent).
  final String fid;

  /// The refresh token.
  final String refreshToken;

  /// The first auth token.
  final AuthTokenResult token;

  @override
  String toString() => 'RegisteredInstallation(<redacted>)';
}

/// An auth token from the server.
final class AuthTokenResult {
  /// A [token] living [expiresIn] from [createdAt].
  const AuthTokenResult({
    required this.token,
    required this.expiresIn,
    required this.createdAt,
  });

  /// The auth token.
  final String token;

  /// How long the token lives from [createdAt].
  final Duration expiresIn;

  /// The clock when the response was parsed.
  final DateTime createdAt;

  @override
  String toString() => 'AuthTokenResult(<redacted>)';
}

/// The REST client of the Firebase Installations API (`/v1/projects/{projectId}/installations`).
///
/// Each call sends at most two attempts: one retry after 1 s on a 5xx or a transport error.
/// `beforeAttempt`, when given, runs before each attempt (the caller re-stamps its marker there).
///
/// Statuses map to error codes per endpoint: 400 and 403 are `bad-config`; 401 and 404 are `bad-config`
/// on create (the project or the key is wrong: no installation exists yet) and `installation-not-found`
/// on generate; 429 is `too-many-requests`; 5xx is `unavailable`; a 3xx and any other 4xx (405, 408,
/// 409, 410 and so on) are `invalid-response`: they say nothing about the app's configuration.
final class InstallationsRestClient {
  /// A client sending to `origin` (already checked) with the app's `apiKey`, `projectId` and `appId`.
  InstallationsRestClient({
    required http.Client client,
    required Uri origin,
    required String apiKey,
    required String projectId,
    required String appId,
    required Map<String, String> headers,
    required DateTime Function() clock,
    required Future<void> Function(Duration duration) delay,
  }) : _client = client,
       _origin = origin,
       _apiKey = apiKey,
       _projectId = projectId,
       _appId = appId,
       _headers = headers,
       _clock = clock,
       _delay = delay;

  final http.Client _client;
  final Uri _origin;
  final String _apiKey;
  final String _projectId;
  final String _appId;
  final Map<String, String> _headers;
  final DateTime Function() _clock;
  final Future<void> Function(Duration duration) _delay;

  /// Registers [fid] (`POST /installations`).
  Future<RegisteredInstallation> create(
    String fid, {
    Future<void> Function()? beforeAttempt,
  }) async {
    final CappedResponse response = await _send(
      'POST',
      <String>['installations'],
      body: <String, Object?>{
        'fid': fid,
        'authVersion': 'FIS_v2',
        'appId': _appId,
        'sdkVersion': 'd:$packageVersion',
      },
      beforeAttempt: beforeAttempt,
    );
    if (!response.isSuccess) {
      throw _errorFor(response, create: true);
    }
    final Map<String, Object?> json = _decodeObject(response);
    final Object? serverFid = json['fid'];
    final Object? refreshToken = json['refreshToken'];
    final Object? authToken = json['authToken'];
    if ((serverFid != null &&
            (serverFid is! String || !isValidFid(serverFid))) ||
        refreshToken is! String ||
        !isValidTokenText(refreshToken) ||
        authToken is! Map<String, Object?>) {
      throw _invalidResponse(response.statusCode);
    }
    return RegisteredInstallation(
      fid: serverFid is String ? serverFid : fid,
      refreshToken: refreshToken,
      token: _tokenFrom(authToken, response.statusCode),
    );
  }

  /// A new auth token for [fid] (`POST /installations/{fid}/authTokens:generate`).
  Future<AuthTokenResult> generateAuthToken(
    String fid,
    String refreshToken, {
    Future<void> Function()? beforeAttempt,
  }) async {
    final CappedResponse response = await _send(
      'POST',
      <String>['installations', _checkedFid(fid), 'authTokens:generate'],
      body: <String, Object?>{
        'installation': <String, Object?>{'sdkVersion': 'd:$packageVersion'},
      },
      refreshToken: refreshToken,
      beforeAttempt: beforeAttempt,
    );
    if (!response.isSuccess) {
      throw _errorFor(response, create: false);
    }
    return _tokenFrom(_decodeObject(response), response.statusCode);
  }

  /// Deletes [fid] (`DELETE /installations/{fid}`). 200, 401 and 404 count as done.
  Future<void> delete(
    String fid,
    String refreshToken, {
    Future<void> Function()? beforeAttempt,
  }) async {
    final CappedResponse response = await _send(
      'DELETE',
      <String>['installations', _checkedFid(fid)],
      refreshToken: refreshToken,
      beforeAttempt: beforeAttempt,
    );
    final int status = response.statusCode;
    if (response.isSuccess || status == 401 || status == 404) {
      return;
    }
    throw _errorFor(response, create: false);
  }

  String _checkedFid(String fid) {
    if (!isValidFid(fid)) {
      throw ArgumentError.value('<redacted>', 'fid', 'is not a valid FID');
    }
    return fid;
  }

  Future<CappedResponse> _send(
    String method,
    List<String> path, {
    Map<String, Object?>? body,
    String? refreshToken,
    Future<void> Function()? beforeAttempt,
  }) async {
    final Uri url = _origin.replace(
      pathSegments: <String>['v1', 'projects', _projectId, ...path],
    );
    final Uint8List? bytes = body == null
        ? null
        : Uint8List.fromList(utf8.encode(jsonEncode(body)));
    for (int attempt = 0; ; attempt++) {
      if (beforeAttempt != null) {
        await beforeAttempt();
      }
      final CappedResponse response;
      try {
        response = await sendCapped(
          _client,
          (Future<void> abort) =>
              _request(method, url, abort, bytes, refreshToken),
          successCap: _successCap,
          errorCap: _errorCap,
          deadline: requestDeadline,
        );
      } on CapExceededException {
        throw _invalidResponse(
          null,
          'The response of the server is too large.',
        );
      } on Exception catch (error, stackTrace) {
        if (attempt == 0) {
          await _delay(_retryDelay);
          continue;
        }
        throw FirebaseInstallationsException(
          code: 'network-error',
          message: error is TimeoutException
              ? 'The Firebase Installations request took longer than 10 s.'
              : 'Could not reach the Firebase Installations server.',
          cause: error,
          stackTrace: stackTrace,
        );
      }
      if (response.statusCode >= 500 &&
          response.statusCode < 600 &&
          attempt == 0) {
        await _delay(_retryDelay);
        continue;
      }
      return response;
    }
  }

  http.BaseRequest _request(
    String method,
    Uri url,
    Future<void> abort,
    Uint8List? body,
    String? refreshToken,
  ) {
    final http.AbortableRequest request = http.AbortableRequest(
      method,
      url,
      abortTrigger: abort,
    );
    request.headers.addAll(_headers);
    request.headers['Accept'] = 'application/json';
    request.headers['x-goog-api-key'] = _apiKey;
    if (refreshToken != null) {
      request.headers['Authorization'] = 'FIS_v2 $refreshToken';
    }
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.bodyBytes = body;
    }
    return request;
  }

  AuthTokenResult _tokenFrom(Map<String, Object?> json, int status) {
    final Object? token = json['token'];
    final Object? expiresIn = json['expiresIn'];
    if (token is! String || !isValidTokenText(token) || expiresIn is! String) {
      throw _invalidResponse(status);
    }
    final RegExpMatch? match = _expiresInPattern.firstMatch(expiresIn);
    final int? seconds = parseBoundedInt(
      match?.group(1),
      min: 1,
      max: _maxExpiresInSeconds,
    );
    if (seconds == null) {
      throw _invalidResponse(status);
    }
    return AuthTokenResult(
      token: token,
      expiresIn: Duration(seconds: seconds),
      createdAt: _clock(),
    );
  }

  Map<String, Object?> _decodeObject(CappedResponse response) {
    try {
      final Object? json = jsonDecode(utf8.decode(response.body));
      if (json is Map<String, Object?>) {
        return json;
      }
    } on FormatException {
      // Reported below.
    }
    throw _invalidResponse(response.statusCode);
  }

  FirebaseInstallationsException _invalidResponse(
    int? status, [
    String message =
        'The response of the Firebase Installations server could not be read.',
  ]) => FirebaseInstallationsException(
    code: 'invalid-response',
    message: message,
    httpStatus: status,
  );

  /// The error of a non-2xx [response]; [create] says whether it answers a create request.
  FirebaseInstallationsException _errorFor(
    CappedResponse response, {
    required bool create,
  }) {
    final int status = response.statusCode;
    if (status < 400) {
      return _invalidResponse(
        status,
        'The Firebase Installations server answered with an unexpected status.',
      );
    }
    final _ServerError error = _ServerError.parse(response.body);
    final (String code, String message) = switch (status) {
      400 || 403 => (
        'bad-config',
        'The Firebase Installations server refused the app configuration '
            '(check the API key, its restrictions and the app id).',
      ),
      401 || 404 when create => (
        'bad-config',
        'The Firebase Installations server refused to register the installation '
            '(check the project id, the API key and the app id).',
      ),
      401 || 404 => (
        'installation-not-found',
        'The Firebase Installations server does not know this installation.',
      ),
      429 => (
        'too-many-requests',
        'The Firebase Installations server received too many requests.',
      ),
      >= 500 => (
        'unavailable',
        'The Firebase Installations server is unavailable.',
      ),
      _ => (
        'invalid-response',
        'The Firebase Installations server answered with an unexpected status.',
      ),
    };
    return FirebaseInstallationsException(
      code: code,
      message: message,
      httpStatus: status,
      serverStatus: error.status,
      serverMessage: error.message,
    );
  }
}

/// The `status` and `message` of an error body: `{"error": {"code", "status", "message"}}` or
/// `{"error": "<string>"}`. A body that is neither gives nulls.
final class _ServerError {
  const _ServerError(this.status, this.message);

  final String? status;
  final String? message;

  static _ServerError parse(Uint8List body) {
    final Object? json;
    try {
      json = jsonDecode(decodeUtf8Lenient(body));
    } on FormatException {
      return const _ServerError(null, null);
    }
    final Object? error = json is Map<String, Object?> ? json['error'] : null;
    if (error is String) {
      return _ServerError(null, sanitizeServerText(error));
    }
    if (error is Map<String, Object?>) {
      final Object? status = error['status'];
      final Object? message = error['message'];
      return _ServerError(
        status is String ? sanitizeServerText(status) : null,
        message is String ? sanitizeServerText(message) : null,
      );
    }
    return const _ServerError(null, null);
  }
}
