import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

import 'native/sqlite_database.dart';

/// The Dart VM and Flutter: SQLite files in [directory].
OpenDatabase platformSqliteOpener({
  required String? directory,
  required int? pageCacheMb,
  required Uri sqlite3Wasm,
  required Uri? opfsWorker,
  required String storagePrefix,
  required Duration lockTimeout,
  required bool acceptIndexedDbWriteLoss,
}) {
  if (directory == null) {
    throw ArgumentError.notNull('directory');
  }
  return nativeSqliteOpener(directory, pageCacheMb: pageCacheMb);
}
