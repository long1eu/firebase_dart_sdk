// File created by
// Lung Razvan <long1eu>
// on 04/03/2020

library firebase_core_dart;

import 'dart:async';

import 'package:connectivity/connectivity.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart'
    as flutter;
import 'package:firebase_core_vm/firebase_core_vm.dart' as vm;
import 'package:firebase_core_vm/platform_dependencies.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

export 'package:firebase_core_vm/firebase_core_vm.dart'
    show isWeb, isMobile, isDesktop;

/// The implementation of `firebase_core` for web.
class FirebaseCoreDart extends flutter.FirebaseCorePlatform {
  /// Registers that [FirebaseCoreDart] is the platform implementation.
  ///
  /// If [options] is provided the default Firebase app will be initialized.
  static Future<void> register({
    flutter.FirebaseOptions options,
    PlatformDependencies dependencies,
  }) async {
    if (options != null) {
      if (dependencies == null) {
        WidgetsFlutterBinding.ensureInitialized();
        final SharedPreferences preferences =
            await SharedPreferences.getInstance();
        dependencies = _DefaultPlatformDependencies(preferences);
      }

      vm.FirebaseApp.withOptions(_createFromPlatformOptions(options),
          dependencies: dependencies);
    }

    flutter.FirebaseCorePlatform.instance = FirebaseCoreDart();
  }

  @override
  Future<flutter.PlatformFirebaseApp> appNamed(String name) async {
    try {
      name = _normalizeName(name);
      final vm.FirebaseApp app = vm.FirebaseApp.getInstance(name);
      return _createFromDartApp(app);
    } on StateError catch (e) {
      if (e.message.startsWith('FirebaseApp with name $name does\'t exist.')) {
        return null;
      }

      rethrow;
    }
  }

  @override
  Future<void> configure(String name, flutter.FirebaseOptions options,
      [PlatformDependencies dependencies]) async {
    name = _normalizeName(name);
    vm.FirebaseApp.withOptions(
      vm.FirebaseOptions(
        apiKey: options.apiKey,
        databaseUrl: options.databaseURL,
        projectId: options.projectID,
        storageBucket: options.storageBucket,
        gcmSenderId: options.gcmSenderID,
        gaTrackingId: options.trackingID,
        applicationId: options.googleAppID,
      ),
      dependencies: dependencies,
      name: name,
    );
  }

  @override
  Future<List<flutter.PlatformFirebaseApp>> allApps() async {
    return vm.FirebaseApp.apps //
        .map<flutter.PlatformFirebaseApp>(_createFromDartApp)
        .toList();
  }

  String _normalizeName(String name) {
    if (name == '__FIRAPP_DEFAULT' || name == '[DEFAULT]') {
      return vm.FirebaseApp.defaultAppName;
    } else {
      return name;
    }
  }
}

/// This implementation provides basic information to Firebase services about
/// connectivity and background state and also provides a light storage solution
/// for persisting state across restarts.
class _DefaultPlatformDependencies extends PlatformDependencies
    with WidgetsBindingObserver
    implements LocalStorage {
  _DefaultPlatformDependencies(this._preferences)
      : onBackgroundChanged = BehaviorSubject<bool>.seeded(false),
        onNetworkConnected = BehaviorSubject<bool>.seeded(true) {
    WidgetsBinding.instance.addObserver(this);
    Connectivity()
      ..checkConnectivity().then(_connectivityChanged)
      ..onConnectivityChanged.listen(_connectivityChanged);
  }

  final SharedPreferences _preferences;
  @override
  final BehaviorSubject<bool> onBackgroundChanged;
  @override
  final BehaviorSubject<bool> onNetworkConnected;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    onBackgroundChanged.add(state == AppLifecycleState.paused);
  }

  void _connectivityChanged(ConnectivityResult event) {
    onNetworkConnected.add(event != ConnectivityResult.none);
  }

  @override
  String get(String key) {
    return _preferences.getString(key);
  }

  @override
  Future<void> set(String key, String value) {
    return _preferences.setString(key, value);
  }
}

flutter.PlatformFirebaseApp _createFromDartApp(vm.FirebaseApp app) {
  return flutter.PlatformFirebaseApp(
      app.name, _createFromDartOptions(app.options));
}

flutter.FirebaseOptions _createFromDartOptions(vm.FirebaseOptions options) {
  return flutter.FirebaseOptions(
    apiKey: options.apiKey,
    trackingID: options.gaTrackingId,
    gcmSenderID: options.gcmSenderId,
    projectID: options.projectId,
    googleAppID: options.applicationId,
    databaseURL: options.databaseUrl,
    storageBucket: options.storageBucket,
  );
}

vm.FirebaseOptions _createFromPlatformOptions(flutter.FirebaseOptions options) {
  return vm.FirebaseOptions(
    apiKey: options.apiKey,
    gaTrackingId: options.trackingID,
    gcmSenderId: options.gcmSenderID,
    projectId: options.projectID,
    applicationId: options.googleAppID,
    databaseUrl: options.databaseURL,
    storageBucket: options.storageBucket,
  );
}
