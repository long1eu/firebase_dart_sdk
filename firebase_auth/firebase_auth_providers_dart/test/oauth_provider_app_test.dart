// The OAuth sign-in through a provider app (a fake ProviderAppPresenter that returns the
// provider's tokens itself, as Facebook's SDK or Google Credential Manager would), against the
// fake backend: no loopback server and no code exchange.

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:test/test.dart';

import 'harness.dart';

/// A provider app for [providers] that returns [result] for each request.
final class _FakeProviderApp implements ProviderAppPresenter {
  _FakeProviderApp(this.providers, this.result);

  final Set<String> providers;
  final OAuthResult Function(OAuthAppRequest request) result;
  final List<OAuthAppRequest> requests = <OAuthAppRequest>[];

  @override
  SecurePresenterKind get kind => SecurePresenterKind.providerApp;

  @override
  bool canSignIn(String providerId) => providers.contains(providerId);

  @override
  Future<OAuthResult> signIn(OAuthAppRequest request) async {
    requests.add(request);
    return result(request);
  }
}

/// An unsigned JWT with [claims] (the fake backend, like this client, does not check signatures).
String _jwt(Map<String, Object?> claims) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part(<String, String>{'alg': 'none'})}.${part(claims)}.sig';
}

String _sha256Hex(String value) =>
    sha256.convert(utf8.encode(value)).toString();

OAuthLoopbackProvider _oidc() => OAuthLoopbackProvider.oidc(
  providerId: 'oidc.fake',
  authorizationEndpoint: Uri.parse('https://idp.example/authorize'),
  tokenEndpoint: Uri.parse('https://idp.example/token'),
  clientId: 'client-1',
  clientSecret: 'secret',
);

TypeMatcher<FirebaseAuthException> _authError(String code) =>
    isA<FirebaseAuthException>().having(
      (FirebaseAuthException e) => e.code,
      'code',
      code,
    );

void main() {
  test(
    'tokens of a provider app go to signInWithIdp with the raw nonce; the ID token holds its hash',
    () async {
      final FakeBackend backend = FakeBackend();
      final FirebaseUserAuth auth = backend.create();
      addTearDown(auth.dispose);
      final _FakeProviderApp app = _FakeProviderApp(
        <String>{'oidc.fake'},
        (OAuthAppRequest request) => OAuthTokens(
          idToken: _jwt(<String, Object?>{
            'sub': 'idp-user',
            'nonce': request.hashedNonce,
          }),
          accessToken: 'app-access-token',
        ),
      );
      Map<String, String>? post;
      backend.on('accounts:signInWithIdp', (Map<String, Object?> body) {
        post = Uri.splitQueryString(body['postBody']! as String);
        return jsonResponse(<String, Object?>{
          'providerId': 'oidc.fake',
          'isNewUser': true,
          ...backend.tokensFor('idp-user', provider: 'oidc.fake'),
        });
      });

      // No presenter: the flow picks the provider app the environment offers, ahead of the
      // system browser.
      final UserCredential result = await auth.signInWithOAuthLoopback(
        _oidc(),
        environment: SecureEnvironment(
          operatingSystem: 'macos',
          registered: <SecurePresenter>[app],
        ),
      );

      expect(result.user!.uid, 'idp-user');
      final OAuthAppRequest request = app.requests.single;
      expect(request.providerId, 'oidc.fake');
      expect(request.scopes, <String>['openid', 'email', 'profile']);
      expect(request.rawNonce, hasLength(43));
      expect(request.hashedNonce, _sha256Hex(request.rawNonce!));
      expect(post!['providerId'], 'oidc.fake');
      expect(post!['id_token'], startsWith('eyJ'));
      expect(post!['access_token'], 'app-access-token');
      expect(post!['nonce'], request.rawNonce);
    },
  );

  test('an access token alone is enough', () async {
    final FakeBackend backend = FakeBackend();
    final FirebaseUserAuth auth = backend.create();
    addTearDown(auth.dispose);
    backend.on('accounts:signInWithIdp', (Map<String, Object?> body) {
      final Map<String, String> post = Uri.splitQueryString(
        body['postBody']! as String,
      );
      expect(post['access_token'], 'only-access');
      expect(post.containsKey('id_token'), isFalse);
      return jsonResponse(<String, Object?>{
        'providerId': 'oidc.fake',
        ...backend.tokensFor('u2', provider: 'oidc.fake'),
      });
    });
    final UserCredential result = await auth.signInWithOAuthLoopback(
      _oidc(),
      presenter: _FakeProviderApp(<String>{
        'oidc.fake',
      }, (_) => OAuthTokens(accessToken: 'only-access')),
    );
    expect(result.user!.uid, 'u2');
  });

  test(
    'an ID token with another nonce is refused by the client before Firebase is called',
    () async {
      final FakeBackend backend = FakeBackend();
      final FirebaseUserAuth auth = backend.create();
      addTearDown(auth.dispose);
      await expectLater(
        auth.signInWithOAuthLoopback(
          _oidc(),
          presenter: _FakeProviderApp(
            <String>{'oidc.fake'},
            (_) => OAuthTokens(
              idToken: _jwt(<String, Object?>{'nonce': 'replayed'}),
            ),
          ),
        ),
        throwsA(_authError('missing-or-invalid-nonce')),
      );
      expect(backend.methods, isNot(contains('accounts:signInWithIdp')));
    },
  );

  test(
    'authorizeWithOAuthLoopback returns the tokens and a Google credential without the nonce',
    () async {
      final OAuthLoopbackResult result = await authorizeWithOAuthLoopback(
        OAuthLoopbackProvider.google(clientId: 'id', clientSecret: 'secret'),
        presenter: _FakeProviderApp(
          <String>{'google.com'},
          (OAuthAppRequest r) => OAuthTokens(
            idToken: _jwt(<String, Object?>{'nonce': r.hashedNonce}),
          ),
        ),
      );
      expect(result.credential.providerId, 'google.com');
      expect(result.idToken, isNotNull);
      expect(result.refreshToken, isNull);
      expect(result.rawNonce, isNotNull);
    },
  );

  test(
    'a provider app for another provider is refused, not replaced by the browser',
    () async {
      await expectLater(
        authorizeWithOAuthLoopback(
          _oidc(),
          presenter: _FakeProviderApp(<String>{
            'facebook.com',
          }, (_) => OAuthTokens(idToken: 'x')),
        ),
        throwsA(isA<SecureFlowRefused>()),
      );
    },
  );
}
