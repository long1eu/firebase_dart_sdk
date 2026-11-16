// Keeping the user signed in across restarts: a file-backed AuthStorage,
// against the Firebase Auth emulator.
//
//     tool/start_auth_emulators.sh        (repository root; needs the firebase CLI)
//     FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9197 dart run example/persistent_session.dart
//
// The program plays two runs of a command line tool: the first signs in, the
// second finds the user signed in. The session file goes to a temporary
// directory that the program removes at the end; a real tool keeps it in the
// configuration directory of the user. Dart VM only (dart:io).
//
// The stored value holds the refresh token: whoever reads it can act as the
// user. This storage creates the file readable by its owner only (mode 0600,
// in a directory with mode 0700) on macOS and Linux. On Windows, on iOS and
// Android, and in Flutter apps in general, use the secret store of the
// platform instead (for example flutter_secure_storage).

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';

/// An [AuthStorage] that keeps its values in a JSON file.
class FileAuthStorage implements AuthStorage {
  /// Creates a storage on top of [file], which need not exist yet.
  FileAuthStorage(this.file);

  /// The file that holds the values.
  final File file;

  Map<String, Object?> _readAll() {
    if (!file.existsSync()) {
      return <String, Object?>{};
    }
    return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  }

  @override
  String? read(String key) => _readAll()[key] as String?;

  @override
  Future<void> write(String key, String? value) async {
    final Map<String, Object?> values = _readAll();
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
    if (!file.existsSync()) {
      await _createPrivate(file);
    }
    // Write a copy and rename it over the file, so that a crash never leaves
    // half a file behind. The copy is private before it holds anything.
    final File copy = File('${file.path}.tmp');
    await _createPrivate(copy);
    await copy.writeAsString(jsonEncode(values), flush: true);
    await copy.rename(file.path);
  }

  /// Creates [target] (and its directory) readable by its owner only.
  static Future<void> _createPrivate(File target) async {
    final bool newDirectory = !target.parent.existsSync();
    await target.create(recursive: true);
    if (Platform.isMacOS || Platform.isLinux) {
      if (newDirectory) {
        await Process.run('chmod', <String>['700', target.parent.path]);
      }
      await Process.run('chmod', <String>['600', target.path]);
    }
  }
}

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
      // session from the file.
      await auth.deleteCurrentUser();
      return uid;
    });
    print('session left in the file: ${sessionFile.readAsStringSync()}');
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
    storage: FileAuthStorage(sessionFile),
    emulatorHost: emulator,
  );
  try {
    return await body(auth);
  } finally {
    await auth.dispose();
    app.delete();
  }
}
