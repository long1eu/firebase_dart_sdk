import 'package:sqlite3/sqlite3.dart' as sql;

/// `sqlite3` of `package:sqlite3`, the SQLite of the tests that open a
/// database themselves.
///
/// Which library is loaded is up to `package:sqlite3`, as in
/// `cloud_firestore_dart_sqlite`: with 3.x (Dart 3.10 and later) the one its
/// build hook bundles, with 2.x (the lowest supported SDK) its default lookup,
/// which on Linux needs `libsqlite3.so` (`libsqlite3-dev` on Debian and
/// Ubuntu; the GitHub runner images have it).
sql.Sqlite3 get nativeSqlite3 => sql.sqlite3;
