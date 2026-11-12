// The Firestore emulator and `mockUserToken`: act as a signed-in user without
// Firebase Auth, to test security rules.
//
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run example/emulator_mock_user_token.dart

import 'dart:io';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

import 'common.dart';

Future<void> main() async {
  // The emulator is selected in the settings that are passed when the
  // instance is created. FIRESTORE_EMULATOR_HOST is not read by the SDK
  // itself: read it (or hard-code the address) in your own code.
  final String emulator =
      Platform.environment['FIRESTORE_EMULATOR_HOST'] ?? '127.0.0.1:8080';
  final int colon = emulator.lastIndexOf(':');
  final String host = emulator.substring(0, colon);
  final int port = int.parse(emulator.substring(colon + 1));

  // The claims of the ID token the emulator should see. `sub` (or `user_id`)
  // is the uid that `request.auth.uid` has in the security rules; the other
  // claims are available as `request.auth.token`.
  final Firestore asAlice = await Firestore.instanceFor(
    app: exampleApp('alice'),
    settings: FirestoreSettings(cacheSettings: const MemoryCacheSettings())
        .withEmulator(
      host,
      port,
      mockUserToken: <String, Object?>{
        'sub': 'alice',
        'email': 'alice@example.com',
        'admin': true,
      },
    ),
  );
  print('connected to ${asAlice.projectId} / ${asAlice.databaseName} '
      'on $host:$port');

  final DocumentReference<Map<String, Object?>> profile =
      asAlice.doc('${scratch('profiles')}/alice');
  await profile.set(<String, Object?>{'displayName': 'Alice'});
  print('alice wrote: ${(await profile.get(Source.server)).data}');

  // Without a token the requests are unauthenticated. Whether they are
  // allowed depends on the rules loaded into the emulator; a rule such as
  //
  //     allow write: if request.auth.uid == userId;
  //
  // rejects the write below with `permissionDenied`, while open rules (the
  // emulator's default without a rules file) accept it.
  final Firestore anonymous = await Firestore.instanceFor(
    app: exampleApp('anonymous'),
    settings: emulatorSettings(),
  );
  try {
    await anonymous.doc(profile.path).update(<String, Object?>{'hacked': true});
    print('anonymous write: allowed by the rules');
  } on FirestoreError catch (e) {
    print('anonymous write: ${e.code}');
  }

  await asAlice.terminate();
  await anonymous.terminate();
}
