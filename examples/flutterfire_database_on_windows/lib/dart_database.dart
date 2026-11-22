import 'dart:io';

import 'package:firebase_database_dart_platform/firebase_database_dart_platform.dart';
import 'package:firebase_database_dart_sqlite/firebase_database_dart_sqlite.dart';
import 'package:path_provider/path_provider.dart';

/// Keeps the cache and the pending writes of every Realtime Database instance
/// in SQLite files under [directory] (or the application support directory
/// when it is empty).
///
/// The only place where the app names `firebase_database_dart_platform`.
/// Without it nothing is needed: as a direct dependency the package registers
/// itself before `main()` and keeps everything in memory. `use` replaces that
/// configuration, and must run before the first Realtime Database operation.
Future<void> useDiskCache(String directory) async {
  final String path = directory.isNotEmpty
      ? directory
      : '${(await getApplicationSupportDirectory()).path}'
            '${Platform.pathSeparator}firebase_database';
  await Directory(path).create(recursive: true);
  FirebaseDatabaseDart.use(
    persistenceFor: (int cacheSizeBytes) =>
        sqlitePersistence(path, cacheSizeBytes: cacheSizeBytes),
  );
}
