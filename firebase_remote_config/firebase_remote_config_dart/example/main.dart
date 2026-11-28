// Fetches and activates the Remote Config template of a Firebase app, then
// reads a value.
//
// There is no emulator for Remote Config; pass your own project:
//
//     dart run example/main.dart <api key> <app id> <project id>

import 'dart:io';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_installations_dart/io.dart';
import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 3) {
    stderr.writeln(
      'Usage: dart run example/main.dart <api key> <app id> <project id>',
    );
    exit(64);
  }
  final FirebaseApp app = FirebaseApp.withOptions(
    FirebaseOptions(
      apiKey: arguments[0],
      appId: arguments[1],
      projectId: arguments[2],
    ),
  );
  // Keep the store in a directory of the user, so the installation and the
  // fetched template survive restarts. A temporary one is enough here.
  final Directory directory = Directory.systemTemp.createTempSync('rc');
  final FirebaseInstallations installations = FirebaseInstallations(
    app,
    store: FileKeyValueStore(directory.path),
  );
  final FirebaseRemoteConfig remoteConfig = FirebaseRemoteConfig(
    app,
    installations: installations,
    defaults: <String, Object>{'welcome_message': 'Hello from the defaults'},
  );
  try {
    final bool activated = await remoteConfig.fetchAndActivate();
    final RemoteConfigValue value = remoteConfig.getValue('welcome_message');
    print('activated: $activated');
    print('welcome_message = "${value.asString()}" (${value.source.name})');
  } on FirebaseRemoteConfigException catch (e) {
    print('Failed: ${e.code}: ${e.message}');
  } finally {
    await remoteConfig.close();
    await installations.close();
    await installations.store.close();
  }
}
