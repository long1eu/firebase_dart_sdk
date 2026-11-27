# firebase_database_dart_sqlite

The SQLite offline cache of [`firebase_database_dart`](../firebase_database_dart/README.md), the unofficial Dart client
of the Firebase Realtime Database. It is for the Dart VM and Flutter (Android, iOS, macOS, Windows, Linux), on top of
`package:sqlite3`. It keeps your pending writes across a restart and serves listeners and `get()` from disk while the
app is offline. It is not affiliated with or endorsed by Google or Firebase.

> **Status: 0.0.1, work in progress, not published.** What has run (the counts are from the maintainer's runs on the
> merged trunk):
>
> - The package has 249 tests, which pass on Dart 3.12.2 (2026-11-27; 247 passed on Dart 3.11.5 and on Dart 3.8.0 at
>   an earlier commit), including Android's own persistence suites run on the SQLite engine.
> - On Windows 11 x64 the disk cache test of the Windows example app passed with an earlier version of the app.
> - The SQLite engine had an independent review (1 high, 5 medium and 10 low findings), all fixed with a test each.
> - Nothing ran on Android or iOS or in a release build of a desktop app. Against production one check of the
>   client's verification kit used this cache: it closed and reopened a cache file and listened again (one run).
> - Cost of the cache, measured on one Mac mini (macOS, AOT, medians of 5, rows of about 100 bytes; see Limits). Not
>   measured: JSON against a binary codec, `synchronous = FULL` against `NORMAL`, and any write cost on Linux or
>   Windows.
>
> One person maintains it.

## Use it when

- A desktop app or a command line tool must not lose a write made while it was offline, even if it quits.
- Listeners should have data on start-up, before the connection is up.

## Do not use it when

- You build for the web. There is no web persistence.
- Several apps or isolates must share one cache. One owner holds a file; the others run memory-only.
- Cached data must be encrypted by the package. The file is clear text; disk encryption is the operating system's job.
- A user on a shared machine must never see the previous user's cached data, unless you clear the cache at sign-out
  (see [Limits](#limits)).

## Install

```shell
dart pub add firebase_database_dart firebase_database_dart_sqlite
```

Dart 3.8 or later. SQLite is loaded by `package:sqlite3` as in `cloud_firestore_dart_sqlite` (see "Which `sqlite3`" in
its README); this package does not override the lookup. The `pubspec.yaml` of 0.0.1 still says `publish_to: none`:
publishing is the maintainer's step, so until then depend on the packages from the repository.

## Use

```dart
import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:firebase_database_dart_sqlite/firebase_database_dart_sqlite.dart';

final FirebaseDatabase cached = FirebaseDatabase(
  app,
  persistence: sqlitePersistence('/path/to/app/support/firebase_database'),
);
await cached.close();
```

`sqlitePersistence` returns the client's `DatabasePersistence`. `FirebaseDatabase.persistenceEnabled` tells whether the
disk is really in use (false for a second instance on the same file, and after a storage error). Persistence is off
unless you pass it.

- **`cacheSizeBytes`**: the size above which the client prunes cached server data, 1 MiB to 100 MiB, 10 MiB by default;
  anything else throws an `ArgumentError`. The least recently used queries go first, 20 % of the inactive ones at a
  time; queries with a listener and pending writes are never pruned.
- **What is cached.** Only data under a listener or `keepSynced` is written to the cache. An offline `get()` is
  answered from it only when it holds the complete value for that query, with its limit applied.
- **`cacheServerData: false`** (the default is `true`): only the pending writes are stored. They survive a restart and
  are sent again; no server data is kept on disk, so after a restart a listener waits for the server.

```dart
import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:firebase_database_dart_sqlite/firebase_database_dart_sqlite.dart';

await database.close();
await clearSqlitePersistence(
  '/path/to/app/support/firebase_database',
  appName: app.name,
  databaseUrl: database.databaseUrl,
);
```

`clearSqlitePersistence` deletes a cache while no instance holds it: it waits about 7.5 s to see whether an owner is
alive, throws a `StateError` while one is, and throws a `ClearPersistenceException` that lists the files it could not
delete; a retry in the same isolate can start at once. It normalises the URL with `persistenceDatabaseUrl`, which maps a
URL onto the key the client builds: `database.databaseUrl` always works, and so does any spelling of a production URL
that the constructor accepts. On a `*.cloudworkstations.dev` host two things differ: a production database written with
`?ns=` equal to the first label names the emulator's cache (pass `database.databaseUrl` there), and a production
database with any other `?ns=` shares one cache with the emulator on that host at port 443.
`SqlitePersistence.pathOf(key)` gives the path of the file of an app and database URL. There is one SQLite file per app
and normalised database URL in the directory you give (every spelling of one URL shares a file, two `?ns=` values on one
host get two); its name is a hash, never the URL or the user. On macOS and Linux the directory is created with mode 0700
and the file gets mode 0600; elsewhere the platform's default permissions apply. Tokens, the server host and session ids
are never written.

## How it works

Pending writes are stored when you make them and removed in one SQLite transaction when the server acknowledges them,
together with applying the value to the cache. At start-up the client takes ownership of the file, loads the writes
and the tracked queries, restores the writes, and then connects. The layout is Android's: a node larger than about
16 KiB is saved child by child, and the tables are `lease`, `server_cache`, `user_writes`, `tracked_queries` and
`tracked_keys`. The database runs in WAL mode with `synchronous = FULL`.

## Limits

- **One owner per file.** One process or isolate owns a file at a time, by a lease that the owner refreshes every
  5 s. Another one watches the lease for about 7.5 s (one observation period), then keeps its data in memory and logs
  one warning; its writes are not durable. A stalled owner (a paused debugger, an isolate blocked for longer than the
  refresh interval plus the slack) can lose the lease to a new process that then sends the same pending writes.
- **At-least-once writes.** A persisted write is sent again if its removal was lost, so a `ServerValue.increment`
  can apply twice; a transaction is the exact way to count. Transactions and `onDisconnect` registrations are not
  stored.
- **A storage error makes the instance memory-only for the session.** Nothing is deleted: the writes committed before
  the error stay in the file and are sent at the next start. Of those, the writes the server acknowledged or refused
  before the instance closed are removed at close, when no other instance took the file over and no clear deleted it in
  the meantime, and the file can be written then. After a crash, or with the file still failing at close, they are sent
  again at the next start (a `ServerValue.increment` among them is applied twice). When another instance took the file
  over, that instance sends them; when a clear deleted the file, nothing is sent. A write made after the error is not
  durable. The store keeps its lease without refreshing it, so another instance takes the file over after one
  observation period; when the store ran in another process, that takeover first runs `PRAGMA quick_check`, whose time
  grows with the size of the file. The app never receives a `SqliteException`; a row that does not decode is skipped and
  logged once.
- **One moved-aside copy.** A file that cannot be used (damaged, of another program, or written by a newer major
  version of this package) is renamed to `<file>.bad-<time>` and the cache starts empty. Only the newest such copy is
  kept: the next quarantine deletes the previous one, also the file of a newer version after a downgrade and a second
  quarantine.
- **The cache belongs to the app and the database URL, not to a user.** A second user on a shared machine can read the
  first user's cached data until you call `clearSqlitePersistence`; call it at sign-out.
- **SQLite is synchronous and runs on the caller's isolate**, which in Flutter is the UI isolate. A cold read of a
  large subtree or a prune can take long enough to drop a frame. Measured on one Mac mini (macOS, AOT, medians of 5,
  rows of about 100 bytes): a point read takes 0.1 to 0.2 ms and one pending write 0.1 ms, whatever the size of the
  cache. Loading a whole subtree takes 56.2 ms for 1 MB, 615.2 ms for 10 MB and 2,968.3 ms for 50 MB; writing it takes
  51.9, 483.8 and 2,123.7 ms; reopening the file takes 3.4, 12.7 and 55.5 ms. A listener loads the subtree below its
  path, so listen below the root of a large cache.
- **On macOS `fsync` does not flush the drive cache** and `fullfsync` is not set, so those write costs are not the
  cost on Linux or Windows; nothing was measured there.
- **No web persistence.**

## Platforms

| Platform | What ran |
|---|---|
| Dart VM | 249 tests on Dart 3.12.2 (2026-11-27; 247 on Dart 3.11.5 and on Dart 3.8.0 at an earlier commit), including Android's persistence suites on the SQLite engine |
| Windows 11 x64 | the disk cache test of the Windows example app, with an earlier version of the app |
| Linux x64 | no run of this package is recorded; the client's own suites ran there (see its README) |
| Android, iOS | declared in `pubspec.yaml`; no run is recorded |
| Web | not supported |

More: [the client's README](../firebase_database_dart/README.md), which has the sections on the database itself, and
[docs/database_decisions.md](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/database_decisions.md),
sections 15 and 16, for why the cache is built this way.

## License

Apache License 2.0, as the rest of the repository.
