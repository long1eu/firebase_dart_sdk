import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_app_dart/platform_dependencies.dart';
import 'package:firebase_core/firebase_core.dart' as flutterfire;
import 'package:rxdart/rxdart.dart';

/// The `firebase_app_dart` options for the FlutterFire [options] (of `firebase_core`).
///
/// | FlutterFire | `firebase_app_dart` |
/// | --- | --- |
/// | `apiKey` | `apiKey` |
/// | `appId` | `applicationId` |
/// | `projectId` | `projectId` |
/// | `messagingSenderId` | `messagingSenderId` |
/// | `storageBucket` | `storageBucket` |
/// | `databaseURL` | `databaseURL` |
/// | `trackingId` | `trackingId` |
///
/// The other FlutterFire options (`authDomain`, `measurementId`, the iOS and Android client ids, ...) have no
/// counterpart and are dropped. An empty optional value becomes null.
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
    projectId: optional(options.projectId),
    messagingSenderId: optional(options.messagingSenderId),
    storageBucket: optional(options.storageBucket),
    databaseURL: optional(options.databaseURL),
    trackingId: optional(options.trackingId),
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
