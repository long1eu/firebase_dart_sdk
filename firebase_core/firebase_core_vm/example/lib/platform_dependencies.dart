// File created by
// Lung Razvan <long1eu>
// on 03/03/2020

import 'package:connectivity/connectivity.dart';
import 'package:firebase_core_vm/platform_dependencies.dart' as core;
import 'package:flutter/widgets.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ignore_for_file: prefer_mixin
class PlatformDependencies extends core.PlatformDependencies with WidgetsBindingObserver {
  PlatformDependencies(this._preferences)
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

  @override
  String get(String key) {
    return _preferences.getString(key);
  }

  @override
  Future<void> set(String key, String value) {
    return _preferences.setString(key, value);
  }

  void _connectivityChanged(ConnectivityResult event) {
    onNetworkConnected.add(event != ConnectivityResult.none);
  }
}
