// The loop of a test or a job, end to end against the Firebase Auth emulator: create a user, mint a custom
// token with claims, sign in with it through firebase_auth_providers_dart, read the claims of the ID token,
// verify the ID token, delete the user.
//
//     firebase emulators:start --only auth --project demo-test     (or tool/start_auth_emulators.sh)
//     FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 dart run example/main.dart
//
// With a real project the only change is the app: FirebaseAdminApp(projectId: ..., credential:
// AdminCredential.serviceAccount(key)) and a FirebaseUserAuth with the Web API key and no emulator host. See
// example/production_check.dart.

// ignore_for_file: avoid_print

import 'package:firebase_admin_dart/auth.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';

Future<void> main() async {
  // Read explicitly: the admin package never picks the emulator from the environment on its own.
  final String? emulator = FirebaseUserAuth.emulatorHostFromEnvironment;
  if (emulator == null) {
    print(
      'Set FIREBASE_AUTH_EMULATOR_HOST (see the comment at the top of this file).',
    );
    return;
  }

  final FirebaseAdminApp app = FirebaseAdminApp.emulator(
    projectId: 'demo-test',
    authEmulatorHost: emulator,
  );
  final FirebaseAuthAdmin admin = app.auth();
  // The client side, as the app under test would run it.
  final FirebaseUserAuth client = FirebaseUserAuth(
    apiKey: 'fake-api-key',
    emulatorHost: emulator,
  );

  final AdminUser user = await admin.createUser(
    displayName: 'Test user',
    customClaims: <String, Object?>{'role': 'tester'},
  );
  try {
    print('created ${user.uid} with claims ${user.customClaims}');

    // The claims of the token are added to those of the user, for this sign-in.
    final String customToken = await admin.createCustomToken(
      user.uid,
      claims: <String, Object?>{'tier': 'pro'},
    );
    await client.signInWithCustomToken(customToken);

    final GetTokenResult idToken = await client.getAccessToken(
      forceRefresh: false,
    );
    print(
      'claims seen by the client: role=${idToken.claims['role']}, tier=${idToken.claims['tier']}',
    );

    // What a server does with the ID token a client sends it.
    final VerifiedIdToken verified = await admin.verifyIdToken(
      idToken.token,
      checkRevoked: true,
    );
    print(
      'verified: uid matches ${verified.uid == user.uid}, provider ${verified.signInProvider}',
    );
  } finally {
    await admin.deleteUser(user.uid);
    print('deleted ${user.uid}');
    await client.dispose();
    await app.close();
  }
}
