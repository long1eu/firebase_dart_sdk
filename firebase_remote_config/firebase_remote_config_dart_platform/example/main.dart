// A Flutter program that uses the official firebase_remote_config API, with
// firebase_remote_config_dart doing the work underneath.
//
// On Linux the FirebaseRemoteConfigDart.use() call is optional: Flutter
// registers the package before main() runs. On the other platforms it
// replaces the official implementation. Remote Config has no emulator: run it
// with the options of your own project (flutterfire configure) and a template
// with a parameter named rc_probe_flag.

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:firebase_remote_config_dart_platform/firebase_remote_config_dart_platform.dart';
import 'package:flutter/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseRemoteConfigDart.use();
  await Firebase.initializeApp(
    // Use your own options (flutterfire configure).
    options: const FirebaseOptions(
      apiKey: 'your-api-key',
      appId: '1:1234567890:web:0123456789abcdef',
      messagingSenderId: '1234567890',
      projectId: 'your-project-id',
    ),
  );
  final FirebaseRemoteConfig remoteConfig = FirebaseRemoteConfig.instance;
  await remoteConfig.setConfigSettings(
    RemoteConfigSettings(
      fetchTimeout: const Duration(seconds: 30),
      minimumFetchInterval: const Duration(minutes: 5),
    ),
  );
  await remoteConfig.setDefaults(const <String, dynamic>{
    'rc_probe_flag': false,
  });
  await remoteConfig.ensureInitialized();

  final bool updated = await remoteConfig.fetchAndActivate();
  debugPrint(
    'updated: $updated, rc_probe_flag: ${remoteConfig.getBool('rc_probe_flag')}',
  );

  // Listening opens the realtime connection: a template published in the
  // console arrives here; activate it to read its values.
  remoteConfig.onConfigUpdated.listen((RemoteConfigUpdate update) async {
    await remoteConfig.activate();
    debugPrint(
      'changed: ${update.updatedKeys.join(', ')}; rc_probe_flag: '
      '${remoteConfig.getBool('rc_probe_flag')}',
    );
  });
}
