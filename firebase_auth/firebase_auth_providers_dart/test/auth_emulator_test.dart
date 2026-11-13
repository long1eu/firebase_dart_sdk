// FirebaseUserAuth against the Firebase Auth emulator (the real request and response shapes).
//
//     tool/start_auth_emulators.sh        # repository root; prints the export
//     FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9197 dart test test/auth_emulator_test.dart
//
// Skipped unless FIREBASE_AUTH_EMULATOR_HOST is set. Never talks to the real service.

@TestOn('vm')
library;

import 'dart:convert';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:test/test.dart';

int _counter = 0;
String uniqueEmail() =>
    'user${DateTime.now().microsecondsSinceEpoch}x${_counter++}@example.com';

Matcher throwsAuth(Object code) => throwsA(isA<FirebaseAuthProviderException>()
    .having((FirebaseAuthProviderException e) => e.code, 'code', code));

void main() {
  final String? host = FirebaseUserAuth.emulatorHostFromEnvironment;
  final String? skip = host == null
      ? 'FIREBASE_AUTH_EMULATOR_HOST is not set (start the emulators with tool/start_auth_emulators.sh)'
      : null;

  late InMemoryAuthStorage storage;
  final List<FirebaseUserAuth> created = <FirebaseUserAuth>[];

  FirebaseUserAuth create() {
    final FirebaseUserAuth auth = FirebaseUserAuth(
        apiKey: 'fake-api-key', emulatorHost: host, storage: storage);
    created.add(auth);
    return auth;
  }

  setUp(() => storage = InMemoryAuthStorage());

  tearDown(() async {
    for (final FirebaseUserAuth auth in created) {
      await auth.dispose();
    }
    created.clear();
  });

  group('Auth emulator', () {
    test('anonymous sign-in, token, refresh and sign-out', () async {
      final FirebaseUserAuth auth = create();
      final AuthUser user = await auth.signInAnonymously();
      expect(user.isAnonymous, isTrue);
      expect(user.uid, isNotEmpty);

      final GetTokenResult token =
          await auth.getAccessToken(forceRefresh: false);
      expect(token.claims['user_id'], user.uid);
      expect(token.signInProvider, 'anonymous');
      expect(token.expirationTimestamp.isAfter(DateTime.now()), isTrue);

      // The token endpoint issues a token with a later `iat` (one second resolution).
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      final GetTokenResult refreshed =
          await auth.getAccessToken(forceRefresh: true);
      expect(refreshed.token, isNot(token.token));
      expect(refreshed.claims['user_id'], user.uid);

      await auth.signOut();
      expect(auth.uid, isNull);
      await expectLater(auth.getAccessToken(forceRefresh: false),
          throwsA(isA<FirebaseNoSignedInUserError>()));
    });

    test('email and password: create, sign in, and the errors of the backend',
        () async {
      final FirebaseUserAuth auth = create();
      final String email = uniqueEmail();
      final AuthUser createdUser =
          await auth.createUserWithEmailAndPassword(email, 'correct horse');
      expect(createdUser.email, email);
      expect(createdUser.isAnonymous, isFalse);
      await auth.signOut();

      final AuthUser signedIn =
          await auth.signInWithEmailAndPassword(email, 'correct horse');
      expect(signedIn.uid, createdUser.uid);
      expect((await auth.getAccessToken(forceRefresh: false)).claims['email'],
          email);
      await auth.signOut();

      await expectLater(auth.signInWithEmailAndPassword(email, 'wrong'),
          throwsAuth(anyOf('wrong-password', 'invalid-credential')));
      await expectLater(
          auth.signInWithEmailAndPassword(uniqueEmail(), 'whatever'),
          throwsAuth(anyOf('user-not-found', 'invalid-credential')));
      await expectLater(
          auth.createUserWithEmailAndPassword(email, 'another password'),
          throwsAuth('email-already-in-use'));
      await expectLater(auth.createUserWithEmailAndPassword(uniqueEmail(), '1'),
          throwsAuth('weak-password'));
      await expectLater(
          auth.createUserWithEmailAndPassword('not an email', 'password'),
          throwsAuth('invalid-email'));
      expect(auth.uid, isNull);
    });

    test('custom token sign-in', () async {
      // The emulator accepts an unsigned custom token; a real one is signed by a service account.
      String encode(Object json) =>
          base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
      final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final String uid = 'custom-${DateTime.now().microsecondsSinceEpoch}';
      final String customToken =
          '${encode(<String, Object?>{'alg': 'none', 'typ': 'JWT'})}.'
          '${encode(<String, Object?>{
            'iss': 'tests@example.com',
            'sub': 'tests@example.com',
            'aud':
                'https://identitytoolkit.googleapis.com/google.identity.identitytoolkit.v1.IdentityToolkit',
            'iat': now,
            'exp': now + 3600,
            'uid': uid,
            'claims': <String, Object?>{'role': 'tester'},
          })}.';
      final FirebaseUserAuth auth = create();
      final AuthUser user = await auth.signInWithCustomToken(customToken);
      expect(user.uid, uid);
      final GetTokenResult token =
          await auth.getAccessToken(forceRefresh: false);
      expect(token.claims['role'], 'tester');
      expect(token.signInProvider, 'custom');

      await expectLater(auth.signInWithCustomToken('garbage'),
          throwsAuth('invalid-custom-token'));
    });

    test('a stored session is restored by a new instance', () async {
      final FirebaseUserAuth first = create();
      final AuthUser user = await first.signInAnonymously();
      await first.dispose();

      final FirebaseUserAuth second = create();
      await second.restore();
      expect(second.uid, user.uid);
      expect(
          (await second.getAccessToken(forceRefresh: false)).claims['user_id'],
          user.uid);
    });

    test('a deleted account ends the session at the next refresh', () async {
      final FirebaseUserAuth auth = create();
      final AuthUser user = await auth.signInAnonymously();
      // Another instance with the same session deletes the account.
      final FirebaseUserAuth other = create();
      await other.restore();
      expect(other.uid, user.uid);
      await other.deleteCurrentUser();
      expect(other.uid, isNull);

      // The first instance still has its ID token; the refresh is refused and it signs out.
      expect(auth.uid, user.uid);
      await expectLater(
          auth.getAccessToken(forceRefresh: true),
          throwsA(isA<FirebaseAuthProviderException>().having(
              (FirebaseAuthProviderException e) => e.invalidatesSession,
              'invalidatesSession',
              isTrue)));
      expect(auth.uid, isNull);
    });
  }, skip: skip);
}
