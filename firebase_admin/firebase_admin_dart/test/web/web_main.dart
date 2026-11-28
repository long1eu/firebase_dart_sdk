// Compiled (not run) by web_compile_test.dart: the main, auth and app_check libraries must not need dart:io or
// dart:ffi.

import 'package:firebase_admin_dart/app_check.dart';
import 'package:firebase_admin_dart/auth.dart';

Future<void> main() async {
  final FirebaseAdminApp app = FirebaseAdminApp.emulator(
    projectId: 'demo-test',
    authEmulatorHost: '127.0.0.1:9099',
  );
  final FirebaseAuthAdmin auth = app.auth();
  // ignore: avoid_print
  print(<Object?>[
    await auth.createCustomToken('u'),
    auth.verifyIdToken,
    auth.createUser,
    auth.deleteUsers,
    AdminCredential.serviceAccount,
    AdminCredential.iam,
    const FirebaseAuthAdminException(code: 'c', message: 'm'),
    app.appCheck().verifyToken,
    const FirebaseAppCheckAdminException(code: 'c', message: 'm'),
  ]);
  await app.close();
}
