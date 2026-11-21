/// Ready-made token providers for `firebase_app_dart` and `cloud_firestore_dart`.
///
/// * [FirebaseUserAuth]: Firebase Auth user sign-in over REST (anonymous, email and password, email
///   link, custom tokens, phone numbers, and federated providers by token exchange; authenticator
///   app and SMS second factors), with FlutterFire's names, and the storages of its session
///   ([InMemoryAuthStorage], `FileAuthStorage` on the VM, `WebAuthStorage` in a browser).
/// * [OAuthTokenProvider.serviceAccount]: a service account, for servers. Bypasses security rules.
/// * `applicationDefaultCredentials()` in `package:firebase_auth_providers_dart/adc.dart` (needs `dart:io`):
///   Application Default Credentials, for servers and command line tools. Bypasses security rules.
///
/// This library does not import `dart:io` unconditionally and works on the web (`FileAuthStorage` is the VM's,
/// `WebAuthStorage` the browser's; each throws an [UnsupportedError] on the other platform).
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

// The presenters of the browser flows and their errors, so that one import is enough for
// `signInWithOAuthLoopback`, `AppVerification.recaptchaV2Loopback` and a reCAPTCHA Enterprise token
// source (`RecaptchaFlow.enterprise`).
export 'package:secure_flow/secure_flow.dart'
    show
        CallbackPresenter,
        ConsolePresenter,
        InPageRecaptchaPresenter,
        LoopbackPresenter,
        OAuthAppRequest,
        OAuthRedirect,
        OAuthResult,
        OAuthTokens,
        PromptPresenter,
        ProviderAppPresenter,
        RecaptchaFailure,
        RecaptchaFailureReason,
        RecaptchaFlow,
        SecureEnvironment,
        SecureFlowCancelled,
        SecureFlowException,
        SecureFlowNoPresenter,
        SecureFlowRefused,
        SecureFlowTimeout,
        SecurePresenter,
        SecurePresenterKind,
        ShowUrl,
        SystemBrowserPresenter,
        openInSystemBrowser;

// Imported for the references in the documentation above.
import 'src/auth_storage.dart';
import 'src/firebase_user_auth.dart';
import 'src/oauth_token_provider.dart';

export 'src/action_code.dart';
export 'src/app_verification.dart' hide appVerificationFields;
export 'src/auth_constants.dart';
export 'src/auth_credential.dart' hide credentialJsonMap;
export 'src/auth_emulator_config.dart';
export 'src/auth_exception.dart';
export 'src/auth_storage.dart';
export 'src/auth_user.dart';
export 'src/firebase_user_auth.dart';
export 'src/multi_factor.dart'
    hide createMultiFactorResolver, timestampOf, totpSessionInfoOf;
export 'src/oauth_loopback/oauth_loopback.dart';
export 'src/oauth_loopback/oauth_loopback_stub.dart'
    if (dart.library.io) 'src/oauth_loopback/oauth_loopback_io.dart';
export 'src/oauth_token_provider.dart';
export 'src/recaptcha_config.dart';
export 'src/password_policy.dart';
export 'src/phone_auth.dart' hide phoneCredentialFromProof, redactPhoneSecrets;
export 'src/service_account_key.dart';
export 'src/storage/file_auth_storage_stub.dart'
    if (dart.library.io) 'src/storage/file_auth_storage_io.dart';
export 'src/storage/indexed_db_auth_storage_stub.dart'
    if (dart.library.js_interop) 'src/storage/indexed_db_auth_storage_web.dart';
export 'src/storage/indexed_db_types.dart';
export 'src/storage/web_auth_storage_stub.dart'
    if (dart.library.js_interop) 'src/storage/web_auth_storage_web.dart';
