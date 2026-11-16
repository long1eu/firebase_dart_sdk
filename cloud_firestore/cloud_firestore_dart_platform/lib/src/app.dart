import 'package:firebase_app_dart/firebase_app_dart.dart' as dart_app;
import 'package:firebase_core/firebase_core.dart' as core;

/// Returns the token provider that the Firestore requests of the FlutterFire
/// [app] use, or null for requests without a user.
///
/// See `CloudFirestoreDart.use` for how it is called.
typedef TokenProviderFactory =
    dart_app.InternalTokenProvider? Function(core.FirebaseApp app);

/// The `firebase_app_dart` options for the FlutterFire [options].
///
/// `appId` becomes `applicationId`, `messagingSenderId` becomes `gcmSenderId`,
/// `databaseURL` becomes `databaseUrl` and `trackingId` becomes
/// `gaTrackingId`. The options that `firebase_app_dart` does not have
/// (`authDomain`, `measurementId`, the client ids, ...) are dropped. An empty
/// optional value becomes null.
dart_app.FirebaseOptions dartOptionsOf(core.FirebaseOptions options) {
  String? optional(String? value) =>
      value == null || value.isEmpty ? null : value;
  return dart_app.FirebaseOptions(
    apiKey: options.apiKey,
    applicationId: options.appId,
    projectId: optional(options.projectId),
    gcmSenderId: optional(options.messagingSenderId),
    storageBucket: optional(options.storageBucket),
    databaseUrl: optional(options.databaseURL),
    gaTrackingId: optional(options.trackingId),
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
  for (final dart_app.FirebaseApp existing in dart_app.FirebaseApp.apps) {
    if (existing.name == app.name) {
      if (existing.options != options) {
        throw StateError(
          'A firebase_app_dart app named "${app.name}" exists with other '
          'options than the FlutterFire app.',
        );
      }
      return existing;
    }
  }
  final dart_app.FirebaseApp created = dart_app.FirebaseApp.withOptions(
    options,
    name: app.name,
  );
  final dart_app.InternalTokenProvider? provider = tokenProviderFor?.call(app);
  if (provider != null) {
    created.authProvider = provider;
  }
  return created;
}
