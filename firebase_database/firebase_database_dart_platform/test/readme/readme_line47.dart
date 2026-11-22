// GENERATED from the docs by test/readme_snippets_test.dart. Do not edit: change the
// document and regenerate (see that file).
//
// This file is only analyzed, never run.

// ignore_for_file: type=lint, unused_local_variable, unused_import
// ignore_for_file: unused_element

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database_dart_platform/firebase_database_dart_platform.dart';

import 'package:firebase_core/firebase_core.dart' as ctx show FirebaseOptions;

/// Stands for the firebase_options.dart that `flutterfire configure` generates.
class DefaultFirebaseOptions {
  static ctx.FirebaseOptions get currentPlatform => throw UnimplementedError();
}

// README.md:47
Future<void> readmeLine47() async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await FirebaseDatabase.instance.ref('notes/today').set('Hello');
}
