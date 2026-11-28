// Setup shared by the examples in this directory: the command-line options
// that name a Firebase app, and a logger that writes to stderr.
//
// There is no App Check emulator: the examples talk to the project you name.
// Run any of them with
//
//     dart run example/<name>.dart --api-key <key> --app-id <id> --project-id <project>

import 'dart:io';

import 'package:args/args.dart';
import 'package:firebase_app_check_dart/firebase_app_check_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';

/// A parser with the three options that name a Firebase app. Examples add
/// their own options to it.
ArgParser exampleParser() {
  return ArgParser()
    ..addOption('api-key', help: 'The web API key of the project.')
    ..addOption('app-id', help: 'The app id, for example 1:123:web:abc.')
    ..addOption('project-id', help: 'The project id.');
}

/// The [FirebaseApp] named by `--api-key`, `--app-id` and `--project-id` in
/// [results]. The program stops with a usage message when one is missing.
FirebaseApp exampleApp(ArgParser parser, ArgResults results) {
  final String? apiKey = results.option('api-key');
  final String? appId = results.option('app-id');
  final String? projectId = results.option('project-id');
  if (apiKey == null || appId == null || projectId == null) {
    stderr.writeln('Usage: dart run example/<name>.dart ${parser.usage}');
    exit(64);
  }
  return FirebaseApp.withOptions(
    FirebaseOptions(apiKey: apiKey, appId: appId, projectId: projectId),
  );
}

/// Writes every log line of App Check to stderr. Lines never contain a token.
void exampleLogger(AppCheckLogLevel level, String message) {
  stderr.writeln('[${level.name}] $message');
}

/// What the examples print about a token: its length and expiry, never the
/// token itself.
String describeToken(AppCheckToken token) {
  return 'token of ${token.token.length} characters, '
      'expires ${token.expireTime.toIso8601String()}';
}
