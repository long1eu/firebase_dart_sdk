/// Ready-made token providers for `firebase_app_dart` and `cloud_firestore_dart`.
///
/// * [FirebaseUserAuth]: Firebase Auth user sign-in over REST (anonymous, email and password, custom tokens).
/// * [OAuthTokenProvider.serviceAccount]: a service account, for servers. Bypasses security rules.
/// * `applicationDefaultCredentials()` in `package:firebase_auth_providers_dart/adc.dart` (needs `dart:io`):
///   Application Default Credentials, for servers and command line tools. Bypasses security rules.
///
/// This library does not import `dart:io` and works on the web.
library;

// Imported for the references in the documentation above.
import 'src/firebase_user_auth.dart';
import 'src/oauth_token_provider.dart';

export 'src/action_code.dart';
export 'src/auth_exception.dart';
export 'src/auth_storage.dart';
export 'src/auth_user.dart';
export 'src/firebase_user_auth.dart';
export 'src/oauth_token_provider.dart';
