/// Suffixes of the files SQLite keeps next to a database file: the rollback
/// journal, the write-ahead log and its shared memory index.
const List<String> sqliteSideFileSuffixes = <String>[
  '-journal',
  '-wal',
  '-shm'
];

/// There is no file system on the web, so there is nothing to delete: a
/// database opened there is not a file this library can reach.
void deleteSqliteDatabaseFiles(String path) {}
