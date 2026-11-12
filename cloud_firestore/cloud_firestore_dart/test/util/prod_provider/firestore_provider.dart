// File created by
// Lung Razvan <long1eu>
// on 08/10/2018

import 'dart:convert';
import 'dart:io';

import '../test_backend.dart';

/// Provides locations of production Firestore and Firebase Rules.
class FirestoreProvider {
  String get firestoreHost => 'firestore.googleapis.com';

  /// Project id used when no `res/google-services.json` is present (for
  /// example against the local emulator).
  static const String fallbackProjectId = 'demo-test';

  /// The project the integration tests use: `FIRESTORE_TEST_PROJECT_ID` when
  /// the suite is pointed at a real project (see `test_backend.dart`), else
  /// the one of `res/google-services.json`, else [fallbackProjectId].
  String get projectId {
    final TestBackend backend = TestBackend();
    if (backend.usesRealProject) {
      return backend.realProjectId!;
    }

    final File config =
        File('${Directory.current.path}/res/google-services.json');

    if (!config.existsSync()) {
      return fallbackProjectId;
    }

    final Map<String, dynamic> json = jsonDecode(config.readAsStringSync());
    return json['project_info']['project_id'];
  }
}
