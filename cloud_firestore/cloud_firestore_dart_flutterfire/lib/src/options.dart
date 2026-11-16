import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_app_dart/platform_dependencies.dart';
import 'package:firebase_core/firebase_core.dart' as flutterfire;
import 'package:rxdart/rxdart.dart';

/// The `firebase_app_dart` options for the FlutterFire [options] (of `firebase_core`).
///
/// Both packages use the same field names, and every field is copied: `apiKey`, `appId`,
/// `messagingSenderId`, `projectId`, `authDomain`, `databaseURL`, `storageBucket`, `measurementId`,
/// `trackingId`, `deepLinkURLScheme`, `androidClientId`, `iosClientId`, `iosBundleId` and `appGroupId`.
/// `recaptchaSiteKey` (newer `firebase_core` releases) has no counterpart and is dropped. An empty
/// optional value becomes null. `cloud_firestore_dart_platform` maps the options the same way, so both
/// packages agree on the `firebase_app_dart` app of a FlutterFire app.
///
/// ```dart
/// final FirebaseOptions options =
///     firebaseOptionsFromFlutterFire(Firebase.app().options);
/// ```
FirebaseOptions firebaseOptionsFromFlutterFire(
  flutterfire.FirebaseOptions options,
) {
  String? optional(String? value) =>
      value == null || value.isEmpty ? null : value;
  return FirebaseOptions(
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

/// The `firebase_app_dart` app called [name] with the [options] of a FlutterFire app, created on the first call.
///
/// A later call with the same name and equal options returns the same app; [authProvider] and
/// [appCheckProvider] only apply when the app is created. Throws a [StateError] when an app with that name
/// exists with other options.
///
/// [dependencies] are passed to `FirebaseApp.withOptions`; [authProvider] and [appCheckProvider] take the place
/// of theirs. A provider given here is not asked for a token at once, unlike one assigned with the
/// `authProvider` setter of the app (which forces a refresh to warm it up).
FirebaseApp dartAppFor(
  String name,
  flutterfire.FirebaseOptions options, {
  PlatformDependencies? dependencies,
  AuthTokenProvider? authProvider,
  AppCheckTokenProvider? appCheckProvider,
}) {
  final FirebaseOptions mapped = firebaseOptionsFromFlutterFire(options);
  final FirebaseApp? existing = existingDartApp(name);
  if (existing != null) {
    if (existing.options != mapped) {
      throw StateError(
        'A firebase_app_dart app named "$name" exists with other options than the FlutterFire app.',
      );
    }
    return existing;
  }
  return FirebaseApp.withOptions(
    mapped,
    name: name,
    dependencies: authProvider == null && appCheckProvider == null
        ? dependencies
        : _BridgeDependencies(dependencies, authProvider, appCheckProvider),
  );
}

/// The `firebase_app_dart` app called [name], or null when there is none.
FirebaseApp? existingDartApp(String name) {
  final String trimmed = name.trim();
  for (final FirebaseApp app in Firebase.apps) {
    if (app.name == trimmed) {
      return app;
    }
  }
  return null;
}

/// The dependencies of the caller, with the token providers of the bridge.
class _BridgeDependencies extends PlatformDependencies {
  _BridgeDependencies(this._inner, this._auth, this._appCheck);

  final PlatformDependencies? _inner;
  final AuthTokenProvider? _auth;
  final AppCheckTokenProvider? _appCheck;

  @override
  AuthTokenProvider? get authProvider => _auth ?? _inner?.authProvider;

  @override
  AppCheckTokenProvider? get appCheckProvider =>
      _appCheck ?? _inner?.appCheckProvider;

  @override
  BehaviorSubject<bool> get onNetworkConnected =>
      _inner?.onNetworkConnected ?? super.onNetworkConnected;

  @override
  BehaviorSubject<bool> get onBackgroundChanged =>
      _inner?.onBackgroundChanged ?? super.onBackgroundChanged;

  @override
  HeaderBuilder? get headersBuilder => _inner?.headersBuilder;

  @override
  LocalStorage get storage => _inner?.storage ?? this;
}
