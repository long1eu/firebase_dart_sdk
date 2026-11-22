// GENERATED from the docs by test/readme_snippets_test.dart. Do not edit: change the
// document and regenerate (see that file).
//
// This file is only analyzed, never run.

// ignore_for_file: type=lint, unused_local_variable, unused_import
// ignore_for_file: unused_element

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart';

// ../../docs/guides/database_flutter.md:153
Future<void> guideLine153() async {
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: '<the apiKey of your options>',
      appId: '<the appId>',
      projectId: '<the projectId>',
    ),
  );
  final FirebaseDatabase database = FirebaseDatabase(app, emulatorHost: '127.0.0.1:9100');
}
