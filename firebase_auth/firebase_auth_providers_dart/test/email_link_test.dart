// Email link sign-in: ActionCodeURL, sendSignInLinkToEmail, isSignInWithEmailLink, signInWithEmailLink, and the
// email credentials with signInWithCredential, linkWithCredential and reauthenticateWithCredential.

import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:test/test.dart';

import 'harness.dart';

const String link =
    'https://my-project.firebaseapp.com/__/auth/action?apiKey=test-api-key&mode=signIn&oobCode=CODE-1'
    '&continueUrl=https%3A%2F%2Fexample.com%2Ffinish%3Fx%3D1&lang=fr';

void main() {
  late FakeBackend backend;
  late FirebaseUserAuth auth;

  setUp(() {
    backend = FakeBackend();
    auth = backend.create();
    backend.on('accounts:signInWithEmailLink', (Map<String, Object?> body) {
      final String email = body['email']! as String;
      final String uid = body['idToken'] == null
          ? 'link-of-$email'
          : 'anon-user';
      backend.accounts[uid] = <String, Object?>{
        ...?backend.accounts[uid],
        'email': email,
        'emailVerified': true,
        'providerUserInfo': <Object?>[
          <String, Object?>{
            'providerId': 'password',
            'rawId': email,
            'email': email,
          },
        ],
      };
      return jsonResponse(<String, Object?>{
        'kind': 'identitytoolkit#EmailLinkSigninResponse',
        'email': email,
        'isNewUser': body['idToken'] == null,
        ...backend.tokensFor(uid, email: email),
      });
    });
  });

  tearDown(() => auth.dispose());

  group('ActionCodeURL.parseLink', () {
    test('reads the parts of an action link', () {
      final ActionCodeURL url = ActionCodeURL.parseLink(link)!;
      expect(url.apiKey, 'test-api-key');
      expect(url.code, 'CODE-1');
      expect(url.operation, ActionCodeOperation.emailSignIn);
      expect(url.continueUrl, 'https://example.com/finish?x=1');
      expect(url.languageCode, 'fr');
      expect(url.tenantId, isNull);
      expect('$url', 'ActionCodeURL(emailSignIn)');
      expect('$url', isNot(contains('CODE-1')));
      expect(
        ActionCodeURL.parseLink('$link&tenantId=tenant-1#fragment')!.tenantId,
        'tenant-1',
      );
    });

    test('every mode of the JS SDK', () {
      const Map<String, ActionCodeOperation> modes =
          <String, ActionCodeOperation>{
            'recoverEmail': ActionCodeOperation.recoverEmail,
            'resetPassword': ActionCodeOperation.passwordReset,
            'signIn': ActionCodeOperation.emailSignIn,
            'verifyEmail': ActionCodeOperation.verifyEmail,
            'verifyAndChangeEmail': ActionCodeOperation.verifyAndChangeEmail,
            'revertSecondFactorAddition':
                ActionCodeOperation.revertSecondFactorAddition,
          };
      for (final MapEntry<String, ActionCodeOperation> mode in modes.entries) {
        expect(
          ActionCodeURL.parseLink(
            'https://x/?apiKey=k&oobCode=c&mode=${mode.key}',
          )?.operation,
          mode.value,
        );
      }
    });

    test('null for what is not an action link', () {
      for (final String other in <String>[
        'https://example.com/',
        'not a url',
        'https://x/?apiKey=k&oobCode=c',
        'https://x/?apiKey=k&mode=signIn',
        'https://x/?oobCode=c&mode=signIn',
        'https://x/?apiKey=k&oobCode=c&mode=somethingElse',
      ]) {
        expect(ActionCodeURL.parseLink(other), isNull, reason: other);
      }
    });

    test('unwraps Dynamic Links and iOS deep links', () {
      final String encoded = Uri.encodeComponent(link);
      expect(
        ActionCodeURL.parseLink(
          'https://example.page.link/?link=$encoded&apn=com.example',
        )?.code,
        'CODE-1',
      );
      final String wrapped = Uri.encodeComponent(
        'https://example.page.link/?deep_link_id=$encoded',
      );
      expect(
        ActionCodeURL.parseLink('https://x/?link=$wrapped')?.code,
        'CODE-1',
      );
      expect(
        ActionCodeURL.parseLink('myapp://open?deep_link_id=$encoded')?.code,
        'CODE-1',
      );
      final String iOSWrapped = Uri.encodeComponent('https://y/?link=$encoded');
      expect(
        ActionCodeURL.parseLink('myapp://open?deep_link_id=$iOSWrapped')?.code,
        'CODE-1',
      );
    });
  });

  test('isSignInWithEmailLink', () {
    expect(auth.isSignInWithEmailLink(link), isTrue);
    expect(
      auth.isSignInWithEmailLink(link.replaceAll('signIn', 'resetPassword')),
      isFalse,
    );
    expect(auth.isSignInWithEmailLink('https://example.com'), isFalse);
  });

  group('sendSignInLinkToEmail', () {
    test('the request of the JS SDK', () async {
      auth.tenantId = 'tenant-1';
      await auth.sendSignInLinkToEmail(
        email: 'ada@example.com',
        actionCodeSettings: const ActionCodeSettings(
          url: 'https://example.com/finish',
          handleCodeInApp: true,
          iOSBundleId: 'com.example.ios',
        ),
      );
      expect(backend.bodiesOf('accounts:sendOobCode').single, <String, Object?>{
        'requestType': 'EMAIL_SIGNIN',
        'email': 'ada@example.com',
        'continueUrl': 'https://example.com/finish',
        'canHandleCodeInApp': true,
        'iOSBundleId': 'com.example.ios',
        'tenantId': 'tenant-1',
      });
    });

    test('needs handleCodeInApp', () async {
      for (final bool? inApp in <bool?>[null, false]) {
        await expectLater(
          auth.sendSignInLinkToEmail(
            email: 'ada@example.com',
            actionCodeSettings: ActionCodeSettings(
              url: 'https://example.com/finish',
              handleCodeInApp: inApp,
            ),
          ),
          throwsAuth('argument-error'),
        );
      }
      expect(backend.requests, isEmpty);
    });
  });

  group('signInWithEmailLink', () {
    test('signs in with the code of the link', () async {
      final UserCredential result = await auth.signInWithEmailLink(
        email: 'ada@example.com',
        emailLink: link,
      );
      expect(backend.methods, <String>[
        'accounts:signInWithEmailLink',
        'accounts:lookup',
      ]);
      expect(
        backend.bodiesOf('accounts:signInWithEmailLink').single,
        <String, Object?>{'email': 'ada@example.com', 'oobCode': 'CODE-1'},
      );
      expect(result.uid, 'link-of-ada@example.com');
      expect(result.emailVerified, isTrue);
      expect(result.additionalUserInfo?.isNewUser, isTrue);
      expect(result.additionalUserInfo?.providerId, 'password');
    });

    test('a link that is not an action link is an argument-error', () async {
      await expectLater(
        auth.signInWithEmailLink(
          email: 'ada@example.com',
          emailLink: 'https://example.com/',
        ),
        throwsAuth('argument-error'),
      );
      expect(backend.requests, isEmpty);
    });

    test('the tenant of the link must be the tenant of the instance', () async {
      await expectLater(
        auth.signInWithEmailLink(
          email: 'ada@example.com',
          emailLink: '$link&tenantId=tenant-1',
        ),
        throwsAuth('tenant-id-mismatch'),
      );
      auth.tenantId = 'tenant-1';
      await expectLater(
        auth.signInWithEmailLink(email: 'ada@example.com', emailLink: link),
        throwsAuth('tenant-id-mismatch'),
      );
      expect(backend.requests, isEmpty);
    });

    test('errors of the backend', () async {
      backend.on(
        'accounts:signInWithEmailLink',
        (_) => errorResponse('INVALID_OOB_CODE'),
      );
      await expectLater(
        auth.signInWithEmailLink(email: 'ada@example.com', emailLink: link),
        throwsAuth('invalid-action-code'),
      );
      expect(auth.currentUser, isNull);
    });
  });

  group('email credentials', () {
    test('toString shows no secret', () {
      final AuthCredential password = EmailAuthProvider.credential(
        email: 'ada@example.com',
        password: 'p4ssw0rd',
      );
      final AuthCredential emailLink = EmailAuthProvider.credentialWithLink(
        email: 'ada@example.com',
        emailLink: link,
      );
      expect(
        '$password',
        'EmailAuthCredential(providerId: password, signInMethod: password)',
      );
      expect(
        '$emailLink',
        'EmailAuthCredential(providerId: password, signInMethod: emailLink)',
      );
      expect('$emailLink', isNot(contains('CODE-1')));
    });

    test('signInWithCredential with a password', () async {
      await auth.signInWithCredential(
        EmailAuthProvider.credential(email: 'a@example.com', password: 'p'),
      );
      expect(
        backend.bodiesOf('accounts:signInWithPassword').single,
        <String, Object?>{
          'email': 'a@example.com',
          'password': 'p',
          'returnSecureToken': true,
        },
      );
      expect(auth.uid, 'uid-of-a@example.com');
    });

    test(
      'link a password to an anonymous user: accounts:signUp with the ID token',
      () async {
        await auth.signInAnonymously();
        auth.tenantId = null;
        final String idToken = (await auth.getAccessToken(
          forceRefresh: false,
        )).token;
        backend.requests.clear();
        final UserCredential result = await auth.linkWithCredential(
          EmailAuthProvider.credential(email: 'a@example.com', password: 'p'),
        );
        expect(backend.methods, <String>[
          'accounts:lookup', // _assertLinkedStatus
          'accounts:signUp',
          'accounts:lookup',
        ]);
        expect(backend.bodiesOf('accounts:signUp').single, <String, Object?>{
          'idToken': idToken,
          'email': 'a@example.com',
          'password': 'p',
          'returnSecureToken': true,
        });
        expect(result.uid, 'anon-user');
        expect(result.isAnonymous, isFalse);
        expect(result.email, 'a@example.com');
        expect(auth.currentUser!.providerData.single.providerId, 'password');
        // Linked already.
        await expectLater(
          auth.linkWithCredential(
            EmailAuthProvider.credentialWithLink(
              email: 'a@example.com',
              emailLink: link,
            ),
          ),
          throwsAuth('provider-already-linked'),
        );
      },
    );

    test('link an email link to an anonymous user', () async {
      await auth.signInAnonymously();
      auth.tenantId = null;
      final String idToken = (await auth.getAccessToken(
        forceRefresh: false,
      )).token;
      await auth.linkWithCredential(
        EmailAuthProvider.credentialWithLink(
          email: 'ada@example.com',
          emailLink: link,
        ),
      );
      expect(
        backend.bodiesOf('accounts:signInWithEmailLink').single,
        <String, Object?>{
          'idToken': idToken,
          'email': 'ada@example.com',
          'oobCode': 'CODE-1',
        },
      );
      expect(auth.currentUser!.isAnonymous, isFalse);
      expect(auth.currentUser!.emailVerified, isTrue);
    });

    test('link needs a signed-in user', () async {
      await expectLater(
        auth.linkWithCredential(
          EmailAuthProvider.credential(email: 'a@example.com', password: 'p'),
        ),
        throwsAuth('null-user'),
      );
    });

    test('reauthenticate with an email link', () async {
      await auth.signInWithEmailLink(email: 'ada@example.com', emailLink: link);
      final UserCredential again = await auth.reauthenticateWithCredential(
        EmailAuthProvider.credentialWithLink(
          email: 'ada@example.com',
          emailLink: link,
        ),
      );
      expect(again.uid, 'link-of-ada@example.com');
      expect(backend.bodiesOf('accounts:signInWithEmailLink'), hasLength(2));
      // The link of another address is another account.
      await expectLater(
        auth.reauthenticateWithCredential(
          EmailAuthProvider.credentialWithLink(
            email: 'bob@example.com',
            emailLink: link,
          ),
        ),
        throwsAuth('user-mismatch'),
      );
      expect(auth.uid, 'link-of-ada@example.com');
    });

    test('a credential of another kind is refused', () async {
      await expectLater(
        auth.signInWithCredential(const _Other()),
        throwsArgumentError,
      );
    });
  });
}

class _Other extends AuthCredential {
  const _Other() : super(providerId: 'other', signInMethod: 'other');
}
