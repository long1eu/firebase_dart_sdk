/// Firebase Auth admin calls: custom tokens (signed with a service account key, by IAM `signBlob`, or unsigned
/// for the emulator), users, custom claims, revocation and ID token verification.
///
/// Start from a [FirebaseAdminApp] (exported here too) and call [FirebaseAdminAppAuth.auth], or
/// `FirebaseAuthAdmin(app)`.
///
/// **For trusted code only: servers, CLIs, CI jobs and integration tests.** See [FirebaseAuthAdmin].
///
/// ```dart
/// import 'package:firebase_admin_dart/auth.dart';
///
/// Future<void> main() async {
///   final FirebaseAdminApp app = FirebaseAdminApp.emulator(
///     projectId: 'demo-test',
///     authEmulatorHost: '127.0.0.1:9099',
///   );
///   final AdminUser user = await app.auth().createUser();
///   final String token = await app.auth().createCustomToken(user.uid);
///   print(token.isNotEmpty);
///   await app.auth().deleteUser(user.uid);
///   await app.close();
/// }
/// ```
library;

import 'firebase_admin_dart.dart';
import 'src/auth/firebase_auth_admin.dart';

export 'firebase_admin_dart.dart';
export 'src/auth/exception.dart';
export 'src/auth/firebase_auth_admin.dart';
export 'src/auth/records.dart';
