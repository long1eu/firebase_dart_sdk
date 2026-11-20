// Federated credentials: the provider classes, the accounts:signInWithIdp requests of the JS SDK for sign-in, link
// and reauthentication, unlink, and the credentials the backend gives back in results and errors.

import 'dart:convert';

import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:test/test.dart';

import 'harness.dart';

void main() {
  late FakeBackend backend;
  late FirebaseUserAuth auth;

  /// The fields of the postBody of the last signInWithIdp request.
  Map<String, String> postBody() => Uri.splitQueryString(
    backend.bodiesOf('accounts:signInWithIdp').last['postBody']! as String,
  );

  setUp(() {
    backend = FakeBackend();
    auth = backend.create();
    // A sign-in of the provider in the postBody: uid idp-<providerId>, or the user of the ID token when linking.
    backend.on('accounts:signInWithIdp', (Map<String, Object?> body) {
      final String? pending = body['pendingToken'] as String?;
      final Map<String, String> post = pending == null
          ? Uri.splitQueryString(body['postBody']! as String)
          : <String, String>{'providerId': 'oidc.pending'};
      final String providerId = post['providerId']!;
      final String uid = body['idToken'] is String
          ? 'anon-user'
          : 'idp-$providerId';
      final bool isNew = !backend.accounts.containsKey(uid);
      backend.accounts[uid] = <String, Object?>{
        ...?backend.accounts[uid],
        'providerUserInfo': <Object?>[
          <String, Object?>{'providerId': providerId, 'rawId': 'raw-$uid'},
        ],
      };
      return jsonResponse(<String, Object?>{
        'kind': 'identitytoolkit#VerifyAssertionResponse',
        'providerId': providerId,
        'isNewUser': isNew,
        'rawUserInfo': jsonEncode(<String, Object?>{'sub': 'raw-$uid'}),
        if (post['id_token'] != null) 'oauthIdToken': post['id_token'],
        if (post['access_token'] != null)
          'oauthAccessToken': post['access_token'],
        if (post['oauth_token_secret'] != null)
          'oauthTokenSecret': post['oauth_token_secret'],
        ...backend.tokensFor(uid, provider: providerId),
      });
    });
  });

  tearDown(() => auth.dispose());

  group('the request of each provider', () {
    final Map<String, (AuthCredential, Map<String, String>)>
    cases = <String, (AuthCredential, Map<String, String>)>{
      'Google ID token': (
        GoogleAuthProvider.credential(idToken: 'g-id'),
        <String, String>{'id_token': 'g-id', 'providerId': 'google.com'},
      ),
      'Google both tokens': (
        GoogleAuthProvider.credential(idToken: 'g-id', accessToken: 'g-at'),
        <String, String>{
          'id_token': 'g-id',
          'access_token': 'g-at',
          'providerId': 'google.com',
        },
      ),
      'Apple ID token and nonce': (
        AppleAuthProvider.credentialWithIDToken('a-id', 'raw nonce/+='),
        <String, String>{
          'id_token': 'a-id',
          'providerId': 'apple.com',
          'nonce': 'raw nonce/+=',
        },
      ),
      'Apple access token': (
        AppleAuthProvider.credential('a-at'),
        <String, String>{'access_token': 'a-at', 'providerId': 'apple.com'},
      ),
      'Facebook': (
        FacebookAuthProvider.credential('fb-at'),
        <String, String>{'access_token': 'fb-at', 'providerId': 'facebook.com'},
      ),
      'GitHub': (
        GithubAuthProvider.credential('gh-at'),
        <String, String>{'access_token': 'gh-at', 'providerId': 'github.com'},
      ),
      'Twitter': (
        TwitterAuthProvider.credential(accessToken: 'tw-at', secret: 'tw-s'),
        <String, String>{
          'access_token': 'tw-at',
          'oauth_token_secret': 'tw-s',
          'providerId': 'twitter.com',
        },
      ),
      'Microsoft': (
        MicrosoftAuthProvider.credential(
          idToken: 'ms-id',
          accessToken: 'ms-at',
        ),
        <String, String>{
          'id_token': 'ms-id',
          'access_token': 'ms-at',
          'providerId': 'microsoft.com',
        },
      ),
      'Yahoo': (
        YahooAuthProvider.credential('y-at'),
        <String, String>{'access_token': 'y-at', 'providerId': 'yahoo.com'},
      ),
      'OpenID Connect': (
        OAuthProvider('oidc.example').credential(idToken: 'o-id'),
        <String, String>{'id_token': 'o-id', 'providerId': 'oidc.example'},
      ),
      'OpenID Connect with a nonce': (
        OAuthProvider(
          'oidc.example',
        ).credential(idToken: 'o-id', rawNonce: 'n'),
        <String, String>{
          'id_token': 'o-id',
          'providerId': 'oidc.example',
          'nonce': 'n',
        },
      ),
    };
    for (final MapEntry<String, (AuthCredential, Map<String, String>)> c
        in cases.entries) {
      test(c.key, () async {
        auth.tenantId = null;
        final UserCredential result = await auth.signInWithCredential(
          c.value.$1,
        );
        final Map<String, Object?> body = backend
            .bodiesOf('accounts:signInWithIdp')
            .single;
        expect(body.keys, <String>[
          'requestUri',
          'returnSecureToken',
          'postBody',
        ]);
        expect(body['requestUri'], 'http://localhost');
        expect(body['returnSecureToken'], isTrue);
        expect(postBody(), c.value.$2);
        // The order of the JS SDK.
        expect(
          (body['postBody']! as String)
              .split('&')
              .map((String p) => p.split('=').first),
          <String>[
            for (final String key in <String>[
              'id_token',
              'access_token',
              'oauth_token_secret',
              'providerId',
              'nonce',
            ])
              if (c.value.$2.containsKey(key)) key,
          ],
        );
        final String providerId = c.value.$2['providerId']!;
        expect(result.uid, 'idp-$providerId');
        expect(result.additionalUserInfo?.providerId, providerId);
        expect(result.additionalUserInfo?.isNewUser, isTrue);
        expect(result.providerData.single.providerId, providerId);
        expect(c.value.$1.providerId, providerId);
        expect(c.value.$1.signInMethod, providerId);
      });
    }

    test('the tenant goes into the request', () async {
      auth.tenantId = 'tenant-1';
      backend.accounts['idp-google.com'] = <String, Object?>{
        'tenantId': 'tenant-1',
      };
      await auth.signInWithCredential(
        GoogleAuthProvider.credential(idToken: 'g'),
      );
      expect(
        backend.bodiesOf('accounts:signInWithIdp').single['tenantId'],
        'tenant-1',
      );
    });

    test('a credential needs a token', () {
      expect(() => GoogleAuthProvider.credential(), throwsArgumentError);
      expect(
        () => OAuthProvider('oidc.x').credential(rawNonce: 'n'),
        throwsArgumentError,
      );
      expect(
        () => MicrosoftAuthProvider.credential(idToken: ''),
        throwsArgumentError,
      );
    });

    test('toString shows no token', () {
      final OAuthCredential credential = OAuthProvider('oidc.x').credential(
        idToken: 'secret-id',
        accessToken: 'secret-at',
        rawNonce: 'secret-nonce',
      );
      expect(
        '$credential',
        'OAuthCredential(providerId: oidc.x, signInMethod: oidc.x)',
      );
    });

    test('signInMethod can be given, like FlutterFire', () {
      expect(
        OAuthProvider(
          'oidc.x',
        ).credential(idToken: 'i', signInMethod: 'm').signInMethod,
        'm',
      );
    });
  });

  test('UserCredential.credential holds what the backend returned', () async {
    final UserCredential google = await auth.signInWithCredential(
      GoogleAuthProvider.credential(idToken: 'g-id', accessToken: 'g-at'),
    );
    final OAuthCredential credential = google.credential! as OAuthCredential;
    expect(credential.providerId, 'google.com');
    expect(credential.idToken, 'g-id');
    expect(credential.accessToken, 'g-at');
    expect('$google', isNot(contains('g-id')));

    final UserCredential twitter = await auth.signInWithCredential(
      TwitterAuthProvider.credential(accessToken: 'tw-at', secret: 'tw-s'),
    );
    expect((twitter.credential! as OAuthCredential).secret, 'tw-s');

    final UserCredential password = await auth.signInWithEmailAndPassword(
      email: 'a@example.com',
      password: 'p',
    );
    expect(password.credential, isNull);
  });

  test('a pending token is sent instead of the tokens', () async {
    await auth.signInWithCredential(
      const OAuthCredential(
        providerId: 'oidc.pending',
        signInMethod: 'oidc.pending',
        idToken: 'ignored',
        pendingToken: 'pending-1',
      ),
    );
    final Map<String, Object?> body = backend
        .bodiesOf('accounts:signInWithIdp')
        .single;
    expect(body['pendingToken'], 'pending-1');
    expect(body, isNot(contains('postBody')));
  });

  group('link and reauthenticate', () {
    test('link sends the ID token of the user', () async {
      await auth.signInAnonymously();
      final String idToken = (await auth.getAccessToken(
        forceRefresh: false,
      )).token;
      final UserCredential result = await auth.linkWithCredential(
        GoogleAuthProvider.credential(idToken: 'g-id'),
      );
      final Map<String, Object?> body = backend
          .bodiesOf('accounts:signInWithIdp')
          .single;
      expect(body['idToken'], idToken);
      expect(body, isNot(contains('autoCreate')));
      expect(result.uid, 'anon-user');
      expect(result.isAnonymous, isFalse);
      expect(result.providerData.single.providerId, 'google.com');
      expect((result.credential! as OAuthCredential).idToken, 'g-id');
      // The new ID token of the answer is the session's now.
      expect(
        (await auth.getAccessToken(forceRefresh: false)).token,
        isNot(idToken),
      );
      await expectLater(
        auth.linkWithCredential(GoogleAuthProvider.credential(idToken: 'x')),
        throwsAuth('provider-already-linked'),
      );
    });

    test('reauthenticate does not create accounts', () async {
      await auth.signInWithCredential(
        GoogleAuthProvider.credential(idToken: 'g-id'),
      );
      final UserCredential again = await auth.reauthenticateWithCredential(
        GoogleAuthProvider.credential(idToken: 'g-id-2'),
      );
      expect(
        backend.bodiesOf('accounts:signInWithIdp').last['autoCreate'],
        isFalse,
      );
      expect(again.uid, 'idp-google.com');
      await expectLater(
        auth.reauthenticateWithCredential(
          FacebookAuthProvider.credential('fb'),
        ),
        throwsAuth('user-mismatch'),
      );
      expect(auth.uid, 'idp-google.com');
    });
  });

  test('the operation type of sign-in, link and reauthentication', () async {
    final UserCredential federated = await auth.signInWithCredential(
      GoogleAuthProvider.credential(idToken: 'g-id'),
    );
    expect(federated.operationType, OperationType.signIn);
    final UserCredential again = await auth.reauthenticateWithCredential(
      GoogleAuthProvider.credential(idToken: 'g-id-2'),
    );
    expect(again.operationType, OperationType.reauthenticate);
    final UserCredential anonymous = await auth.signInAnonymously();
    expect(anonymous.operationType, OperationType.signIn);
    final UserCredential linked = await auth.linkWithCredential(
      GithubAuthProvider.credential('gh-token'),
    );
    expect(linked.operationType, OperationType.link);
    expect(
      OperationType.values.map((OperationType type) => type.value),
      <String>['signIn', 'link', 'reauthenticate'],
    );
  });

  group('unlink', () {
    test('removes the provider', () async {
      backend.accounts['uid-of-a@example.com'] = <String, Object?>{
        'email': 'a@example.com',
        'phoneNumber': '+15555550100',
        'providerUserInfo': <Object?>[
          <String, Object?>{'providerId': 'password', 'rawId': 'a@example.com'},
          <String, Object?>{'providerId': 'google.com', 'rawId': 'g'},
          <String, Object?>{'providerId': 'phone', 'rawId': '+15555550100'},
        ],
      };
      await auth.signInWithEmailAndPassword(
        email: 'a@example.com',
        password: 'p',
      );
      final List<AuthUser?> changes = <AuthUser?>[];
      auth.userChanges().listen(changes.add);
      backend.on(
        'accounts:update',
        (_) => jsonResponse(<String, Object?>{
          'providerUserInfo': <Object?>[
            <String, Object?>{'providerId': 'password'},
            <String, Object?>{'providerId': 'google.com'},
          ],
        }),
      );
      final AuthUser user = await auth.unlink('phone');
      expect(backend.bodiesOf('accounts:update').single, <String, Object?>{
        'idToken': (await auth.getAccessToken(forceRefresh: false)).token,
        'deleteProvider': <Object?>['phone'],
      });
      expect(user.providerData.map((UserInfo i) => i.providerId), <String>[
        'password',
        'google.com',
      ]);
      expect(user.phoneNumber, isNull);
      expect(auth.currentUser, user);
      await Future<void>.delayed(Duration.zero);
      expect(changes.last, user);
    });

    test('no-such-provider', () async {
      await auth.signInAnonymously();
      await expectLater(
        auth.unlink('google.com'),
        throwsAuth('no-such-provider'),
      );
      expect(backend.bodiesOf('accounts:update'), isEmpty);
    });
  });

  group('errors that carry the credential', () {
    test('account-exists-with-different-credential', () async {
      backend.on(
        'accounts:signInWithIdp',
        (_) => jsonResponse(<String, Object?>{
          'needConfirmation': true,
          'email': 'a@example.com',
          'providerId': 'google.com',
          'oauthIdToken': 'g-id',
          'verifiedProvider': <Object?>['facebook.com'],
        }),
      );
      try {
        await auth.signInWithCredential(
          GoogleAuthProvider.credential(idToken: 'g-id'),
        );
        fail('no exception');
      } on FirebaseAuthException catch (e) {
        expect(e.code, 'account-exists-with-different-credential');
        expect(e.email, 'a@example.com');
        expect((e.credential! as OAuthCredential).idToken, 'g-id');
        expect('$e', isNot(contains('g-id')));
        expect(e.message, isNot(contains('g-id')));
      }
      expect(auth.currentUser, isNull);
    });

    test('credential-already-in-use with the answer of the backend', () async {
      await auth.signInAnonymously();
      backend.on(
        'accounts:signInWithIdp',
        (_) => jsonResponse(<String, Object?>{
          'errorMessage': 'FEDERATED_USER_ID_ALREADY_LINKED',
          'providerId': 'oidc.example',
          'pendingToken': 'pending-1',
          'email': 'a@example.com',
        }),
      );
      try {
        await auth.linkWithCredential(
          OAuthProvider('oidc.example').credential(idToken: 'o'),
        );
        fail('no exception');
      } on FirebaseAuthException catch (e) {
        expect(e.code, 'credential-already-in-use');
        expect((e.credential! as OAuthCredential).pendingToken, 'pending-1');
        expect(e.email, 'a@example.com');
      }
      expect(auth.uid, 'anon-user');
    });
  });
}
