// Google sign-in for a desktop app or a command line tool: the system browser
// opens Google's sign-in page, the redirect comes back to 127.0.0.1, and the
// Google ID token signs the user in to Firebase.
//
//     GOOGLE_DESKTOP_CLIENT_ID=<client id> \
//     GOOGLE_DESKTOP_CLIENT_SECRET=<client secret> \
//     FIREBASE_API_KEY=<the Web API key of the project> \
//     dart run example/google_desktop_sign_in.dart
//
// It needs an OAuth client of the "Desktop app" type in the Google Cloud
// project of the Firebase project (Google Auth Platform, Clients) and the
// Google provider enabled in Firebase Authentication. Google documents that the
// secret of a desktop client is not confidential; to keep it on a server
// anyway, set GOOGLE_CODE_EXCHANGE_URL to an exchange endpoint (see
// OAuthLoopbackProvider) instead of GOOGLE_DESKTOP_CLIENT_SECRET.
//
// With FIREBASE_AUTH_EMULATOR_HOST set, the Firebase part runs against the Auth
// emulator (FIREBASE_API_KEY is then not needed); the Google part is always
// the real one.

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';

Future<void> main() async {
  final Map<String, String> env = Platform.environment;
  final String? clientId = env['GOOGLE_DESKTOP_CLIENT_ID'];
  final String? emulator = FirebaseUserAuth.emulatorHostFromEnvironment;
  final String? apiKey =
      env['FIREBASE_API_KEY'] ?? (emulator == null ? null : 'fake-api-key');
  if (clientId == null || clientId.isEmpty || apiKey == null) {
    print(
      'Set GOOGLE_DESKTOP_CLIENT_ID and FIREBASE_API_KEY (see the comment at the top of this file).',
    );
    return;
  }
  final String? exchange = env['GOOGLE_CODE_EXCHANGE_URL'];

  final FirebaseUserAuth auth = FirebaseUserAuth(
    apiKey: apiKey,
    emulatorHost: emulator,
  );
  try {
    final UserCredential result = await auth.signInWithOAuthLoopback(
      OAuthLoopbackProvider.google(
        clientId: clientId,
        clientSecret: env['GOOGLE_DESKTOP_CLIENT_SECRET'],
        exchangeEndpoint: exchange == null ? null : Uri.parse(exchange),
      ),
      // Opens the system browser; also print the address, for a machine
      // without one (open it on the same machine: the redirect goes to
      // 127.0.0.1).
      presenter: (Uri url) async {
        print('Sign in in your browser. If it did not open, visit:\n$url\n');
        try {
          await openInSystemBrowser(url);
        } on Object catch (e) {
          print('(could not open the browser: $e)');
        }
      },
    );
    final AuthUser user = result.user!;
    print('signed in: ${user.uid} (${user.email ?? 'no email'})');
    print('new account: ${result.additionalUserInfo?.isNewUser}');
  } on FirebaseAuthException catch (e) {
    print('sign-in failed: ${e.code}: ${e.message}');
    exitCode = 1;
  } finally {
    await auth.dispose();
  }
}
