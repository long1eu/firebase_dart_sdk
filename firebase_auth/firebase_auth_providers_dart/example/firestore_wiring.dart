// A FirebaseUserAuth wired into Firestore: the security rules see the
// signed-in user. Runs against the Firebase Auth emulator and a Firestore
// emulator whose rules let a user reach only users/<their uid>.
//
//     tool/start_auth_emulators.sh        (repository root; needs the firebase CLI and java)
//     FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9197 \
//     FIRESTORE_AUTH_RULES_EMULATOR_HOST=127.0.0.1:8197 \
//       dart run example/firestore_wiring.dart
//
// The rules are those of tool/auth_emulators/firestore.rules in the
// repository. The order is what matters: create the FirebaseUserAuth (which
// makes itself the token provider of the app) before the Firestore instance,
// which reads the provider once. A server uses an OAuthTokenProvider the same
// way (service_account.dart, adc_server.dart).

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';

Future<void> main() async {
  final String? authEmulator = FirebaseUserAuth.emulatorHostFromEnvironment;
  final String? firestoreEmulator =
      Platform.environment['FIRESTORE_AUTH_RULES_EMULATOR_HOST'];
  if (authEmulator == null ||
      firestoreEmulator == null ||
      firestoreEmulator.isEmpty) {
    print(
      'Set FIREBASE_AUTH_EMULATOR_HOST and FIRESTORE_AUTH_RULES_EMULATOR_HOST '
      '(see the comment at the top of this file).',
    );
    return;
  }

  // Firestore logs every refused request as a warning; this program provokes
  // two on purpose.
  FirebaseFirestore.setLogLevel(LogLevel.error);

  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'fake-api-key',
      appId: '1:1234567890:dart:example',
      projectId: 'demo-test',
    ),
  );

  // 1. The token provider of the app.
  final FirebaseUserAuth auth = await FirebaseUserAuth.forApp(
    app,
    emulatorHost: authEmulator,
  );

  // 2. Then the Firestore instance, which picks it up.
  final int colon = firestoreEmulator.lastIndexOf(':');
  final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
    app: app,
    settings: Settings().withEmulator(
      firestoreEmulator.substring(0, colon),
      int.parse(firestoreEmulator.substring(colon + 1)),
    ),
  );

  // Signed out, the rules refuse the write.
  try {
    await firestore.doc('users/nobody/notes/first').set(<String, Object?>{
      'text': 'hello',
    });
    print('signed out, write accepted');
  } on FirestoreException catch (e) {
    print('signed out, write refused: ${e.errorCode}');
  }

  // Signed in, the user writes below users/<uid>. sign-in completes after
  // Firestore heard about the new user, so this write carries the new token.
  final AuthUser user = await auth.signInAnonymously();
  final DocumentReference<Map<String, Object?>> note = firestore.doc(
    'users/${user.uid}/notes/first',
  );
  await note.set(<String, Object?>{'text': 'hello'});
  final DocumentSnapshot<Map<String, Object?>> snapshot = await note.get(
    Source.server,
  );
  print('signed in, read back: ${snapshot.data?['text']}');

  // Another user's documents stay closed.
  try {
    await firestore.doc('users/somebody-else/notes/first').get(Source.server);
    print('read of another user accepted');
  } on FirestoreException catch (e) {
    print('read of another user refused: ${e.errorCode}');
  }

  await auth.deleteCurrentUser();
  await firestore.terminate();
  await auth.dispose();
  await app.delete();
}
