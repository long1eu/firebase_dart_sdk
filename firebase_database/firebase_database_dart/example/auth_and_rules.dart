// Acting as a signed-in user, and a rule that refuses.
//
// Shows: mockUserToken, security rules, FirebaseDatabaseException with
// permission-denied.
// Platform: Dart VM.
// Run: FIREBASE_DATABASE_EMULATOR_HOST=127.0.0.1:9100 dart run example/auth_and_rules.dart
// Backend: Realtime Database emulator, project demo-example. The program loads
// its own rules into the namespace demo-example-default-rtdb when it starts, with
// PUT /.settings/rules.json?ns=demo-example-default-rtdb and `Authorization:
// Bearer owner` (setEmulatorRules in common.dart), and puts open rules back when
// it ends, also after an error. It refuses to do this against anything but a
// local emulator. The rules are:
//
//     { "rules": { "example-private": {
//         "$uid": { ".read": "auth.uid === $uid", ".write": "auth.uid === $uid" } } } }

import 'package:firebase_database_dart/firebase_database_dart.dart';

import 'common.dart';

/// The rules this program needs (see the header).
const String _rules = r'''
{"rules": {"example-private": {
  "$uid": {".read": "auth.uid === $uid", ".write": "auth.uid === $uid"}}}}
''';

Future<void> main() async {
  await setEmulatorRules(_rules);
  try {
    await _run();
  } finally {
    // Open rules again, so that the examples run next see the emulator as
    // it started.
    await setEmulatorRules(openRules);
  }
}

Future<void> _run() async {
  // No user: rules that read `auth` see null.
  final FirebaseDatabase anonymous = emulatorDatabase(appName: 'anonymous');
  // A mock user: mockUserTokenFor builds an unsigned token that the emulator
  // takes as the signed-in user `ada`. Only the emulator accepts it. Do not
  // pass a plain string: the emulator treats that as an admin credential,
  // which bypasses the rules. With a real project the token comes from the
  // app's Auth (firebase_auth_providers_dart); there is nothing to pass here.
  final FirebaseDatabase ada = emulatorDatabase(
    mockUserToken: mockUserTokenFor('ada', projectId: projectId),
    appName: 'ada',
  );
  final String key = freshKey('auth');
  try {
    // A refused write fails with a FirebaseDatabaseException. The write was
    // already applied locally and is rolled back with events before the
    // Future fails.
    try {
      await anonymous.ref('example-private/ada/$key').set('secret');
      print('anonymous write: allowed');
    } on FirebaseDatabaseException catch (error) {
      print('anonymous write: ${error.code}');
    }

    try {
      await ada.ref('example-private/ada/$key').set('secret');
      print('ada write: allowed');
      final DataSnapshot read = await ada.ref('example-private/ada/$key').get();
      print('ada reads: ${read.value}');
    } on FirebaseDatabaseException catch (error) {
      print('ada write: ${error.code} (${error.serverStatus})');
    }

    // A refused read: get() fails, and a listener gets the error on its
    // stream, which then ends.
    try {
      await anonymous.ref('example-private/ada/$key').onValue.first;
      print('anonymous read: allowed');
    } on FirebaseDatabaseException catch (error) {
      print('anonymous read: ${error.code}');
    }
  } finally {
    try {
      await ada.ref('example-private/ada/$key').remove();
    } on FirebaseDatabaseException {
      // Not allowed or nothing to remove: nothing to clean up.
    }
    await anonymous.close();
    await ada.close();
  }
}
