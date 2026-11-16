import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

import 'web/sqlite_database_web.dart';

/// A browser: SQLite as WebAssembly, in IndexedDB or OPFS.
OpenDatabase platformSqliteOpener({
  required String? directory,
  required int? pageCacheMb,
  required Uri sqlite3Wasm,
  required Uri? opfsWorker,
  required String storagePrefix,
  required Duration lockTimeout,
}) {
  return sqliteWebOpener(
    sqlite3Wasm: sqlite3Wasm,
    opfsWorker: opfsWorker,
    storagePrefix: storagePrefix,
    lockTimeout: lockTimeout,
  );
}
