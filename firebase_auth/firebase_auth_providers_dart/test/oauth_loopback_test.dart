// The loopback OAuth helper against an in-process identity provider: a local HttpServer plays the authorization,
// token endpoints, and the presenter follows the redirect itself instead of opening a browser.

@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart' show GetTokenResult;
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

/// Whether the loopback listener of a sign-in still answers at [redirectUri].
///
/// A bare connect is not enough: once the listener is closed, its ephemeral port can be bound again at once by
/// another process or test, or a connect from an equal source port can open onto itself. So the port only counts
/// as ours when it answers the redirect path with one of the listener's own pages: "not this sign-in" while it
/// waits, "not found" once the redirect came.
Future<bool> _listenerAnswers(Uri redirectUri) async {
  final http.Client probe = http.Client();
  try {
    final http.Response response = await probe
        .get(
          redirectUri.replace(
            queryParameters: <String, String>{'state': 'not-this-sign-in'},
          ),
          headers: <String, String>{HttpHeaders.connectionHeader: 'close'},
        )
        .timeout(const Duration(seconds: 5));
    return switch (response.statusCode) {
      HttpStatus.badRequest => response.body.contains(
        'This request does not belong to the sign-in in progress.',
      ),
      HttpStatus.notFound => response.body.contains(
        'This address only receives the sign-in redirect.',
      ),
      _ => false,
    };
  } on http.ClientException {
    return false;
  } on TimeoutException {
    return false;
  } finally {
    probe.close();
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
    presenter: CallbackPresenter(presenter.call),
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

  test(
    'a redirect with another state gets a 400 and does not end the wait',
    () async {
      idp.redirect = (Map<String, String> a) => <String, String>{
        'code': 'the-code',
        'state': 'forged',
      };
      await expectLater(
        run(oidc(), timeout: const Duration(milliseconds: 500)),
        throwsA(authError('timeout')),
      );
      expect(idp.tokenForm, isNull);
      expect(presenter.page!.statusCode, 400);
    },
  );

  test('a redirect without state does not end the wait', () async {
    idp.redirect = (Map<String, String> a) => <String, String>{
      'code': 'the-code',
    };
    await expectLater(
      run(oidc(), timeout: const Duration(milliseconds: 500)),
      throwsA(authError('timeout')),
    );
    expect(idp.tokenForm, isNull);
    expect(presenter.page!.statusCode, 400);
  });

  test(
    'a query that does not parse and another Host get a 400; the real redirect still signs in',
    () async {
      final List<int> statuses = <int>[];
      final OAuthLoopbackResult result = await authorizeWithOAuthLoopback(
        oidc(),
        presenter: CallbackPresenter((Uri url) async {
          final Uri redirect = Uri.parse(url.queryParameters['redirect_uri']!);
          final String state = url.queryParameters['state']!;
          // An invalid UTF-8 escape: Uri.queryParameters throws on it.
          statuses.add(
            (await presenter.client.get(
              Uri.parse('$redirect/?code=x&state=%ff'),
            )).statusCode,
          );
          // The right state, but the Host header of another name (DNS rebinding).
          final HttpClient io = HttpClient();
          try {
            final HttpClientRequest request = await io.getUrl(
              redirect.replace(
                queryParameters: <String, String>{'code': 'x', 'state': state},
              ),
            );
            request.headers.host = 'evil.example';
            final HttpClientResponse response = await request.close();
            await response.drain<void>();
            statuses.add(response.statusCode);
          } finally {
            io.close(force: true);
          }
          await presenter(url);
        }),
        timeout: const Duration(seconds: 10),
        httpClient: client,
      );
      expect(statuses, <int>[400, 400]);
      expect(result.accessToken, 'the-access-token');
      expect(idp.tokenForm!['code'], 'the-code');
    },
  );

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
          authError('invalid-oauth-response')
              .having(
                (FirebaseAuthException e) => e.serverCode,
                'serverCode',
                isNull,
              )
              .having(
                (FirebaseAuthException e) => e.message,
                'message',
                isNot(contains('<script>')),
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
        presenter: CallbackPresenter((Uri u) => url = u),
        timeout: const Duration(milliseconds: 200),
        httpClient: client,
      ),
      throwsA(authError('timeout')),
    );
    final Uri redirectUri = Uri.parse(url!.queryParameters['redirect_uri']!);
    expect(await _listenerAnswers(redirectUri), isFalse);
  });

  test('the server is closed after a success', () async {
    await run(oidc());
    final Uri redirectUri = Uri.parse(idp.authorization['redirect_uri']!);
    expect(await _listenerAnswers(redirectUri), isFalse);
  });

  test('other paths get a 404 and do not end the wait', () async {
    final Completer<int> other = Completer<int>();
    final Future<OAuthLoopbackResult> result = authorizeWithOAuthLoopback(
      oidc(redirectPath: '/callback'),
      presenter: CallbackPresenter((Uri url) async {
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
      }),
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
        presenter: CallbackPresenter((_) => throw StateError('no browser')),
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

  test(
    'the GitHub preset: PKCE, client secret, no nonce, access token only',
    () async {
      final FakeBackend backend = FakeBackend();
      final FirebaseUserAuth auth = backend.create();
      addTearDown(auth.dispose);
      Map<String, String>? postBody;
      backend.on('accounts:signInWithIdp', (Map<String, Object?> body) {
        postBody = Uri.splitQueryString(body['postBody']! as String);
        return jsonResponse(<String, Object?>{
          'providerId': 'github.com',
          ...backend.tokensFor('github-user', provider: 'github.com'),
        });
      });
      // GitHub's token endpoint, played in process: nothing leaves the machine.
      http.Request? tokenRequest;
      final MockClient github = MockClient((http.Request request) async {
        tokenRequest = request;
        return jsonResponse(<String, Object?>{
          'access_token': 'gho_access',
          'scope': 'read:user,user:email',
          'token_type': 'bearer',
        });
      });
      Uri? url;

      final UserCredential result = await auth.signInWithOAuthLoopback(
        OAuthLoopbackProvider.github(
          clientId: 'github-client',
          clientSecret: 'github-secret',
        ),
        presenter: CallbackPresenter((Uri authorizationUrl) async {
          url = authorizationUrl;
          final Uri redirect = Uri.parse(
            authorizationUrl.queryParameters['redirect_uri']!,
          );
          await presenter.client.get(
            redirect.replace(
              queryParameters: <String, String>{
                'code': 'github-code',
                'state': authorizationUrl.queryParameters['state']!,
              },
            ),
          );
        }),
        httpClient: github,
      );

      expect(
        '${url!.scheme}://${url!.host}${url!.path}',
        'https://github.com/login/oauth/authorize',
      );
      final Map<String, String> a = url!.queryParameters;
      expect(a['client_id'], 'github-client');
      expect(a['scope'], 'read:user user:email');
      expect(a['response_type'], 'code');
      expect(a['code_challenge_method'], 'S256');
      expect(a['redirect_uri'], matches(RegExp(r'^http://127\.0\.0\.1:\d+$')));
      expect(a, isNot(contains('nonce')));

      expect(
        tokenRequest!.url.toString(),
        'https://github.com/login/oauth/access_token',
      );
      expect(tokenRequest!.method, 'POST');
      expect(tokenRequest!.headers['accept'], 'application/json');
      final Map<String, String> form = tokenRequest!.bodyFields;
      expect(form['client_id'], 'github-client');
      expect(form['client_secret'], 'github-secret');
      expect(form['code'], 'github-code');
      expect(form['redirect_uri'], a['redirect_uri']);
      expect(_challengeOf(form['code_verifier']!), a['code_challenge']);

      expect(postBody, <String, String>{
        'access_token': 'gho_access',
        'providerId': 'github.com',
      });
      expect(result.user!.uid, 'github-user');
    },
  );

  test(
    'GitHub: comma-separated scopes are split, and an error with status 200 is invalid-credential',
    () async {
      Future<OAuthLoopbackResult> run(Map<String, Object?> answer) {
        return authorizeWithOAuthLoopback(
          OAuthLoopbackProvider.github(
            clientId: 'github-client',
            clientSecret: 'github-secret',
          ),
          presenter: CallbackPresenter((Uri authorizationUrl) async {
            final Uri redirect = Uri.parse(
              authorizationUrl.queryParameters['redirect_uri']!,
            );
            await presenter.client.get(
              redirect.replace(
                queryParameters: <String, String>{
                  'code': 'github-code',
                  'state': authorizationUrl.queryParameters['state']!,
                },
              ),
            );
          }),
          httpClient: MockClient(
            (http.Request request) async => jsonResponse(answer),
          ),
        );
      }

      final OAuthLoopbackResult result = await run(<String, Object?>{
        'access_token': 'gho_access',
        'scope': 'read:user,user:email',
        'token_type': 'bearer',
      });
      expect(result.grantedScopes, <String>['read:user', 'user:email']);

      await expectLater(
        run(<String, Object?>{
          'error': 'bad_verification_code',
          'error_description': 'The code passed is incorrect or expired.',
        }),
        throwsA(
          authError('invalid-credential').having(
            (FirebaseAuthException e) => e.serverCode,
            'serverCode',
            'bad_verification_code',
          ),
        ),
      );
    },
  );

  test('the GitHub preset needs a client secret, and takes other scopes', () {
    expect(
      () => OAuthLoopbackProvider.github(clientId: 'c', clientSecret: ''),
      throwsArgumentError,
    );
    final OAuthLoopbackProvider github = OAuthLoopbackProvider.github(
      clientId: 'c',
      clientSecret: 's',
      scopes: <String>['repo'],
    );
    expect(github.scopes, <String>['repo']);
    expect(github.useNonce, isFalse);
  });

  test('copyWith replaces the scopes and parameters and keeps the rest', () {
    Future<Map<String, Object?>> exchange(OAuthAuthorizationCode code) async =>
        <String, Object?>{};
    final OAuthLoopbackProvider original = OAuthLoopbackProvider.oidc(
      providerId: 'oidc.x',
      authorizationEndpoint: Uri.parse('https://idp.example.com/authorize'),
      tokenEndpoint: Uri.parse('https://idp.example.com/token'),
      clientId: 'c',
      clientSecret: 's',
      exchangeCode: exchange,
      customParameters: <String, String>{'prompt': 'login'},
      redirectPath: '/cb',
      port: 4000,
    );
    final OAuthLoopbackProvider copy = original.copyWith(
      scopes: <String>['openid', 'extra'],
      customParameters: <String, String>{'hd': 'example.com'},
    );
    expect(copy.scopes, <String>['openid', 'extra']);
    expect(copy.customParameters, <String, String>{'hd': 'example.com'});
    expect(copy.providerId, 'oidc.x');
    expect(copy.authorizationEndpoint, original.authorizationEndpoint);
    expect(copy.tokenEndpoint, original.tokenEndpoint);
    expect(copy.clientId, 'c');
    expect(copy.clientSecret, 's');
    expect(copy.exchangeCode, same(original.exchangeCode));
    expect(copy.useNonce, isTrue);
    expect(copy.sendNonceToFirebase, isTrue);
    expect(copy.redirectPath, '/cb');
    expect(copy.port, 4000);

    final OAuthLoopbackProvider unchanged = original.copyWith();
    expect(unchanged.scopes, original.scopes);
    expect(unchanged.customParameters, <String, String>{'prompt': 'login'});
  });

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

  /// Runs [body] with the 30 second network timers caught: [fire] runs them now.
  Future<T> withNetworkTimers<T>(
    Future<T> Function(void Function() fire) body,
  ) {
    final List<void Function()> pending = <void Function()>[];
    void fire() {
      final List<void Function()> due = List<void Function()>.of(pending);
      pending.clear();
      for (final void Function() f in due) {
        f();
      }
    }

    return runZoned(
      () => body(fire),
      zoneSpecification: ZoneSpecification(
        createTimer:
            (
              Zone self,
              ZoneDelegate parent,
              Zone zone,
              Duration duration,
              void Function() f,
            ) {
              if (duration != const Duration(seconds: 30)) {
                return parent.createTimer(zone, duration, f);
              }
              pending.add(f);
              return parent.createTimer(zone, const Duration(days: 1), () {});
            },
      ),
    );
  }

  test(
    'an exchangeCode that does not answer fails with network-request-failed',
    () async {
      await withNetworkTimers((void Function() fire) async {
        await expectLater(
          run(
            oidc(
              exchangeCode: (OAuthAuthorizationCode code) {
                // The exchange started: let its 30 seconds pass.
                Timer.run(fire);
                return Completer<Map<String, Object?>>().future;
              },
            ),
          ),
          throwsA(authError('network-request-failed')),
        );
      });
    },
  );

  test(
    'a discovery request that does not answer fails with network-request-failed',
    () async {
      await withNetworkTimers((void Function() fire) async {
        final MockClient hanging = MockClient((http.Request request) {
          Timer.run(fire);
          return Completer<http.Response>().future;
        });
        await expectLater(
          OAuthLoopbackProvider.discover(
            issuer: Uri.parse('https://idp.example.com'),
            providerId: 'oidc.fake',
            clientId: 'client-1',
            httpClient: hanging,
          ),
          throwsA(authError('network-request-failed')),
        );
      });
    },
  );

  test('an expires_in that is not finite is ignored', () async {
    final OAuthLoopbackResult result = await run(
      oidc(
        exchangeCode: (_) =>
            jsonDecode('{"access_token": "at", "expires_in": 1e400}')
                as Map<String, Object?>,
      ),
    );
    expect(result.accessToken, 'at');
    expect(result.expiresIn, isNull);
  });

  test(
    'a discovery document with an http endpoint is invalid-oauth-provider',
    () async {
      final MockClient discovery = MockClient(
        (http.Request request) async => http.Response(
          jsonEncode(<String, Object?>{
            'issuer': 'https://idp.example.com',
            'authorization_endpoint': 'http://idp.example.com/authorize',
            'token_endpoint': 'https://idp.example.com/token',
          }),
          200,
        ),
      );
      await expectLater(
        OAuthLoopbackProvider.discover(
          issuer: Uri.parse('https://idp.example.com'),
          providerId: 'oidc.fake',
          clientId: 'client-1',
          httpClient: discovery,
        ),
        throwsA(authError('invalid-oauth-provider')),
      );
    },
  );

  test('plain http is accepted on 127.0.0.1 and ::1, not on localhost', () {
    OAuthLoopbackProvider withEndpoint(String url) =>
        OAuthLoopbackProvider.oidc(
          providerId: 'oidc.x',
          authorizationEndpoint: Uri.parse(url),
          tokenEndpoint: Uri.parse('https://idp.example.com/token'),
          clientId: 'c',
        );
    expect(withEndpoint('http://127.0.0.1:8080/a'), isNotNull);
    expect(withEndpoint('http://[::1]:8080/a'), isNotNull);
    expect(() => withEndpoint('http://localhost:8080/a'), throwsArgumentError);
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
        presenter: CallbackPresenter(presenter.call),
        httpClient: client,
      );
      expect(result.user!.uid, 'idp-user');
      expect(result.additionalUserInfo?.isNewUser, isTrue);
    },
  );

  test(
    'FirebaseUserAuth.linkWithOAuthLoopback links the credential to the signed-in user',
    () async {
      final FakeBackend backend = FakeBackend();
      final FirebaseUserAuth auth = backend.create();
      addTearDown(auth.dispose);

      // Nobody signed in: it fails before the browser opens.
      await expectLater(
        auth.linkWithOAuthLoopback(
          oidc(),
          presenter: CallbackPresenter(presenter.call),
          httpClient: client,
        ),
        throwsA(authError('null-user')),
      );
      expect(presenter.url, isNull);

      final AuthUser anonymous = (await auth.signInAnonymously()).user!;
      backend.on('accounts:signInWithIdp', (Map<String, Object?> body) {
        expect(
          GetTokenResult(body['idToken']! as String).claims['sub'],
          anonymous.uid,
        );
        final Map<String, String> post = Uri.splitQueryString(
          body['postBody']! as String,
        );
        expect(post['providerId'], 'oidc.fake');
        expect(post['access_token'], 'the-access-token');
        backend.accounts[anonymous.uid] = <String, Object?>{
          'providerUserInfo': <Object?>[
            <String, Object?>{'providerId': 'oidc.fake', 'rawId': 'user-1'},
          ],
        };
        return jsonResponse(<String, Object?>{
          'providerId': 'oidc.fake',
          ...backend.tokensFor(anonymous.uid, provider: 'oidc.fake'),
        });
      });

      final UserCredential result = await auth.linkWithOAuthLoopback(
        oidc(),
        presenter: CallbackPresenter(presenter.call),
        httpClient: client,
      );
      expect(presenter.url, isNotNull);
      expect(result.user!.uid, anonymous.uid);
      expect(
        result.user!.providerData.map((UserInfo info) => info.providerId),
        contains('oidc.fake'),
      );
    },
  );

  test(
    'FirebaseUserAuth.reauthenticateWithOAuthLoopback signs the same user in again',
    () async {
      final FakeBackend backend = FakeBackend();
      final FirebaseUserAuth auth = backend.create();
      addTearDown(auth.dispose);
      final AuthUser user = (await auth.signInWithEmailAndPassword(
        email: 'ada@example.com',
        password: 'secret-1',
      )).user!;
      backend.on('accounts:signInWithIdp', (Map<String, Object?> body) {
        final Map<String, String> post = Uri.splitQueryString(
          body['postBody']! as String,
        );
        expect(post['providerId'], 'oidc.fake');
        expect(post['access_token'], 'the-access-token');
        return jsonResponse(<String, Object?>{
          'providerId': 'oidc.fake',
          ...backend.tokensFor(user.uid, provider: 'oidc.fake'),
        });
      });

      final UserCredential result = await auth.reauthenticateWithOAuthLoopback(
        oidc(),
        presenter: CallbackPresenter(presenter.call),
        httpClient: client,
      );
      expect(result.user!.uid, user.uid);
      expect(auth.currentUser!.uid, user.uid);
      expect(backend.methods, contains('accounts:signInWithIdp'));
    },
  );
}
