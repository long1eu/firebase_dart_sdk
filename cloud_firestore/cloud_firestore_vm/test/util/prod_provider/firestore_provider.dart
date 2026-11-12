// File created by
// Lung Razvan <long1eu>
// on 08/10/2018

import 'dart:convert';
import 'dart:io';

/// Provides locations of production Firestore and Firebase Rules.
class FirestoreProvider {
  String get firestoreHost => 'firestore.googleapis.com';

  /// Project id used when no `res/google-services.json` is present (for
  /// example against the local emulator).
  static const String fallbackProjectId = 'demo-test';

  String get projectId {
    final File config =
        File('${Directory.current.path}/res/google-services.json');

    if (!config.existsSync()) {
      return fallbackProjectId;
    }

    final Map<String, dynamic> json = jsonDecode(config.readAsStringSync());
    return json['project_info']['project_id'];
  }
}
