// The production verification kit of firebase_error_reporting_dart and of this relay. For the maintainer to run
// against a project of their own; see the README of this example, "Production verification kit".
//
//   export ER_PROJECT_ID=my-project
//   export ER_ACCESS_TOKEN="$(gcloud auth print-access-token)"   # and/or: read -rs ER_API_KEY && export ER_API_KEY
//   dart run tool/verify_production.dart          # prints the plan, sends nothing
//   dart run tool/verify_production.dart --yes    # runs the checks
//
// Credentials come only from the environment and are never printed.

import 'dart:io';

import 'package:error_reporting_relay/verify_production.dart';
import 'package:http/http.dart' as http;

Future<void> main(List<String> args) async {
  final bool yes = args.contains('--yes');
  for (final String arg in args) {
    if (arg != '--yes') {
      // Only the option's name: a credential passed here by mistake stays hidden.
      stderr.writeln(
        'Unknown argument ${arg.startsWith('--') ? arg.split('=').first : '(not an option)'}.',
      );
      exitCode = 64;
      return;
    }
  }
  String? env(String name) {
    final String? value = Platform.environment[name]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  final String? projectId = env('ER_PROJECT_ID');
  if (projectId == null ||
      !RegExp(r'^[a-z][a-z0-9-]{4,28}[a-z0-9]$').hasMatch(projectId)) {
    stderr.writeln('Set ER_PROJECT_ID to the Google Cloud project id.');
    exitCode = 64;
    return;
  }
  final KitConfig config = KitConfig(
    projectId: projectId,
    accessToken: env('ER_ACCESS_TOKEN'),
    apiKey: env('ER_API_KEY'),
    otherApiKey: env('ER_OTHER_API_KEY'),
    runTag: newRunTag(),
  );
  if (config.accessToken == null && config.apiKey == null) {
    stderr.writeln('Set ER_ACCESS_TOKEN or ER_API_KEY (see the README).');
    exitCode = 64;
    return;
  }
  stdout.writeln(
    '''
Error Reporting production verification kit
  project      ${config.projectId}
  credentials  ${<String>[if (config.accessToken != null) 'access token', if (config.apiKey != null) 'API key', if (config.otherApiKey != null) 'other key'].join(', ')} (not shown)
  service      $kitService
  version      ${config.runTag}   (the run tag)
It sends at most six reports to projects.events.report, one of them through a relay it runs on 127.0.0.1.''',
  );
  if (!yes) {
    stdout.writeln('\nNothing was sent. Run again with --yes.');
    exitCode = 2;
    return;
  }
  final http.Client client = http.Client();
  try {
    final List<CheckResult> results = await runKit(
      config,
      client: client,
      log: (String line) => stdout.writeln('  $line'),
    );
    stdout.writeln('');
    results.forEach(stdout.writeln);
    stdout.writeln('\n${consoleChecklist(config)}');
    if (results.any((CheckResult r) => r.outcome == Outcome.fail)) {
      exitCode = 1;
    }
  } finally {
    client.close();
  }
}
