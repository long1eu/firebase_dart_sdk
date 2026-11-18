# flutterfire_on_linux

A Flutter Linux desktop app written against the **official FlutterFire API** (`firebase_core` and
`cloud_firestore`), running on Linux, where FlutterFire has no implementation of its own. The work is
done by [`cloud_firestore_dart`](https://pub.dev/packages/cloud_firestore_dart) through
[`cloud_firestore_dart_platform`](https://pub.dev/packages/cloud_firestore_dart_platform), which Flutter
registers before `main()` on Linux. The app code does not import it; the only sign of it is one line in
`pubspec.yaml`, plus `lib/disk_cache.dart` for the optional disk cache.

| What | Where |
| --- | --- |
| `Firebase.initializeApp(options: FirebaseOptions(...))` with placeholder `demo-` values, `useFirestoreEmulator(host, port)` from `--dart-define` | `lib/bootstrap.dart` |
| A live list: `orderBy('createdAt').snapshots(includeMetadataChanges: true)` in a `StreamBuilder` | `lib/items_page.dart` |
| Add (`add` with `FieldValue.serverTimestamp()`), edit (`update`), delete | `_add`, `_edit`, the delete button |
| A transaction (read the priority, write it + 1) and a write batch (three items) | `_bump`, `_addBatch` |
| A query: `where('priority', isGreaterThanOrEqualTo: 2).orderBy('priority', descending: true).limit(3)` | `_runQuery` |
| A status line with `metadata.isFromCache` and `hasPendingWrites`, a cloud icon per item for its pending write | `_StatusLine`, `_buildItem` |
| `disableNetwork()` / `enableNetwork()` behind a switch | `_setOnline` |
| Optional disk cache: `CloudFirestoreDart.use(openDatabase: sqliteOpener(...))` of `cloud_firestore_dart_sqlite` | `lib/disk_cache.dart` |

## Dependencies

```yaml
dependencies:
  cloud_firestore: ^7.1.0
  cloud_firestore_dart_platform: ^0.1.0   # registers itself on Linux
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
| `CACHE_DIR` | application support directory + `/firestore` | Directory of the SQLite files |
| `START_OFFLINE` | `false` | `true`: `disableNetwork()` before the first read |
| `COLLECTION` | `items` | The collection the app lists and writes |

The project id is `demo-flutterfire-linux`; the emulator accepts any `demo-` project without credentials.

## Running it on Linux

You need Flutter with the Linux desktop toolchain (`clang`, `cmake`, `ninja`, `pkg-config`, GTK 3
headers; see `flutter doctor`) and a Firestore emulator. From the root of the repository, on a machine
with Java and the emulator JAR (`firebase emulators:start --only firestore` downloads it):

```sh
./tool/start_private_emulator.sh 8161      # or: firebase emulators:start --only firestore
cd examples/flutterfire_on_linux
flutter pub get
flutter run -d linux --dart-define=EMULATOR_PORT=8161
flutter run -d linux --dart-define=EMULATOR_PORT=8161 --dart-define=DISK_CACHE=true
```

If the emulator runs on another machine, forward the port over SSH instead of exposing it, for example
`ssh -R 8161:127.0.0.1:8161 linux-box` from the machine with the emulator.

On a machine without a display, start a virtual one first: `Xvfb :61 -screen 0 1280x800x24 -nolisten tcp &`
and `export DISPLAY=:61`.

### Integration tests

`integration_test/app_test.dart` drives the real app on the desktop device: it waits for the first
snapshot from the server, adds an item through the text field and the Add button, waits for the server
timestamp, edits it in the dialog, deletes it, then adds three items in a batch, raises one in a
transaction and runs the query. After each step it checks the server with `GetOptions(source:
Source.server)`.

```sh
flutter test integration_test/app_test.dart -d linux --dart-define=EMULATOR_PORT=8161
```

`integration_test/disk_cache_test.dart` checks the disk cache across a restart of the app, in two runs
(two processes) that share `CACHE_DIR`:

```sh
D="--dart-define=DISK_CACHE=true --dart-define=CACHE_DIR=/tmp/ffl-cache --dart-define=RUN_ID=r1"
flutter test integration_test/disk_cache_test.dart -d linux $D --dart-define=PHASE=write
# stop the emulator, so that nothing can come from the network
flutter test integration_test/disk_cache_test.dart -d linux $D --dart-define=PHASE=read \
  --dart-define=START_OFFLINE=true
```

The first run writes `persisted-r1` through the UI and waits for the server. The second starts a new
process with the network disabled from the start and must show `persisted-r1` with `isFromCache: true`.

## What was observed

Run on 2026-11-16 on **Debian GNU/Linux 13 (trixie), x86_64** (a VM, kernel 6.12), **Flutter 3.44.9**
(Dart 3.12.2), under **Xvfb** (no GPU, no window manager), against the Firestore emulator 1.22.0 on the
same machine (OpenJDK 21), with `cloud_firestore` 7.1.0, `firebase_core` 5.1.0,
`cloud_firestore_dart_platform` 0.1.0, `cloud_firestore_dart` 0.2.0, `cloud_firestore_dart_sqlite` 0.1.0
and `sqlite3` 3.5.2 from pub.dev.

- **Registration.** After `flutter pub get`, `.flutter-plugins-dependencies` lists
  `cloud_firestore_dart_platform` (with `native_build: false`) as the Linux implementation, and the
  generated `dart_plugin_registrant.dart` calls `CloudFirestoreDart.registerWith()` under
  `Platform.isLinux`. `Firebase.initializeApp(options: ...)` worked with no native `firebase_core`: the
  package's Dart `firebase_core` was in place before `main()`.
- **Build.** `flutter build linux --debug` succeeded with no change to the generated `linux/` folder. The
  bundle has `libflutter_linux_gtk.so`, `libsqlite3.so` (built by the hook of `sqlite3` 3.x, there even
  when the disk cache is off) and `libdartjni.so` (from `jni`, which `path_provider_android` brings in and
  which declares a Linux FFI plugin; unused here).
- **Integration test.** `app_test.dart`: 3 of 3 passed (the first snapshot from the server, add/edit/delete,
  batch/transaction/query), about 5 seconds after the build. gRPC to the emulator over plain HTTP/2 worked
  inside the Flutter Linux process.
- **Emulator side.** The emulator's REST API (`GET /v1/projects/demo-flutterfire-linux/databases/(default)/documents/items`)
  returned the three batch documents the app wrote, with `batch-3` at priority 4 after the transaction and
  `createdAt` set by the server.
- **Disk cache.** The write phase passed and left
  `firestore.%5BDEFAULT%5D.demo-flutterfire-linux.%28default%29.db` (with its `-wal` and `-shm`) in
  `CACHE_DIR`. With the emulator **stopped**, the read phase (a new process, network disabled from the
  start) passed: the document came from the SQLite file. A control run of the read phase with an empty
  `CACHE_DIR` failed as it should (timed out with `0 docs`).
- **Not yet done:** a screenshot of the window, and typing through the real X keyboard path (`xdotool`); the
  integration tests enter text through the test binding, not through GTK.

One problem was found on the way, in this example and not in a package: the edit dialog disposed its
`TextEditingController` as soon as `showDialog` returned, while the dialog's closing animation still used it
("A TextEditingController was used after being disposed"). The dialog now owns its controller
(`_EditDialog`).

### Limits

Not tried here: sign-in (`firebase_auth` has no Linux implementation; see the package README for
`FirebaseUserAuth`), App Check, a production project (only the emulator, over plain text), TLS to a real
backend from a Flutter Linux process, a real desktop session with a GPU and a window manager, other
distributions, arm64, release and profile builds, and packaging (snap, Flatpak, AppImage). The SQLite files
were left with a `-wal` file after the test process ended, which SQLite replays on the next open; a desktop app
should call `FirebaseFirestore.instance.terminate()` when it quits.
