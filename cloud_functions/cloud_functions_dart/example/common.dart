// Setup shared by the examples in this directory: a FirebaseApp and a
// FirebaseFunctions built from the command line.
//
// Against a deployed project:
//
//     dart run example/call.dart --api-key <key> --app-id <id> --project-id <project>
//
// Against the Functions emulator of this repository (see tool/README.md):
//
//     ./tool/start_functions_emulator.sh 9501
//     dart run example/call.dart --emulator 127.0.0.1:9501
//
// The emulator's project is demo-functions and it accepts any API key and
// application id, so --emulator alone is enough. Without --emulator the
// FIREBASE_FUNCTIONS_EMULATOR_HOST variable is used when it is set.

import 'dart:io';

import 'package:args/args.dart';
import 'package:cloud_functions_dart/cloud_functions_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';

/// The project of the emulator fixture.
const String emulatorProjectId = 'demo-functions';

/// The options of the example programs.
final ArgParser parser = ArgParser()
  ..addOption('api-key', help: 'The web API key of the project.')
  ..addOption('app-id', help: 'The app id, for example 1:123:web:abc.')
  ..addOption('project-id', help: 'The project id.')
  ..addOption('region', defaultsTo: 'us-central1', help: 'The function region.')
  ..addOption(
    'emulator',
    help: 'host:port of the Functions emulator; replaces the project options.',
  );

/// A [FirebaseFunctions] for the app named by [arguments]. The program stops
/// with a usage message when neither `--emulator` (or the environment
/// variable) nor the three project options are given.
FirebaseFunctions exampleFunctions(
  List<String> arguments, {
  void Function(FirebaseApp app)? configureApp,
}) {
  final ArgResults results = parser.parse(arguments);
  final String? emulator =
      results.option('emulator') ??
      FirebaseFunctions.emulatorHostFromEnvironment;
  final String? apiKey = results.option('api-key');
  final String? appId = results.option('app-id');
  final String? projectId = results.option('project-id');
  if (emulator == null &&
      (apiKey == null || appId == null || projectId == null)) {
    stderr.writeln('Usage: dart run example/<name>.dart ${parser.usage}');
    exit(64);
  }
  final FirebaseApp app = FirebaseApp.withOptions(
    FirebaseOptions(
      apiKey: apiKey ?? 'demo-key',
      appId: appId ?? '1:1234567890:dart:example',
      projectId: projectId ?? emulatorProjectId,
    ),
  );
  configureApp?.call(app);
  return FirebaseFunctions(
    app,
    region: results.option('region') ?? 'us-central1',
    emulatorHost: emulator,
    onWarning: (String message) => stderr.writeln('warning: $message'),
  );
}
