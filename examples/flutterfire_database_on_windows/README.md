# flutterfire_database_on_windows

A Flutter Windows desktop app written against the **official FlutterFire API** (`firebase_core` and
`firebase_database`), with the Realtime Database run by
[`firebase_database_dart`](../../firebase_database/firebase_database_dart) through
[`firebase_database_dart_platform`](../../firebase_database/firebase_database_dart_platform) instead of the native
plugin. Listed as a direct dependency, the adapter replaces the native `firebase_database` plugin on Windows, which
then leaves the build, and Flutter registers it before `main()` through its `dartPluginClass`. `firebase_core` stays
native. The app code names the adapter in one place only, to select the optional disk cache
(`lib/dart_database.dart`).

It is the Windows sibling of [`flutterfire_database_on_linux`](../flutterfire_database_on_linux): the two show the
same things in the same way. On Windows the native plugin is the Firebase C++ SDK, which does not resolve
`ServerValue.increment` and treats `startAfter` and `endBefore` as inclusive (FlutterFire's own tests skip those
there).

| What | Where |
| --- | --- |
| `Firebase.initializeApp(options: FirebaseOptions(...))` with placeholder `demo-` values and a `databaseURL`, `useDatabaseEmulator(host, port)` from `--dart-define` | `lib/bootstrap.dart` |
| The connection state from `.info/connected`, shown as a chip | `initState`, `_onConnected`, `build` in `lib/notes_page.dart` |
| The last 10 notes: `orderByChild('createdAt').limitToLast(10)` bound to `onChildAdded`, `onChildChanged`, `onChildMoved` and `onChildRemoved`; the list is placed with `previousChildKey`, and the oldest note leaves through `onChildRemoved` when a new one enters | `initState`, `_place`, `_replace`, `_drop` in `lib/notes_page.dart` |
| Edit of a note with `update({'text': ...})`, which fires `onChildChanged` | `_edit` |
| A text field that pushes a note with `push()`, `set` and `ServerValue.timestamp` | `_push` |
| Delete of a note with `remove()` | `_remove` |
| A counter changed by `runTransaction` | `_increment` |
| A second counter changed by `set(ServerValue.increment(1))`, shown from `onValue` of its reference | `_hit` |
| An offline switch: `goOffline()` and `goOnline()`; the chip follows `.info/connected`; a note pushed offline shows at once and is sent on going online | `_setOffline`, `_onConnected` |
| Presence: an `onDisconnect().set(...)` registered on every (re)connection, then `set` of the online entry; the list of entries under `presence` | `_onConnected`, `initState` |
| The disk cache (Windows only): `FirebaseDatabaseDart.use(persistenceFor: ...)` with `sqlitePersistence(...)`, before the first Database operation | `lib/dart_database.dart` |
| Integration tests: connect; push, edit and delete; the order and the window of 10; the counters, a note pushed offline and the presence entry; the disk cache across a restart | `integration_test/` |

Errors are shown in the status line at the bottom with their `FirebaseException` code.

## Dependencies

```yaml
dependencies:
  firebase_core: ^5.1.0
  firebase_database: ^13.1.0
  firebase_database_dart_platform: ^0.1.0   # replaces the native plugin on Windows
  firebase_database_dart_sqlite: ^0.1.0     # only for the disk cache
  path_provider: ^2.1.6                     # only for the disk cache directory
```

`firebase_database_dart_platform` and the packages under it are on pub.dev; `pubspec.yaml` still has a
`dependency_overrides` section that takes them, `firebase_database_dart` and `firebase_app_dart` from this
repository. Outside the repository, remove that section and use the versions on pub.dev. The dependencies need
Dart 3.12, so Flutter 3.44 or later.

Without `DISK_CACHE` the app does not call `FirebaseDatabaseDart.use()`: the registration is automatic, and the
emulator needs no signed-in user. The adapter's README says how to pass a token provider or App Check.

## Settings (`--dart-define`)

| Name | Default | What it does |
| --- | --- | --- |
| `EMULATOR_HOST` | `127.0.0.1` | Host of the Database emulator |
| `EMULATOR_PORT` | `9100` | Port of the Database emulator |
| `ROOT` | `ffdb` | The node of the database the app reads and writes under |
| `DATABASE_URL` | `https://demo-test-default-rtdb.firebaseio.com` | The database URL; its first label is the emulator namespace |
| `DISK_CACHE` | `false` | `true`: the cache and the pending writes are kept in SQLite; otherwise memory |
| `CACHE_DIR` | application support directory + `\firebase_database` | Directory of the SQLite files |
| `START_OFFLINE` | `false` | `true`: `goOffline()` before the first read |

The project id is `demo-test` and the database `demo-test-default-rtdb` (open rules), the ones of
`tool/start_database_emulator.sh`. The app always calls `useDatabaseEmulator`, so it never talks to a real
project; to use one, replace `demoOptions` in `lib/bootstrap.dart` with your own options and remove that call.

## Running it on Windows

You need Flutter with the Windows desktop toolchain (Visual Studio 2022 or its Build Tools with "Desktop
development with C++"; see `flutter doctor`). The Database emulator runs where the Firebase CLI and Java are, with
`tool/start_database_emulator.sh` (see `tool/README.md`), and the app reaches it on `127.0.0.1:9100`: on the same
machine, or from the Windows machine through an SSH tunnel opened on the emulator's machine:

```sh
./tool/start_database_emulator.sh 9100
ssh -R 9100:127.0.0.1:9100 <windows-host>   # only when the emulator is on another machine
```

Then in PowerShell on the Windows machine:

```powershell
cd examples\flutterfire_database_on_windows
flutter pub get
flutter run -d windows
flutter run -d windows --dart-define=DISK_CACHE=true
```

The first build downloads the Firebase C++ SDK for the native `firebase_core`. To see the presence entry change,
run a second copy of the app (each run has its own `windows-<number>` id) and close one.

### Integration tests

```powershell
flutter test integration_test/app_test.dart -d windows --dart-define=ROOT=ffdb-test
```

It empties the node before each test. It waits for **Connected** and the empty list; pushes a note through the
field, edits it (the same row shows the new text) and deletes it (the row leaves the list), checking the server
with `get()`; pushes 11 notes and checks that the 10 newest are shown, newest first; counts twice with the
transaction and twice with `increment(1)`, switches offline, pushes a note (shown at once), switches online, reads
the note from the server and checks that the presence entry of the run is `online`.

`integration_test/disk_cache_test.dart` checks the disk cache across a restart of the app, in two runs (two
processes) that share `CACHE_DIR`:

```powershell
$D = "--dart-define=DISK_CACHE=true", "--dart-define=CACHE_DIR=$env:TEMP\ffdw-cache", "--dart-define=RUN_ID=r1"
flutter test integration_test/disk_cache_test.dart -d windows @D --dart-define=PHASE=write
# stop the emulator, so that nothing can come from the network
flutter test integration_test/disk_cache_test.dart -d windows @D `
  --dart-define=PHASE=read --dart-define=START_OFFLINE=true
```

The second run may wait about 7.5 seconds before it owns the SQLite file, if the first process did not release it.

## Status

- `flutter analyze` reports no issues (Flutter 3.44.9, macOS).
- Run on Windows 11 x64 (a VM, Flutter 3.47.8, debug build), against the Database emulator on another machine
  through an SSH tunnel, by the maintainer at commit `ec9f1fdc`, with the earlier version of this app whose list was
  bound to `onValue`:
  - `flutter build windows --debug` succeeds.
  - The generated plugin registrant calls `FirebaseDatabaseDart.registerWith()`, and `generated_plugins.cmake`
    lists `firebase_core` only.
  - `integration_test/app_test.dart`: 4 of 4 pass.
  - `integration_test/disk_cache_test.dart` passes in both phases (write with the emulator up, then read with the
    emulator stopped and `START_OFFLINE=true`).
- The child-event version, on the same VM at a later trunk: `app_test.dart` passes 4 of 4 (connect and the empty
  list; push, edit and delete through the UI; the order kept and the oldest leaving the window of 10; both counters,
  presence and a note pushed offline). `disk_cache_test.dart` passed with the earlier `onValue` version and has not
  been rerun with this one.
- Not run: a release build, the app against a production project, the window drawn on a screen (the tests ran
  over SSH).
