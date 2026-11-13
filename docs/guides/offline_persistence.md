# Offline persistence and cache settings

Every `Firestore` instance keeps a local cache. Listeners and reads are answered from it while
the client is offline, writes are applied to it at once and sent when the client is online, and
queries against it use what earlier listens returned. Where the cache lives is up to you:

| You pass | The cache |
|---|---|
| no `openDatabase` | in memory, gone when the instance is terminated |
| an `openDatabase` (SQLite on the VM) | in a SQLite file, kept across restarts |
| the web `openDatabase` (web) | SQLite compiled to WebAssembly, stored in IndexedDB or OPFS |

## Cache settings

`FirestoreSettings.cacheSettings` chooses the kind of cache and its size:

```dart
// Persistent (needs an openDatabase): unused documents are removed once the
// cache grows beyond about 100 MB, the default.
final FirestoreSettings persistent = FirestoreSettings(
  cacheSettings: PersistentCacheSettings(sizeBytes: 100 * 1024 * 1024),
);

// Never removes anything.
final FirestoreSettings unlimited = FirestoreSettings(
  cacheSettings: PersistentCacheSettings(sizeBytes: FirestoreSettings.cacheSizeUnlimited),
);

// In memory, dropping documents as soon as no listener needs them (the default
// for a memory cache)...
final FirestoreSettings eager = FirestoreSettings(cacheSettings: const MemoryCacheSettings());

// ...or keeping them up to a size, so that a query that was listened to before
// can be answered offline.
final FirestoreSettings lru = FirestoreSettings(
  cacheSettings: MemoryCacheSettings(gcSettings: MemoryLruGcSettings(sizeBytes: 40 * 1024 * 1024)),
);
```

- The size is a threshold, not a hard limit: garbage collection runs in the background and
  removes documents that no active listener uses, least recently used first. The minimum is
  1 MB; a smaller value throws an `ArgumentError`.
- Without an `openDatabase` the cache is in memory whatever the settings say.
- Pending writes are never removed by garbage collection.
- Settings only apply to the `instanceFor` call that creates the instance.

## SQLite on the Dart VM

The package does not open SQLite files itself, so that you choose the binding. You pass a
function that opens a database. A complete one for `package:sqlite3` is
[`example/sqlite_database.dart`](../../cloud_firestore/cloud_firestore_dart/example/sqlite_database.dart):
copy it into your app and add `sqlite3` to your dependencies (in a Flutter app also
`sqlite3_flutter_libs`, which bundles the native library).

```dart
import 'dart:io';

import 'sqlite_database.dart'; // copied from the package's example/ folder

final Directory directory = Directory('/home/ada/.local/share/my_app');
final Firestore firestore = Firestore.instanceFor(
  app: app,
  openDatabase: sqliteOpener(directory),
  settings: FirestoreSettings(cacheSettings: PersistentCacheSettings()),
);
```

The opener receives a name that is unique per app name, project and database (for example
`firestore.[DEFAULT].my-project.(default)`) and decides where the file goes. If you write your
own opener over another binding, implement `Database` (`execute`, `query`, `delete`, `close`,
`path`) and call the callbacks in the order the example does: `onConfigure`, then `onCreate` for
a new file or `onUpgrade` / `onDowngrade` when the stored version differs, store the version,
then `onOpen`. The doc comment of `OpenDatabase` has the details.

`example/offline_persistence.dart` is a runnable program: it writes online, restarts on the same
file, reads offline and writes offline.

### Reading and writing offline

```dart
// Only the cache, never the network.
final DocumentSnapshot<Map<String, Object?>> cached =
    await firestore.doc('cities/SF').get(Source.cache);
print(cached.metadata.isFromCache); // true

// A write made offline is in the cache at once; its future completes when the
// backend has accepted it, so do not wait for it before showing the change.
final Future<void> write = firestore.doc('cities/SF').update({'visited': true});

// Listeners say whether a snapshot holds writes the backend has not seen.
firestore.doc('cities/SF').getSnapshots(MetadataChanges.include).listen(
  (DocumentSnapshot<Map<String, Object?>> snapshot) {
    print('pending: ${snapshot.metadata.hasPendingWrites}');
  },
);

// To take the client offline (or online) on purpose:
await firestore.disableNetwork();
await firestore.enableNetwork();
```

### Protect the cache files

The cache holds every document the app has read and its pending writes, in clear text. SQLite
creates the database and its `-wal`, `-shm` and `-journal` files with mode 0644 minus the
process umask, and `Directory.createSync` creates directories with 0777 minus the umask. With
the usual umask 022 every local user can read them. On a desktop or server that other people can
log in to:

- put the database in a per-user application directory (`getApplicationSupportDirectory()` of
  `path_provider` in Flutter, `$XDG_DATA_HOME` or `~/.local/share/<app>` on Linux,
  `~/Library/Application Support/<app>` on macOS, `%LOCALAPPDATA%` on Windows), never in a
  shared location such as `/tmp`;
- make that directory private before the first file is opened (`dart:io` has no chmod), or run
  the process with `umask 077` so that the files come out 0600:

```dart
import 'dart:io';

final Directory directory = Directory('/home/ada/.local/share/my_app')
  ..createSync(recursive: true);
if (!Platform.isWindows) {
  Process.runSync('chmod', <String>['700', directory.path]);
}
```

- signing out does not delete the cache; `clearPersistence()` does (see below). Call it when a
  user signs out of a shared machine.

## On the web

The cache is in memory by default. To keep it across page loads, copy
[`example/sqlite_database_web.dart`](../../cloud_firestore/cloud_firestore_dart/example/sqlite_database_web.dart)
into your app, add `sqlite3` and `web` to your dependencies, and serve the `sqlite3.wasm` file of
the same `sqlite3` version next to your page (from the
[sqlite3.dart releases](https://github.com/simolus3/sqlite3.dart/releases)):

```dart
import 'sqlite_database_web.dart'; // copied from the package's example/ folder

// IndexedDB: SQLite runs in the page on a copy of the whole database in memory.
final Firestore firestore = Firestore.instanceFor(
  app: app,
  openDatabase: sqliteWebOpener(sqlite3Wasm: Uri.parse('sqlite3.wasm')),
);
```

To keep the database out of memory, also copy
[`example/sqlite_opfs_worker.dart`](../../cloud_firestore/cloud_firestore_dart/example/sqlite_opfs_worker.dart),
compile it with `dart compile js` and pass its URL. SQLite then runs in that dedicated worker on a
file in the origin private file system (OPFS) and reads what it needs. No cross-origin isolation
headers are needed; a browser without synchronous OPFS access in workers falls back to
IndexedDB, and the first OPFS open of a cache that is in IndexedDB moves it, pending writes
included.

```dart
import 'sqlite_database_web.dart'; // copied from the package's example/ folder

final Firestore firestore = Firestore.instanceFor(
  app: app,
  openDatabase: sqliteWebOpener(
    sqlite3Wasm: Uri.parse('sqlite3.wasm'),
    opfsWorker: Uri.parse('sqlite_opfs_worker.js'),
  ),
);
```

What to know (all measured in Chrome against the emulator; other browsers are untested):

- **One tab at a time.** The database is guarded by a Web Lock. A second tab (or a second
  instance in the same page) that opens the same cache waits two seconds for the lock and then
  fails: the operations of that instance fail with a `FirestoreError` whose code is
  `failedPrecondition`. Such a tab should use a memory cache. `Firestore.instanceFor` returns
  at once and opens the cache in the background, so the error comes from the first operation:
  the `openWithMemoryFallback` helper of the example waits for a first operation that only
  reads the cache, and on `failedPrecondition` terminates that instance and creates one with a
  memory cache.
- **Crash safety.** What a write future acknowledged is stored. A tab that dies in the middle
  of a transaction loses only that transaction. A crash of the browser itself or a power cut is
  not covered.
- **Memory.** With IndexedDB the whole database is read into memory when it is opened (about
  1.4 KB per document of 1 KB; 100,000 documents take about 1 s to open and 130 MB). With OPFS
  memory stays at a few MB and the cache opens in well under 0.2 s at any size. The default
  size limit of 100 MB starts removing unused documents before 100,000 documents.
  [Platforms](platforms.md#the-web-experimental) has the measurements.
- **Size.** The persistent cache adds about 220 KB of JavaScript (60 KB gzipped) to a small
  app, plus the `sqlite3.wasm` file (731 KB, 349 KB gzipped); the OPFS worker is 183 KB more.
- `clearPersistence()` deletes the IndexedDB database or the OPFS directory.

## Deleting the cache

```dart
await firestore.terminate();        // the cache must not be in use by this instance
await firestore.clearPersistence(); // deletes the files (or the browser storage)
final Firestore fresh = Firestore.instanceFor(app: app);
```

`clearPersistence()` on an instance that is still running fails with `failedPrecondition`.
Pending writes that were not sent are lost. When another client still has the same SQLite file
open, the cache is emptied in place instead of deleted; see
[Several clients on one cache](multiple_clients.md#clearpersistence).

## Persistent cache indexes

Queries against the SQLite cache (offline, `Source.cache`, and the first results of a
listener) normally scan the cached documents of the collection, or start from the result of an
earlier listen. A persistent cache index lets them read only the matching documents. The index
only exists inside the SDK, on the device; it is not a Cloud Firestore index and it never
changes what a query returns.

```dart
final indexes = firestore.persistentCacheIndexManager; // null with a memory cache
await indexes?.enableIndexAutoCreation();
```

- **Automatic creation** (off by default, not stored: turn it on after creating the instance).
  When a cache query was run as a collection scan that read at least 100 cached documents and
  more than twice as many as it returned, the SDK creates an index for that query. Only
  documents that came from the backend are counted, not pending writes.
- **Filling.** An index is filled in the background while the app runs: 50 documents per run,
  the first run 15 seconds after the instance was created and then one per minute. A query uses
  an index as far as it is filled and reads the rest, so results are complete at every moment.
- `disableIndexAutoCreation()` stops creating indexes (existing ones stay in use);
  `deleteAllIndexes()` removes them all.
- `Firestore.setIndexConfiguration(json)` (deprecated, as in the other SDKs) configures the
  indexes from a definition in the format of `firestore.indexes.json`; `queryScope` and
  `fieldOverrides` are ignored. It replaces the previous configuration.
- All query forms can be served: comparison operators, `in` / `not-in`, `array-contains(-any)`,
  `Filter.or` / `Filter.and`, `orderBy`, cursors, `limit` and `limitToLast`, also with BSON
  values. Queries with inequalities on several fields are scanned, as upstream.
- The index state is kept per signed-in user; the list of indexes is shared.

`example/cache_indexes.dart` is a runnable example. The stored index entries are not
byte-compatible with the ones of the Android SDK (they are never exchanged); the differences
are listed in `docs/ARCHITECTURE.md` in the repository.

## Connectivity

A failed stream is the only thing that makes the client consider itself offline, and it retries with an exponential backoff (up to one minute). Two things can make
it retry at once instead of waiting for the backoff:

- **Built in, on the VM** (not on the web, which uses the `online` / `offline` events of the
  browser): while a stream is failing, and only then, the client reads the addresses of the
  network interfaces every 2 seconds (`NetworkInterface.list`). When an address appears (Wi-Fi
  joined again, a cable, a VPN, a new DHCP lease), or when the clock shows that the machine
  was asleep, it restarts its streams right away. This is a hint only: it never declares the
  client offline, a wrong hint costs one connection attempt, and a client whose streams work
  has no timer. In a test, after a 16 second outage a listener received a change 40 to 140 ms
  after such a hint, and 2 to 8 seconds after the network was back without one (the rest of
  the backoff, which is random). Only tested on macOS; the hint itself was simulated.
- **From your app**: subclass `PlatformDependencies`, override `onNetworkConnected` and feed
  it from your own source (for example the `connectivity_plus` plugin in a Flutter app).
  Firestore restarts its streams, resetting the backoff, on every `true` event (after a 5
  second debounce); `false` is ignored. The first event from the app switches the built-in
  detector off for that instance, so there is nothing to configure to replace it.

Instances are independent: each `Firestore` has its own scheduler and work queue, and the
persistence lock is per database, so an instance never waits for another one.

## A cache that is busy for a moment

A `Database` reports an error that may go away on its own (SQLite busy or locked, an I/O error,
a full disk) as a `TransientDatabaseException`; the example openers do. A write or a listen that
could not be stored then fails with `unavailable` and can be tried again; a change from the
backend that could not be stored takes the client offline until the cache works again, with a
backoff. `example/database_recovery.dart` shows both with a `Database` wrapper that fails a few
times.
