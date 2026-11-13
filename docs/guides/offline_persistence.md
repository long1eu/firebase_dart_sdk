# Offline persistence and cache settings

Every `Firestore` instance keeps a local cache. Listeners and reads are answered from it while
the client is offline, writes are applied to it at once and sent when the client is online, and
queries against it use what earlier listens returned. Where the cache lives is up to you:

| You pass | The cache |
|---|---|
| no `openDatabase` | in memory, gone when the instance is terminated |
| an `openDatabase` (SQLite on the VM) | in a SQLite file, kept across restarts |
| the IndexedDB `openDatabase` (web) | SQLite compiled to WebAssembly, stored in IndexedDB |

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

final Firestore firestore = Firestore.instanceFor(
  app: app,
  openDatabase: sqliteWebOpener(sqlite3Wasm: Uri.parse('sqlite3.wasm')),
);
```

What to know (all measured in Chrome against the emulator; other browsers are untested):

- **One tab at a time.** The database is guarded by a Web Lock. A second tab (or a second
  instance in the same page) that opens the same cache waits two seconds for the lock and then
  fails: the operations of that instance fail with a `FirestoreError` whose code is
  `failedPrecondition`. Such a tab should use a memory cache.
  *Known issue*: `Firestore.instanceFor` now returns at once and opens the cache in the
  background, so the `openWithMemoryFallback` helper of the example, which catches the error
  around `instanceFor`, no longer sees it; and the first operation queued on the instance can
  fail with an internal error instead of the `FirestoreError`. Until this is fixed, open the
  persistent cache in one tab only, for example the tab that holds a lock of your own.
- **Crash safety.** What a write future acknowledged is stored. A tab that dies in the middle
  of a transaction loses only that transaction. A crash of the browser itself or a power cut is
  not covered.
- **Memory.** The whole database is read into memory when it is opened. Some tens of thousands
  of cached documents is the practical limit (100,000 documents of 1 KB are a 160 MB database
  that takes about 1 s to open and 0.5 GB of memory); the default size limit of 100 MB starts
  removing unused documents before that.
- **Size.** The persistent cache adds about 220 KB of JavaScript (60 KB gzipped) to a small
  app, plus the `sqlite3.wasm` file (731 KB, 349 KB gzipped).
- `clearPersistence()` deletes the IndexedDB database.

## Deleting the cache

```dart
await firestore.terminate();        // the cache must not be in use by this instance
await firestore.clearPersistence(); // deletes the files (or the IndexedDB database)
final Firestore fresh = Firestore.instanceFor(app: app);
```

`clearPersistence()` on an instance that is still running fails with `failedPrecondition`.
Pending writes that were not sent are lost. When another client still has the same SQLite file
open, the cache is emptied in place instead of deleted; see
[Several clients on one cache](multiple_clients.md#clearpersistence).

## Faster cache queries

A query against the cache scans the cached documents of its collection, or starts from the
result of an earlier listen. For large caches the SDK can create its own indexes on the device:

```dart
final PersistentCacheIndexManager? indexes = firestore.persistentCacheIndexManager;
await indexes?.enableIndexAutoCreation(); // null with a memory cache
```

See [Persistent cache indexes](../../cloud_firestore/cloud_firestore_dart/README.md#persistent-cache-indexes)
for when an index is created and how it is filled.
