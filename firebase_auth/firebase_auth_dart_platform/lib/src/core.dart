import 'package:firebase_app_dart/firebase_app_dart.dart' as dart_app;
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/foundation.dart';

/// Installs [LinuxFirebaseCore] when [force] is true, or, when it is null, on
/// Linux while `firebase_core` still has its default (method channel)
/// implementation, which has nothing behind it there.
///
/// Another package may install a core of its own (the Firestore platform
/// package of this repository does); whichever registers first is kept, so both
/// can be in one app in either order. Nothing here depends on the type of the
/// core that is in place.
void installCoreIfNeeded({bool? force}) {
  final bool install =
      force ??
      (!kIsWeb &&
          defaultTargetPlatform == TargetPlatform.linux &&
          FirebasePlatform.instance is MethodChannelFirebase);
  if (install) {
    FirebasePlatform.instance = LinuxFirebaseCore();
  }
}

/// A small pure-Dart [FirebasePlatform] for platforms where `firebase_core` has
/// no implementation (Linux), so that `Firebase.initializeApp` works there.
///
/// It keeps the apps in memory, and `Firebase.initializeApp` needs `options`:
/// there is no native configuration file to read them from.
class LinuxFirebaseCore extends FirebasePlatform {
  final Map<String, _App> _apps = <String, _App>{};

  @override
  List<FirebaseAppPlatform> get apps =>
      List<FirebaseAppPlatform>.unmodifiable(_apps.values);

  @override
  Future<FirebaseAppPlatform> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) async {
    final String appName = name ?? defaultFirebaseAppName;
    final _App? existing = _apps[appName];
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
    return _apps[appName] = _App(this, appName, options);
  }

  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) {
    final _App? app = _apps[name];
    if (app == null) {
      throw name == defaultFirebaseAppName
          ? coreNotInitialized()
          : noAppExists(name);
    }
    return app;
  }
}

class _App extends FirebaseAppPlatform {
  _App(this._core, super.name, super.options);

  final LinuxFirebaseCore _core;
  bool _dataCollectionEnabled = true;

  @override
  bool get isAutomaticDataCollectionEnabled => _dataCollectionEnabled;

  /// Removes the app. The `firebase_app_dart` app of the same name, which other
  /// pure-Dart packages (Firestore) keep for a FlutterFire app, is deleted too.
  /// The default app cannot be deleted, as with the official implementation.
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

  /// Stored only: nothing in this package collects data.
  @override
  Future<void> setAutomaticDataCollectionEnabled(bool enabled) async {
    _dataCollectionEnabled = enabled;
  }

  /// Accepted and ignored.
  @override
  Future<void> setAutomaticResourceManagementEnabled(bool enabled) async {}
}
