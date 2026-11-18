// Keeping the user signed in across restarts: the package's FileAuthStorage,
// against the Firebase Auth emulator.
//
//     tool/start_auth_emulators.sh        (repository root; needs the firebase CLI)
//     FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9197 dart run example/persistent_session.dart
//
// The program plays two runs of a command line tool: the first signs in, the
// second finds the user signed in. The session file goes to a temporary
// directory that the program removes at the end; a real tool keeps it in the
// configuration directory of the user. Dart VM only (dart:io); on the web use
// WebAuthStorage.
//
// The stored value holds the refresh token: whoever reads it can act as the
// user. FileAuthStorage writes the file readable by its owner only (mode 0600,
// in a directory with mode 0700) on macOS and Linux; on Windows the file
// inherits the access list of its directory (keep it in the user's profile).
// In Flutter apps on mobile, the secret store of the platform (for example
// flutter_secure_storage) is the better place.

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';

const FirebaseOptions _options = FirebaseOptions(
  apiKey: 'fake-api-key',
  appId: '1:1234567890:dart:example',
  projectId: 'demo-test',
);

Future<void> main() async {
  final String? emulator = FirebaseUserAuth.emulatorHostFromEnvironment;
  if (emulator == null) {
    print(
      'Set FIREBASE_AUTH_EMULATOR_HOST (see the comment at the top of this file).',
    );
    return;
  }
  final Directory home = await Directory.systemTemp.createTemp('auth_example');
  final File sessionFile = File('${home.path}/config/session.json');

  try {
    // The first run: nobody is signed in, the user signs in.
    final String uid = await _run(emulator, sessionFile, (
      FirebaseUserAuth auth,
    ) async {
      print('first run, signed in: ${auth.currentUser != null}');
      final AuthUser user = await auth.signInAnonymously();
      return user.uid;
    });
    if (Platform.isMacOS || Platform.isLinux) {
      print('session file mode: ${sessionFile.statSync().modeString()}');
    }

    // The second run: the session is restored from the file.
    await _run(emulator, sessionFile, (FirebaseUserAuth auth) async {
      print('second run, same user: ${auth.currentUser?.uid == uid}');
      // The restored session has no ID token yet: the first request gets one
      // with the stored refresh token.
      final GetTokenResult token = await auth.getAccessToken(
        forceRefresh: false,
      );
      print('fresh ID token for the user: ${token.claims['user_id'] == uid}');
      // Deleting the account signs out (as signOut() does), which removes the
      // session from the storage.
      await auth.deleteCurrentUser();
      return uid;
    });
    // The last value gone, FileAuthStorage removes the file.
    print('session file removed: ${!sessionFile.existsSync()}');
  } finally {
    await home.delete(recursive: true);
  }
}

/// One run of the tool: an app, a [FirebaseUserAuth] on [sessionFile], and
/// [body].
Future<String> _run(
  String emulator,
  File sessionFile,
  Future<String> Function(FirebaseUserAuth auth) body,
) async {
  final FirebaseApp app = FirebaseApp.withOptions(_options);
  final FirebaseUserAuth auth = await FirebaseUserAuth.forApp(
    app,
    storage: FileAuthStorage(sessionFile.path),
    emulatorHost: emulator,
  );
  try {
    return await body(auth);
  } finally {
    await auth.dispose();
    await app.delete();
  }
}
