// The official firebase_auth API against the Firebase Auth emulator.
//
//     tool/start_auth_emulators.sh
//     FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9197 flutter test test/emulator_test.dart
//
// Skipped unless FIREBASE_AUTH_EMULATOR_HOST is set. The project is demo-test.

import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_dart_platform/firebase_auth_dart_platform.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart'
    show InMemoryAuthStorage;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

final String? _host = Platform.environment['FIREBASE_AUTH_EMULATOR_HOST'];

void main() {
  final String? skip = _host == null
      ? 'FIREBASE_AUTH_EMULATOR_HOST is not set (tool/start_auth_emulators.sh)'
      : null;
  late FirebaseAuth auth;
  final String email =
      'user${DateTime.now().microsecondsSinceEpoch}@example.com';

  setUpAll(() async {
    if (_host == null) {
      return;
    }
    // flutter_test replaces the HTTP client with one that answers 400.
    HttpOverrides.global = null;
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    FirebaseAuthDart.registerWith();
    FirebaseAuthDart.use(
      storageFor: (FirebaseApp app) => InMemoryAuthStorage(),
    );
    final FirebaseApp app = await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'fake-api-key',
        appId: '1:1:web:1',
        messagingSenderId: '1',
        projectId: 'demo-test',
      ),
    );
    auth = FirebaseAuth.instanceFor(app: app);
    final List<String> parts = _host!.split(':');
    await auth.useAuthEmulator(parts[0], int.parse(parts[1]));
  });

  tearDownAll(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('anonymous sign-in, then link a password', () async {
    final UserCredential anonymous = await auth.signInAnonymously();
    expect(anonymous.user!.isAnonymous, isTrue);
    final UserCredential linked = await anonymous.user!.linkWithCredential(
      EmailAuthProvider.credential(email: email, password: 'first-password'),
    );
    expect(linked.user!.uid, anonymous.user!.uid);
    expect(auth.currentUser!.isAnonymous, isFalse);
    expect(auth.currentUser!.email, email);
  }, skip: skip);

  test('sign out, sign in with the password, read the token', () async {
    await auth.signOut();
    expect(auth.currentUser, isNull);
    final UserCredential credential = await auth.signInWithEmailAndPassword(
      email: email,
      password: 'first-password',
    );
    final IdTokenResult token = await credential.user!.getIdTokenResult();
    expect(token.claims!['email'], email);
    expect(token.signInProvider, 'password');
  }, skip: skip);

  test('a wrong password maps to the official code', () async {
    await expectLater(
      auth.signInWithEmailAndPassword(email: email, password: 'nope-nope'),
      throwsA(
        isA<FirebaseAuthException>().having(
          (FirebaseAuthException e) => e.code,
          'code',
          anyOf('wrong-password', 'invalid-credential'),
        ),
      ),
    );
  }, skip: skip);

  test('profile update, Google credential, streams and delete', () async {
    final User user = auth.currentUser!;
    await user.updateDisplayName('Ada');
    await user.reload();
    expect(auth.currentUser!.displayName, 'Ada');

    // The emulator accepts an unsigned JSON ID token.
    final UserCredential google = await auth.currentUser!.linkWithCredential(
      GoogleAuthProvider.credential(
        idToken:
            '{"sub":"g-${DateTime.now().microsecondsSinceEpoch}",'
            '"email":"$email","email_verified":true}',
      ),
    );
    expect(
      google.user!.providerData.map((UserInfo i) => i.providerId),
      containsAll(<String>['password', 'google.com']),
    );

    final Future<User?> signedOut = auth.authStateChanges().firstWhere(
      (User? u) => u == null,
    );
    await auth.currentUser!.delete();
    expect(await signedOut, isNull);
    await expectLater(
      auth.signInWithEmailAndPassword(email: email, password: 'first-password'),
      throwsA(isA<FirebaseAuthException>()),
    );
  }, skip: skip);
}
