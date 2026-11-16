// Email and password accounts against the Firebase Auth emulator: sign up,
// sign out, sign in again, and the errors a sign-in form has to handle.
//
//     tool/start_auth_emulators.sh        (repository root; needs the firebase CLI)
//     FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9197 dart run example/email_password.dart
//
// Against a real project, enable the Email/Password provider in the Firebase
// console, pass the Web API key of the project and leave the emulator host
// out. account_flows.dart goes on with email verification, password reset and
// account deletion.

// ignore_for_file: avoid_print

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
      appId: '1:1234567890:dart:example',
      projectId: 'demo-test',
    ),
  );
  final FirebaseUserAuth auth = await FirebaseUserAuth.forApp(
    app,
    emulatorHost: emulator,
  );

  // Sign up. A new address per run, so that the program can run again.
  final String email =
      'grace${DateTime.now().microsecondsSinceEpoch}@example.com';
  final AuthUser created = await auth.createUserWithEmailAndPassword(
    email: email,
    password: 'correct horse battery',
  );
  print(
    'signed up: anonymous ${created.isAnonymous}, '
    'email verified ${created.emailVerified}',
  );

  // Sign out and back in: the same account.
  await auth.signOut();
  print('signed out: ${auth.currentUser == null}');
  final AuthUser signedIn = await auth.signInWithEmailAndPassword(
    email: email,
    password: 'correct horse battery',
  );
  print('signed in again, same user: ${signedIn.uid == created.uid}');

  // The errors of a sign-in form. Projects with email enumeration protection
  // (the default for new projects) answer invalid-credential for both a wrong
  // password and an unknown address.
  await _show(
    'wrong password',
    () => auth.signInWithEmailAndPassword(
      email: email,
      password: 'wrong password',
    ),
  );
  await _show(
    'address taken',
    () => auth.createUserWithEmailAndPassword(
      email: email,
      password: 'another password',
    ),
  );
  await _show(
    'weak password',
    () => auth.createUserWithEmailAndPassword(
      email: 'new-$email',
      password: '123',
    ),
  );
  await _show(
    'bad address',
    () => auth.createUserWithEmailAndPassword(
      email: 'not an address',
      password: 'a password',
    ),
  );

  // A failed sign-in leaves the signed-in user as it was.
  print('still signed in: ${auth.currentUser?.uid == created.uid}');

  await auth.deleteCurrentUser();
  await auth.dispose();
  await app.delete();
}

/// Runs [signIn] and prints the code of the [FirebaseAuthException].
Future<void> _show(String what, Future<AuthUser> Function() signIn) async {
  try {
    await signIn();
    print('$what: no error');
  } on FirebaseAuthException catch (e) {
    print('$what: ${e.code}');
  }
}
