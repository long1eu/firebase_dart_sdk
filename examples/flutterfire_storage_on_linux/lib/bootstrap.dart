import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/widgets.dart';

/// The settings of a run, from `--dart-define` values.
abstract final class AppConfig {
  /// Host of the Storage emulator.
  static const String emulatorHost = String.fromEnvironment(
    'EMULATOR_HOST',
    defaultValue: '127.0.0.1',
  );

  /// Port of the Storage emulator.
  static const int emulatorPort = int.fromEnvironment(
    'EMULATOR_PORT',
    defaultValue: 9199,
  );

  /// The folder the app lists and writes in the bucket.
  static const String folder = String.fromEnvironment(
    'FOLDER',
    defaultValue: 'images',
  );
}

/// Placeholder options. The emulator of `tool/start_storage_emulator.sh` has
/// the bucket `demo-test.appspot.com`; it needs no real API key or app id.
const FirebaseOptions demoOptions = FirebaseOptions(
  apiKey: 'demo-api-key',
  appId: '1:000000000000:linux:0000000000000000',
  messagingSenderId: '000000000000',
  projectId: 'demo-test',
  storageBucket: 'demo-test.appspot.com',
);

bool _started = false;

/// Initializes Firebase and Storage once: the same calls as in an app on the
/// official plugins.
Future<void> bootstrap() async {
  if (_started) {
    return;
  }
  _started = true;
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: demoOptions);
  await FirebaseStorage.instance.useStorageEmulator(
    AppConfig.emulatorHost,
    AppConfig.emulatorPort,
  );
}
