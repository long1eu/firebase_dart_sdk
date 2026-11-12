import 'dart:io';

import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';

/// Suffixes of the files SQLite keeps next to a database file: the rollback
/// journal, the write-ahead log and its shared memory index.
const List<String> sqliteSideFileSuffixes = <String>[
  '-journal',
  '-wal',
  '-shm',
];

/// Deletes the SQLite database file at [path] and its side files. Files that
/// don't exist are skipped.
///
/// Throws a [FirestoreError] with [FirestoreErrorCode.unknown] when a file
/// can't be deleted (like `SQLitePersistence.clearPersistence` on Android).
void deleteSqliteDatabaseFiles(String path) {
  try {
    for (final String suffix in <String>['', ...sqliteSideFileSuffixes]) {
      final File target = File('$path$suffix');
      if (target.existsSync()) {
        target.deleteSync();
      }
    }
  } on FileSystemException catch (e) {
    throw FirestoreError(
      'Failed to clear persistence.$e',
      FirestoreErrorCode.unknown,
      e,
    );
  }
}
