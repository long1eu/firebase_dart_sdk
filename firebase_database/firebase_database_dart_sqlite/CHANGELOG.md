## 0.1.0

- First version. The SQLite offline cache of `firebase_database_dart`, for the Dart VM and Flutter, on top of
  `package:sqlite3`. `sqlitePersistence(directory, {cacheSizeBytes, cacheServerData})` returns the client's
  `DatabasePersistence`. Pending writes survive a restart and are sent again; cached server data answers listeners
  and `get()` while the app is offline. `clearSqlitePersistence` deletes a cache that no instance holds.
- Where it ran. Dart VM: 287 tests of the package on Dart 3.12.2 (247 on Dart 3.11.5 and on Dart 3.8.0 at an earlier
  commit), including Android's own persistence suites run on the SQLite engine. Windows 11 x64: the disk cache test
  of the Windows example app, with an earlier version of the app. Not run: Android, iOS, a release build of a desktop
  app. No run of this package is recorded on Linux x64 (the client's own suites ran there).
- Verified against production. One check of the client's verification kit (checks 1 to 39 ran as one run on
  2026-11-25 and 26, against a dedicated database instance of one Firebase project) used this cache: it closed and
  reopened a cache file and listened again. All 39 of that run passed. Checks 40 and 41 of the kit, which ran alone
  later, do not use this package. Nothing else of this package ran against production.
- Known limits:
  - One owner per cache file, by a lease. A second process or isolate runs memory-only after about 7.5 s with one
    logged warning, and its writes are not durable.
  - After a storage error the instance is memory-only for the rest of the session. Nothing is deleted: the writes
    committed before the error stay in the file. Those the server acknowledged or refused before the instance closed
    are removed at close, when no other instance took the file over and no clear deleted it, and the file can still be
    written; otherwise they are sent again at the next start, and a `ServerValue.increment` among them applies twice.
    A write made after the error is not durable. (README, "Limits".)
  - A file that cannot be used (damaged, of another program, or of a newer major version) is renamed to
    `<file>.bad-<time>` with its pending writes and the cache starts empty; only the newest such copy is kept.
    (README, "Limits", "One moved-aside copy".)
  - The cache belongs to the app and the database URL, not to a user. Call `clearSqlitePersistence` at sign-out.
  - The cache file is clear text.
  - SQLite runs on the caller's isolate, which in Flutter is the UI isolate. A cold read of a large subtree can drop
    a frame.
  - Writes are delivered at least once; transactions and `onDisconnect` registrations are not stored.
  - No web persistence and no write-behind journal.
- Differences from the JS SDK, which has no disk cache here, are in section 25 of `docs/database_decisions.md`
  (row 18 for this package) and in the README of `firebase_database_dart`, "How it differs from the JS SDK".
- `sqlitePersistence(directory, {cacheSizeBytes, cacheServerData})` returns the client's `DatabasePersistence`.
  `cacheSizeBytes` is 1 MiB to 100 MiB, 10 MiB by default; `cacheServerData: false` stores the pending writes only.
- Pending writes survive a restart and are sent again; cached server data answers listeners and `get()` offline.
  Least recently used queries are pruned above the size limit; pending writes never are.
- One owner per cache file, by a lease; a second instance runs memory-only after about 7.5 s and logs a warning.
- A storage error makes the instance memory-only for the session and deletes nothing; a file that cannot be used is
  moved aside once and the cache starts empty.
- `clearSqlitePersistence(directory, appName:, databaseUrl:)` deletes a cache that no instance holds.
- The file is named by a hash of the app name and the normalised database URL (two `?ns=` values on one host are two
  caches); on POSIX the directory is 0700 and the file 0600.
- Only data under a listener or `keepSynced` is written to the cache, and an offline `get()` is answered from it only
  when it holds the complete value for the query.
