// A service account as the token provider of an app, for a server or a
// command line tool that you run on a trusted machine.
//
//     FIREBASE_SERVICE_ACCOUNT_KEY_FILE=/path/to/key.json dart run example/service_account.dart
//
// Needs a service account key of a real project (Google Cloud console, IAM,
// Service accounts, Keys) with the Cloud Datastore User role, and network
// access to Google's token endpoint: there is no emulator for this. Keep the
// key file out of the repository and pass its path at run time. Without the
// variable the program prints this note and exits.
//
// The access token of a service account bypasses the security rules: access
// is decided by IAM, and request.auth is not a Firebase user. Where you can,
// prefer Application Default Credentials (adc_server.dart), which need no key
// file on a Google Cloud machine.

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';

Future<void> main() async {
  final String? keyFile =
      Platform.environment['FIREBASE_SERVICE_ACCOUNT_KEY_FILE'];
  if (keyFile == null || keyFile.isEmpty) {
    print(
      'Set FIREBASE_SERVICE_ACCOUNT_KEY_FILE to the path of a service account '
      'key file (see the comment at the top of this file).',
    );
    return;
  }

  // The decoded key file (a String with its content works too). Throws an
  // ArgumentError, without quoting the file, when it is not a key.
  final Map<String, Object?> key =
      jsonDecode(File(keyFile).readAsStringSync()) as Map<String, Object?>;
  final OAuthTokenProvider provider = OAuthTokenProvider.serviceAccount(key);

  final FirebaseApp app = FirebaseApp.withOptions(
    FirebaseOptions(
      // An empty API key is not sent with Firestore requests.
      apiKey: '',
      // Any non-empty id works outside of Android and iOS.
      appId: '1:1234567890:dart:server',
      // The project of the key.
      projectId: key['project_id'] as String?,
    ),
  );
  // Before the Firestore instance of the app is created: Firestore reads the
  // provider once. firestore_wiring.dart shows the Firestore side.
  app.authProvider = provider;

  // The first token request signs an assertion with the key and exchanges it
  // at Google's token endpoint. Later requests reuse the token until five
  // minutes before it expires.
  try {
    final GetTokenResult token = await provider.getAccessToken(
      forceRefresh: false,
    );
    // Never print or log the token itself.
    print(
      'got an access token for ${app.options.projectId}: '
      '${token.token.isNotEmpty}',
    );
    print('a service account is not a user: uid ${provider.uid}');
  } on FirebaseAuthException catch (e) {
    // invalid-credential: the endpoint refused the key (deleted or disabled
    // key, wrong clock); network-request-failed; internal-error.
    print('token request failed: ${e.code}: ${e.message}');
    exitCode = 1;
  } finally {
    await app.delete();
  }
}
