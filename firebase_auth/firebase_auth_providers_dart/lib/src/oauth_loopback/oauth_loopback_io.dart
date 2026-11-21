import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:secure_flow/secure_flow.dart';

import '../auth_exception.dart';
import '../secure_flow_errors.dart';
import '../secure_random.dart';
import 'oauth_loopback.dart';

/// Signs the user in to [provider] in the system browser and returns the provider's tokens with a
/// ready credential (RFC 8252, "OAuth 2.0 for Native Apps"). VM only: on the web it throws an
/// [UnsupportedError].
///
/// 1. An [OAuthFlow] of `package:secure_flow` carries the request: an authorization code request
///    with PKCE (S256), a random `state` and, with [OAuthLoopbackProvider.useNonce], a nonce. It
///    runs with [presenter], or without one with the presenter of [environment]
///    ([SecureEnvironment.current] when null) that it ranks best: a [ProviderAppPresenter]
///    registered for [OAuthLoopbackProvider.providerId], the system browser, an in-app browser,
///    the console (the URL on stderr). A web view is refused. On Flutter mobile pass a
///    [CallbackPresenter] of your own (`url_launcher`'s `launchUrl`).
///
///    A provider app returns the provider's tokens itself ([OAuthTokens]): no server and no code
///    exchange; the nonce claim of its ID token is checked as below, and the credential carries
///    the raw nonce when [OAuthLoopbackProvider.sendNonceToFirebase] is set. The other presenters
///    show the authorization URL; the redirect comes back to a one-shot HTTP server bound to
///    127.0.0.1 (never to another interface), on [OAuthLoopbackProvider.port] (any free port by
///    default).
/// 2. The first GET on the redirect path whose `Host` header is `127.0.0.1:<port>` and whose
///    `state` is the one sent (compared in constant time) ends the wait. A request with another
///    host, a missing or wrong state, or a query that does not parse gets a 400 and does not end
///    the wait; requests to other paths get a 404. Then an `error` of the provider is reported, or
///    the code is exchanged at the token endpoint or by the provider's `exchangeCode` (see
///    [OAuthLoopbackProvider]), each with a 30 second limit. The browser gets a short page that
///    says whether it worked.
/// 3. The server is closed in every case: success, error, [timeout] (default five minutes) or a
///    presenter that throws.
///
/// [httpClient] is used for the code exchange and is not closed; without it one is created and
/// closed.
///
/// Throws a [FirebaseAuthException]:
///
/// | Code | When |
/// | --- | --- |
/// | `timeout` | no redirect of this sign-in came back within [timeout] |
/// | `user-cancelled` | the provider answered `access_denied` (the user refused) |
/// | `invalid-oauth-response` | the provider answered another `error` ([FirebaseAuthException.serverCode]), no code, or no token |
/// | `missing-or-invalid-nonce` | the ID token carries another nonce than the one sent |
/// | `invalid-credential` | the token endpoint or `exchangeCode` refused the code ([FirebaseAuthException.serverCode] is its `error`) |
/// | `network-request-failed` | the token endpoint could not be reached, or it or `exchangeCode` did not answer within 30 seconds |
///
/// A [SecureFlowRefused] (a presenter that shows pages inside the app), a [SecureFlowNoPresenter]
/// (no default presenter for the environment) and an error of [presenter] are rethrown as they are.
/// Nothing of the flow is logged; the tokens are never part of an exception message.
///
/// The ID token is not verified here: its signature, issuer and audience are checked by Firebase
/// when the credential signs in. Do not trust its claims before that.
///
/// On a machine shared with other users, another local user can read the authorization URL from the
/// list of processes while the browser opens. This is inherent to loopback flows (RFC 8252); PKCE
/// keeps the code useless to them.
///
/// ```dart
/// final OAuthLoopbackResult result = await authorizeWithOAuthLoopback(
///   OAuthLoopbackProvider.google(clientId: clientId, clientSecret: clientSecret),
/// );
/// await auth.signInWithCredential(result.credential);
/// ```
Future<OAuthLoopbackResult> authorizeWithOAuthLoopback(
  OAuthLoopbackProvider provider, {
  SecurePresenter? presenter,
  SecureEnvironment? environment,
  Duration timeout = const Duration(minutes: 5),
  http.Client? httpClient,
}) async {
  final String state = randomUnreservedString();
  final String codeVerifier = randomUnreservedString(64);
  final String? rawNonce = provider.useNonce ? randomUnreservedString() : null;
  final String? hashedNonce = rawNonce == null ? null : _sha256Hex(rawNonce);

  final OAuthFlow flow = OAuthFlow(
    providerId: provider.providerId,
    scopes: provider.scopes,
    rawNonce: rawNonce,
    hashedNonce: hashedNonce,
    authorizationUrl: (String redirectUri) =>
        provider.authorizationEndpoint.replace(
          queryParameters: <String, String>{
            ...provider.authorizationEndpoint.queryParameters,
            ...provider.customParameters,
            'client_id': provider.clientId,
            'redirect_uri': redirectUri,
            'response_type': 'code',
            'scope': provider.scopes.join(' '),
            'state': state,
            'code_challenge': _codeChallenge(codeVerifier),
            'code_challenge_method': 'S256',
            'nonce': ?hashedNonce,
          },
        ),
    state: state,
    redirectPath: provider.redirectPath,
    port: provider.port,
    donePage: const SecurePage.message(
      title: 'Signed in',
      text:
          'You are signed in. You can close this window and return to the app.',
    ),
  );
  return runSecureFlow<OAuthLoopbackResult>(
    flow.map(
      (OAuthResult result) => switch (result) {
        OAuthRedirect(
          :final Map<String, String> parameters,
          :final String redirectUri,
        ) =>
          _complete(
            provider,
            parameters,
            codeVerifier: codeVerifier,
            redirectUrl: redirectUri,
            rawNonce: rawNonce,
            hashedNonce: hashedNonce,
            httpClient: httpClient,
          ),
        OAuthTokens(:final String? idToken, :final String? accessToken) =>
          _fromTokens(
            provider,
            idToken: idToken,
            accessToken: accessToken,
            rawNonce: rawNonce,
            hashedNonce: hashedNonce,
          ),
      },
    ),
    presenter: presenter,
    environment: environment,
    timeout: timeout,
    timeoutMessage:
        'No sign-in redirect came back within ${timeout.inSeconds} seconds.',
  );
}

Future<OAuthLoopbackResult> _complete(
  OAuthLoopbackProvider provider,
  Map<String, String> response, {
  required String codeVerifier,
  required String redirectUrl,
  required String? rawNonce,
  required String? hashedNonce,
  required http.Client? httpClient,
}) async {
  final String? error = response['error'];
  if (error != null) {
    // The value comes from the address bar: only a short code goes into the exception.
    final String? serverCode = _shortText(error);
    throw FirebaseAuthException(
      code: error == 'access_denied'
          ? 'user-cancelled'
          : 'invalid-oauth-response',
      serverCode: serverCode,
      message: error == 'access_denied'
          ? 'The user did not grant the requested permissions.'
          : 'The provider answered with an error'
                '${serverCode == null ? '' : ' ($serverCode)'}.',
    );
  }
  final String? code = response['code'];
  if (code == null || code.isEmpty) {
    throw const FirebaseAuthException(
      code: 'invalid-oauth-response',
      message: 'The sign-in redirect carried no authorization code.',
    );
  }

  final http.Client client = httpClient ?? http.Client();
  final Map<String, Object?> tokens;
  try {
    tokens = await _exchange(
      provider,
      client,
      code: code,
      codeVerifier: codeVerifier,
      redirectUrl: redirectUrl,
    );
  } finally {
    if (httpClient == null) {
      client.close();
    }
  }

  final String? idToken = _nonEmptyString(tokens['id_token']);
  final String? accessToken = _nonEmptyString(tokens['access_token']);
  if (idToken == null && accessToken == null) {
    throw const FirebaseAuthException(
      code: 'invalid-oauth-response',
      message:
          'The code exchange returned neither an ID token nor an access token.',
    );
  }
  _checkNonce(idToken, hashedNonce);
  final Object? scope = tokens['scope'];
  return OAuthLoopbackResult(
    credential: provider.credentialFor(
      idToken: idToken,
      accessToken: accessToken,
      rawNonce: rawNonce,
    ),
    idToken: idToken,
    accessToken: accessToken,
    refreshToken: _nonEmptyString(tokens['refresh_token']),
    expiresIn: _expiresIn(tokens['expires_in']),
    grantedScopes: scope is String
        ? scope.split(RegExp('[ ,]')).where((String s) => s.isNotEmpty).toList()
        : null,
    rawNonce: rawNonce,
  );
}

/// The result of the tokens a provider app returned ([OAuthTokens]): no code exchange; the nonce
/// of the ID token is checked as after an exchange.
OAuthLoopbackResult _fromTokens(
  OAuthLoopbackProvider provider, {
  required String? idToken,
  required String? accessToken,
  required String? rawNonce,
  required String? hashedNonce,
}) {
  final String? id = _nonEmptyString(idToken);
  final String? access = _nonEmptyString(accessToken);
  _checkNonce(id, hashedNonce);
  return OAuthLoopbackResult(
    credential: provider.credentialFor(
      idToken: id,
      accessToken: access,
      rawNonce: rawNonce,
    ),
    idToken: id,
    accessToken: access,
    rawNonce: rawNonce,
  );
}

/// Throws `missing-or-invalid-nonce` when [idToken] has a `nonce` claim that is not
/// [hashedNonce]. A token without the claim passes: Firebase checks the raw nonce of the
/// credential (as the JS SDK leaves the check to the backend).
void _checkNonce(String? idToken, String? hashedNonce) {
  if (idToken == null || hashedNonce == null) {
    return;
  }
  final Object? nonce = _claimsOf(idToken)?['nonce'];
  if (nonce != null && !constantTimeEquals('$nonce', hashedNonce)) {
    throw const FirebaseAuthException(
      code: 'missing-or-invalid-nonce',
      message: 'The ID token carries another nonce than the one sent.',
    );
  }
}

/// Exchanges [code] at the token endpoint (form, RFC 6749 section 4.1.3), or through the provider's
/// [OAuthLoopbackProvider.exchangeCode], and returns the decoded token response.
Future<Map<String, Object?>> _exchange(
  OAuthLoopbackProvider provider,
  http.Client client, {
  required String code,
  required String codeVerifier,
  required String redirectUrl,
}) async {
  final OAuthCodeExchange? exchangeCode = provider.exchangeCode;
  if (exchangeCode != null) {
    try {
      return await Future<Map<String, Object?>>.sync(
        () => exchangeCode(
          OAuthAuthorizationCode(
            code: code,
            codeVerifier: codeVerifier,
            redirectUri: redirectUrl,
            clientId: provider.clientId,
          ),
        ),
      ).timeout(_networkTimeout);
    } on FirebaseAuthException {
      rethrow;
    } on TimeoutException {
      throw const FirebaseAuthException(
        code: 'network-request-failed',
        message: 'The code exchange did not answer in time.',
      );
    } on Object catch (e) {
      throw FirebaseAuthException(
        code: 'invalid-credential',
        message: 'The code exchange failed: $e',
      );
    }
  }
  final http.Response response;
  try {
    response = await client
        .post(
          provider.tokenEndpoint,
          headers: <String, String>{'accept': 'application/json'},
          body: <String, String>{
            'grant_type': 'authorization_code',
            'code': code,
            'redirect_uri': redirectUrl,
            'client_id': provider.clientId,
            'code_verifier': codeVerifier,
            'client_secret': ?provider.clientSecret,
          },
        )
        .timeout(_networkTimeout);
  } on TimeoutException {
    throw const FirebaseAuthException(
      code: 'network-request-failed',
      message: 'The token endpoint did not answer in time.',
    );
  } on http.ClientException catch (e) {
    throw FirebaseAuthException(
      code: 'network-request-failed',
      message: 'The code exchange failed: ${e.message}',
    );
  } on SocketException catch (e) {
    throw FirebaseAuthException(
      code: 'network-request-failed',
      message: 'The code exchange failed: ${e.message}',
    );
  }

  Object? body;
  try {
    body = jsonDecode(response.body);
  } on FormatException {
    body = null;
  }
  // GitHub answers a refused code with status 200 and an `error` field.
  final bool errorIn200 =
      body is Map<String, Object?> &&
      body['error'] is String &&
      body['access_token'] == null &&
      body['id_token'] == null;
  if (response.statusCode != 200 || errorIn200) {
    // An OAuth error ({"error": "invalid_grant", ...}) or some other text. Neither carries a token.
    final String? serverCode = body is Map<String, Object?>
        ? _nonEmptyString(body['error'])
        : _shortText(response.body);
    throw FirebaseAuthException(
      code: 'invalid-credential',
      serverCode: serverCode,
      httpStatus: response.statusCode,
      message:
          'The token endpoint refused the authorization code'
          '${serverCode == null ? '' : ' ($serverCode)'}.',
    );
  }
  if (body is! Map<String, Object?>) {
    throw FirebaseAuthException(
      code: 'invalid-oauth-response',
      httpStatus: response.statusCode,
      message: 'The code exchange did not return a JSON object.',
    );
  }
  return body;
}

/// The S256 code challenge of RFC 7636: the unpadded base64url of the SHA-256 of the verifier.
String _codeChallenge(String verifier) => base64Url
    .encode(sha256.convert(ascii.encode(verifier)).bytes)
    .replaceAll('=', '');

String _sha256Hex(String value) =>
    sha256.convert(utf8.encode(value)).toString();

/// The claims of a JWT, without checking its signature (the Firebase backend checks it), or null if it is not one.
Map<String, Object?>? _claimsOf(String jwt) {
  final List<String> parts = jwt.split('.');
  if (parts.length != 3) {
    return null;
  }
  try {
    final Object? claims = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    return claims is Map<String, Object?> ? claims : null;
  } on FormatException {
    return null;
  }
}

/// How long a request of the code exchange may take before it fails with `network-request-failed`.
const Duration _networkTimeout = Duration(seconds: 30);

/// The `expires_in` of a token response (a number or a numeric string, in seconds), or null when it is missing or
/// not a sane duration (negative, not finite, or longer than a year).
Duration? _expiresIn(Object? value) {
  final num? seconds = value is num
      ? value
      : value is String
      ? num.tryParse(value)
      : null;
  if (seconds == null ||
      !seconds.isFinite ||
      seconds < 0 ||
      seconds > const Duration(days: 366).inSeconds) {
    return null;
  }
  return Duration(seconds: seconds.toInt());
}

String? _nonEmptyString(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

/// [text] if it looks like an error code (one short line), else null: an unexpected body is not put in a message.
String? _shortText(String text) {
  final String trimmed = text.trim();
  return trimmed.isNotEmpty &&
          trimmed.length <= 64 &&
          RegExp(r'^[\w.\-]+$').hasMatch(trimmed)
      ? trimmed
      : null;
}
