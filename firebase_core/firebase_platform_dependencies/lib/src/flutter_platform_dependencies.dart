// File created by
// Lung Razvan <long1eu>
// on 01/09/2020

import 'dart:async';
import 'dart:typed_data';

import 'package:connectivity/connectivity.dart';
import 'package:firebase_core_vm/firebase_core_vm.dart' as core;
import 'package:firebase_core_vm/platform_dependencies.dart' as core;
import 'package:flutter/widgets.dart';
import 'package:hive/hive.dart';
import 'package:rxdart/rxdart.dart';

import '_init_io.dart' if (dart.library.html) '_init_web.dart';

// ignore_for_file: prefer_mixin, unawaited_futures, close_sinks
class FlutterPlatformDependencies extends core.PlatformDependencies with WidgetsBindingObserver {
  FlutterPlatformDependencies._(this.box, this.onBackgroundChanged, this.onNetworkConnected);

  static Future<core.PlatformDependencies> initializeForApp([String appName = core.FirebaseApp.defaultAppName]) async {
    if (_instances.containsKey(appName)) {
      return _instances[appName];
    } else if (_completers.containsKey(appName)) {
      return _completers[appName].future;
    }
    _completers[appName] = Completer<core.PlatformDependencies>();
    WidgetsFlutterBinding.ensureInitialized();

    final InitArguments args = await init();

    final Box<Uint8List> keyBox = await Hive.openBox<Uint8List>('encryption.store', path: args.boxPath);
    if (!keyBox.containsKey('key')) {
      final List<int> key = Hive.generateSecureKey();
      await keyBox.put('key', key);
    }
    final Uint8List key = keyBox.get('key');

    final Box<String> box = await Hive.openBox<String>('firebase.store', encryptionKey: key, path: args.boxPath);
    final BehaviorSubject<bool> onBackgroundChanged = BehaviorSubject<bool>.seeded(false);
    final BehaviorSubject<bool> onNetworkConnected = BehaviorSubject<bool>.seeded(true);

    Connectivity()
      ..checkConnectivity().then((ConnectivityResult event) => onNetworkConnected.add(event != ConnectivityResult.none))
      ..onConnectivityChanged
          .listen((ConnectivityResult event) => onNetworkConnected.add(event != ConnectivityResult.none));

    final FlutterPlatformDependencies instance =
        FlutterPlatformDependencies._(box, onBackgroundChanged, onNetworkConnected);
    WidgetsBinding.instance.addObserver(instance);
    _completers[appName].complete(instance);
    _instances[appName] = instance;
    return instance;
  }

  static core.PlatformDependencies get instance {
    if (_instances.containsKey(core.FirebaseApp.defaultAppName)) {
      return _instances[core.FirebaseApp.defaultAppName];
    } else {
      throw StateError(
          'Make sure you first initialize the default instance by calling [FlutterPlatformDependencies.initializeForApp]');
    }
  }

  static core.PlatformDependencies getInstance([String appName = core.FirebaseApp.defaultAppName]) {
    if (_instances.containsKey(appName)) {
      return _instances[appName];
    } else {
      throw StateError(
          'Make sure you first initialize the instance by calling [FlutterPlatformDependencies.initializeForApp]. Available instances are ${_instances.keys.toList()}.');
    }
  }

  static final Map<String, Completer<core.PlatformDependencies>> _completers =
      <String, Completer<core.PlatformDependencies>>{};
  static final Map<String, core.PlatformDependencies> _instances = <String, core.PlatformDependencies>{};

  @override
  final Box<String> box;

  @override
  final BehaviorSubject<bool> onBackgroundChanged;

  @override
  final BehaviorSubject<bool> onNetworkConnected;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    onBackgroundChanged.add(state == AppLifecycleState.paused);
  }
}

class InitArguments {
  const InitArguments(this.boxPath);

  final String boxPath;
}
