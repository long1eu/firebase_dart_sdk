import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';

import 'disk_cache.dart';

/// The settings of a run, from `--dart-define` values.
abstract final class AppConfig {
  /// Host of the Firestore emulator.
  static const String emulatorHost = String.fromEnvironment(
    'EMULATOR_HOST',
    defaultValue: '127.0.0.1',
  );

  /// Port of the Firestore emulator.
  static const int emulatorPort = int.fromEnvironment(
    'EMULATOR_PORT',
    defaultValue: 8161,
  );

  /// `true` keeps the offline cache in SQLite on disk; the default is memory.
  static const bool diskCache = bool.fromEnvironment('DISK_CACHE');

  /// Directory of the SQLite files when [diskCache] is on. Empty: the
  /// application support directory of `path_provider`.
  static const String cacheDir = String.fromEnvironment('CACHE_DIR');

  /// `true` calls `disableNetwork()` before the first read, so the app starts
  /// with what the disk cache has.
  static const bool startOffline = bool.fromEnvironment('START_OFFLINE');

  /// The collection the app lists and writes.
  static const String collection = String.fromEnvironment(
    'COLLECTION',
    defaultValue: 'items',
  );
}

/// Placeholder options: the emulator accepts any project id that starts with
/// `demo-`, and needs no real API key or app id.
const FirebaseOptions demoOptions = FirebaseOptions(
  apiKey: 'demo-api-key',
  appId: '1:000000000000:linux:0000000000000000',
  messagingSenderId: '000000000000',
  projectId: 'demo-flutterfire-linux',
);

bool _started = false;

/// Initializes Firebase and Firestore once: the same calls as in an app on the
/// official plugins, plus the optional disk cache.
Future<void> bootstrap() async {
  if (_started) {
    return;
  }
  _started = true;
  WidgetsFlutterBinding.ensureInitialized();
  if (AppConfig.diskCache) {
    // Must run before the first Firestore operation.
    await enableDiskCache(AppConfig.cacheDir);
  }
  await Firebase.initializeApp(options: demoOptions);
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  firestore.useFirestoreEmulator(
    AppConfig.emulatorHost,
    AppConfig.emulatorPort,
  );
  if (AppConfig.startOffline) {
    await firestore.disableNetwork();
  }
}
