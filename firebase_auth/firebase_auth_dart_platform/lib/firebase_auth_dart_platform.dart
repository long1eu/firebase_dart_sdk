/// An implementation of FlutterFire's Firebase Auth platform interface on top
/// of the pure-Dart client `firebase_auth_providers_dart`.
///
/// An app keeps the official `firebase_auth` API
/// (`FirebaseAuth.instance.signInWithEmailAndPassword(...)`), and
/// `FirebaseUserAuth` of `firebase_auth_providers_dart` does the work
/// underneath, over the Firebase Auth REST API:
///
/// * On Linux, where neither `firebase_auth` nor `firebase_core` has an
///   implementation, adding this package is enough: Flutter calls
///   [FirebaseAuthDart.registerWith] before `main`.
/// * On any other platform, call [FirebaseAuthDart.use] at the start of
///   `main`, before the first use of Firebase, to replace the official
///   implementation.
///
/// ```dart
/// Future<void> main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   FirebaseAuthDart.use();
///   await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
///   await FirebaseAuth.instance.signInAnonymously();
/// }
/// ```
library;

import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart'
    show
        AppVerification,
        FirebaseUserAuth,
        InMemoryAuthStorage,
        OAuthLoopbackProvider,
        RecaptchaEnterpriseVerification,
        SecurePresenter;
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;

import 'src/convert.dart' show guard, passwordValidationStatusOf;
import 'src/core.dart';
import 'src/firebase_auth.dart';
import 'package:firebase_auth_dart_platform/src/phone.dart';

import 'src/multi_factor.dart';
import 'src/storage.dart' show runningUnderFlutterTest;

export 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart'
    show
        AppVerification,
        CallbackPresenter,
        ConsolePresenter,
        OAuthAuthorizationCode,
        OAuthCodeExchange,
        OAuthLoopbackProvider,
        RecaptchaClientType,
        RecaptchaEnterpriseRequest,
        RecaptchaEnterpriseVerification,
        SecurePresenter,
        SystemBrowserPresenter;
export 'package:secure_flow/secure_flow.dart'
    show InPageRecaptchaPresenter, RecaptchaFlow;

export 'src/convert.dart' show DartFirebaseAuthException;
export 'src/firebase_auth.dart'
    show AuthStorageFactory, DartFirebaseAuth, OAuthProvidersFactory;
export 'src/storage.dart' show defaultSessionFile;

/// Selects `firebase_auth_providers_dart` as the implementation of the official
/// `firebase_auth` package.
abstract final class FirebaseAuthDart {
  static DartFirebaseAuth? _registered;

  /// Whether [use] (or [registerWith]) made this package the Firebase Auth
  /// implementation, and nothing replaced it since.
  static bool get isRegistered {
    final DartFirebaseAuth? registered = _registered;
    return registered != null &&
        identical(FirebaseAuthPlatform.instance, registered);
  }

  /// Called by Flutter's plugin registrant on the platforms this package
  /// declares in its pubspec (Linux only), before `main` runs. Same as [use]
  /// without arguments.
  ///
  /// Under `flutter test` (`FLUTTER_TEST` is set) it installs neither the
  /// Dart `firebase_core`, so that `setupFirebaseCoreMocks` keeps working, nor
  /// the session file: each app keeps its session in memory, so that tests do
  /// not share a file. A test that wants either calls [use].
  static void registerWith() {
    if (runningUnderFlutterTest()) {
      use(
        storageFor: (FirebaseApp app) => InMemoryAuthStorage(),
        useDartCore: false,
      );
    } else {
      use();
    }
  }

  /// Makes `firebase_auth_providers_dart` the implementation of
  /// `firebase_auth` on any platform. Call it at the start of `main`, before
  /// `Firebase` or `FirebaseAuth` is used; calling it again changes the
  /// configuration.
  ///
  /// * [storageFor] returns where the session (the refresh token) of a
  ///   FlutterFire app is kept; whatever it returns replaces the default.
  ///   By default it is the secure store of the platform (the Keychain, the
  ///   Android Keystore, libsecret, DPAPI) through
  ///   `firebase_auth_secure_storage_flutter`. A session left in the file of
  ///   earlier versions ([defaultSessionFile]) moves there at its first read.
  ///   When a probe (write, read back, delete) before the first operation
  ///   finds the store unavailable (no Secret Service, a locked keyring, a
  ///   macOS build without the keychain entitlement), the
  ///   sessions are kept in that file for the run instead (memory where there
  ///   is none), and one line says so. On the web it is memory. To keep the
  ///   file, return `FileAuthStorage(defaultSessionFile()!)`.
  /// * [httpClient] sends the requests (for tests and proxies); by default
  ///   each app's client creates its own.
  /// * [useDartCore] replaces the implementation of `firebase_core` with a
  ///   small pure-Dart one. By default (null) that happens only on Linux, and
  ///   only while `firebase_core` has no other implementation, so that another
  ///   package that installed its own core (the Firestore platform package of
  ///   this repository) keeps it; pass true to force it (for example in tests),
  ///   false to never do it.
  /// * [oauthProviders] back `signInWithProvider`, `User.linkWithProvider` and
  ///   `User.reauthenticateWithProvider` with the loopback OAuth flow of the
  ///   client (the system browser and a redirect to 127.0.0.1): the call with
  ///   a `GoogleAuthProvider` uses the [OAuthLoopbackProvider] whose
  ///   `providerId` is `google.com`, and so on. The scopes and custom
  ///   parameters of the FlutterFire provider are added to its request. A
  ///   provider id without one throws `unimplemented`. Two providers with one
  ///   id throw an [ArgumentError].
  /// * [oauthProvidersFor] returns the providers of one FlutterFire app, for an
  ///   app with several Firebase projects that each have their own OAuth
  ///   client: it is called once, when the instance of the app is created.
  ///   With both, an app has the providers of [oauthProviders] and its own,
  ///   and its own replace those of [oauthProviders] with the same id. Two of
  ///   its providers with one id throw an [ArgumentError] then, at the first
  ///   use of that app's `FirebaseAuth`.
  /// * [presenter] runs the browser part of those flows: shows the
  ///   authorization URL and takes the redirect on 127.0.0.1. By default the
  ///   system browser on macOS, Linux and Windows (the URL on stderr over SSH
  ///   or without a display). On Android and iOS pass one, for example
  ///   `CallbackPresenter((Uri url) => launchUrl(url))` with `url_launcher`.
  /// * [appVerification] is the proof that the phone requests
  ///   (`verifyPhoneNumber`, `signInWithPhoneNumber`,
  ///   `User.linkWithPhoneNumber`, the SMS second factor) come from a real
  ///   app. By default `AppVerification.recaptchaV2Loopback()`: a reCAPTCHA v2
  ///   page on 127.0.0.1 in the system browser, once per request. With the
  ///   Auth emulator, or after
  ///   `setSettings(appVerificationDisabledForTesting: true)`, no proof is
  ///   sent unless one is passed here. On the web, without one, the
  ///   `RecaptchaVerifier` the app passes to `signInWithPhoneNumber` (or the
  ///   invisible one `firebase_auth` makes) renders the reCAPTCHA v2 widget in
  ///   the page and gives the token.
  /// * [recaptchaEnterprise] makes the reCAPTCHA Enterprise tokens of the
  ///   requests the project protects with reCAPTCHA Enterprise (password
  ///   sign-in and sign-up, password reset and email link emails, SMS), as
  ///   `FirebaseUserAuth.recaptchaEnterprise` describes. On the web it is
  ///   reCAPTCHA Enterprise in the app's page by default; elsewhere there is
  ///   none unless one is passed here (for example
  ///   `RecaptchaEnterpriseVerification((r) => RecaptchaFlow.enterprise(siteKey:
  ///   r.siteKey!, action: r.action.value).run())`, a page on localhost in the
  ///   system browser, whose key must allow `localhost`).
  ///
  /// It also replaces the multi-factor generators of `firebase_auth` (TOTP and
  /// SMS) and the `RecaptchaVerifier` factory (on the web the reCAPTCHA v2
  /// widget in the page; elsewhere it renders nothing and the proof is
  /// [appVerification]) with those of this package.
  ///
  /// Throws a [StateError] when the instance of an app has already been
  /// created: the configuration is read then.
  static void use({
    AuthStorageFactory? storageFor,
    http.Client? httpClient,
    bool? useDartCore,
    Iterable<OAuthLoopbackProvider> oauthProviders =
        const <OAuthLoopbackProvider>[],
    OAuthProvidersFactory? oauthProvidersFor,
    SecurePresenter? presenter,
    AppVerification? appVerification,
    RecaptchaEnterpriseVerification? recaptchaEnterprise,
  }) {
    final Map<String, OAuthLoopbackProvider> byId = providersById(
      oauthProviders,
      'oauthProviders',
    );
    if (DartFirebaseAuth.anyStarted) {
      throw StateError(
        'FirebaseAuthDart.use must be called before the first use of '
        'FirebaseAuth.',
      );
    }
    DartFirebaseAuth.config = DartAuthConfig(
      storageFor: storageFor,
      httpClient: httpClient,
      oauthProviders: byId,
      oauthProvidersFor: oauthProvidersFor,
      presenter: presenter,
      appVerification: appVerification,
      recaptchaEnterprise: recaptchaEnterprise,
    );
    installCoreIfNeeded(force: useDartCore);
    if (!isRegistered) {
      final DartFirebaseAuth platform = DartFirebaseAuth();
      FirebaseAuthPlatform.instance = platform;
      _registered = platform;
    }
    PhoneMultiFactorGeneratorPlatform.instance =
        DartPhoneMultiFactorGenerator();
    TotpMultiFactorGeneratorPlatform.instance = DartTotpMultiFactorGenerator();
    RecaptchaVerifierFactoryPlatform.instance = DartRecaptchaVerifierFactory();
  }

  /// The `FirebaseUserAuth` behind `FirebaseAuth.instanceFor(app: app)`, for
  /// what the official API does not have (`authStateReady`,
  /// `beforeAuthStateChanged`, `validatePassword` with a tenant, ...), and as
  /// a token provider for `cloud_firestore_dart`, and for
  /// `signInWithOAuthLoopback`, the provider sign-in of a desktop app. Only
  /// for an app whose `FirebaseAuth` this package implements.
  static FirebaseUserAuth userAuthFor(FirebaseApp app) =>
      DartFirebaseAuth.forApp(app).client;

  /// Checks [password] against the password policy of the project of [app]
  /// (of its tenant when `FirebaseAuth.tenantId` is set), with the result type
  /// of `FirebaseAuth.validatePassword`.
  ///
  /// Use it instead of `FirebaseAuth.validatePassword`, which fetches the
  /// policy itself from the production endpoint: this one goes through the
  /// app's client, so it uses the emulator, the tenant and the HTTP client
  /// configured here, and caches the policy as the JS SDK does.
  ///
  /// Throws a [FirebaseAuthException] with the code `invalid-password` when
  /// [password] is empty, as `FirebaseAuth.validatePassword` does.
  static Future<PasswordValidationStatus> validatePassword(
    FirebaseApp app,
    String password,
  ) async {
    if (password.isEmpty) {
      throw FirebaseAuthException(
        code: 'invalid-password',
        message: 'Password cannot be null or empty',
      );
    }
    final DartFirebaseAuth auth = DartFirebaseAuth.forApp(app);
    return guard(
      auth,
      () async => passwordValidationStatusOf(
        await auth.client.validatePassword(password),
      ),
    );
  }
}
