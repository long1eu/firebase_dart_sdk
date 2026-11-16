import 'package:firebase_app_dart/firebase_app_dart.dart' as dart_app;
import 'package:firebase_core/firebase_core.dart' as core;

/// Returns the token provider that the Firestore requests of the FlutterFire
/// [app] use, or null for requests without a user.
///
/// See `CloudFirestoreDart.use` for how it is called.
typedef TokenProviderFactory =
    dart_app.AuthTokenProvider? Function(core.FirebaseApp app);

/// The `firebase_app_dart` options for the FlutterFire [options].
///
/// The two packages use the same field names. An empty optional value becomes
/// null; `recaptchaSiteKey` has no counterpart and is dropped.
/// `cloud_firestore_dart_flutterfire` maps the options the same way, so both
/// packages agree on the `firebase_app_dart` app of a FlutterFire app.
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
/// An existing app of that name is used as it is, with its token providers (an
/// app that another package, such as `cloud_firestore_dart_flutterfire`, set
/// up). Otherwise the app is created with the mapped options and the token
/// provider that [tokenProviderFor] returns. Throws a [StateError] when an
/// existing app has other options.
dart_app.FirebaseApp dartAppFor(
  core.FirebaseApp app,
  TokenProviderFactory? tokenProviderFor,
) {
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
  return created;
}
