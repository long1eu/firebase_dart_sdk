// Signs in an anonymous user against the Firebase Auth emulator and prints who is signed in.
//
//     tool/start_auth_emulators.sh        (repository root; needs the firebase CLI)
//     FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9197 dart run example/main.dart
//
// Against a real project, pass its Web API key and leave the emulator host out. With
// cloud_firestore_dart, create the Firestore instance after `FirebaseUserAuth.forApp(app)`:
// its requests then carry the ID token of the signed-in user.

// ignore_for_file: avoid_print

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';

Future<void> main() async {
  final String? emulator = FirebaseUserAuth.emulatorHostFromEnvironment;
  if (emulator == null) {
    print(
        'Set FIREBASE_AUTH_EMULATOR_HOST (see the comment at the top of this file).');
    return;
  }

  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'fake-api-key',
      applicationId: '1:1234567890:dart:example',
      projectId: 'demo-test',
    ),
  );
  final FirebaseUserAuth auth =
      await FirebaseUserAuth.forApp(app, emulatorHost: emulator);
  auth.userChanges.listen(
      (AuthUser? user) => print('user changed: ${user?.uid ?? 'signed out'}'));

  final AuthUser user = await auth.signInAnonymously();
  final GetTokenResult token = await auth.getAccessToken(forceRefresh: false);
  print('signed in: ${user.uid} (anonymous: ${user.isAnonymous}), '
      'token expires ${token.expirationTimestamp.toUtc()}');

  await auth.deleteCurrentUser();
  await auth.dispose();
  app.delete();
}
