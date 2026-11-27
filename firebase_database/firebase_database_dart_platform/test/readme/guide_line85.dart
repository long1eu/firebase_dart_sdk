// GENERATED from the docs by test/readme_snippets_test.dart. Do not edit: change the
// document and regenerate (see that file).
//
// This file is only analyzed, never run.

// ignore_for_file: type=lint, unused_local_variable, unused_import
// ignore_for_file: unused_element

import 'package:firebase_database_dart_platform/firebase_database_dart_platform.dart';
import 'package:firebase_database_dart_sqlite/firebase_database_dart_sqlite.dart';

// ../../docs/guides/database_flutter.md:85
Future<void> guideLine85() async {
  void usePersistence(String directory) {
    FirebaseDatabaseDart.use(
      persistenceFor: (int cacheSizeBytes) =>
          sqlitePersistence(directory, cacheSizeBytes: cacheSizeBytes),
    );
  }
}
