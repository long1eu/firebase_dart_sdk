// File created by
// Lung Razvan <long1eu>
// on 03/03/2020

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectivity/connectivity.dart';
import 'package:connectivity_linux/connectivity_linux.dart';
import 'package:firebase_core_vm/platform_dependencies.dart' as core;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rxdart/rxdart.dart';

// ignore_for_file: prefer_mixin, unawaited_futures
class PlatformDependencies extends core.PlatformDependencies with WidgetsBindingObserver {
  PlatformDependencies._();

  static PlatformDependencies instance = PlatformDependencies._();

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
