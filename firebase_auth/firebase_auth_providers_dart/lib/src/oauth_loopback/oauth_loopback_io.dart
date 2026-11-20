import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../auth_exception.dart';
import 'oauth_loopback.dart';

/// Signs the user in to [provider] in the system browser and returns the provider's tokens with a ready credential
/// (RFC 8252, "OAuth 2.0 for Native Apps"). VM only: on the web it throws an [UnsupportedError].
///
/// 1. A one-shot HTTP server is bound to 127.0.0.1 (never to another interface), on [OAuthLoopbackProvider.port]
///    (any free port by default).
/// 2. [presenter] opens the authorization URL: an authorization code request with PKCE (S256), a random `state`
///    and, with [OAuthLoopbackProvider.useNonce], a nonce. Without a presenter, [openInSystemBrowser] opens it.
///    On Flutter mobile pass a presenter of your own (`url_launcher`'s `launchUrl`).
/// 3. The first GET on the redirect path ends the wait: its `state` is compared in constant time, an `error` of
///    the provider is reported, and the code is exchanged at the token endpoint or by the provider's `exchangeCode` (see
///    [OAuthLoopbackProvider]). The browser gets a short page that says whether it worked. Requests to other paths
///    get a 404 and do not end the wait.
/// 4. The server is closed in every case: success, error, [timeout] (default five minutes) or a presenter that
///    throws.
///
/// [httpClient] is used for the code exchange and is not closed; without it one is created and closed.
///
/// Throws a [FirebaseAuthException]:
///
/// | Code | When |
/// | --- | --- |
/// | `timeout` | no redirect came back within [timeout] |
/// | `user-cancelled` | the provider answered `access_denied` (the user refused) |
/// | `invalid-oauth-response` | the provider answered another `error` ([FirebaseAuthException.serverCode]), no code, or no token |
/// | `oauth-state-mismatch` | the `state` of the redirect is not the one sent (another page or program called the server) |
/// | `missing-or-invalid-nonce` | the ID token carries another nonce than the one sent |
/// | `invalid-credential` | the token endpoint or `exchangeCode` refused the code ([FirebaseAuthException.serverCode] is its `error`) |
/// | `network-request-failed` | the token endpoint could not be reached |
///
/// An error of [presenter] is rethrown as it is. Nothing of the flow is logged; the tokens are never part of an
/// exception message.
///
/// ```dart
/// final OAuthLoopbackResult result = await authorizeWithOAuthLoopback(
///   OAuthLoopbackProvider.google(clientId: clientId, clientSecret: clientSecret),
/// );
/// await auth.signInWithCredential(result.credential);
/// ```
Future<OAuthLoopbackResult> authorizeWithOAuthLoopback(
  OAuthLoopbackProvider provider, {
  UrlPresenter? presenter,
  Duration timeout = const Duration(minutes: 5),
  http.Client? httpClient,
}) async {
  final String state = _randomString();
  final String codeVerifier = _randomString(64);
  final String? rawNonce = provider.useNonce ? _randomString() : null;
  final String? hashedNonce = rawNonce == null ? null : _sha256Hex(rawNonce);

  final HttpServer server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    provider.port,
  );
  try {
    final String redirectUrl = provider.redirectPath == '/'
        ? 'http://127.0.0.1:${server.port}'
        : 'http://127.0.0.1:${server.port}${provider.redirectPath}';

    final Completer<HttpRequest> callback = Completer<HttpRequest>();
    server.listen((HttpRequest request) {
      if (!callback.isCompleted &&
          request.method == 'GET' &&
          request.uri.path == provider.redirectPath) {
        callback.complete(request);
      } else {
        // Favicons, other paths, other methods, and anything after the one redirect.
        unawaited(
          _respond(
            request,
            HttpStatus.notFound,
            'Not found',
            'This address only receives the sign-in redirect.',
          ),
        );
      }
    }, onError: (Object _) {});

    final Uri authorizationUrl = provider.authorizationEndpoint.replace(
      queryParameters: <String, String>{
        ...provider.authorizationEndpoint.queryParameters,
        ...provider.customParameters,
        'client_id': provider.clientId,
        'redirect_uri': redirectUrl,
        'response_type': 'code',
        'scope': provider.scopes.join(' '),
        'state': state,
        'code_challenge': _codeChallenge(codeVerifier),
        'code_challenge_method': 'S256',
        'nonce': ?hashedNonce,
      },
    );

    // The presenter may return only once the browser is done (a test that follows the redirects itself), so it
    // is not awaited before the wait for the redirect; its errors end the wait.
    unawaited(
      Future<void>.sync(
        () => (presenter ?? openInSystemBrowser)(authorizationUrl),
      ).then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          if (!callback.isCompleted) {
            callback.completeError(error, stackTrace);
          }
        },
      ),
    );

    final HttpRequest request;
    try {
      request = await callback.future.timeout(timeout);
    } on TimeoutException {
      throw FirebaseAuthException(
        code: 'timeout',
        message:
            'No sign-in redirect came back within ${timeout.inSeconds} seconds.',
      );
    }

    try {
      final OAuthLoopbackResult result = await _complete(
        provider,
        request.uri.queryParameters,
        state: state,
        codeVerifier: codeVerifier,
        redirectUrl: redirectUrl,
        rawNonce: rawNonce,
        hashedNonce: hashedNonce,
        httpClient: httpClient,
      );
      await _respond(
        request,
        HttpStatus.ok,
        'Signed in',
        'You are signed in. You can close this window and return to the app.',
      );
      return result;
    } on FirebaseAuthException catch (e) {
      await _respond(
        request,
        HttpStatus.badRequest,
        'Sign-in failed',
        'The sign-in did not complete (${e.code}). Return to the app and try again.',
      );
      rethrow;
    } catch (_) {
      await _respond(
        request,
        HttpStatus.internalServerError,
        'Sign-in failed',
        'The sign-in did not complete. Return to the app and try again.',
      );
      rethrow;
    }
  } finally {
    await server.close(force: true);
  }
}

/// Opens [url] in the default browser of the desktop: `open` on macOS, `xdg-open` on Linux and the BSDs,
/// `rundll32 url.dll,FileProtocolHandler` on Windows. The URL is passed as one argument, without a shell.
///
/// Throws an [UnsupportedError] on Android, iOS and Fuchsia (pass a presenter of your own, for example
/// `url_launcher`'s `launchUrl`), and a [StateError] when the command fails. The message does not contain the URL.
Future<void> openInSystemBrowser(Uri url) async {
  final String executable;
  final List<String> arguments;
  if (Platform.isMacOS) {
    executable = 'open';
    arguments = <String>[url.toString()];
  } else if (Platform.isWindows) {
    executable = 'rundll32';
    arguments = <String>['url.dll,FileProtocolHandler', url.toString()];
  } else if (Platform.isLinux) {
    executable = 'xdg-open';
    arguments = <String>[url.toString()];
  } else {
    throw UnsupportedError(
      'openInSystemBrowser works on macOS, Linux and Windows; pass a presenter '
      'on ${Platform.operatingSystem}.',
    );
  }
  final ProcessResult result;
  try {
    result = await Process.run(executable, arguments);
  } on ProcessException catch (e) {
    throw StateError(
      'Could not open the browser with $executable: ${e.message}',
    );
  }
  if (result.exitCode != 0) {
    throw StateError(
      'Could not open the browser: $executable exited with ${result.exitCode}.',
    );
  }
}

Future<OAuthLoopbackResult> _complete(
  OAuthLoopbackProvider provider,
  Map<String, String> response, {
  required String state,
  required String codeVerifier,
  required String redirectUrl,
  required String? rawNonce,
  required String? hashedNonce,
  required http.Client? httpClient,
}) async {
  if (!_constantTimeEquals(response['state'] ?? '', state)) {
    throw const FirebaseAuthException(
      code: 'oauth-state-mismatch',
      message:
          'The sign-in redirect did not carry the state that was sent; it was ignored.',
    );
  }
  final String? error = response['error'];
  if (error != null) {
    throw FirebaseAuthException(
      code: error == 'access_denied'
          ? 'user-cancelled'
          : 'invalid-oauth-response',
      serverCode: error,
      message: error == 'access_denied'
          ? 'The user did not grant the requested permissions.'
          : 'The provider answered with the error $error.',
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
  if (idToken != null && hashedNonce != null) {
    final Object? nonce = _claimsOf(idToken)?['nonce'];
    if (nonce != null && !_constantTimeEquals('$nonce', hashedNonce)) {
      throw const FirebaseAuthException(
        code: 'missing-or-invalid-nonce',
        message: 'The ID token carries another nonce than the one sent.',
      );
    }
  }
  final Object? expiresIn = tokens['expires_in'];
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
    expiresIn: expiresIn is num
        ? Duration(seconds: expiresIn.toInt())
        : expiresIn is String && int.tryParse(expiresIn) != null
        ? Duration(seconds: int.parse(expiresIn))
        : null,
    grantedScopes: scope is String
        ? scope.split(' ').where((String s) => s.isNotEmpty).toList()
        : null,
    rawNonce: rawNonce,
  );
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
      return await exchangeCode(
        OAuthAuthorizationCode(
          code: code,
          codeVerifier: codeVerifier,
          redirectUri: redirectUrl,
          clientId: provider.clientId,
        ),
      );
    } on FirebaseAuthException {
      rethrow;
    } on Object catch (e) {
      throw FirebaseAuthException(
        code: 'invalid-credential',
        message: 'The code exchange failed: $e',
      );
    }
  }
  final http.Response response;
  try {
    response = await client.post(
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
  if (response.statusCode != 200) {
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

Future<void> _respond(
  HttpRequest request,
  int status,
  String title,
  String text,
) async {
  const HtmlEscape escape = HtmlEscape();
  final HttpResponse response = request.response
    ..statusCode = status
    ..headers.contentType = ContentType.html
    ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
    ..headers.set('referrer-policy', 'no-referrer')
    ..headers.set('x-content-type-options', 'nosniff')
    ..headers.set(
      'content-security-policy',
      "default-src 'none'; style-src 'unsafe-inline'",
    )
    ..write(
      '<!doctype html><html lang="en"><head><meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width, initial-scale=1">'
      '<meta name="color-scheme" content="light dark">'
      '<title>${escape.convert(title)}</title>'
      '<style>body{font:16px/1.5 system-ui,sans-serif;max-width:32em;margin:15vh auto;padding:0 16px}</style>'
      '</head><body><h1>${escape.convert(title)}</h1><p>${escape.convert(text)}</p></body></html>',
    );
  try {
    await response.close();
  } on Object {
    // The browser went away; nothing to tell it.
  }
}

const String _unreserved =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

/// [length] characters of the unreserved set of RFC 3986 (the code verifier alphabet of RFC 7636), from a
/// cryptographically secure source: 64 characters carry 384 bits; 43 (the default) carry 258.
String _randomString([int length = 43]) {
  final Random random = Random.secure();
  return String.fromCharCodes(
    List<int>.generate(
      length,
      (_) => _unreserved.codeUnitAt(random.nextInt(_unreserved.length)),
    ),
  );
}

/// The S256 code challenge of RFC 7636: the unpadded base64url of the SHA-256 of the verifier.
String _codeChallenge(String verifier) => base64Url
    .encode(sha256.convert(ascii.encode(verifier)).bytes)
    .replaceAll('=', '');

String _sha256Hex(String value) =>
    sha256.convert(utf8.encode(value)).toString();

/// Compares without an early exit, so that the time taken does not tell how much of [a] matched. The length is not
/// secret (the values compared here have a fixed length).
bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) {
    return false;
  }
  int difference = 0;
  for (int i = 0; i < a.length; i++) {
    difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return difference == 0;
}

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
