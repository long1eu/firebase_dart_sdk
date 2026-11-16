/// The shared pieces of the admin libraries of `firebase_admin_dart`: the app ([FirebaseAdminApp]), its
/// credential ([AdminCredential]) and the base exception ([FirebaseAdminException]). It also exports
/// `OAuthTokenProvider` and `OAuthAccessToken` of `firebase_auth_providers_dart`, the token source of
/// [AdminCredential.iam].
///
/// The admin calls are in their own libraries: `package:firebase_admin_dart/auth.dart` for Firebase Auth (it
/// also exports this library). `package:firebase_admin_dart/adc.dart` (needs `dart:io`) builds a credential
/// from Application Default Credentials.
///
/// **For trusted code only: servers, CLIs, CI jobs and integration tests.** Admin credentials bypass security
/// rules and can act as any user. Never put a service account key in an app, a web page, a Flutter asset of a
/// release build or a repository.
///
/// The library does not import `dart:io` and compiles for the web, but a browser is not a place for admin
/// credentials.
///
/// ```dart
/// import 'package:firebase_admin_dart/firebase_admin_dart.dart';
///
/// FirebaseAdminApp emulatorApp() => FirebaseAdminApp.emulator(
///   projectId: 'demo-test',
///   authEmulatorHost: '127.0.0.1:9099',
/// );
/// ```
library;

import 'src/app.dart';
import 'src/credential.dart';
import 'src/exception.dart';

// The token source type of AdminCredential.iam, so that one import is enough.
export 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart'
    show OAuthAccessToken, OAuthTokenProvider;

export 'src/app.dart' show FirebaseAdminApp;
export 'src/credential.dart' show AdminCredential;
export 'src/exception.dart' show FirebaseAdminException;
