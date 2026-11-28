// Setup shared by the examples in this directory: a FirebaseApp built from the
// command line and a FirebaseInstallations over a FileKeyValueStore.
//
// There is no emulator for Firebase Installations: the examples talk to the
// project you name. Run any of them with
//
//     dart run example/<name>.dart --api-key <key> --app-id <id> --project-id <project>
//
// Each run creates a new installation in a new temporary directory; run
// example/delete.dart (or call delete()) to remove it from the project.

import 'dart:io';

import 'package:args/args.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_installations_dart/firebase_installations_dart.dart';
import 'package:firebase_installations_dart/io.dart';

/// A [FirebaseInstallations] for the app named by `--api-key`, `--app-id` and
/// `--project-id` in [arguments], stored in a new temporary directory. The
/// program stops with a usage message when one of them is missing.
FirebaseInstallations exampleInstallations(List<String> arguments) {
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
    'firebase_installations_example',
  );
  return FirebaseInstallations(
    app,
    store: FileKeyValueStore(directory.path),
    logger: (InstallationsLogLevel level, String message) =>
        stderr.writeln('[${level.name}] $message'),
  );
}
