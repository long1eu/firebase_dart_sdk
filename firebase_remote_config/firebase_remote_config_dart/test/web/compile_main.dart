// Compiled (not run) by web_compile_test.dart.

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart';

Future<void> main() async {
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'AIzaSyDummyKeyForCompileOnly000000000000',
      appId: '1:123:web:abc',
      projectId: 'demo-test',
    ),
  );
  final FirebaseInstallations installations = FirebaseInstallations(
    app,
    store: MemoryKeyValueStore(),
  );
  final FirebaseRemoteConfig remoteConfig = FirebaseRemoteConfig(
    app,
    installations: installations,
    defaults: <String, Object>{'welcome_message': 'Hello'},
  );
  await remoteConfig.setCustomSignals(<String, Object?>{'tier': 'pro'});
  // ignore: avoid_print
  print(<Object?>[
    await remoteConfig.fetchAndActivate(),
    remoteConfig.getString('welcome_message'),
    remoteConfig.getInt('max_items'),
    remoteConfig.onConfigUpdated.listen((RemoteConfigUpdate update) {}),
  ]);
  await remoteConfig.close();
}
