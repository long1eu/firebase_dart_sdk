// Setup shared by the examples in this directory: a FirebaseApp built from the
// command line, a FirebaseInstallations over a FileKeyValueStore, and a
// FirebaseRemoteConfig on top.
//
// There is no emulator for Remote Config: the examples talk to the project you
// name. Run any of them with
//
//     dart run example/<name>.dart --api-key <key> --app-id <id> --project-id <project>
//
// Each run uses a new temporary directory, so it creates a new installation.

import 'dart:io';

import 'package:args/args.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_installations_dart/io.dart';
import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart';

/// A [FirebaseRemoteConfig] for the app named by `--api-key`, `--app-id` and
/// `--project-id` in [arguments], with [defaults]. The program stops with a
/// usage message when one of them is missing.
FirebaseRemoteConfig exampleRemoteConfig(
  List<String> arguments, {
  Map<String, Object> defaults = const <String, Object>{},
}) {
  final ArgParser parser = ArgParser()
    ..addOption('api-key', help: 'The web API key of the project.')
    ..addOption('app-id', help: 'The app id, for example 1:123:web:abc.')
    ..addOption('project-id', help: 'The project id.');
  final ArgResults results = parser.parse(arguments);
  final String? apiKey = results.option('api-key');
  final String? appId = results.option('app-id');
  final String? projectId = results.option('project-id');
  if (apiKey == null || appId == null || projectId == null) {
    stderr.writeln('Usage: dart run example/<name>.dart ${parser.usage}');
    exit(64);
  }
  final FirebaseApp app = FirebaseApp.withOptions(
    FirebaseOptions(apiKey: apiKey, appId: appId, projectId: projectId),
  );
  final Directory directory = Directory.systemTemp.createTempSync(
    'firebase_remote_config_example',
  );
  final FirebaseInstallations installations = FirebaseInstallations(
    app,
    store: FileKeyValueStore(directory.path),
  );
  return FirebaseRemoteConfig(
    app,
    installations: installations,
    defaults: defaults,
    logger: (RemoteConfigLogLevel level, String message) =>
        stderr.writeln('[${level.name}] $message'),
  );
}

/// Closes [remoteConfig], its Installations instance and their store.
Future<void> closeAll(FirebaseRemoteConfig remoteConfig) async {
  await remoteConfig.close();
  await remoteConfig.installations.close();
  await remoteConfig.installations.store.close();
}
