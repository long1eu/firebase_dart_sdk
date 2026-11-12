/// Deleting the files of a SQLite database, without importing `dart:io` where
/// it does not exist.
library;

export 'sqlite_database_files_web.dart'
    if (dart.library.io) 'sqlite_database_files_io.dart';
