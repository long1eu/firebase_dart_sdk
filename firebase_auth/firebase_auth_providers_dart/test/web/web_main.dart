// Compiled (not run) by web_compile_test.dart: the main library must not need dart:io.

import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';

void main() {
  final FirebaseUserAuth auth = FirebaseUserAuth(apiKey: 'key');
  // ignore: avoid_print
  print(<Object?>[
    auth.uid,
    FirebaseUserAuth.emulatorHostFromEnvironment,
    OAuthTokenProvider.datastoreScopes,
    InMemoryAuthStorage(),
    const FirebaseAuthProviderException('code', 'message'),
    OAuthTokenProvider.serviceAccount,
  ]);
}
