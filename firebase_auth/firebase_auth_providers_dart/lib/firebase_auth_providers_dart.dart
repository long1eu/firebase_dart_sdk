/// Ready-made token providers for `firebase_app_dart` and `cloud_firestore_dart`.
///
/// * [FirebaseUserAuth]: Firebase Auth user sign-in over REST (anonymous, email and password, custom tokens).
/// * [OAuthTokenProvider.serviceAccount]: a service account, for servers. Bypasses security rules.
/// * `applicationDefaultCredentials()` in `package:firebase_auth_providers_dart/adc.dart` (needs `dart:io`):
///   Application Default Credentials, for servers and command line tools. Bypasses security rules.
///
/// This library does not import `dart:io` and works on the web.
///
/// ```dart
/// import 'package:firebase_app_dart/firebase_app_dart.dart';
/// import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
///
/// Future<void> main() async {
///   final FirebaseApp app = FirebaseApp.withOptions(
///     const FirebaseOptions(
///       apiKey: '<the Web API key of the project>',
///       appId: '1:1234567890:dart:example',
///       projectId: 'my-project',
///     ),
///   );
///   final FirebaseUserAuth auth = await FirebaseUserAuth.forApp(app);
///   final AuthUser user = await auth.signInAnonymously();
///   print(user.uid);
/// }
/// ```
///
/// The `example/` folder of the package has one program per task: each sign-in flow, a session kept in a file, a
/// service account, Application Default Credentials, and the wiring into Firestore.
library;

// Imported for the references in the documentation above.
import 'src/firebase_user_auth.dart';
import 'src/oauth_token_provider.dart';

export 'src/action_code.dart';
export 'src/auth_credential.dart';
export 'src/auth_exception.dart';
export 'src/auth_storage.dart';
export 'src/auth_user.dart';
export 'src/firebase_user_auth.dart';
export 'src/oauth_token_provider.dart';
export 'src/password_policy.dart';
export 'src/service_account_key.dart';
