// GENERATED from the docs by test/readme_snippets_test.dart. Do not edit: change the
// document and regenerate (see that file).
//
// This file is only analyzed, never run.

// ignore_for_file: type=lint, unused_local_variable, unused_import
// ignore_for_file: unused_element

import 'package:cloud_firestore_dart_flutterfire/cloud_firestore_dart_flutterfire.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database_dart_platform/firebase_database_dart_platform.dart';

// README.md:99
Future<void> readmeLine99() async {
  FirebaseDatabaseDart.use(
    appCheckProviderFor: (FirebaseApp app) {
      final FirebaseAppCheck appCheck = FirebaseAppCheck.instanceFor(app: app);
      return FlutterFireAppCheckProvider(
        getToken: appCheck.getToken,
        onTokenChange: appCheck.onTokenChange,
      );
    },
  );
}
