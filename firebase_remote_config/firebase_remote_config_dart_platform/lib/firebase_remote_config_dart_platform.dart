/// An implementation of FlutterFire's Remote Config platform interface on top
/// of the pure-Dart clients `firebase_remote_config_dart` and
/// `firebase_installations_dart`.
///
/// An app keeps the official `firebase_remote_config` API
/// (`FirebaseRemoteConfig.instance.fetchAndActivate()`, `getString(...)`,
/// `onConfigUpdated`), and the Dart clients do the work underneath, over the
/// Remote Config and Installations REST APIs:
///
/// * On Linux, where neither `firebase_remote_config` nor `firebase_core` has
///   an implementation, adding this package is enough: Flutter calls
///   [FirebaseRemoteConfigDart.registerWith] before `main`.
/// * On any other platform, call [FirebaseRemoteConfigDart.use] at the start
///   of `main`, before the first use of Firebase, to replace the official
///   implementation.
///
/// ```dart
/// Future<void> main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   FirebaseRemoteConfigDart.use();
///   await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
///   await FirebaseRemoteConfig.instance.fetchAndActivate();
/// }
/// ```
library;

import 'dart:io' show Platform;

import 'package:firebase_installations_dart/firebase_installations_dart.dart';
import 'package:firebase_remote_config_dart_platform/src/core.dart';
import 'package:firebase_remote_config_dart_platform/src/firebase_remote_config_platform.dart';
import 'package:firebase_remote_config_platform_interface/firebase_remote_config_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

export 'package:firebase_installations_dart/firebase_installations_dart.dart'
    show KeyValueStore, MemoryKeyValueStore;

/// Selects `firebase_remote_config_dart` as the implementation of the
/// official `firebase_remote_config` package.
abstract final class FirebaseRemoteConfigDart {
  static DartFirebaseRemoteConfig? _registered;

  /// Whether [use] (or [registerWith]) made this package the Remote Config
  /// implementation, and nothing replaced it since.
  static bool get isRegistered {
    final DartFirebaseRemoteConfig? registered = _registered;
    return registered != null &&
        identical(FirebaseRemoteConfigPlatform.instance, registered);
  }

  /// Called by Flutter's plugin registrant on the platforms this package
  /// declares in its pubspec (Linux only), before `main` runs. Same as [use]
  /// without arguments, except under `flutter test` (`FLUTTER_TEST` is set),
  /// where it leaves `firebase_core` alone so that `setupFirebaseCoreMocks`
  /// keeps working; a test that wants the Dart core calls [use].
  static void registerWith() {
    use(useDartCore: _runningUnderFlutterTest() ? false : null);
  }

  /// Makes `firebase_remote_config_dart` the implementation of
  /// `firebase_remote_config` on any platform. Call it at the start of
  /// `main`, before `Firebase` or `FirebaseRemoteConfig` is used; calling it
  /// again changes the configuration.
  ///
  /// * [store] keeps the installation and the Remote Config records of every
  ///   app. By default one store per isolate: on the VM a file store in
  ///   `firebase_dart` under the application support directory, on the web
  ///   the IndexedDB database `firebase_dart_kv`. On the VM a store directory
  ///   belongs to one process: a second process gets the error `internal`
  ///   with the message "the store directory is in use by another process",
  ///   so give each process of a desktop app that runs more than once its own
  ///   store. Within one process the default store is shared per isolate, not
  ///   per process: two isolates or Flutter engines that both use it are not
  ///   kept apart (on POSIX the lock belongs to the process) and can, for
  ///   example, each create an installation; give each its own directory.
  /// * [httpClient] sends the requests (for tests and proxies); by default
  ///   each client creates its own.
  /// * [languageCode] is the language the templates' conditions see; by
  ///   default the platform's locale.
  /// * [useDartCore] replaces the implementation of `firebase_core` with a
  ///   small pure-Dart one. By default (null) that happens only on Linux, and
  ///   only while `firebase_core` has no other implementation; pass true to
  ///   force it (for example in tests), false to never do it.
  ///
  /// Throws a [StateError] once an instance has created its clients: the
  /// configuration is read then.
  static void use({
    KeyValueStore? store,
    http.Client? httpClient,
    String? languageCode,
    bool? useDartCore,
  }) {
    if (DartFirebaseRemoteConfig.anyStarted) {
      throw StateError(
        'FirebaseRemoteConfigDart.use must be called before the first use of '
        'FirebaseRemoteConfig.',
      );
    }
    DartFirebaseRemoteConfig.config = DartRemoteConfigConfig(
      store: store,
      httpClient: httpClient,
      languageCode: languageCode,
    );
    installCoreIfNeeded(force: useDartCore);
    if (!isRegistered) {
      final DartFirebaseRemoteConfig platform = DartFirebaseRemoteConfig();
      FirebaseRemoteConfigPlatform.instance = platform;
      _registered = platform;
    }
  }
}

/// Whether the program runs under `flutter test`, which sets `FLUTTER_TEST`.
bool _runningUnderFlutterTest() =>
    !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
