import 'package:secure_flow/src/flow.dart';
import 'package:secure_flow/src/presenter.dart';
import 'package:secure_flow/src/environment.dart';
import 'package:secure_flow/src/secrets.dart';

/// Builds the authorization URL of an OAuth request from the redirect URI of this run
/// (`http://127.0.0.1:<port>` or `http://127.0.0.1:<port><path>`), known once the server is bound.
typedef AuthorizationUrlBuilder = Uri Function(String redirectUri);

/// An OAuth sign-in with a provider. The result is an [OAuthResult]: the redirect of an
/// authorization code request ([OAuthRedirect]), or the provider's tokens straight from its app or
/// SDK ([OAuthTokens]). Named `OAuthFlow`, not after the code, because of that second case.
///
/// Presenters, best first ([presenterKinds]): the provider's app when one is available for
/// [providerId] ([ProviderAppPresenter.canSignIn]), the system browser, an in-app browser tab, the
/// console. Never a web view (RFC 8252, section 8.12), and no presenter of kind
/// [SecurePresenterKind.other], whose surface is unknown.
///
/// With a [LoopbackPresenter] (RFC 8252, "OAuth 2.0 for Native Apps"):
///
/// * Host exactly `127.0.0.1` ([SecureFlowHost.loopbackIPv4]): no other interface, and no name a
///   resolver could send elsewhere. A request whose `Host` is not `127.0.0.1:<port>` is refused.
/// * Answer: a GET on [redirectPath] with the parameters in the query ([SecureAnswer.query]). Other
///   paths and methods get a 404 (favicons). The redirect URI of a [redirectPath] of `/` has no
///   path: `http://127.0.0.1:<port>`, the form Google's Desktop clients and GitHub OAuth Apps
///   (callback `http://127.0.0.1`) accept.
///
/// The flow only carries the request out and the result back. PKCE, the code exchange, the check
/// of the nonce in the ID token, and the meaning of `code` and `error` belong to the caller; the
/// caller makes the [state] and the nonces too. The flow checks the state (constant time, one
/// answer) and hands the nonces to a provider app. Use [map] to run the code exchange while the
/// browser waits, so that its page says whether the sign-in worked.
final class OAuthFlow extends SecureFlow<OAuthResult> {
  /// A sign-in with [providerId] (`google.com`, `oidc.<name>`, ...).
  ///
  /// [authorizationUrl] makes the URL a loopback presenter shows; the redirect must carry [state]
  /// on [redirectPath] (it starts with `/`) of a server on [port] (0: any free port). [scopes],
  /// [rawNonce] and [hashedNonce] go to a provider app (an SDK binds its ID token to the nonce).
  /// [donePage] is what the browser gets once the result is taken (and once [map] finished, if
  /// used).
  OAuthFlow({
    required this.providerId,
    required this.authorizationUrl,
    required String state,
    this.scopes = const <String>[],
    this.rawNonce,
    this.hashedNonce,
    this.redirectPath = '/',
    int port = 0,
    SecurePage? donePage,
  }) : _state = state,
       _port = port,
       _donePage = donePage {
    if (providerId.isEmpty) {
      throw ArgumentError.value('', 'providerId', 'must not be empty');
    }
    if (state.isEmpty) {
      throw ArgumentError.value('', 'state', 'must not be empty');
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

  /// The Firebase provider id of the sign-in.
  final String providerId;

  /// Makes the URL a loopback presenter shows.
  final AuthorizationUrlBuilder authorizationUrl;

  /// The scopes of the request, for a provider app.
  final List<String> scopes;

  /// The nonce whose hash the caller sends to the provider, for a provider app; null without one.
  final String? rawNonce;

  /// The SHA-256 hash (hex) of [rawNonce], for a provider app; null without one.
  final String? hashedNonce;

  /// The path of the redirect on the loopback server.
  final String redirectPath;

  final String _state;
  final int _port;
  final SecurePage? _donePage;

  @override
  SecureFlowPurpose get purpose => SecureFlowPurpose.oauth;

  @override
  List<SecurePresenterKind> get presenterKinds => const <SecurePresenterKind>[
    SecurePresenterKind.providerApp,
    SecurePresenterKind.systemBrowser,
    SecurePresenterKind.inAppBrowser,
    SecurePresenterKind.console,
  ];

  @override
  bool canDrive(SecurePresenter presenter) => switch (presenter) {
    ProviderAppPresenter() => presenter.canSignIn(providerId),
    LoopbackPresenter() => true,
    _ => false,
  };

  @override
  Future<OAuthResult>? presentDirectly(SecurePresenter presenter) =>
      presenter is ProviderAppPresenter ? _signInWithApp(presenter) : null;

  Future<OAuthResult> _signInWithApp(ProviderAppPresenter presenter) async {
    final OAuthResult result = await presenter.signIn(
      OAuthAppRequest(
        providerId: providerId,
        scopes: scopes,
        state: _state,
        rawNonce: rawNonce,
        hashedNonce: hashedNonce,
      ),
    );
    if (result is OAuthRedirect &&
        !constantTimeEquals(result.parameters['state'] ?? '', _state)) {
      throw StateError(
        'The redirect of the provider app does not carry the state of this sign-in.',
      );
    }
    return switch (result) {
      OAuthRedirect(
        :final Map<String, String> parameters,
        :final String redirectUri,
      ) =>
        OAuthRedirect(
          parameters: Map<String, String>.of(parameters)..remove('state'),
          redirectUri: redirectUri,
        ),
      OAuthTokens() => result,
    };
  }

  @override
  SecureFlowHost get host => SecureFlowHost.loopbackIPv4;

  @override
  int get port => _port;

  @override
  SecureAnswer get answer => SecureAnswer.query(path: redirectPath);

  @override
  String get state => _state;

  @override
  Uri start(SecureFlowSession session) => authorizationUrl(session.address);

  @override
  OAuthRedirect parse(
    Map<String, String> parameters,
    SecureFlowSession session,
  ) => OAuthRedirect(parameters: parameters, redirectUri: session.address);

  @override
  SecurePage get notFoundPage => const SecurePage.message(
    title: 'Not found',
    text: 'This address only receives the sign-in redirect.',
  );

  @override
  SecurePage get rejectedPage => const SecurePage.message(
    title: 'Not this sign-in',
    text:
        'This request does not belong to the sign-in in progress. Return to the app and try again.',
  );

  @override
  SecurePage get donePage =>
      _donePage ??
      const SecurePage.message(
        title: 'Back to the app',
        text: 'You can close this window and return to the app.',
      );

  @override
  SecurePage get failedPage => const SecurePage.message(
    title: 'Sign-in failed',
    text: 'The sign-in did not complete. Return to the app and try again.',
  );

  /// Leaves out the state and the nonces.
  @override
  String toString() => 'OAuthFlow($providerId, redirectPath: $redirectPath)';
}

/// What an [OAuthFlow] returns: [OAuthRedirect] or [OAuthTokens].
sealed class OAuthResult {
  const OAuthResult();
}

/// The redirect of an authorization code request: its query (`code`, or `error`) and the redirect
/// URI it came to (the `redirect_uri` of the code exchange). The state was checked and removed.
final class OAuthRedirect extends OAuthResult {
  /// A redirect.
  const OAuthRedirect({required this.parameters, required this.redirectUri});

  /// The query parameters of the redirect, without `state`: `code`, or `error` and
  /// `error_description`, and whatever else the provider sent.
  final Map<String, String> parameters;

  /// The redirect URI of this run.
  final String redirectUri;

  /// Leaves out the values (the code is a secret).
  @override
  String toString() =>
      'OAuthRedirect(redirectUri: $redirectUri, parameters: ${parameters.keys.toList()})';
}

/// The provider's tokens, from its app or SDK: an ID token (for Facebook Limited Login a JWT bound
/// to the nonce), an access token, or both. They go to Firebase without a code exchange.
final class OAuthTokens extends OAuthResult {
  /// Tokens; at least one of [idToken] and [accessToken] must be a non-empty string, otherwise an
  /// [ArgumentError] is thrown.
  OAuthTokens({this.idToken, this.accessToken}) {
    if ((idToken?.isEmpty ?? true) && (accessToken?.isEmpty ?? true)) {
      throw ArgumentError('An ID token or an access token is needed.');
    }
  }

  /// The ID token, or null.
  final String? idToken;

  /// The access token, or null.
  final String? accessToken;

  /// Leaves out the tokens.
  @override
  String toString() =>
      'OAuthTokens(idToken: ${idToken == null ? 'none' : 'present'}, '
      'accessToken: ${accessToken == null ? 'none' : 'present'})';
}

/// What a [ProviderAppPresenter] gets from an [OAuthFlow].
final class OAuthAppRequest {
  /// Made by the flow.
  const OAuthAppRequest({
    required this.providerId,
    required this.scopes,
    required this.state,
    this.rawNonce,
    this.hashedNonce,
  });

  /// The Firebase provider id.
  final String providerId;

  /// The scopes to ask for.
  final List<String> scopes;

  /// The state an app redirect ([OAuthRedirect]) must carry back in its `state` parameter.
  final String state;

  /// The raw nonce, or null.
  final String? rawNonce;

  /// The SHA-256 hash (hex) of [rawNonce], or null. Most SDKs take this one (Google Credential
  /// Manager, Sign in with Apple) and put it in the `nonce` claim of the ID token; Firebase then
  /// gets [rawNonce] to check it.
  final String? hashedNonce;

  /// Leaves out the state and the nonces.
  @override
  String toString() => 'OAuthAppRequest($providerId, scopes: $scopes)';
}

/// The provider's own app or SDK, of kind [SecurePresenterKind.providerApp]: it completes an
/// [OAuthFlow] without the loopback server and returns the result itself, the provider's tokens
/// ([OAuthTokens]) or an app redirect ([OAuthRedirect], with the state of the request). None is
/// part of this package; register one in [SecureEnvironment.registered] or pass it to
/// [SecureFlow.run].
abstract interface class ProviderAppPresenter implements SecurePresenter {
  /// Whether this presenter can sign in with [providerId] here (the app is installed, the SDK is
  /// configured). An [OAuthFlow] for another provider refuses it, or passes it over when choosing.
  bool canSignIn(String providerId);

  /// Signs in for [request].
  Future<OAuthResult> signIn(OAuthAppRequest request);
}
