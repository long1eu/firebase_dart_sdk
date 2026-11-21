// Keeps the session of a FirebaseUserAuth in the secure store of the platform.
//
// With firebase_auth_dart_platform (the official firebase_auth API), pass the
// same storage to FirebaseAuthDart.use instead:
//
//   final SecureAuthStorage storage = SecureAuthStorage();
//   FirebaseAuthDart.use(storageFor: (FirebaseApp app) => storage);
//
// Run it against an emulator started with
// `firebase emulators:start --only auth` (project demo-test).

import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:firebase_auth_secure_storage_flutter/firebase_auth_secure_storage_flutter.dart';
import 'package:flutter/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final FirebaseUserAuth auth = FirebaseUserAuth(
    apiKey: 'demo-api-key',
    storage: SecureAuthStorage(),
    emulatorHost: '127.0.0.1:9099',
  );
  try {
    await auth.restore();
  } on SecureAuthStorageException catch (e) {
    // No keyring, a locked keychain, a missing entitlement: the message says
    // which, and what to do.
    debugPrint('$e');
    return;
  }
  if (auth.uid == null) {
    await auth.signInAnonymously();
  }
  debugPrint('Signed in as ${auth.uid}; the session survives a restart.');
  await auth.dispose();
}
