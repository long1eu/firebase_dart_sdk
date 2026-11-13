import 'dart:ffi';

import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// Opens the system SQLite library on Linux.
///
/// `package:sqlite3` 2.x opens `libsqlite3.so`, the unversioned name that only
/// the development package installs (`libsqlite3-dev` on Debian and Ubuntu).
/// A system with just the runtime package (`libsqlite3-0`) has
/// `libsqlite3.so.0` only, so that name is tried next.
DynamicLibrary openLinuxSqlite() {
  try {
    return DynamicLibrary.open('libsqlite3.so');
  } on ArgumentError {
    return DynamicLibrary.open('libsqlite3.so.0');
  }
}

bool _configured = false;

/// `sqlite3` of `package:sqlite3`, after making it fall back to
/// `libsqlite3.so.0` on Linux. The override is per isolate and must be set
/// before the first use of `sqlite3`, so every test opens SQLite through this
/// getter (also in the isolates it spawns).
sql.Sqlite3 get nativeSqlite3 {
  if (!_configured) {
    _configured = true;
    open.overrideFor(OperatingSystem.linux, openLinuxSqlite);
  }
  return sql.sqlite3;
}
