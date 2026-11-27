/// The SQLite offline cache of `firebase_database_dart` on the Dart VM and in Flutter.
///
/// `supportDirectory` below is a directory of the app; `sqlitePersistence` lists one per platform.
///
/// ```dart
/// final FirebaseDatabase database = FirebaseDatabase(
///   app,
///   persistence: sqlitePersistence('$supportDirectory/firebase_database'),
/// );
/// ```
///
/// The limits are in the README of the package.
library;

export 'package:firebase_database_dart_sqlite/src/sqlite_persistence.dart'
    show
        ClearPersistenceException,
        SqlitePersistence,
        clearSqlitePersistence,
        sqlitePersistence;
