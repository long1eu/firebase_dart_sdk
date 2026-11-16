/// The browser opener and its database classes, for code that only runs in a
/// browser: tests, debugging, `is` checks. Apps use `sqliteOpener` of
/// `package:cloud_firestore_dart_sqlite/cloud_firestore_dart_sqlite.dart`,
/// which compiles on every platform.
library;

export 'src/sqlite_opfs_exception.dart' show SqliteOpfsException;
export 'src/web/sqlite_database_web.dart'
    show
        SqliteOpfsDatabase,
        SqliteWebDatabase,
        inspectOpfsDatabase,
        sqliteWebOpener;
