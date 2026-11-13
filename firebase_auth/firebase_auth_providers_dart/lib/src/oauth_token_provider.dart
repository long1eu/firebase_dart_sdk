import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:googleapis_auth/googleapis_auth.dart' as gapi;
import 'package:http/http.dart' as http;

import 'auth_exception.dart';
import 'rs256.dart';

/// An OAuth 2.0 access token and when it expires.
class OAuthAccessToken {
  /// Creates a token that is valid until [expiry].
  const OAuthAccessToken(this.token, this.expiry);

  /// The access token.
  final String token;

  /// When the token stops being valid.
  final DateTime expiry;

  @override
  String toString() => 'OAuthAccessToken(<redacted>, expiry: $expiry)';
}

/// A token provider for servers and command line tools: it hands out Google OAuth 2.0 access tokens (of a service
/// account, or of Application Default Credentials) and gets a new one before the current one expires.
///
/// **These credentials bypass security rules.** A request made with the access token of a service account or of a
/// developer is authorized by IAM (for Firestore: the `Cloud Datastore User` role), not by the security rules of
/// the database, and `request.auth` is not a Firebase user. Use it on trusted machines only; in an application
/// that end users run, use [FirebaseUserAuth].
///
/// Use it by handing it to the app before the Firestore instance is created:
///
/// ```dart
/// final app = FirebaseApp.withOptions(options);
/// app.authProvider = OAuthTokenProvider.serviceAccount(jsonDecode(keyFileContents));
/// final firestore = await Firestore.instanceFor(app: app);
/// ```
///
/// There is no user: [uid] is null, and [onTokenChanged] never emits (a new token is picked up by the next
/// request; open streams keep the token they started with, as the backend allows).
class OAuthTokenProvider implements InternalTokenProvider {
  /// Creates a provider on top of [fetch], which obtains a new access token.
  ///
  /// A token is reused until it is within [refreshBefore] of its expiry. [clock] is for tests.
  OAuthTokenProvider(
    Future<OAuthAccessToken> Function() fetch, {
    this.refreshBefore = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) : _fetch = fetch,
       _clock = clock ?? DateTime.now;

  /// A provider for the service account described by [json]: the decoded content of a service account key file
  /// (a `Map`), or the content itself (a `String`).
  ///
  /// The key never leaves the process: it signs a short-lived assertion (RS256) that is exchanged for an access
  /// token at Google's token endpoint ([tokenUri] replaces the endpoint, for tests). [scopes] defaults to
  /// [datastoreScopes]. [httpClient] is used for the token requests and is not closed by the provider; without it
  /// a client is created per request.
  ///
  /// Throws an [ArgumentError] if [json] is not a service account key.
  factory OAuthTokenProvider.serviceAccount(
    Object json, {
    List<String> scopes = datastoreScopes,
    http.Client? httpClient,
    Duration refreshBefore = const Duration(minutes: 5),
    DateTime Function()? clock,
    Uri? tokenUri,
  }) {
    final Uri endpoint = tokenUri ?? googleTokenUri;
    final gapi.ServiceAccountCredentials credentials;
    try {
      credentials = gapi.ServiceAccountCredentials.fromJson(json);
    } on Object {
      // The original error may quote the input, which holds the private key.
      throw ArgumentError(
        'Not a service account key: expected the JSON of a key file with "type": "service_account", '
        '"client_email", "client_id" and "private_key".',
      );
    }
    final DateTime Function() now = clock ?? DateTime.now;
    return OAuthTokenProvider(
      () async {
        final http.Client client = httpClient ?? http.Client();
        try {
          return await _jwtBearer(credentials, scopes, client, now, endpoint);
        } finally {
          if (httpClient == null) {
            client.close();
          }
        }
      },
      refreshBefore: refreshBefore,
      clock: clock,
    );
  }

  /// Google's OAuth 2.0 token endpoint.
  static final Uri googleTokenUri = Uri.parse(
    'https://oauth2.googleapis.com/token',
  );

  /// The JWT bearer flow (RFC 7523) of a service account: a self-signed assertion is exchanged for an access token.
  static Future<OAuthAccessToken> _jwtBearer(
    gapi.ServiceAccountCredentials credentials,
    List<String> scopes,
    http.Client client,
    DateTime Function() now,
    Uri tokenUri,
  ) async {
    String encode(List<int> bytes) =>
        base64Url.encode(bytes).replaceAll('=', '');
    final DateTime issuedAt = now();
    // A little in the past, for clocks that are slightly ahead of Google's.
    final int iat = issuedAt.millisecondsSinceEpoch ~/ 1000 - 20;
    final String input =
        '${encode(utf8.encode(jsonEncode(<String, Object?>{'alg': 'RS256', 'typ': 'JWT'})))}.'
        '${encode(utf8.encode(jsonEncode(<String, Object?>{'iss': credentials.email, 'scope': scopes.join(' '), 'aud': googleTokenUri.toString(), 'iat': iat, 'exp': iat + 3600})))}';
    // The type of the key is not exported by every supported version of googleapis_auth.
    // ignore: always_specify_types
    final key = credentials.privateRSAKey;
    final Uint8List signature = signRs256(
      ascii.encode(input),
      n: key.n,
      e: key.e,
      p: key.p,
      q: key.q,
      dmp1: key.dmp1,
      dmq1: key.dmq1,
      coeff: key.coeff,
    );
    final String assertion = '$input.${encode(signature)}';

    final http.Response response;
    try {
      response = await client.post(
        tokenUri,
        body: <String, String>{
          'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
          'assertion': assertion,
        },
      );
    } on Object catch (_) {
      throw const FirebaseAuthProviderException(
        'network-request-failed',
        'The request to the token endpoint failed (network error).',
      );
    }
    Object? body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      body = null;
    }
    if (response.statusCode == 200 &&
        body is Map<String, Object?> &&
        body['access_token'] is String) {
      final Object? expiresIn = body['expires_in'];
      return OAuthAccessToken(
        body['access_token']! as String,
        issuedAt.add(
          Duration(seconds: expiresIn is num ? expiresIn.toInt() : 3600),
        ),
      );
    }
    // For example {"error": "invalid_grant", "error_description": "Invalid JWT Signature."}.
    final Object? error = body is Map<String, Object?> ? body['error'] : null;
    final Object? description = body is Map<String, Object?>
        ? body['error_description']
        : null;
    throw FirebaseAuthProviderException(
      error == 'invalid_grant' ? 'invalid-credential' : 'internal-error',
      'The token endpoint refused the service account'
      '${error is String ? ' ($error${description is String ? ': $description' : ''})' : ''}.',
      serverCode: error is String ? error : null,
      httpStatus: response.statusCode,
    );
  }

  /// The scopes Firestore needs.
  static const List<String> datastoreScopes = <String>[
    'https://www.googleapis.com/auth/datastore',
  ];

  final Future<OAuthAccessToken> Function() _fetch;
  final DateTime Function() _clock;

  /// How long before its expiry a token is replaced.
  final Duration refreshBefore;

  OAuthAccessToken? _current;
  Future<OAuthAccessToken>? _pending;

  bool _isFresh(OAuthAccessToken token) =>
      _clock().add(refreshBefore).isBefore(token.expiry);

  @override
  Future<GetTokenResult> getAccessToken({required bool forceRefresh}) async {
    final OAuthAccessToken? current = _current;
    if (!forceRefresh && current != null && _isFresh(current)) {
      return GetTokenResult(current.token);
    }
    // One request at a time: callers that arrive while a token is being fetched share it.
    final Future<OAuthAccessToken> pending = _pending ??= _fetch()
        .then((OAuthAccessToken token) {
          _current = token;
          return token;
        })
        .whenComplete(() => _pending = null);
    return GetTokenResult((await pending).token);
  }

  /// Always null: an access token of a service account is not a Firebase user.
  @override
  String? get uid => null;

  /// Never emits (see the class comment).
  @override
  Stream<InternalTokenResult> get onTokenChanged =>
      const Stream<InternalTokenResult>.empty();
}
