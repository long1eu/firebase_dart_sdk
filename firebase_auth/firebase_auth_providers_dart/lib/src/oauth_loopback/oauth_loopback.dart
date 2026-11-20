import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth_credential.dart';
import '../auth_exception.dart';

/// Opens [url] for the user: the system browser, a browser tab of a Flutter plugin (`url_launcher`), or a line
/// printed by a command line tool. It may return before the user is done; the sign-in waits for the redirect.
typedef UrlPresenter = FutureOr<void> Function(Uri url);

/// An identity provider for the browser sign-in of desktop apps and command line tools
/// (`authorizeWithOAuthLoopback` and `FirebaseUserAuth.signInWithOAuthLoopback`, VM only): the OAuth 2.0
/// authorization code flow with PKCE (S256) whose redirect comes back to a one-shot HTTP server on 127.0.0.1
/// (RFC 8252, "OAuth 2.0 for Native Apps").
///
/// Make one with [OAuthLoopbackProvider.google], [OAuthLoopbackProvider.oidc] or [OAuthLoopbackProvider.discover].
///
/// The code is exchanged for the provider's tokens in one of two ways:
///
/// * directly at [tokenEndpoint], with [clientId] and [clientSecret] (if any). For a Google client of the
///   "Desktop app" type the secret is required and Google documents that it is not treated as a secret: it ships
///   with the app.
/// * through [exchangeEndpoint], a server of yours that holds the client secret (for example a Cloud Function).
///   It receives `{"code", "codeVerifier", "clientId", "redirectUrl"}` as a JSON text (content type `text/plain`)
///   and answers with the token endpoint's JSON. This is the contract of the code exchange endpoint of
///   `google_sign_in_dart` (its `example/gcp`), so an endpoint written for that package keeps working.
///
/// Only the code is exchanged: once signed in, Firebase keeps its own refresh token, so the provider's refresh token
/// (if any) is not used by this package.
class OAuthLoopbackProvider {
  /// A provider from explicit endpoints. Prefer the named constructors.
  ///
  /// * [providerId] is the Firebase provider id of the credential: `google.com`, `oidc.<name>`, `microsoft.com`, ...
  /// * [authorizationEndpoint], [tokenEndpoint] and [exchangeEndpoint] must be `https` URLs (plain `http` is accepted
  ///   only for a loopback host, for tests and local identity providers); otherwise an [ArgumentError] is thrown.
  /// * [scopes] are requested as one space-separated `scope` parameter.
  /// * [useNonce] sends the SHA-256 hash (hex) of a random nonce as the `nonce` parameter and checks it against the
  ///   `nonce` claim of the ID token (when the token has one). [sendNonceToFirebase] adds the raw nonce to the
  ///   credential, for the Firebase backend to check (OpenID Connect providers configured in Identity Platform).
  /// * [customParameters] are added to the authorization request (`prompt`, `login_hint`, ...). They cannot
  ///   replace the parameters of the flow (`state`, `redirect_uri`, `code_challenge`, ...): those win.
  /// * [redirectPath] is the path of the redirect URL, `/` by default (the redirect URL is then
  ///   `http://127.0.0.1:<port>`, without a path). [port] is the port of the loopback server, 0 (any free port) by
  ///   default: set it only for a provider that cannot accept any port on 127.0.0.1.
  OAuthLoopbackProvider({
    required this.providerId,
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    required this.clientId,
    this.clientSecret,
    this.exchangeEndpoint,
    this.scopes = defaultScopes,
    this.useNonce = true,
    this.sendNonceToFirebase = false,
    this.customParameters = const <String, String>{},
    this.redirectPath = '/',
    this.port = 0,
  }) {
    _checkEndpoint(authorizationEndpoint, 'authorizationEndpoint');
    _checkEndpoint(tokenEndpoint, 'tokenEndpoint');
    if (exchangeEndpoint != null) {
      _checkEndpoint(exchangeEndpoint!, 'exchangeEndpoint');
    }
    if (providerId.isEmpty) {
      throw ArgumentError.value(providerId, 'providerId', 'must not be empty');
    }
    if (clientId.isEmpty) {
      throw ArgumentError.value(clientId, 'clientId', 'must not be empty');
    }
    if (!redirectPath.startsWith('/')) {
      throw ArgumentError.value(
        redirectPath,
        'redirectPath',
        'must start with /',
      );
    }
    if (port < 0 || port > 65535) {
      throw ArgumentError.value(port, 'port', 'must be between 0 and 65535');
    }
  }

  /// Google, with an OAuth client of the "Desktop app" type of the Google Cloud project of your Firebase project
  /// (Google Auth Platform, Clients). Add the client id to the allowed client ids of the Google provider in the
  /// Firebase console (Authentication, Sign-in method, Google, "Safelist client IDs from external projects") unless
  /// the client is in the same project, so that Firebase accepts its ID tokens.
  ///
  /// Pass [clientSecret] (Google requires it for the code exchange of a desktop client; it is not confidential), or
  /// [exchangeEndpoint] to exchange the code on a server of yours instead. [loginHint] (an email address) and
  /// [hostedDomain] (a Google Workspace domain) become `login_hint` and `hd`.
  ///
  /// The nonce is sent to Google and checked against the ID token here; it is not sent to Firebase, like the
  /// credential of [GoogleAuthProvider.credential].
  factory OAuthLoopbackProvider.google({
    required String clientId,
    String? clientSecret,
    Uri? exchangeEndpoint,
    List<String> scopes = defaultScopes,
    String? loginHint,
    String? hostedDomain,
    Map<String, String> customParameters = const <String, String>{},
  }) => OAuthLoopbackProvider(
    providerId: GoogleAuthProvider.PROVIDER_ID,
    authorizationEndpoint: googleAuthorizationEndpoint,
    tokenEndpoint: googleTokenEndpoint,
    clientId: clientId,
    clientSecret: clientSecret,
    exchangeEndpoint: exchangeEndpoint,
    scopes: scopes,
    customParameters: <String, String>{
      'login_hint': ?loginHint,
      'hd': ?hostedDomain,
      ...customParameters,
    },
  );

  /// An OpenID Connect provider from its [authorizationEndpoint] and [tokenEndpoint]. [providerId] is its id in
  /// Firebase (`oidc.<name>` for a provider configured in Identity Platform); [clientId] must be the client id
  /// configured for it there, because the backend checks the audience of the ID token. The raw nonce is part of the
  /// credential ([sendNonceToFirebase]) unless set otherwise.
  factory OAuthLoopbackProvider.oidc({
    required String providerId,
    required Uri authorizationEndpoint,
    required Uri tokenEndpoint,
    required String clientId,
    String? clientSecret,
    Uri? exchangeEndpoint,
    List<String> scopes = defaultScopes,
    bool useNonce = true,
    bool sendNonceToFirebase = true,
    Map<String, String> customParameters = const <String, String>{},
    String redirectPath = '/',
    int port = 0,
  }) => OAuthLoopbackProvider(
    providerId: providerId,
    authorizationEndpoint: authorizationEndpoint,
    tokenEndpoint: tokenEndpoint,
    clientId: clientId,
    clientSecret: clientSecret,
    exchangeEndpoint: exchangeEndpoint,
    scopes: scopes,
    useNonce: useNonce,
    sendNonceToFirebase: useNonce && sendNonceToFirebase,
    customParameters: customParameters,
    redirectPath: redirectPath,
    port: port,
  );

  /// An OpenID Connect provider whose endpoints are read from the discovery document of [issuer]
  /// (`<issuer>/.well-known/openid-configuration`). The other arguments are those of [OAuthLoopbackProvider.oidc].
  ///
  /// Throws a [FirebaseAuthException] with `network-request-failed` when the document cannot be fetched, and
  /// `invalid-oauth-provider` when it is not a discovery document of [issuer].
  static Future<OAuthLoopbackProvider> discover({
    required Uri issuer,
    required String providerId,
    required String clientId,
    String? clientSecret,
    Uri? exchangeEndpoint,
    List<String> scopes = defaultScopes,
    bool useNonce = true,
    bool sendNonceToFirebase = true,
    Map<String, String> customParameters = const <String, String>{},
    String redirectPath = '/',
    int port = 0,
    http.Client? httpClient,
  }) async {
    _checkEndpoint(issuer, 'issuer');
    final String base = issuer.toString().replaceFirst(RegExp(r'/+$'), '');
    final Uri url = Uri.parse('$base/.well-known/openid-configuration');
    final http.Client client = httpClient ?? http.Client();
    final http.Response response;
    try {
      response = await client.get(url);
    } on http.ClientException catch (e) {
      throw FirebaseAuthException(
        code: 'network-request-failed',
        message: 'Could not fetch the discovery document of $issuer: $e',
      );
    } finally {
      if (httpClient == null) {
        client.close();
      }
    }
    FirebaseAuthException invalid(String why) => FirebaseAuthException(
      code: 'invalid-oauth-provider',
      message: 'The discovery document of $issuer is not usable: $why.',
      httpStatus: response.statusCode,
    );
    if (response.statusCode != 200) {
      throw invalid('HTTP ${response.statusCode}');
    }
    final Object? document;
    try {
      document = jsonDecode(response.body);
    } on FormatException {
      throw invalid('not JSON');
    }
    if (document is! Map<String, Object?>) {
      throw invalid('not a JSON object');
    }
    final Object? issuerClaim = document['issuer'];
    if (issuerClaim is! String ||
        issuerClaim.replaceFirst(RegExp(r'/+$'), '') != base) {
      throw invalid('its issuer is not $issuer');
    }
    final Object? authorization = document['authorization_endpoint'];
    final Object? token = document['token_endpoint'];
    if (authorization is! String || token is! String) {
      throw invalid('no authorization_endpoint or token_endpoint');
    }
    return OAuthLoopbackProvider.oidc(
      providerId: providerId,
      authorizationEndpoint: Uri.parse(authorization),
      tokenEndpoint: Uri.parse(token),
      clientId: clientId,
      clientSecret: clientSecret,
      exchangeEndpoint: exchangeEndpoint,
      scopes: scopes,
      useNonce: useNonce,
      sendNonceToFirebase: sendNonceToFirebase,
      customParameters: customParameters,
      redirectPath: redirectPath,
      port: port,
    );
  }

  /// The scopes requested by default: `openid`, `email` and `profile`.
  static const List<String> defaultScopes = <String>[
    'openid',
    'email',
    'profile',
  ];

  /// Google's authorization endpoint.
  static final Uri googleAuthorizationEndpoint = Uri.parse(
    'https://accounts.google.com/o/oauth2/v2/auth',
  );

  /// Google's token endpoint.
  static final Uri googleTokenEndpoint = Uri.parse(
    'https://oauth2.googleapis.com/token',
  );

  /// The Firebase provider id of the credential.
  final String providerId;

  /// Where the browser is sent to sign in.
  final Uri authorizationEndpoint;

  /// Where the code is exchanged when there is no [exchangeEndpoint].
  final Uri tokenEndpoint;

  /// The OAuth client id of the app at the provider.
  final String clientId;

  /// The client secret for the exchange at [tokenEndpoint], if the provider wants one. Not part of [toString].
  final String? clientSecret;

  /// A server of yours that exchanges the code (see the class documentation); when set, [tokenEndpoint] and
  /// [clientSecret] are not used.
  final Uri? exchangeEndpoint;

  /// The scopes to request.
  final List<String> scopes;

  /// Whether a nonce is sent with the authorization request and checked in the ID token.
  final bool useNonce;

  /// Whether the credential carries the raw nonce for the Firebase backend.
  final bool sendNonceToFirebase;

  /// Extra parameters of the authorization request.
  final Map<String, String> customParameters;

  /// The path of the redirect URL on the loopback server.
  final String redirectPath;

  /// The port of the loopback server; 0 for any free port.
  final int port;

  /// The credential of the provider's tokens: [GoogleAuthProvider.credential] for Google, otherwise
  /// [OAuthProvider.credential] with the raw nonce when [sendNonceToFirebase] is set.
  OAuthCredential credentialFor({
    String? idToken,
    String? accessToken,
    String? rawNonce,
  }) => providerId == GoogleAuthProvider.PROVIDER_ID
      ? GoogleAuthProvider.credential(
          idToken: idToken,
          accessToken: accessToken,
        )
      : OAuthProvider(providerId).credential(
          idToken: idToken,
          accessToken: accessToken,
          rawNonce: sendNonceToFirebase ? rawNonce : null,
        );

  @override
  String toString() =>
      'OAuthLoopbackProvider(providerId: $providerId, clientId: $clientId, '
      'authorizationEndpoint: $authorizationEndpoint)';

  static void _checkEndpoint(Uri endpoint, String name) {
    final bool loopback =
        endpoint.host == '127.0.0.1' ||
        endpoint.host == 'localhost' ||
        endpoint.host == '::1';
    if (endpoint.host.isEmpty ||
        endpoint.hasFragment ||
        !(endpoint.isScheme('https') ||
            endpoint.isScheme('http') && loopback)) {
      throw ArgumentError.value(
        endpoint,
        name,
        'must be an https URL (http only on a loopback host)',
      );
    }
  }
}

/// What the browser sign-in of an [OAuthLoopbackProvider] returns: the provider's tokens and the [credential] for
/// `FirebaseUserAuth.signInWithCredential`, `linkWithCredential` or `reauthenticateWithCredential`.
///
/// The tokens are secrets: [toString] leaves them out.
class OAuthLoopbackResult {
  /// Creates a result. The package creates them; this is for tests.
  const OAuthLoopbackResult({
    required this.credential,
    this.idToken,
    this.accessToken,
    this.refreshToken,
    this.expiresIn,
    this.grantedScopes,
    this.rawNonce,
  });

  /// The credential of the tokens, for the provider's Firebase provider id.
  final OAuthCredential credential;

  /// The OpenID Connect ID token, if the provider returned one.
  final String? idToken;

  /// The OAuth access token, if the provider returned one.
  final String? accessToken;

  /// The provider's refresh token, if it returned one. This package does not use it (Firebase keeps its own
  /// session); keep it only if you call the provider's APIs yourself, and then as a secret.
  final String? refreshToken;

  /// How long [accessToken] is valid, if the provider said.
  final Duration? expiresIn;

  /// The scopes the provider granted, if it said (it may grant fewer than requested).
  final List<String>? grantedScopes;

  /// The nonce whose hash was sent to the provider, or null without a nonce.
  final String? rawNonce;

  @override
  String toString() =>
      'OAuthLoopbackResult(providerId: ${credential.providerId}, '
      'idToken: ${idToken == null ? 'none' : 'present'}, '
      'accessToken: ${accessToken == null ? 'none' : 'present'})';
}
