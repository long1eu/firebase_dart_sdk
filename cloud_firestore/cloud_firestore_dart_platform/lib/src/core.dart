import 'package:firebase_app_dart/firebase_app_dart.dart' as dart_app;
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';

/// A small pure-Dart [FirebasePlatform] for platforms where `firebase_core`
/// has no implementation (Linux), so that `Firebase.initializeApp` works there.
///
/// It keeps the apps in memory. `Firebase.initializeApp` needs `options` (there
/// is no `google-services.json` or `GoogleService-Info.plist` to read them
/// from); the other plugins of FlutterFire still have no implementation on
/// such a platform.
class DartFirebaseCore extends FirebasePlatform {
  final Map<String, DartFirebaseAppPlatform> _apps =
      <String, DartFirebaseAppPlatform>{};

  @override
  List<FirebaseAppPlatform> get apps =>
      List<FirebaseAppPlatform>.unmodifiable(_apps.values);

  @override
  Future<FirebaseAppPlatform> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) async {
    final String appName = name ?? defaultFirebaseAppName;
    final DartFirebaseAppPlatform? existing = _apps[appName];
    if (options == null) {
      if (existing != null) {
        return existing;
      }
      throw FirebaseException(
        plugin: 'core',
        code: 'no-options',
        message:
            'Firebase.initializeApp needs options on this platform: there is '
            'no native configuration file to read them from.',
      );
    }
    if (existing != null) {
      if (existing.options != options) {
        throw duplicateApp(appName);
      }
      return existing;
    }
    return _apps[appName] = DartFirebaseAppPlatform._(this, appName, options);
  }

  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) {
    final DartFirebaseAppPlatform? app = _apps[name];
    if (app == null) {
      throw name == defaultFirebaseAppName
          ? coreNotInitialized()
          : noAppExists(name);
    }
    return app;
  }
}

/// An app of [DartFirebaseCore].
class DartFirebaseAppPlatform extends FirebaseAppPlatform {
  DartFirebaseAppPlatform._(this._core, super.name, super.options);

  final DartFirebaseCore _core;
  bool _dataCollectionEnabled = true;

  @override
  bool get isAutomaticDataCollectionEnabled => _dataCollectionEnabled;

  /// Removes the app, and deletes the `firebase_app_dart` app of the same name,
  /// which shuts down its `cloud_firestore_dart` instances. The default app
  /// cannot be deleted, as with the official implementation.
  @override
  Future<void> delete() async {
    if (name == defaultFirebaseAppName) {
      throw noDefaultAppDelete();
    }
    _core._apps.remove(name);
    for (final dart_app.FirebaseApp app in dart_app.Firebase.apps) {
      if (app.name == name) {
        await app.delete();
      }
    }
  }

  /// Stored only: no service of this package collects data.
  @override
  Future<void> setAutomaticDataCollectionEnabled(bool enabled) async {
    _dataCollectionEnabled = enabled;
  }

  /// Accepted and ignored: no service of this package reads it.
  @override
  Future<void> setAutomaticResourceManagementEnabled(bool enabled) async {}
}
