/// Suffixes of the files SQLite keeps next to a database file: the rollback
/// journal, the write-ahead log and its shared memory index.
const List<String> sqliteSideFileSuffixes = <String>[
  '-journal',
  '-wal',
  '-shm',
];

/// There is no file system on the web, so there is nothing to delete here. A
/// database that is stored elsewhere (IndexedDB) deletes its own storage: see
/// `ClearableDatabase`.
void deleteSqliteDatabaseFiles(String path) {}
