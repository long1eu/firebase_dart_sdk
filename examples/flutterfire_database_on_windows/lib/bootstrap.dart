import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/widgets.dart';
import 'package:flutterfire_database_on_windows/dart_database.dart';

/// The settings of a run, from `--dart-define` values.
abstract final class AppConfig {
  /// Host of the Database emulator.
  static const String emulatorHost = String.fromEnvironment(
    'EMULATOR_HOST',
    defaultValue: '127.0.0.1',
  );

  /// Port of the Database emulator.
  static const int emulatorPort = int.fromEnvironment(
    'EMULATOR_PORT',
    defaultValue: 9100,
  );

  /// The database URL. Its first label names the emulator namespace
  /// (`demo-test-default-rtdb`), which starts with open rules.
  static const String databaseUrl = String.fromEnvironment(
    'DATABASE_URL',
    defaultValue: 'https://demo-test-default-rtdb.firebaseio.com',
  );

  /// `true` keeps the cache and the pending writes in SQLite on disk; the
  /// default is memory.
  static const bool diskCache = bool.fromEnvironment('DISK_CACHE');

  /// Directory of the SQLite files when [diskCache] is on. Empty: the
  /// application support directory of `path_provider`.
  static const String cacheDir = String.fromEnvironment('CACHE_DIR');

  /// `true` calls `goOffline()` before the first read, so the app starts
  /// with what the disk cache has.
  static const bool startOffline = bool.fromEnvironment('START_OFFLINE');

  /// The node of the database the app reads and writes under.
  static const String root = String.fromEnvironment(
    'ROOT',
    defaultValue: 'ffdb',
  );

  /// The name of this run in the presence list.
  static final String clientId = 'windows-${Random().nextInt(1 << 31)}';
}

/// Placeholder options. The emulator of `tool/start_database_emulator.sh`
/// serves the namespace `demo-test-default-rtdb` with open rules; it needs no
/// real API key or app id.
const FirebaseOptions demoOptions = FirebaseOptions(
  apiKey: 'demo-api-key',
  appId: '1:000000000000:windows:0000000000000000',
  messagingSenderId: '000000000000',
  projectId: 'demo-test',
  databaseURL: AppConfig.databaseUrl,
);

bool _started = false;

/// Initializes Firebase and the Database emulator once: the same calls as in
/// an app on the official plugins, plus the optional disk cache.
/// `useDatabaseEmulator` runs before the first read or write, because the
/// client takes its settings when it is created.
Future<void> bootstrap() async {
  if (_started) {
    return;
  }
  _started = true;
  WidgetsFlutterBinding.ensureInitialized();
  if (AppConfig.diskCache) {
    await useDiskCache(AppConfig.cacheDir);
  }
  await Firebase.initializeApp(options: demoOptions);
  final FirebaseDatabase database = FirebaseDatabase.instance;
  database.useDatabaseEmulator(AppConfig.emulatorHost, AppConfig.emulatorPort);
  if (AppConfig.startOffline) {
    await database.goOffline();
  }
}
