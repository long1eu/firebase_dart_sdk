// The "Shutting down" snippet of docs/guides/database.md, run by shutdown_snippet_test.dart in a
// subprocess. The body of main from `database.onConnected` to the end is the snippet verbatim; the
// lines before it make `database` (over a fake server, so no network) and connect it.

import 'dart:io';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:firebase_database_dart/testing.dart';

void main() {
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'test-key',
      appId: '1:1234567890:dart:test',
      projectId: 'test-project',
    ),
    name: 'shutdown-snippet',
  );
  final FirebaseDatabase database = databaseWithFakeServer(
    app,
    FakeDatabaseServer(),
  );

  // dart format off
  database.onConnected.listen((bool connected) => print('connected: $connected'));
  ProcessSignal.sigterm.watch().first.then((ProcessSignal _) async {
    await database.close();
    exit(0);
  });
  // dart format on
}
