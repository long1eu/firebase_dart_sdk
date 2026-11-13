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
/// The side files go first, and every one of them is attempted. The database
/// file is deleted only when they are all gone: a journal or write-ahead log
/// left next to a new database with the same name would be applied to it (a
/// hot journal is rolled back into whatever file has that name), while one
/// left next to its own database is harmless.
///
/// Throws a [FirestoreError] with [FirestoreErrorCode.unknown] that names every
/// file that couldn't be deleted (like `SQLitePersistence.clearPersistence` on
/// Android).
void deleteSqliteDatabaseFiles(String path) {
  final List<FileSystemException> failures = <FileSystemException>[];
  void delete(String name) {
    if (FileSystemEntity.typeSync(name, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return;
    }
    try {
      File(name).deleteSync();
    } on FileSystemException catch (e) {
      failures.add(e);
    }
  }

  for (final String suffix in sqliteSideFileSuffixes) {
    delete('$path$suffix');
  }
  if (failures.isEmpty) {
    delete(path);
  }
  if (failures.isNotEmpty) {
    throw FirestoreError(
      'Failed to clear persistence: ${failures.join('; ')}',
      FirestoreErrorCode.unknown,
      failures.first,
    );
  }
}
