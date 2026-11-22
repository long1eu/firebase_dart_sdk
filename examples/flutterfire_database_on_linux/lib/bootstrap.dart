import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/widgets.dart';

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

  /// The node of the database the app reads and writes under.
  static const String root = String.fromEnvironment(
    'ROOT',
    defaultValue: 'ffdb',
  );

  /// The name of this run in the presence list.
  static final String clientId = 'linux-${Random().nextInt(1 << 31)}';
}

/// Placeholder options. The emulator of `tool/start_database_emulator.sh`
/// serves the namespace `demo-test-default-rtdb` with open rules; it needs no
/// real API key or app id.
const FirebaseOptions demoOptions = FirebaseOptions(
  apiKey: 'demo-api-key',
  appId: '1:000000000000:linux:0000000000000000',
  messagingSenderId: '000000000000',
  projectId: 'demo-test',
  databaseURL: 'https://demo-test-default-rtdb.firebaseio.com',
);

bool _started = false;

/// Initializes Firebase and the Database emulator once: the same calls as in
/// an app on the official plugins. `useDatabaseEmulator` runs before the first
/// read or write, because the client takes its settings when it is created.
Future<void> bootstrap() async {
  if (_started) {
    return;
  }
  _started = true;
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: demoOptions);
  FirebaseDatabase.instance.useDatabaseEmulator(
    AppConfig.emulatorHost,
    AppConfig.emulatorPort,
  );
}
