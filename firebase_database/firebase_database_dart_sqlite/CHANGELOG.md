## 0.0.1

Work in progress, not published. The SQLite offline cache of `firebase_database_dart` for the Dart VM and Flutter.

- `sqlitePersistence(directory, {cacheSizeBytes, cacheServerData})` returns the client's `DatabasePersistence`.
  `cacheSizeBytes` is 1 MiB to 100 MiB, 10 MiB by default; `cacheServerData: false` stores the pending writes only.
- Pending writes survive a restart and are sent again; cached server data answers listeners and `get()` offline.
  Least recently used queries are pruned above the size limit; pending writes never are.
- One owner per cache file, by a lease; a second instance runs memory-only after about 7.5 s and logs a warning.
- A storage error makes the instance memory-only for the session and deletes nothing; a file that cannot be used is
  moved aside once and the cache starts empty.
- `clearSqlitePersistence(directory, appName:, databaseUrl:)` deletes a cache that no instance holds.
- The file is named by a hash of the app name and the database URL; on POSIX the directory is 0700 and the file 0600.
- Not included: web persistence, a write-behind journal.
