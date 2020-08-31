// File created by
// Lung Razvan <long1eu>
// on 03/03/2020

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectivity/connectivity.dart';
import 'package:connectivity_linux/connectivity_linux.dart';
import 'package:firebase_core_vm/firebase_core_vm.dart' as core;
import 'package:firebase_core_vm/platform_dependencies.dart' as core;
import 'package:flutter/widgets.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rxdart/rxdart.dart';

// ignore: prefer_mixin
class PlatformDependencies extends core.PlatformDependencies with WidgetsBindingObserver {
  PlatformDependencies._();

  static PlatformDependencies instance = PlatformDependencies._();

  static Future<void> initialize() async {
    if (instance._completer != null) {
      return instance._completer.future;
    }
    instance._completer = Completer<void>();
    WidgetsFlutterBinding.ensureInitialized();

    String path;
    if (!core.kIsWeb) {
      ConnectivityLinux.register();
      final Directory parent = await getApplicationDocumentsDirectory();
      path = parent.path;
    }

    final Box<Uint8List> keyBox = await Hive.openBox<Uint8List>('encryption.store', path: path);
    if (!keyBox.containsKey('key')) {
      final List<int> key = Hive.generateSecureKey();
      await keyBox.put('key', key);
    }
    final Uint8List key = keyBox.get('key');

    instance._box = await Hive.openBox<String>('firebase.store', encryptionKey: key, path: path);
    instance._onBackgroundChanged = BehaviorSubject<bool>.seeded(false);
    instance._onNetworkConnected = BehaviorSubject<bool>.seeded(true);
    WidgetsBinding.instance.addObserver(instance);

    Connectivity()
      // ignore: unawaited_futures
      ..checkConnectivity().then(instance._connectivityChanged)
      ..onConnectivityChanged.listen(instance._connectivityChanged);

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
      throw StateError('Make sure to first call [$PlatformDependencies.initialized].');
    }
  }
}
