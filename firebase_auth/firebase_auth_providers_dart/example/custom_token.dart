// Sign-in with a custom token against the Firebase Auth emulator: for users
// that your own backend authenticates.
//
//     tool/start_auth_emulators.sh        (repository root; needs the firebase CLI)
//     FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9197 dart run example/custom_token.dart
//
// In production your server mints the token, signed by a service account (for
// example with createCustomToken of the Firebase Admin SDK), and sends it to
// the client after it checked the user its own way. The emulator also accepts
// an unsigned token, which this program builds itself; the real service does
// not.

// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';

Future<void> main() async {
  final String? emulator = FirebaseUserAuth.emulatorHostFromEnvironment;
  if (emulator == null) {
    print(
      'Set FIREBASE_AUTH_EMULATOR_HOST (see the comment at the top of this file).',
    );
    return;
  }

  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'fake-api-key',
      applicationId: '1:1234567890:dart:example',
      projectId: 'demo-test',
    ),
  );
  final FirebaseUserAuth auth = await FirebaseUserAuth.forApp(
    app,
    emulatorHost: emulator,
  );

  // The uid is yours to choose: the id of the user in your own system.
  final String uid = 'customer-${DateTime.now().microsecondsSinceEpoch}';
  final AuthUser user = await auth.signInWithCustomToken(
    _unsignedEmulatorToken(uid, claims: <String, Object?>{'role': 'tester'}),
  );
  print('signed in with the uid of the token: ${user.uid == uid}');

  // The custom claims of the token are in the ID token, and so in
  // request.auth.token of the security rules.
  final GetTokenResult token = await auth.getAccessToken(forceRefresh: false);
  print('sign-in provider: ${token.signInProvider}');
  print('role claim: ${token.claims['role']}');

  // A token that is not a custom token is refused.
  try {
    await auth.signInWithCustomToken('not a token');
  } on FirebaseAuthProviderException catch (e) {
    print('a malformed token: ${e.code}');
  }

  await auth.deleteCurrentUser();
  await auth.dispose();
  app.delete();
}

/// A custom token without a signature, which only the emulator accepts.
String _unsignedEmulatorToken(
  String uid, {
  Map<String, Object?> claims = const <String, Object?>{},
}) {
  String encode(Object json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return '${encode(<String, Object?>{'alg': 'none', 'typ': 'JWT'})}.'
      '${encode(<String, Object?>{'iss': 'emulator@example.com', 'sub': 'emulator@example.com', 'aud': 'https://identitytoolkit.googleapis.com/google.identity.identitytoolkit.v1.IdentityToolkit', 'iat': now, 'exp': now + 3600, 'uid': uid, 'claims': claims})}.';
}
