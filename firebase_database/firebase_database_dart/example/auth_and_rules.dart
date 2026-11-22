// Acting as a signed-in user, and a rule that refuses.
//
// Shows: mockUserToken, security rules, FirebaseDatabaseException with
// permission-denied.
// Platform: Dart VM.
// Run: FIREBASE_DATABASE_EMULATOR_HOST=127.0.0.1:9000 dart run example/auth_and_rules.dart
// Backend: Realtime Database emulator, project demo-example, started with rules
// such as the ones below (database.rules.json of the emulator):
//
//     { "rules": { "example-private": {
//         "$uid": { ".read": "auth.uid === $uid", ".write": "auth.uid === $uid" } } } }
//
// Without those rules the emulator's own rules apply and the program prints
// what it saw.

import 'package:firebase_database_dart/firebase_database_dart.dart';

import 'common.dart';

Future<void> main() async {
  // No user: rules that read `auth` see null.
  final FirebaseDatabase anonymous = emulatorDatabase(appName: 'anonymous');
  // A mock user: the emulator takes the token as a signed-in user. Only the
  // emulator accepts it. With a real project the token comes from the app's
  // Auth (firebase_auth_providers_dart); there is nothing to pass here.
  final FirebaseDatabase ada = emulatorDatabase(
    mockUserToken: 'ada',
    appName: 'ada',
  );
  final String key = freshKey('auth');
  try {
    // A refused write fails with a FirebaseDatabaseException. The write was
    // already applied locally and is rolled back with events before the
    // Future fails.
    try {
      await anonymous.ref('example-private/ada/$key').set('secret');
      print('anonymous write: allowed by the rules of this emulator');
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
