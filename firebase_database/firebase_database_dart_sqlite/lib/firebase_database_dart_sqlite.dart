/// The SQLite offline cache of `firebase_database_dart` on the Dart VM and in Flutter.
///
/// ```dart
/// final FirebaseDatabase database = FirebaseDatabase(
///   app,
///   persistence: sqlitePersistence('/path/to/app/support/firebase_database'),
/// );
/// ```
///
/// Work in progress: the store opens, owns and quarantines its files; the engine that reads and
/// writes nodes is being written.
library;

export 'package:firebase_database_dart_sqlite/src/sqlite_persistence.dart'
    show
        ClearPersistenceException,
        SqlitePersistence,
        defaultCacheSizeBytes,
        maximumCacheSizeBytes,
        minimumCacheSizeBytes,
        sqlitePersistence;
