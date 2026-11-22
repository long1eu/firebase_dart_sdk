# firebase_database_dart_sqlite

**Work in progress, not published.** The SQLite offline cache of `firebase_database_dart` on the
Dart VM and in Flutter (Android, iOS, macOS, Windows, Linux). It is not affiliated with or endorsed
by Google or Firebase.

```dart
final FirebaseDatabase database = FirebaseDatabase(
  app,
  persistence: sqlitePersistence('/path/to/app/support/firebase_database'),
);
```

`sqlitePersistence` returns the client's `DatabasePersistence`. Its `cacheSizeBytes` (1 MiB to
100 MiB, 10 MiB by default) is the size above which the client prunes cached server data; pending
writes are never pruned. `clearSqlitePersistence` deletes a cache while no instance holds it.

One SQLite file per app and database URL in that directory. One process or isolate owns a file at a
time; another one keeps its data in memory. SQLite is loaded by `package:sqlite3` as in
`cloud_firestore_dart_sqlite` (see "Which `sqlite3`" in its README); this package does not override
the lookup.

## Limitations

- **One moved-aside copy.** A file that can not be used (damaged, of another program, or written by
  a newer major version of this package) is renamed to `<file>.bad-<time>` and the cache starts
  empty. Only the newest such copy is kept: the next quarantine deletes the previous one, also the
  file of a newer version after a downgrade and a second quarantine.
- **A storage error makes the instance memory-only for the session.** Nothing is deleted: pending
  writes committed before the error stay in the file and are sent at the next start.
- **A second instance on the same file keeps its data in memory.** It watches the lease for about
  7.5 s first (one observation period).
