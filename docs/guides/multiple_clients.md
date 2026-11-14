# Several clients on one cache

A persistent cache is one SQLite file per app name, project and database. Sometimes two live
clients open the same file:

- a Flutter **hot restart**, where the new isolate opens the cache while the old one has not let
  go of it yet;
- a **background isolate** that creates its own instance for the same app name;
- a **second process** of the same program.

This page describes what the client does then. In short: the file stays consistent, one client
at a time (the *primary*) talks to the backend, and the others work from the cache. The clients
do not share listeners or writes. That is the first part of the multi-tab support of the JS
SDK; sharing listeners and writes between clients is deferred until after 0.1.0. In a browser a cache can only be open in one tab (see
[Offline persistence on the web](offline_persistence.md#on-the-web)).

## The file stays consistent

Every transaction on the cache takes SQLite's write lock at its start (`BEGIN IMMEDIATE`,
waiting up to 10 seconds for the other connection). A client reads the state it keeps in memory
again when another connection has committed, so target ids and write batch ids stay unique, and
a schema migration runs once. A client fails with `failedPrecondition` when a different version
of the SDK moves the cache to another schema version under it.

On the VM the client switches a cache that is in SQLite's default rollback-journal mode to
write-ahead logging (`PRAGMA journal_mode = WAL`, stored in the file), as SQLite recommends for
concurrent access: readers and the writer then do not block each other. With a rollback journal,
many clients that keep writing could keep another one out for the whole 10 seconds (measured: 32
isolates opening a new cache at once next to a coverage run failed with `database is locked`
after 10 to 12 seconds in 4 of 40 rounds; none in 160 rounds with WAL). A journal mode that your opener sets is kept. The cache then has `-wal`
and `-shm` files next to it, and needs a file system with shared memory (not a network share).

The connection never switches to `PRAGMA locking_mode = EXCLUSIVE`, which the Android SDK uses
(it fails with "Failed to gain exclusive lock" when a second process opens the file): after a
Flutter hot restart the new isolate must be able to open the file that the old isolate still
holds. SQLite's normal file locking keeps the file consistent. The repository tests this with two
clients in one process (`sqlite_shared_clients_test.dart`) and with two processes
(`sqlite_shared_processes_test.dart`, both in `test/unit/firebase/firestore/local/`). Inside one
process the clients of a file also wait for each other's transactions without blocking the
isolate, including two app names that an `OpenDatabase` maps to the same file
(`sqlite_persistence_file_test.dart`).

## One primary client

The clients of one cache elect a primary client with the lease of the JS SDK:

- the lease is valid for 5 seconds and the primary refreshes it every 4 seconds;
- a client that is terminated gives it up at once; a client that dies loses it when it expires,
  and another live client takes it over;
- a client that opens a cache whose lease another live client holds **takes the lease** and logs
  a warning. This is what makes a hot restart work: the new isolate becomes primary even though
  the old one has not stopped yet;
- a client whose network is disabled (`disableNetwork()`) hands the lease to a client with
  network;
- a lone client is always primary, so a program with one client behaves as before.

Only the primary client uses the network, applies what the backend sends and acknowledges, and
runs garbage collection and the index backfill. A client that is not primary (a *secondary*):

- reports itself offline: snapshots have `metadata.isFromCache == true`;
- answers its listeners and its `get()` calls from the cache, as it does while offline;
- keeps its own writes pending: they are in the cache, the primary does not send them (it could
  not tell the secondary their result), and their futures do not complete while it is secondary;
- becomes primary again, and goes online, when the client that took the lease terminates or
  disables its network; it then sends its pending writes, and their futures complete.

The primary does send the writes of a client that is gone: one that terminated, or that has not
refreshed its metadata (a live client does so every 4 seconds) for 60 seconds because it crashed,
its app was killed or it was hot restarted, and writes stored by a version before this one. So a
write is never stranded for long: after a crash, the relaunched app sends it within about a
minute. The other side of this: a client that stalls for more than 60 seconds (a paused isolate,
an app in the background) can have a write sent by the primary, and that client is then not
told the result, so its future for that write does not complete.

A write can reach the backend twice when the lease moves while it is in flight: the client that
sent it can only store the acknowledgement while it holds the lease, so a client that lost the
lease in the meantime keeps the write and sends it again once it is primary. The JS SDK does
the same. A `set()` gives the same result twice, but an `increment` or an `arrayUnion` of a
value that another write removed in between can be applied twice.

Clients do not see each other's listeners. The listeners of a secondary are not updated with the
changes the primary receives from the backend; a later read of the secondary sees what the
primary has stored in the cache by then.

## In practice

- **Hot restart** needs nothing from you: the new isolate takes over, and the old one is gone
  shortly after.
- **A background isolate or a second process that must be online at the same time** as the main
  one should not share its cache: give it its own app name (or database), and so its own file.

```dart
import 'dart:io';

import 'sqlite_database.dart'; // copied from the package's example/ folder

final Directory directory = Directory('/home/ada/.local/share/my_app');

// In the background isolate: the same project, another app name, another cache file.
final FirebaseApp worker = FirebaseApp.withOptions(app.options, name: 'background-sync');
final Firestore workerFirestore = Firestore.instanceFor(
  app: worker,
  openDatabase: sqliteOpener(directory),
);
```

## clearPersistence

`clearPersistence()` needs a terminated instance. When no other client has the file open it
deletes the files. When another live client still uses the cache, it empties the cache in place
instead of deleting the file under that client; the other client then fails with
`failedPrecondition` at its next operation and terminates itself, as in the JS SDK.

On Windows, deleting a file that another handle has open is not possible: `clearPersistence()`
fails with `unknown` while another isolate or process still has the file open, where Linux and
macOS delete it anyway.

```dart
await firestore.terminate();
await firestore.clearPersistence();
```

## Not done

The JS SDK goes further: secondary tabs share the listeners and the writes of the primary
through the cache, so every tab is online through one connection. Here the clients share only
the file and the lease. Until that exists, do not run two active clients on one cache on
purpose.

## Example

`example/two_clients_one_cache.dart` in the package runs the takeover above: a background
isolate opens the cache of the main isolate and takes the lease, the main isolate answers from
the cache and keeps its write pending, and it sends the write once the background isolate
terminates.
