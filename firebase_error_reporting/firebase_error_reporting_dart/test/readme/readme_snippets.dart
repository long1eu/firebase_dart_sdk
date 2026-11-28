// GENERATED from README.md by test/readme_snippets_test.dart. Do not edit: change the README and
// regenerate (see that file).
//
// This file is only analyzed, never run.

// ignore_for_file: type=lint, unused_local_variable, unused_import
// ignore_for_file: unused_element

import 'dart:convert';
import 'dart:io';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:firebase_error_reporting_dart/firebase_error_reporting_dart.dart';
import 'package:firebase_error_reporting_dart/io.dart';

late FirebaseApp app;
late ErrorReporter reporter;

// README.md:37
Future<void> readmeLine37() async {
  final ErrorReporter reporter = ErrorReporter(
    app,
    service: 'notes-desktop',
    version: '1.4.0',
    transport: ErrorReportingTransport.relay(Uri.parse('https://relay.example.com/errors')),
    store: FileErrorReportingStore(Directory.systemTemp),
  );
}

// README.md:59
Future<void> readmeLine59() async {
  final OAuthTokenProvider credentials = OAuthTokenProvider.serviceAccount(
    jsonDecode(File(Platform.environment['SERVICE_ACCOUNT_KEY_FILE']!).readAsStringSync()),
    scopes: const <String>['https://www.googleapis.com/auth/cloud-platform'],
  );
  final ErrorReporter reporter = ErrorReporter(
    app,
    service: 'billing-worker',
    version: '2.0.1',
    transport: ErrorReportingTransport.direct(credentials: credentials),
  );
}

// README.md:84
Future<void> readmeLine84() async {
  await reporter.runGuarded(() async {
    // The program: errors that escape it, and errors of work it starts and nobody awaits, are reported.
  });
}

// README.md:90
Future<void> readmeLine90() async {
  try {
    await File('notes.json').readAsString();
  } on FileSystemException catch (error, stack) {
    await reporter.recordError(error, stack, reason: 'while loading the notes');
  }
}

// README.md:117
Future<void> readmeLine117() async {
  await reporter.setUser('user-7f3a');
  await reporter.recordError(
    StateError('order not found'),
    StackTrace.current,
    httpRequest: const HttpRequestContext(method: 'GET', url: '/orders/42', responseStatusCode: 404),
  );
  await reporter.setCollectionEnabled(false);
}

// README.md:135
Future<void> readmeLine135() async {
  final ErrorReporter scrubbing = ErrorReporter(
    app,
    service: 'notes-desktop',
    transport: ErrorReportingTransport.relay(Uri.parse('https://relay.example.com/errors')),
    beforeSend: (ErrorEvent event) => event.copyWith(
      message: event.message.replaceAll(RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+'), '<email>'),
    ),
  );
}
