// The loopback OAuth helper against an in-process identity provider: a local HttpServer plays the authorization,
// token endpoints, and the presenter follows the redirect itself instead of opening a browser.

@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'harness.dart';

/// An unsigned JWT with [claims].
String _jwt(Map<String, Object?> claims) {
  String part(Object json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${part(<String, Object?>{'alg': 'none'})}.${part(claims)}.sig';
}

/// The identity provider: `/authorize` redirects to the redirect URL with a code (or what the test sets), `/token`
/// takes the form of RFC 6749.
class FakeIdentityProvider {
  late HttpServer _server;

  Uri get base => Uri.parse('http://127.0.0.1:${_server.port}');

  /// The query of the last authorization request.
  Map<String, String> authorization = <String, String>{};

  /// The form of the last token request.
  Map<String, String>? tokenForm;

  /// Builds the redirect query from the authorization request; by default a code with the state sent.
  Map<String, String> Function(Map<String, String> authorization) redirect =
      (Map<String, String> a) => <String, String>{
        'code': 'the-code',
        'state': a['state']!,
      };

  /// The nonce claim of the ID token from the authorization request; by default the one sent.
  String? Function(Map<String, String> authorization) nonceClaim =
      (Map<String, String> a) => a['nonce'];

  int tokenStatus = 200;
  String? tokenError;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> stop() => _server.close(force: true);

  Map<String, Object?> _tokens() => <String, Object?>{
    'access_token': 'the-access-token',
    'id_token': _jwt(<String, Object?>{
      'sub': 'user-1',
      'nonce': ?nonceClaim(authorization),
    }),
    'refresh_token': 'the-refresh-token',
    'expires_in': 3599,
    'scope': 'openid email profile',
    'token_type': 'Bearer',
  };

  Future<void> _handle(HttpRequest request) async {
    final HttpResponse response = request.response;
    switch (request.uri.path) {
      case '/authorize':
        authorization = request.uri.queryParameters;
        final Uri target = Uri.parse(
          authorization['redirect_uri']!,
        ).replace(queryParameters: redirect(authorization));
        response
          ..statusCode = HttpStatus.found
          ..headers.set(HttpHeaders.locationHeader, target.toString());
      case '/token':
        tokenForm = Uri.splitQueryString(
          await utf8.decoder.bind(request).join(),
        );
        response
          ..statusCode = tokenStatus
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(
              tokenError == null
                  ? _tokens()
                  : <String, Object?>{
                      'error': tokenError,
                      'error_description': 'Bad Request',
                    },
            ),
          );
      case '/.well-known/openid-configuration':
        response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(<String, Object?>{
              'issuer': base.toString(),
              'authorization_endpoint': '$base/authorize',
              'token_endpoint': '$base/token',
            }),
          );
      default:
        response.statusCode = HttpStatus.notFound;
    }
    await response.close();
  }
}

/// A presenter that plays the browser: follows the redirects of the authorization URL to the loopback server and
/// keeps what the loopback server answered.
class FollowingPresenter {
  final http.Client client = http.Client();
  http.Response? page;
  Uri? url;

  Future<void> call(Uri url) async {
    this.url = url;
    page = await client.get(url);
  }
}

String _challengeOf(String verifier) => base64Url
    .encode(sha256.convert(ascii.encode(verifier)).bytes)
    .replaceAll('=', '');

Future<bool> _accepts(int port) async {
  try {
    final Socket socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      port,
    );
    socket.destroy();
    return true;
  } on SocketException {
    return false;
  }
}

void main() {
  late FakeIdentityProvider idp;
  late FollowingPresenter presenter;
  late http.Client client;

  setUp(() async {
    idp = FakeIdentityProvider();
    await idp.start();
    presenter = FollowingPresenter();
    client = http.Client();
  });

  tearDown(() async {
    presenter.client.close();
    client.close();
    await idp.stop();
  });

  OAuthLoopbackProvider oidc({
    OAuthCodeExchange? exchangeCode,
    String redirectPath = '/',
  }) => OAuthLoopbackProvider.oidc(
    providerId: 'oidc.fake',
    authorizationEndpoint: idp.base.resolve('/authorize'),
    tokenEndpoint: idp.base.resolve('/token'),
    clientId: 'client-1',
    clientSecret: exchangeCode != null ? null : 'not-so-secret',
    exchangeCode: exchangeCode,
    customParameters: <String, String>{'prompt': 'consent'},
    redirectPath: redirectPath,
  );

  Future<OAuthLoopbackResult> run(
    OAuthLoopbackProvider provider, {
    Duration timeout = const Duration(seconds: 10),
  }) => authorizeWithOAuthLoopback(
    provider,
    presenter: presenter.call,
    timeout: timeout,
    httpClient: client,
  );

  TypeMatcher<FirebaseAuthException> authError(String code) =>
      isA<FirebaseAuthException>().having(
        (FirebaseAuthException e) => e.code,
        'code',
        code,
      );

  test(
    'the authorization request: code flow, PKCE S256, state, nonce, loopback redirect',
    () async {
      await run(oidc());
      final Map<String, String> a = idp.authorization;
      expect(a['response_type'], 'code');
      expect(a['client_id'], 'client-1');
      expect(a['scope'], 'openid email profile');
      expect(a['code_challenge_method'], 'S256');
      expect(a['prompt'], 'consent');
      expect(a['state'], hasLength(greaterThanOrEqualTo(43)));
      expect(a['nonce'], matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(a['redirect_uri'], matches(RegExp(r'^http://127\.0\.0\.1:\d+$')));
      // The verifier the token endpoint gets is the one of the challenge.
      expect(
        _challengeOf(idp.tokenForm!['code_verifier']!),
        a['code_challenge'],
      );
    },
  );

  test(
    'direct exchange at the token endpoint returns the tokens and a credential',
    () async {
      final OAuthLoopbackResult result = await run(oidc());

      expect(idp.tokenForm, <String, String>{
        'grant_type': 'authorization_code',
        'code': 'the-code',
        'redirect_uri': idp.authorization['redirect_uri']!,
        'client_id': 'client-1',
        'code_verifier': idp.tokenForm!['code_verifier']!,
        'client_secret': 'not-so-secret',
      });
      expect(result.accessToken, 'the-access-token');
      expect(result.idToken, startsWith('ey'));
      expect(result.refreshToken, 'the-refresh-token');
      expect(result.expiresIn, const Duration(seconds: 3599));
      expect(result.grantedScopes, <String>['openid', 'email', 'profile']);
      expect(result.toString(), isNot(contains('the-access-token')));

      final OAuthCredential credential = result.credential;
      expect(credential.providerId, 'oidc.fake');
      expect(credential.idToken, result.idToken);
      expect(credential.accessToken, 'the-access-token');
      // OIDC: the raw nonce goes to Firebase, its SHA-256 went to the provider.
      expect(
        sha256.convert(utf8.encode(credential.rawNonce!)).toString(),
        idp.authorization['nonce'],
      );

      expect(presenter.page!.statusCode, 200);
      expect(presenter.page!.body, contains('You are signed in'));
      expect(presenter.page!.headers['cache-control'], 'no-store');
    },
  );

  test(
    'exchangeCode gets the code, the verifier, the redirect and the client id',
    () async {
      OAuthAuthorizationCode? seen;
      final OAuthLoopbackResult result = await run(
        oidc(
          exchangeCode: (OAuthAuthorizationCode code) {
            seen = code;
            return <String, Object?>{'access_token': 'from-my-server'};
          },
        ),
      );

      expect(idp.tokenForm, isNull);
      expect(seen!.code, 'the-code');
      expect(seen!.clientId, 'client-1');
      expect(seen!.redirectUri, idp.authorization['redirect_uri']);
      expect(
        _challengeOf(seen!.codeVerifier),
        idp.authorization['code_challenge'],
      );
      expect(result.accessToken, 'from-my-server');
    },
  );

  test(
    'an error of exchangeCode is invalid-credential; its own FirebaseAuthException is kept',
    () async {
      await expectLater(
        run(oidc(exchangeCode: (_) => throw StateError('server down'))),
        throwsA(authError('invalid-credential')),
      );
      expect(presenter.page!.statusCode, 400);
      await expectLater(
        run(
          oidc(
            exchangeCode: (_) => throw const FirebaseAuthException(
              code: 'network-request-failed',
              message: 'no route',
            ),
          ),
        ),
        throwsA(authError('network-request-failed')),
      );
    },
  );

  test('a refused code at the token endpoint is invalid-credential', () async {
    idp
      ..tokenStatus = 400
      ..tokenError = 'invalid_grant';
    await expectLater(
      run(oidc()),
      throwsA(
        authError('invalid-credential').having(
          (FirebaseAuthException e) => e.serverCode,
          'serverCode',
          'invalid_grant',
        ),
      ),
    );
  });

  test('a state mismatch fails without an exchange', () async {
    idp.redirect = (Map<String, String> a) => <String, String>{
      'code': 'the-code',
      'state': 'forged',
    };
    await expectLater(run(oidc()), throwsA(authError('oauth-state-mismatch')));
    expect(idp.tokenForm, isNull);
    expect(presenter.page!.statusCode, 400);
    expect(presenter.page!.body, contains('oauth-state-mismatch'));
  });

  test('a redirect without state fails', () async {
    idp.redirect = (Map<String, String> a) => <String, String>{
      'code': 'the-code',
    };
    await expectLater(run(oidc()), throwsA(authError('oauth-state-mismatch')));
  });

  test('access_denied is user-cancelled', () async {
    idp.redirect = (Map<String, String> a) => <String, String>{
      'error': 'access_denied',
      'state': a['state']!,
    };
    await expectLater(run(oidc()), throwsA(authError('user-cancelled')));
    expect(idp.tokenForm, isNull);
  });

  test(
    'another error of the provider is invalid-oauth-response, escaped in the page',
    () async {
      idp.redirect = (Map<String, String> a) => <String, String>{
        'error': '<script>x</script>',
        'state': a['state']!,
      };
      await expectLater(
        run(oidc()),
        throwsA(
          authError('invalid-oauth-response').having(
            (FirebaseAuthException e) => e.serverCode,
            'serverCode',
            '<script>x</script>',
          ),
        ),
      );
      expect(presenter.page!.body, isNot(contains('<script>')));
    },
  );

  test('a redirect without a code is invalid-oauth-response', () async {
    idp.redirect = (Map<String, String> a) => <String, String>{
      'state': a['state']!,
    };
    await expectLater(
      run(oidc()),
      throwsA(authError('invalid-oauth-response')),
    );
  });

  test('an ID token with another nonce is refused', () async {
    idp.nonceClaim = (_) => 'another';
    await expectLater(
      run(oidc()),
      throwsA(authError('missing-or-invalid-nonce')),
    );
  });

  test('timeout, and the server is closed afterwards', () async {
    Uri? url;
    await expectLater(
      authorizeWithOAuthLoopback(
        oidc(),
        presenter: (Uri u) => url = u,
        timeout: const Duration(milliseconds: 200),
        httpClient: client,
      ),
      throwsA(authError('timeout')),
    );
    final int port = Uri.parse(url!.queryParameters['redirect_uri']!).port;
    expect(await _accepts(port), isFalse);
  });

  test('the server is closed after a success', () async {
    await run(oidc());
    final int port = Uri.parse(idp.authorization['redirect_uri']!).port;
    expect(await _accepts(port), isFalse);
  });

  test('other paths get a 404 and do not end the wait', () async {
    final Completer<int> other = Completer<int>();
    final Future<OAuthLoopbackResult> result = authorizeWithOAuthLoopback(
      oidc(redirectPath: '/callback'),
      presenter: (Uri url) async {
        final Uri redirect = Uri.parse(url.queryParameters['redirect_uri']!);
        expect(redirect.path, '/callback');
        final http.Response favicon = await presenter.client.get(
          redirect.replace(path: '/favicon.ico'),
        );
        final http.Response root = await presenter.client.get(
          redirect.replace(
            path: '/',
            queryParameters: <String, String>{
              'code': 'x',
              'state': url.queryParameters['state']!,
            },
          ),
        );
        other.complete(favicon.statusCode + root.statusCode);
        await presenter(url);
      },
      timeout: const Duration(seconds: 10),
      httpClient: client,
    );
    expect(await other.future, 404 + 404);
    expect((await result).accessToken, 'the-access-token');
  });

  test('a presenter that throws ends the flow with its error', () async {
    await expectLater(
      authorizeWithOAuthLoopback(
        oidc(),
        presenter: (_) => throw StateError('no browser'),
        httpClient: client,
      ),
      throwsStateError,
    );
  });

  test(
    'the Google preset: endpoints, hints, and a credential without the nonce',
    () async {
      final OAuthLoopbackProvider google = OAuthLoopbackProvider.google(
        clientId: 'id.apps.googleusercontent.com',
        clientSecret: 'desktop-secret',
        loginHint: 'ada@example.com',
        hostedDomain: 'example.com',
      );
      expect(google.providerId, 'google.com');
      expect(
        google.authorizationEndpoint.toString(),
        'https://accounts.google.com/o/oauth2/v2/auth',
      );
      expect(
        google.tokenEndpoint.toString(),
        'https://oauth2.googleapis.com/token',
      );
      expect(google.customParameters, <String, String>{
        'login_hint': 'ada@example.com',
        'hd': 'example.com',
      });
      expect(google.toString(), isNot(contains('desktop-secret')));
      final OAuthCredential credential = google.credentialFor(
        idToken: 'id',
        accessToken: 'at',
        rawNonce: 'raw',
      );
      expect(credential.providerId, 'google.com');
      expect(credential.rawNonce, isNull);
    },
  );

  test('endpoints must be https except on loopback', () {
    expect(
      () => OAuthLoopbackProvider.oidc(
        providerId: 'oidc.x',
        authorizationEndpoint: Uri.parse('http://idp.example.com/authorize'),
        tokenEndpoint: Uri.parse('https://idp.example.com/token'),
        clientId: 'c',
      ),
      throwsArgumentError,
    );
  });

  test('discovery reads the endpoints of the issuer', () async {
    final OAuthLoopbackProvider provider = await OAuthLoopbackProvider.discover(
      issuer: idp.base,
      providerId: 'oidc.fake',
      clientId: 'client-1',
      httpClient: client,
    );
    expect(provider.authorizationEndpoint, idp.base.resolve('/authorize'));
    expect(provider.tokenEndpoint, idp.base.resolve('/token'));
    expect(provider.sendNonceToFirebase, isTrue);
  });

  test(
    'FirebaseUserAuth.signInWithOAuthLoopback signs in with the credential',
    () async {
      final FakeBackend backend = FakeBackend();
      final FirebaseUserAuth auth = backend.create();
      addTearDown(auth.dispose);
      backend.on('accounts:signInWithIdp', (Map<String, Object?> body) {
        final Map<String, String> post = Uri.splitQueryString(
          body['postBody']! as String,
        );
        expect(post['providerId'], 'oidc.fake');
        expect(post['access_token'], 'the-access-token');
        expect(post['nonce'], isNotEmpty);
        return jsonResponse(<String, Object?>{
          'providerId': 'oidc.fake',
          'isNewUser': true,
          ...backend.tokensFor('idp-user', provider: 'oidc.fake'),
        });
      });

      final UserCredential result = await auth.signInWithOAuthLoopback(
        oidc(),
        presenter: presenter.call,
        httpClient: client,
      );
      expect(result.user!.uid, 'idp-user');
      expect(result.additionalUserInfo?.isNewUser, isTrue);
    },
  );
}
