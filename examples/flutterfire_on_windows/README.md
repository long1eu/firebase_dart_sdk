# flutterfire_on_windows

A Flutter Windows desktop app written against the **official FlutterFire API** (`firebase_core` and
`cloud_firestore`), with Firestore run by [`cloud_firestore_dart`](https://pub.dev/packages/cloud_firestore_dart)
through [`cloud_firestore_dart_platform`](https://pub.dev/packages/cloud_firestore_dart_platform) instead of the
native plugin. On Windows the official plugins have native implementations (the Firebase C++ SDK), which
Flutter registers before `main()`; the app replaces the Firestore one with `CloudFirestoreDart.use(...)` at the
start of `main()` (`lib/dart_firestore.dart`). `firebase_core` stays native.

It includes a count, sum and average aggregation, because the native Windows plugin rejects sum and
average ("not supported by the Firebase C++ SDK on Windows").

| What | Where |
| --- | --- |
| `CloudFirestoreDart.use()` (memory cache) or `CloudFirestoreDart.use(openDatabase: sqliteOpener(...))` (disk cache), before the first Firestore operation | `lib/dart_firestore.dart` |
| `Firebase.initializeApp(options: FirebaseOptions(...))` with placeholder `demo-` values, `useFirestoreEmulator(host, port)` from `--dart-define` | `lib/bootstrap.dart` |
| A live list: `orderBy('createdAt').snapshots(includeMetadataChanges: true)` in a `StreamBuilder` | `lib/items_page.dart` |
| Add (`add` with `FieldValue.serverTimestamp()`), edit (`update`), delete | `_add`, `_edit`, the delete button |
| A transaction (read the priority, write it + 1) and a write batch (three items) | `_bump`, `_addBatch` |
| A query: `where('priority', isGreaterThanOrEqualTo: 2).orderBy('priority', descending: true).limit(3)` | `_runQuery` |
| `aggregate(count(), sum('priority'), average('priority'))` | `_runAggregate` |
| A status line with `metadata.isFromCache` and `hasPendingWrites`, a cloud icon per item for its pending write | `_StatusLine`, `_buildItem` |
| `disableNetwork()` / `enableNetwork()` behind a switch | `_setOnline` |

## Dependencies

```yaml
dependencies:
  cloud_firestore: ^7.1.0
  cloud_firestore_dart_platform: ^0.1.0   # selected with CloudFirestoreDart.use()
  cloud_firestore_dart_sqlite: ^0.1.0     # only for the disk cache
  firebase_core: ^5.1.0
  path_provider: ^2.1.6                   # only for the disk cache directory
```

All from pub.dev, so the folder can be copied anywhere and built on its own.

## Settings (`--dart-define`)

| Name | Default | What it does |
| --- | --- | --- |
| `EMULATOR_HOST` | `127.0.0.1` | Host of the Firestore emulator |
| `EMULATOR_PORT` | `8161` | Port of the Firestore emulator |
| `DISK_CACHE` | `false` | `true`: the offline cache is a SQLite file; otherwise memory |
| `CACHE_DIR` | application support directory + `\firestore` | Directory of the SQLite files |
| `START_OFFLINE` | `false` | `true`: `disableNetwork()` before the first read |
| `COLLECTION` | `items` | The collection the app lists and writes |

The project id is `demo-flutterfire-windows`; the emulator accepts any `demo-` project without credentials.

## Running it on Windows

You need Flutter with the Windows desktop toolchain (Visual Studio 2022 or its Build Tools with "Desktop
development with C++"; see `flutter doctor`), Java 21 and the Firestore emulator JAR
(`firebase emulators:start --only firestore` downloads it to `~/.cache/firebase/emulators`). In PowerShell:

```powershell
java -jar cloud-firestore-emulator-v1.22.0.jar --host 127.0.0.1 --port 8161 --project_id demo-test
# in another window:
cd examples\flutterfire_on_windows
flutter pub get
flutter run -d windows --dart-define=EMULATOR_PORT=8161
flutter run -d windows --dart-define=EMULATOR_PORT=8161 --dart-define=DISK_CACHE=true
```

The first build downloads the Firebase C++ SDK for the official plugins (see below).

### Integration tests

`integration_test/app_test.dart` drives the real app on the desktop device: it waits for the first snapshot
from the server, adds an item through the text field and the Add button, waits for the server timestamp, edits
it in the dialog, deletes it, then adds three items in a batch, raises one in a transaction, runs the query and
the aggregation. After each step it checks the server with `GetOptions(source: Source.server)`.

```powershell
flutter test integration_test/app_test.dart -d windows --dart-define=EMULATOR_PORT=8161
```

`integration_test/disk_cache_test.dart` checks the disk cache across a restart of the app, in two runs (two
processes) that share `CACHE_DIR`:

```powershell
$D = "--dart-define=DISK_CACHE=true", "--dart-define=CACHE_DIR=$env:TEMP\ffw-cache", "--dart-define=RUN_ID=r1"
flutter test integration_test/disk_cache_test.dart -d windows @D --dart-define=PHASE=write
# stop the emulator, so that nothing can come from the network
flutter test integration_test/disk_cache_test.dart -d windows @D --dart-define=PHASE=read --dart-define=START_OFFLINE=true
```

## What was observed

Run on 2026-11-17 on **Windows 11 Pro x64** (build 26300, a VM with 6 cores and 8 GB, no GPU), **Flutter
3.47.8** (Dart 3.13.7), Visual Studio Build Tools 2022 17.14, against the Firestore emulator 1.22.0 on the same
machine (OpenJDK 21), with `cloud_firestore` 7.2.0, `firebase_core` 5.2.0 (Firebase C++ SDK 14.1.0),
`cloud_firestore_dart_platform` 0.1.0, `cloud_firestore_dart` 0.2.0, `cloud_firestore_dart_sqlite` 0.1.0 and
`sqlite3` 3.5.2 from pub.dev. Everything ran from an SSH session: nobody was logged on at the console.

- **Selection.** `.flutter-plugins-dependencies` lists the native `cloud_firestore` and `firebase_core` as the
  Windows implementations; `cloud_firestore_dart_platform` is not registered there, and `CloudFirestoreDart.use()`
  in `main()` replaced the Firestore one. `firebase_core` stayed native: `Firebase.initializeApp(options: ...)`
  went through the C++ SDK with the placeholder `demo-` options.
- **Build.** `flutter build windows --debug` with no change to the generated `windows/` folder: 210 seconds for
  the first build, which includes downloading and extracting the Firebase C++ SDK (8.4 GB under
  `build\windows\x64\extracted`; the whole `build` folder was 10 GB). The native Firestore is still compiled and
  linked although nothing calls it: the linker pulls in `firebase_firestore.lib` (with its own gRPC), and the
  debug `flutterfire_on_windows.exe` is 55.7 MB. The `Debug` folder is 289 MB in 18 files (with the 84 MB
  `.pdb`, `flutter_windows.dll` 44.5 MB, `sqlite3.dll` 1.6 MB from the build hook of `sqlite3`, and `dartjni.dll`
  from `jni`, which `path_provider_android` brings in, unused). For comparison, `examples/flutter_notes`
  (`cloud_firestore_dart` without the official plugins) built in 84 seconds and its exe is 1.0 MB.
  `flutter build windows --release` (built, not run): 137 seconds, a 49.8 MB `Release` folder with a 14.7 MB
  exe, against 30.1 MB and 0.1 MB for `flutter_notes`; so the unused native Firebase adds about 15 MB to a
  release build. Both folders also contain the plugins' `.lib` files, which are not needed at run time.
- **Integration test.** `app_test.dart`: 3 of 3 passed (the first snapshot from the server, add/edit/delete,
  batch/transaction/query/aggregation) in about 8 seconds after a 48-second build. The aggregation returned
  `count 3, sum 7, average 2.33`, which the native Windows plugin would have rejected.
- **Disk cache.** The write phase passed and left
  `firestore.%5BDEFAULT%5D.demo-flutterfire-windows.%28default%29.db` (with `-wal` and `-shm`) in `CACHE_DIR`.
  With the emulator stopped, the read phase (a new process, network disabled from the start) passed: the
  document came from the SQLite file. A control run with an empty `CACHE_DIR` failed as it should (timed out).
- **The real window, driven.** `flutter run -d windows` with the [Marionette](https://pub.dev/packages/marionette_flutter)
  binding (a local entry point, not in this folder) and its MCP tools over the VM service: typing a title and
  Add, editing it in the dialog, deleting it, the batch, the transaction, the query (`batch-3 (4), batch-2 (2)`),
  the aggregation (`count 4, sum 8, average 2.00`), and the network switch (an item added offline showed
  `hasPendingWrites: true` and `isFromCache: true`, then was sent when the switch went back on). These go
  through Flutter's gesture and text input, not through Windows input.
- **No picture.** From the SSH session the window exists but Flutter cannot draw it: Direct3D cannot create a
  swap chain outside an interactive desktop (`SwapChain11 ... HRESULT 0x887A0022`, then `EGL Error: Context
  Lost` and "Failed to create platform view rendering surface"). The widgets, the input and Firestore all work,
  but there is nothing to screenshot. A run in a logged-on desktop session was not done.

### Limits

Not tried here: a logged-on desktop session (so no screenshot, and no real keyboard or mouse input), sign-in
(the official `firebase_auth` on Windows with `FlutterFireAuthTokenProvider`), App Check, a production project
(only the emulator, over plain text), TLS from a Flutter Windows process, Windows on ARM64, MSIX or other
packaging, and a machine with a GPU. `snapshots(source: ListenSource.cache)` and
`persistentCacheIndexManager()` still throw `UnimplementedError` on Windows: `cloud_firestore` checks the platform
before it calls the implementation.
