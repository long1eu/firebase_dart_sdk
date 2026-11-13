// The account operations of FirebaseUserAuth against the Firebase Auth emulator: password reset, email
// verification and action codes, email, password and profile updates, reauthentication, deletion and the sign-in
// methods of an email address. The action codes come from the emulator's oobCodes endpoint.
//
//     tool/start_auth_emulators.sh        # repository root; prints the export
//     FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9197 dart test test/account_management_emulator_test.dart
//
// Skipped unless FIREBASE_AUTH_EMULATOR_HOST is set. The project of the emulator is demo-test (the one
// tool/start_auth_emulators.sh starts), or FIREBASE_AUTH_EMULATOR_PROJECT.

@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:test/test.dart';

int _counter = 0;
String uniqueEmail([String prefix = 'user']) =>
    '$prefix${DateTime.now().microsecondsSinceEpoch}x${_counter++}@example.com';

Matcher throwsAuth(Object code) => throwsA(
  isA<FirebaseAuthProviderException>().having(
    (FirebaseAuthProviderException e) => e.code,
    'code',
    code,
  ),
);

void main() {
  final String? host = FirebaseUserAuth.emulatorHostFromEnvironment;
  final String project =
      Platform.environment['FIREBASE_AUTH_EMULATOR_PROJECT'] ?? 'demo-test';
  final String? skip = host == null
      ? 'FIREBASE_AUTH_EMULATOR_HOST is not set (start the emulators with tool/start_auth_emulators.sh)'
      : null;

  final List<FirebaseUserAuth> created = <FirebaseUserAuth>[];

  FirebaseUserAuth create() {
    final FirebaseUserAuth auth = FirebaseUserAuth(
      apiKey: 'fake-api-key',
      emulatorHost: host,
    );
    created.add(auth);
    return auth;
  }

  tearDown(() async {
    for (final FirebaseUserAuth auth in created) {
      await auth.dispose();
    }
    created.clear();
  });

  /// The last action code the emulator "sent" to [email] for [requestType].
  Future<String> oobCode(String email, String requestType) async {
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request = await client.getUrl(
        Uri.parse('http://$host/emulator/v1/projects/$project/oobCodes'),
      );
      final HttpClientResponse response = await request.close();
      final Map<String, Object?> body =
          jsonDecode(await utf8.decodeStream(response)) as Map<String, Object?>;
      final List<Map<String, Object?>>
      codes = (body['oobCodes'] as List<Object?>? ?? const <Object?>[])
          .cast<Map<String, Object?>>()
          .where(
            (Map<String, Object?> c) =>
                // A change of address is listed under the current address, with the new one in newEmail.
                (c['email'] == email || c['newEmail'] == email) &&
                c['requestType'] == requestType,
          )
          .toList();
      expect(codes, isNotEmpty, reason: 'no $requestType code for $email');
      return codes.last['oobCode']! as String;
    } finally {
      client.close(force: true);
    }
  }

  group('Account management on the Auth emulator', () {
    test('password reset: send, check, confirm', () async {
      final FirebaseUserAuth auth = create();
      final String email = uniqueEmail('reset');
      await auth.createUserWithEmailAndPassword(email, 'old-password');
      await auth.signOut();

      await auth.sendPasswordResetEmail(email);
      final String code = await oobCode(email, 'PASSWORD_RESET');
      expect(await auth.verifyPasswordResetCode(code), email);
      final ActionCodeInfo info = await auth.checkActionCode(code);
      expect(info.operation, ActionCodeOperation.passwordReset);
      expect(info.email, email);

      await expectLater(
        auth.confirmPasswordReset(code, '1'),
        throwsAuth('weak-password'),
      );
      await auth.confirmPasswordReset(code, 'new-password');
      await expectLater(
        auth.confirmPasswordReset(code, 'another-password'),
        throwsAuth('invalid-action-code'),
      );
      await expectLater(
        auth.signInWithEmailAndPassword(email, 'old-password'),
        throwsAuth(anyOf('wrong-password', 'invalid-credential')),
      );
      expect(
        (await auth.signInWithEmailAndPassword(email, 'new-password')).email,
        email,
      );

      // With action code settings, and the errors.
      await auth.sendPasswordResetEmail(
        email,
        actionCodeSettings: const ActionCodeSettings(
          url: 'https://example.com/after-reset',
          handleCodeInApp: false,
        ),
      );
      await expectLater(
        auth.sendPasswordResetEmail(
          email,
          actionCodeSettings: const ActionCodeSettings(url: ''),
        ),
        throwsAuth('invalid-continue-uri'),
      );
      await expectLater(
        auth.sendPasswordResetEmail(uniqueEmail('nobody')),
        throwsAuth('user-not-found'),
      );
      await expectLater(
        auth.checkActionCode('not-a-code'),
        throwsAuth('invalid-action-code'),
      );
    });

    test('email verification: send, apply, reload', () async {
      final FirebaseUserAuth auth = create();
      final String email = uniqueEmail('verify');
      await auth.createUserWithEmailAndPassword(email, 'password');
      expect(auth.currentUser!.emailVerified, isFalse);
      final List<AuthUser?> changes = <AuthUser?>[];
      final StreamSubscription<AuthUser?> sub = auth.userChanges.listen(
        changes.add,
      );
      addTearDown(sub.cancel);

      await auth.sendEmailVerification();
      final String code = await oobCode(email, 'VERIFY_EMAIL');
      expect(
        (await auth.checkActionCode(code)).operation,
        ActionCodeOperation.verifyEmail,
      );
      await auth.applyActionCode(code);
      // Like the JS SDK, the user is not reloaded by applyActionCode.
      expect(auth.currentUser!.emailVerified, isFalse);
      await auth.reload();
      expect(auth.currentUser!.emailVerified, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(changes.last!.emailVerified, isTrue);
      // A new ID token says so too.
      expect(
        (await auth.getAccessToken(
          forceRefresh: true,
        )).claims['email_verified'],
        isTrue,
      );
      await expectLater(
        auth.applyActionCode(code),
        throwsAuth('invalid-action-code'),
      );
    });

    test('update email and password; the session continues', () async {
      final FirebaseUserAuth auth = create();
      final String email = uniqueEmail('before');
      final AuthUser user = await auth.createUserWithEmailAndPassword(
        email,
        'password-1',
      );
      final List<String> tokens = <String>[];
      final StreamSubscription<InternalTokenResult> sub = auth.onTokenChanged
          .listen((InternalTokenResult r) => tokens.add(r.token));
      addTearDown(sub.cancel);

      final String newEmail = uniqueEmail('after');
      await auth.updateEmail(newEmail);
      expect(auth.uid, user.uid);
      expect(auth.currentUser!.email, newEmail);
      expect(
        (await auth.getAccessToken(forceRefresh: false)).claims['email'],
        newEmail,
      );
      // The ID token stamps `iat` in seconds: wait for a different token.
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await auth.updatePassword('password-2');
      expect(auth.uid, user.uid);
      expect(tokens, hasLength(2), reason: 'a new ID token after each update');
      expect(tokens.toSet(), hasLength(2));

      await expectLater(auth.updatePassword('1'), throwsAuth('weak-password'));
      await expectLater(
        auth.updateEmail('not an email'),
        throwsAuth('invalid-email'),
      );
      final String taken = uniqueEmail('taken');
      await create().createUserWithEmailAndPassword(taken, 'password');
      await expectLater(
        auth.updateEmail(taken),
        throwsAuth('email-already-in-use'),
      );

      await auth.signOut();
      await expectLater(
        auth.signInWithEmailAndPassword(email, 'password-1'),
        throwsAuth(anyOf('user-not-found', 'invalid-credential')),
      );
      expect(
        (await auth.signInWithEmailAndPassword(newEmail, 'password-2')).uid,
        user.uid,
      );
    });

    test('verifyBeforeUpdateEmail changes the email when applied', () async {
      final FirebaseUserAuth auth = create();
      final String email = uniqueEmail('old');
      await auth.createUserWithEmailAndPassword(email, 'password');
      final String newEmail = uniqueEmail('new');
      await auth.verifyBeforeUpdateEmail(newEmail);
      expect(auth.currentUser!.email, email);

      final String code = await oobCode(newEmail, 'VERIFY_AND_CHANGE_EMAIL');
      final ActionCodeInfo info = await auth.checkActionCode(code);
      expect(info.operation, ActionCodeOperation.verifyAndChangeEmail);
      expect(info.email, newEmail);
      expect(info.previousEmail, email);
      await auth.applyActionCode(code);
      await auth.reload();
      expect(auth.currentUser!.email, newEmail);
      expect(auth.currentUser!.emailVerified, isTrue);
      await auth.signOut();
      expect(
        (await auth.signInWithEmailAndPassword(newEmail, 'password')).email,
        newEmail,
      );
    });

    test('updateProfile sets and removes the name and the photo', () async {
      final FirebaseUserAuth auth = create();
      await auth.createUserWithEmailAndPassword(
        uniqueEmail('profile'),
        'pw1234',
      );
      await auth.updateProfile(
        displayName: 'Ada Lovelace',
        photoUrl: 'https://example.com/ada.png',
      );
      expect(auth.currentUser!.displayName, 'Ada Lovelace');
      expect(auth.currentUser!.photoUrl, 'https://example.com/ada.png');
      expect(
        (await auth.getAccessToken(forceRefresh: true)).claims['name'],
        'Ada Lovelace',
      );

      await auth.updateProfile(displayName: 'Ada');
      expect(auth.currentUser!.displayName, 'Ada');
      expect(auth.currentUser!.photoUrl, 'https://example.com/ada.png');

      await auth.updateProfile(displayName: '', photoUrl: '');
      expect(auth.currentUser!.displayName, isNull);
      expect(auth.currentUser!.photoUrl, isNull);
      await auth.reload();
      expect(auth.currentUser!.displayName, isNull);
      expect(auth.currentUser!.photoUrl, isNull);
    });

    test('reauthentication with a password', () async {
      final FirebaseUserAuth auth = create();
      final String email = uniqueEmail('reauth');
      final AuthUser user = await auth.createUserWithEmailAndPassword(
        email,
        'password',
      );
      final String before = (await auth.getAccessToken(
        forceRefresh: false,
      )).token;
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(
        (await auth.reauthenticateWithEmailAndPassword(email, 'password')).uid,
        user.uid,
      );
      expect(
        (await auth.getAccessToken(forceRefresh: false)).token,
        isNot(before),
      );

      await expectLater(
        auth.reauthenticateWithEmailAndPassword(email, 'wrong'),
        throwsAuth(anyOf('wrong-password', 'invalid-credential')),
      );
      final String other = uniqueEmail('other');
      await create().createUserWithEmailAndPassword(other, 'password');
      await expectLater(
        auth.reauthenticateWithEmailAndPassword(other, 'password'),
        throwsAuth('user-mismatch'),
      );
      await expectLater(
        auth.reauthenticateWithEmailAndPassword(uniqueEmail('none'), 'x'),
        throwsAuth(anyOf('user-mismatch', 'invalid-credential')),
      );
      expect(auth.uid, user.uid);
    });

    test('delete, and the operations without a user', () async {
      final FirebaseUserAuth auth = create();
      final String email = uniqueEmail('delete');
      await auth.createUserWithEmailAndPassword(email, 'password');
      await auth.deleteCurrentUser();
      expect(auth.uid, isNull);
      await expectLater(
        auth.signInWithEmailAndPassword(email, 'password'),
        throwsAuth(anyOf('user-not-found', 'invalid-credential')),
      );
      await expectLater(auth.reload(), throwsAuth('null-user'));
      await expectLater(
        auth.updateProfile(displayName: 'x'),
        throwsAuth('null-user'),
      );
      await expectLater(auth.sendEmailVerification(), throwsAuth('null-user'));
    });

    test('an account deleted elsewhere signs the user out on reload', () async {
      final FirebaseUserAuth auth = create();
      final String email = uniqueEmail('gone');
      await auth.createUserWithEmailAndPassword(email, 'password');
      final FirebaseUserAuth other = create();
      await other.signInWithEmailAndPassword(email, 'password');
      await other.deleteCurrentUser();

      await expectLater(auth.reload(), throwsAuth('user-token-expired'));
      expect(auth.uid, isNull);
    });

    test('fetchSignInMethodsForEmail', () async {
      final FirebaseUserAuth auth = create();
      final String email = uniqueEmail('methods');
      await auth.createUserWithEmailAndPassword(email, 'password');
      expect(await auth.fetchSignInMethodsForEmail(email), <String>[
        'password',
      ]);
      expect(
        await auth.fetchSignInMethodsForEmail(uniqueEmail('unknown')),
        isEmpty,
      );
      await expectLater(
        auth.fetchSignInMethodsForEmail('not an email'),
        throwsAuth('invalid-email'),
      );
    });

    test('an anonymous user with an email and a password is no longer '
        'anonymous', () async {
      final FirebaseUserAuth auth = create();
      final AuthUser user = await auth.signInAnonymously();
      expect(user.isAnonymous, isTrue);
      final String email = uniqueEmail('upgrade');
      await auth.updateEmail(email);
      expect(auth.currentUser!.isAnonymous, isTrue);
      await auth.updatePassword('password');
      expect(auth.currentUser!.isAnonymous, isFalse);
      expect(auth.uid, user.uid);
      await auth.signOut();
      expect(
        (await auth.signInWithEmailAndPassword(email, 'password')).uid,
        user.uid,
      );
    });
  }, skip: skip);
}
