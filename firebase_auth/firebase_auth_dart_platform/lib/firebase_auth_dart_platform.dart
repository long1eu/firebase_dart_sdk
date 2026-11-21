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
        FirebaseUserAuth,
        InMemoryAuthStorage,
        OAuthLoopbackProvider,
        UrlPresenter;
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;

import 'src/convert.dart' show guard, passwordValidationStatusOf;
import 'src/core.dart';
import 'src/firebase_auth.dart';
import 'src/multi_factor.dart';
import 'src/storage.dart' show runningUnderFlutterTest;

export 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart'
    show
        OAuthAuthorizationCode,
        OAuthCodeExchange,
        OAuthLoopbackProvider,
        UrlPresenter;

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
  ///   FlutterFire app is kept, for example a `FileAuthStorage` of your choice
  ///   or a storage on top of a secure storage plugin. By default it is a file
  ///   in the user's data directory ([defaultSessionFile]), or memory where
  ///   there is none (Android, iOS, web).
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
  /// * [presentUrl] opens the authorization URL of those flows, for example
  ///   `url_launcher`'s `launchUrl` on Android and iOS; by default the system
  ///   browser on macOS, Linux and Windows.
  ///
  /// It also replaces the multi-factor generators of `firebase_auth`: the
  /// TOTP one works through the client, the phone one throws
  /// `unimplemented`.
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
    UrlPresenter? presentUrl,
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
      presentUrl: presentUrl,
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
