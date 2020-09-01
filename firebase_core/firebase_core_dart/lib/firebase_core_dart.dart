// File created by
// Lung Razvan <long1eu>
// on 04/03/2020

library firebase_core_dart;

import 'dart:async';

import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart' as flutter;
import 'package:firebase_core_vm/firebase_core_vm.dart' as vm;
import 'package:firebase_core_vm/platform_dependencies.dart';
import 'package:firebase_platform_dependencies/firebase_platform_dependencies.dart';

export 'package:firebase_core_vm/firebase_core_vm.dart' show kIsWeb, kIsMobile, kIsDesktop;

/// The entry point for accessing Firebase.
class FirebaseDart extends flutter.FirebasePlatform {
  /// Registers that [FirebaseDart] is the platform implementation.
  ///
  /// If [options] and [name] is provided a Firebase app will be initialized.
  /// If only [options] is provided the default Firebase app will be initialized.
  ///
  /// Note: This is the only way to initialize an app that has a custom [PlatformDependencies]
  /// implementation.
  static Future<void> register({
    String name = flutter.defaultFirebaseAppName,
    flutter.FirebaseOptions options,
    PlatformDependencies dependencies,
  }) async {
    if (options != null) {
      dependencies ??= await FlutterPlatformDependencies.initializeForApp(name);
      vm.FirebaseApp.withOptions(_createFromPlatformOptions(options), name: name, dependencies: dependencies);
    }

    flutter.FirebasePlatform.instance = FirebaseDart();
  }

  @override
  flutter.FirebaseAppPlatform app([String name = flutter.defaultFirebaseAppName]) {
    vm.FirebaseApp.getInstance(name);
    return FirebaseAppDart._(name);
  }

  @override
  List<flutter.FirebaseAppPlatform> get apps {
    return vm.FirebaseApp.apps //
        .map((vm.FirebaseApp app) => FirebaseAppDart._(app.name))
        .toList();
  }

  /// Initializes a new [FirebaseAppPlatform] instance by [name] and [options] and returns
  /// the created app. This method should be called before any usage of FlutterFire plugins.
  ///
  /// The platform interface doesn't allow use to pass a custom [PlatformDependencies] object,
  /// the default implementation will be used in this case. See [_DefaultPlatformDependencies].
  /// To create an app with a custom [PlatformDependencies] use [FirebaseDart.register] and then
  /// call [Firebase.app] to get a reference of that app.
  @override
  Future<flutter.FirebaseAppPlatform> initializeApp({String name, flutter.FirebaseOptions options}) async {
    final PlatformDependencies dependencies = await FlutterPlatformDependencies.initializeForApp(name);
    vm.FirebaseApp.withOptions(_createFromPlatformOptions(options), name: name, dependencies: dependencies);
    return FirebaseAppDart._(name);
  }
}

/// The entry point for accessing a Firebase app instance.
///
/// To get an instance, call the the `app` method on the [Firebase]
/// instance, for example:
///
/// ```dart
/// Firebase.app('SecondaryApp`);
/// ```
class FirebaseAppDart extends flutter.FirebaseAppPlatform {
  FirebaseAppDart._(String name) : super(name, null);

  vm.FirebaseApp get _app {
    return vm.FirebaseApp.getInstance(name);
  }

  /// Returns the [FirebaseOptions] that this app was configured with.
  @override
  flutter.FirebaseOptions get options => _createFromDartOptions(_app.options);

  /// Deletes this app and frees up system resources.
  ///
  /// Once deleted, any plugin functionality using this app instance will throw an error.
  @override
  Future<void> delete() async {
    _app.delete();
  }

  /// Returns whether automatic data collection enabled or disabled.
  @override
  bool get isAutomaticDataCollectionEnabled {
    return _app.dataCollectionEnabled;
  }

  /// Sets whether automatic data collection is enabled or disabled.
  @override
  Future<void> setAutomaticDataCollectionEnabled(bool enabled) async {
    _app.dataCollectionEnabled = enabled;
  }

  /// Sets whether automatic resource management is enabled or disabled.
  @override
  Future<void> setAutomaticResourceManagementEnabled(bool enabled) async {
    _app.setAutomaticResourceManagementEnabled(enabled: enabled);
  }
}

flutter.FirebaseOptions _createFromDartOptions(vm.FirebaseOptions options) {
  return flutter.FirebaseOptions(
    apiKey: options.apiKey,
    appId: options.appId,
    messagingSenderId: options.messagingSenderId,
    projectId: options.projectId,
    authDomain: options.authDomain,
    databaseURL: options.databaseUrl,
    storageBucket: options.storageBucket,
    measurementId: options.measurementId,
    trackingId: options.trackingId,
    androidClientId: options.clientId,
    iosClientId: options.clientId,
  );
}

vm.FirebaseOptions _createFromPlatformOptions(flutter.FirebaseOptions options) {
  return vm.FirebaseOptions(
    apiKey: options.apiKey,
    appId: options.appId,
    messagingSenderId: options.messagingSenderId,
    projectId: options.projectId,
    authDomain: options.authDomain,
    databaseUrl: options.databaseURL,
    storageBucket: options.storageBucket,
    measurementId: options.measurementId,
    trackingId: options.trackingId,
    clientId: options.androidClientId ?? options.iosClientId,
  );
}
