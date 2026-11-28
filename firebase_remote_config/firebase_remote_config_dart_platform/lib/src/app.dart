import 'package:firebase_app_dart/firebase_app_dart.dart' as dart_app;
import 'package:firebase_core/firebase_core.dart' as core;

/// Returns a token provider for the FlutterFire [app], or null for none.
///
/// Remote Config and Installations send no user token, so this package never
/// passes one; the type stays so that [dartAppFor] keeps the signature it has
/// in the other platform packages of this repository.
typedef TokenProviderFactory =
    dart_app.AuthTokenProvider? Function(core.FirebaseApp app);

/// Returns an App Check token provider for the FlutterFire [app], or null for
/// none.
///
/// Remote Config and Installations send no App Check token, so this package
/// never passes one; the type stays so that [dartAppFor] keeps the signature
/// it has in the other platform packages of this repository.
typedef AppCheckProviderFactory =
    dart_app.AppCheckTokenProvider? Function(core.FirebaseApp app);

/// The `firebase_app_dart` options for the FlutterFire [options].
///
/// The same mapping as `dartOptionsOf` of `cloud_firestore_dart_platform`, so
/// that the platform packages agree on the `firebase_app_dart` app of a
/// FlutterFire app and can share it. An empty optional value becomes null;
/// `recaptchaSiteKey` has no counterpart and is dropped.
dart_app.FirebaseOptions dartOptionsOf(core.FirebaseOptions options) {
  String? optional(String? value) =>
      value == null || value.isEmpty ? null : value;
  return dart_app.FirebaseOptions(
    apiKey: options.apiKey,
    appId: options.appId,
    messagingSenderId: optional(options.messagingSenderId),
    projectId: optional(options.projectId),
    authDomain: optional(options.authDomain),
    databaseURL: optional(options.databaseURL),
    storageBucket: optional(options.storageBucket),
    measurementId: optional(options.measurementId),
    trackingId: optional(options.trackingId),
    deepLinkURLScheme: optional(options.deepLinkURLScheme),
    androidClientId: optional(options.androidClientId),
    iosClientId: optional(options.iosClientId),
    iosBundleId: optional(options.iosBundleId),
    appGroupId: optional(options.appGroupId),
  );
}

/// The `firebase_app_dart` app with the name of the FlutterFire [app].
///
/// An existing app of that name is used as it is (an app that another
/// platform package of this repository set up), and only gets the App Check
/// provider that [appCheckProviderFor] returns when it has none. Otherwise the
/// app is created with the mapped options and the providers that
/// [tokenProviderFor] and [appCheckProviderFor] return. Remote Config calls it
/// without providers. Throws a [StateError] when an existing app has other
/// options.
dart_app.FirebaseApp dartAppFor(
  core.FirebaseApp app, {
  TokenProviderFactory? tokenProviderFor,
  AppCheckProviderFactory? appCheckProviderFor,
}) {
  final dart_app.FirebaseOptions options = dartOptionsOf(app.options);
  // Firebase.app(name) of firebase_app_dart throws when there is no app, and
  // Firebase.initializeApp is asynchronous: look the app up in the list.
  final dart_app.FirebaseApp? existing = dart_app.Firebase.apps
      .where((dart_app.FirebaseApp candidate) => candidate.name == app.name)
      .firstOrNull;
  if (existing != null) {
    if (existing.options != options) {
      throw StateError(
        'A firebase_app_dart app named "${app.name}" exists with other '
        'options than the FlutterFire app.',
      );
    }
    existing.appCheckProvider ??= appCheckProviderFor?.call(app);
    return existing;
  }
  final dart_app.FirebaseApp created = dart_app.FirebaseApp.withOptions(
    options,
    name: app.name,
  );
  final dart_app.AuthTokenProvider? provider = tokenProviderFor?.call(app);
  if (provider != null) {
    created.authProvider = provider;
  }
  created.appCheckProvider = appCheckProviderFor?.call(app);
  return created;
}
