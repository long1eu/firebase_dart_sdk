// File created by
// Lung Razvan <long1eu>
// on 04/03/2020

library firebase_core_dart;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectivity/connectivity.dart';
import 'package:connectivity_linux/connectivity_linux.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart' as flutter;
import 'package:firebase_core_vm/firebase_core_vm.dart' as vm;
import 'package:firebase_core_vm/platform_dependencies.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rxdart/rxdart.dart';

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
      if (dependencies == null) {
        await _DefaultPlatformDependencies.initialize();
        dependencies = _DefaultPlatformDependencies.instance;
      }

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
    await _DefaultPlatformDependencies.initialize();

    vm.FirebaseApp.withOptions(_createFromPlatformOptions(options),
        name: name, dependencies: _DefaultPlatformDependencies.instance);
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

/// This implementation provides basic information to Firebase services about
/// connectivity and background state and also provides a light storage solution
/// for persisting state across restarts.
class _DefaultPlatformDependencies extends PlatformDependencies with WidgetsBindingObserver {
  _DefaultPlatformDependencies._();

  static _DefaultPlatformDependencies instance = _DefaultPlatformDependencies._();

  static Future<void> initialize() async {
    if (instance._completer != null) {
      return instance._completer.future;
    }
    instance._completer = Completer<void>();

    final Directory parent = await getApplicationDocumentsDirectory();
    final Box<Uint8List> keyBox = await Hive.openBox<Uint8List>('encryption.store', path: parent.path);
    if (!keyBox.containsKey('key')) {
      final List<int> key = Hive.generateSecureKey();
      await keyBox.put('key', key);
    }
    final Uint8List key = keyBox.get('key');

    instance._box = await Hive.openBox<String>('firebase.store', encryptionKey: key, path: parent.path);
    instance._onBackgroundChanged = BehaviorSubject<bool>.seeded(false);
    instance._onNetworkConnected = BehaviorSubject<bool>.seeded(true);
    WidgetsBinding.instance.addObserver(instance);

    // todo(long1eu): remove this if the plugin is endorsed for Linux
    if (!kIsWeb && Platform.isLinux) {
      // ConnectivityLinux.register();
      NetworkManager.instance.stateChanged
          .map((NetworkManagerState event) =>
              event == NetworkManagerState.connectedGlobal || event == NetworkManagerState.unknown
                  ? ConnectivityResult.wifi
                  : ConnectivityResult.none)
          .listen(instance._connectivityChanged);
    } else {
      Connectivity()
        ..checkConnectivity().then(instance._connectivityChanged)
        ..onConnectivityChanged.listen(instance._connectivityChanged);
    }

    instance._completer.complete();
  }

  Completer<void> _completer;
  Box<String> _box;
  BehaviorSubject<bool> _onBackgroundChanged;
  BehaviorSubject<bool> _onNetworkConnected;

  @override
  Box<String> get box {
    _ensureInitialized();
    return _box;
  }

  @override
  BehaviorSubject<bool> get onBackgroundChanged {
    _ensureInitialized();
    return _onBackgroundChanged;
  }

  @override
  BehaviorSubject<bool> get onNetworkConnected {
    _ensureInitialized();
    return _onNetworkConnected;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _ensureInitialized();
    _onBackgroundChanged.add(state == AppLifecycleState.paused);
  }

  void _connectivityChanged(ConnectivityResult event) {
    _ensureInitialized();
    _onNetworkConnected.add(event != ConnectivityResult.none);
  }

  void _ensureInitialized() {
    if (_completer == null || !_completer.isCompleted) {
      throw StateError('Make sure to first call [PlatformDependencies.initialized].');
    }
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
