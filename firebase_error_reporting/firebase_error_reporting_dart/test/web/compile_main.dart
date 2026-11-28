// Compiled (not run) by web_compile_test.dart.

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_error_reporting_dart/firebase_error_reporting_dart.dart';

Future<void> main() async {
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'key',
      appId: '1:123:dart:abc',
      projectId: 'demo-test',
    ),
  );
  final ErrorReporter reporter = ErrorReporter(
    app,
    service: 'web',
    transport: ErrorReportingTransport.relay(
      Uri.parse('https://example.com/errors'),
    ),
    store: ErrorReportingStore.localStorage(),
  );
  await reporter.runGuarded(() => throw StateError('x'));
  await reporter.close();
}
