// The account flows of an email and password user against the Firebase Auth
// emulator: sign up, verify the email address, update the profile, reset a
// forgotten password, delete the account.
//
//     tool/start_auth_emulators.sh        (repository root; needs the firebase CLI)
//     FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9197 dart run example/account_flows.dart
//
// A real project sends emails with links that carry an action code; the user
// opens the link and your app (or the hosted Firebase page) passes the code
// to `applyActionCode` or `confirmPasswordReset`. The emulator sends no email:
// it lists the codes at its oobCodes endpoint, which this program reads in
// place of an inbox. The project is demo-test (the one
// tool/start_auth_emulators.sh starts), or FIREBASE_AUTH_EMULATOR_PROJECT.

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

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
  final String project =
      Platform.environment['FIREBASE_AUTH_EMULATOR_PROJECT'] ?? 'demo-test';
  final Inbox inbox = Inbox(emulator, project);

  final FirebaseApp app = FirebaseApp.withOptions(
    FirebaseOptions(
      apiKey: 'fake-api-key',
      applicationId: '1:1234567890:dart:example',
      projectId: project,
    ),
  );
  final FirebaseUserAuth auth = await FirebaseUserAuth.forApp(
    app,
    emulatorHost: emulator,
  );

  // Sign up. A new address per run, so that the program can run again.
  final String email =
      'ada${DateTime.now().microsecondsSinceEpoch}@example.com';
  final AuthUser user = await auth.createUserWithEmailAndPassword(
    email,
    'first password',
  );
  print('signed up, email verified: ${user.emailVerified}');

  // Verify the email address.
  await auth.sendEmailVerification();
  await auth.applyActionCode(await inbox.code(email, 'VERIFY_EMAIL'));
  // applyActionCode does not reload the signed-in user (as in the JS SDK).
  await auth.reload();
  print('email verified: ${auth.currentUser!.emailVerified}');

  await auth.updateProfile(displayName: 'Ada Lovelace');
  print('display name: ${auth.currentUser!.displayName}');

  // Reset a forgotten password: the user is signed out and asks for an email.
  await auth.signOut();
  await auth.sendPasswordResetEmail(email);
  final String resetCode = await inbox.code(email, 'PASSWORD_RESET');
  // The page that handles the link can show whose password it resets.
  print(
    'reset code is for this address: '
    '${await auth.verifyPasswordResetCode(resetCode) == email}',
  );
  await auth.confirmPasswordReset(resetCode, 'second password');
  try {
    await auth.signInWithEmailAndPassword(email, 'first password');
  } on FirebaseAuthProviderException catch (e) {
    print('old password refused: ${e.code}');
  }
  final AuthUser again = await auth.signInWithEmailAndPassword(
    email,
    'second password',
  );
  print('signed in with the new password, same user: ${again.uid == user.uid}');

  // Deleting an account needs a recent sign-in, as do password and email
  // changes; reauthenticate when the backend answers requires-recent-login.
  await auth.reauthenticateWithEmailAndPassword(email, 'second password');
  await auth.deleteCurrentUser();
  print('account deleted, signed in: ${auth.currentUser != null}');

  await auth.dispose();
  app.delete();
}

/// Reads the action codes the emulator would have sent by email.
class Inbox {
  Inbox(this._emulator, this._project);

  final String _emulator;
  final String _project;

  /// The last code of [requestType] (`VERIFY_EMAIL`, `PASSWORD_RESET`, ...)
  /// sent to [email].
  Future<String> code(String email, String requestType) async {
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request = await client.getUrl(
        Uri.parse('http://$_emulator/emulator/v1/projects/$_project/oobCodes'),
      );
      final HttpClientResponse response = await request.close();
      final Map<String, Object?> body =
          jsonDecode(await utf8.decodeStream(response)) as Map<String, Object?>;
      final List<Object?> codes =
          body['oobCodes'] as List<Object?>? ?? const <Object?>[];
      for (final Object? entry in codes.reversed) {
        final Map<String, Object?> code = entry! as Map<String, Object?>;
        if (code['email'] == email && code['requestType'] == requestType) {
          return code['oobCode']! as String;
        }
      }
      throw StateError('The emulator has no $requestType code for $email.');
    } finally {
      client.close(force: true);
    }
  }
}
