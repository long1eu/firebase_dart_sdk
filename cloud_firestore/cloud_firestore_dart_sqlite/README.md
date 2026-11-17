# cloud_firestore_dart_sqlite

The SQLite offline cache of [`cloud_firestore_dart`](https://pub.dev/packages/cloud_firestore_dart) on the
Dart VM, in Flutter and in the browser, as one dependency. You need it when the cache must survive a restart:
pending writes kept while offline, data read without a network after the app starts again. Without it
`cloud_firestore_dart` keeps its cache in memory. This package is the function that opens the SQLite database,
on top of [`sqlite3`](https://pub.dev/packages/sqlite3). It is not affiliated with or endorsed by Google or
Firebase.

> **Status: 0.1.1.** The openers were the `example/` files of `cloud_firestore_dart` 0.1.1 that
> apps had to copy. The browser storage is **experimental**. Run on macOS (Dart VM, `sqlite3`
> 2.9.4 and 3.9.1) and in headless Chrome (dart2js and dart2wasm, `sqlite3` 2.9.4 and 3.9.1),
> against the Firestore emulator, and in one Flutter Linux desktop app (Debian 13 x86_64,
> `sqlite3` 3.5.2, a cache read back after a restart, 2026-11-16). On Windows 11 x64
> (2026-11-17): the Dart VM with `sqlite3` 3.9.1 (the build hook's `sqlite3.dll`) and 2.9.4 (the
> `winsqlite3.dll` of Windows), and two Flutter Windows apps with 3.5.2. Not run on Android or
> iOS, or in Safari or Firefox.
>
> **Upgrade from 0.1.0 if your app runs in a browser.** With `sqlite3` 3.x, 0.1.0's IndexedDB
> storage could lose writes acknowledged shortly before the tab was killed or crashed (see the
> CHANGELOG). OPFS, the Dart VM and Flutter were not affected.

## Install

```shell
dart pub add cloud_firestore_dart_sqlite
```

Dart 3.8 or later, with `cloud_firestore_dart` 0.2. It brings `sqlite3` with it; see [Which `sqlite3`](#which-sqlite3) for what
else each platform needs.

## Use

One import and one call, the same on every platform:

```dart
import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart_sqlite/cloud_firestore_dart_sqlite.dart';
```

**Dart VM** (a server, a command line tool): pass the directory of the SQLite files.

```dart
final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
  app: app,
  openDatabase: sqliteOpener(directory: '/var/lib/my_app/firestore'),
);
```

**Flutter** (Android, iOS, macOS, Windows, Linux): a directory from `path_provider`.

```dart
final Directory support = await getApplicationSupportDirectory();
final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
  app: app,
  openDatabase: sqliteOpener(directory: '${support.path}/firestore'),
);
```

**Browser**: no directory. The cache is in IndexedDB; `sqlite3.wasm` must be next to the page.

```dart
final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
  app: app,
  openDatabase: sqliteOpener(),
);
```

A Flutter app that also builds for the web uses one call: `sqliteOpener(directory: kIsWeb ? null
: '${support.path}/firestore')`.

## Options

`sqliteOpener` takes named arguments. Each platform reads its own and ignores the others.

| Argument | Platform | What it does |
| --- | --- | --- |
| `directory` | VM, Flutter | Where the files go: `<directory>/<name>.db`, one per app and database. Required there (an `ArgumentError` otherwise); created when missing. |
| `pageCacheMb` | VM, Flutter | SQLite's page cache of the connection (`PRAGMA cache_size`). SQLite's default is 2 MB. |
| `sqlite3Wasm` | browser | The URL of `sqlite3.wasm`. Default `sqlite3.wasm`, resolved against the page. |
| `opfsWorker` | browser | The URL of the compiled OPFS worker. With it the database is a file in the origin private file system, read as needed by SQLite in a worker. Without it, or in a browser without synchronous OPFS access in workers, the database is in IndexedDB. |
| `storagePrefix` | browser | Names the IndexedDB databases, OPFS directories and Web Locks (`<prefix>/<name>`). Default `cloud_firestore_dart`, the name the copied opener used, so an existing cache is found again. |
| `lockTimeout` | browser | How long an open waits for a cache that is open elsewhere. Default 2 seconds. |

Also exported: `openWithMemoryFallback`, which creates the instance with the persistent cache, or
with a memory cache when another client (in a browser: another tab) has that cache:

```dart
final FirebaseFirestore firestore = await openWithMemoryFallback(
  app: app,
  openDatabase: sqliteOpener(opfsWorker: Uri.parse('sqlite_opfs_worker.js')),
);
```

and `SqliteOpfsException`, the cause of a failed statement in the OPFS worker.
`package:cloud_firestore_dart_sqlite/web.dart` (browser only) has the database classes and
`inspectOpfsDatabase`, for tests and debugging; `package:cloud_firestore_dart_sqlite/opfs_worker.dart`
has `runOpfsWorker`, to build the worker yourself.

## The browser

The page needs one or two files next to it:

| File | When | Where it comes from |
| --- | --- | --- |
| `sqlite3.wasm` | always | SQLite compiled to WebAssembly, an asset of the release `sqlite3-<version>` of [simolus3/sqlite3.dart](https://github.com/simolus3/sqlite3.dart/releases). It must be the build of the exact `sqlite3` version your app resolves (`pubspec.lock`). |
| `sqlite_opfs_worker.js` | with `opfsWorker` | The worker of this package compiled to JavaScript, with your app's dependencies. |

One command does the second and tells you the URL of the first. From your app's directory, after
`dart pub get` or `flutter pub get`:

```shell
dart run cloud_firestore_dart_sqlite:setup_web web
```

It writes `web/sqlite_opfs_worker.js` (`dart compile js -O2`; the worker stays JavaScript also for
a dart2wasm page) and prints a `curl` command for the matching `sqlite3.wasm`. It downloads
nothing. Run it again when this package or `sqlite3` changes version. `--no-worker` skips the
worker for an app that only uses IndexedDB. `flutter build web` copies `web/` into the build.

Which storage:

- **IndexedDB** (the default). SQLite runs in the page on a copy of the whole database in memory,
  which `sqlite3` copies back to IndexedDB. Measured in Chrome: 133 to 138 MB for 100,000
  documents of about 1 KB, and 0.5 to 1.2 s to open.
- **OPFS** (`opfsWorker`). SQLite runs in a dedicated worker and reads the file as it needs:
  3 to 8 MB once open whatever the size, 45 to 170 ms to open. No cross-origin isolation is
  needed. The first OPFS open of a cache that is in IndexedDB moves it, pending writes included.

Limits:

- **One tab at a time.** A Web Lock guards each cache. A second tab (or a second instance in one
  page) fails after `lockTimeout` with a `FirestoreException` with the code
  `failed-precondition`; use `openWithMemoryFallback` to get a memory cache there instead. The Web Locks API needs a secure
  context (HTTPS or `localhost`).
- **Crash safety** was tested by killing a worker at random moments (in the repository of
  `cloud_firestore_dart`): with `sqlite3` 2.9.4 (2,700 kills on IndexedDB, 1,500 on OPFS) and,
  from 0.1.1, with 3.9.1 (900 kills on IndexedDB, 900 on OPFS): the database stayed intact and kept every acknowledged
  transaction. A crash of the browser itself or a power cut is not covered.
- Only Chrome was tried.

## Which `sqlite3`

The package allows `sqlite3` `>=2.7.3 <4.0.0`. Pub picks 3.x on Dart 3.10 or later (Flutter 3.38
or later) and 2.x on older SDKs. Pin one with your own `sqlite3` dependency if you need to.

**`sqlite3` 3.x** loads SQLite through a [build hook](https://dart.dev/tools/hooks): by default it
downloads a SQLite build for the target from the GitHub releases of `sqlite3` (checked against
hashes in the package) and bundles it with the program or app. Nothing else is needed:

- Flutter, every platform: no other package. Remove `sqlite3_flutter_libs` if you had it (its 0.6
  release is an empty end-of-life package).
- Dart VM: no system SQLite needed. `dart run`, `dart test` and `dart build cli` use the bundled
  one (`dart build cli` puts it in `bundle/lib/` next to the program). A program compiled with
  plain `dart compile exe` does not get it and falls back to the system SQLite where there is one
  (it did on macOS); use `dart build cli`.
- To use the operating system's SQLite, a build of your own, or an internal download mirror, set
  the `hooks: user_defines: sqlite3:` options in your app's `pubspec.yaml`, see the
  [`sqlite3` hook documentation](https://github.com/simolus3/sqlite3.dart/blob/main/sqlite3/doc/hook.md).

**`sqlite3` 2.x** (2.7.3 or later) loads a native library at run time:

| Platform | What it loads | What you add |
| --- | --- | --- |
| Flutter Android | `libsqlite3.so` from the app | `sqlite3_flutter_libs: ^0.5.0` (required) |
| Flutter iOS, macOS | the framework of `sqlite3_flutter_libs`, else the system SQLite | `sqlite3_flutter_libs` (recommended) |
| Flutter Windows | `sqlite3.dll` from `sqlite3_flutter_libs`, else `winsqlite3.dll` of Windows (2.7.5 and later; not tried in Flutter) | `sqlite3_flutter_libs` (recommended) |
| Flutter Linux | the library bundled by `sqlite3_flutter_libs`, else the system `libsqlite3.so` | `sqlite3_flutter_libs` (recommended) |
| Dart VM, macOS | the system SQLite | nothing |
| Dart VM, Linux | `libsqlite3.so` | `libsqlite3-dev` (Debian, Ubuntu), or the override below |
| Dart VM, Windows | `sqlite3.dll` next to the program or on the `PATH`, else `winsqlite3.dll` (2.7.5 and later; seen with 2.9.4 on Windows 11: `System32\winsqlite3.dll`, SQLite 3.51.1) | nothing |

This package does not override the 2.x lookup (the copied opener did, see the CHANGELOG). On a
Linux machine with only the runtime package (`libsqlite3-0`, which has `libsqlite3.so.0`), run
this once at the start of the program, before the first FirebaseFirestore instance:

```dart
import 'dart:ffi';

import 'package:sqlite3/open.dart'; // sqlite3 2.x only

void useLibsqlite3So0() {
  open.overrideFor(OperatingSystem.linux, () {
    try {
      return DynamicLibrary.open('libsqlite3.so');
    } on ArgumentError {
      return DynamicLibrary.open('libsqlite3.so.0');
    }
  });
}
```

Not in a Flutter app: there the override would hide the library of `sqlite3_flutter_libs`.

In a browser both majors work the same way; only the `sqlite3.wasm` file differs per version. The
IndexedDB storage reports a transaction as stored once the IndexedDB file system of `sqlite3` has
written it, and what `flush()` waits for differs per version:

| `sqlite3` | `flush()` waits for | IndexedDB storage |
| --- | --- | --- |
| 2.7.3 to 3.3.4 | every write made before it | safe |
| 3.4.0 to 3.5.2 | nothing while a batch of writes is in progress | **unsafe**: do not use |
| 3.6.0 to 3.9.1 | the batch in progress, not the writes queued behind it | safe from 0.1.1, which waits for those too; lost writes with 0.1.0 |

Recommended: `cloud_firestore_dart_sqlite` 0.1.1 or later, with any `sqlite3` but 3.4.0 to 3.5.2
(pub picks the newest one your SDK allows; check `pubspec.lock` if you pinned `sqlite3`). The
browser tests run with 2.9.4 and 3.9.1. The OPFS storage does not use this file system.

## Recovery and errors

The VM opener reports SQLite's `BUSY`, `LOCKED`, `IOERR` and `FULL` as a
`TransientDatabaseException`, after which FirebaseFirestore goes offline and retries; every other error
fails the operation. The OPFS worker does the same where nothing of the failed statement can have
been stored, and the IndexedDB storage reports a copy to IndexedDB that failed the same way. To
inject errors in tests, wrap the `Database` that the opener returns (the `database_recovery.dart`
example of `cloud_firestore_dart` shows how). `FirebaseFirestore.clearPersistence()` deletes the SQLite
file (and its journal), the IndexedDB database or the OPFS directory.

## Licence

Apache-2.0, see `LICENSE` and `NOTICE`. `sqlite3` is under the MIT licence (Copyright (c) 2020
Simon Binder); SQLite is in the public domain. A browser app ships `sqlite3.wasm`, which contains
code of the `sqlite3` package: ship its MIT notice with your app.
