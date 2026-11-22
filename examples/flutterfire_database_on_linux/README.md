# flutterfire_database_on_linux

A Flutter Linux desktop app written against the **official FlutterFire API** (`firebase_core` and
`firebase_database`), for Linux, where FlutterFire has no Realtime Database implementation of its own. The work
is done by [`firebase_database_dart`](../../firebase_database/firebase_database_dart) through
[`firebase_database_dart_platform`](../../firebase_database/firebase_database_dart_platform), which Flutter
registers before `main()` on Linux. The app code does not import it; the only sign of it is one line in
`pubspec.yaml`.

| What | Where |
| --- | --- |
| `Firebase.initializeApp(options: FirebaseOptions(...))` with placeholder `demo-` values and a `databaseURL`, `useDatabaseEmulator(host, port)` from `--dart-define` | `lib/bootstrap.dart` |
| The connection state from `.info/connected`, shown as a chip | `initState`, `_onConnected`, `build` in `lib/notes_page.dart` |
| The last 10 notes: `orderByChild('createdAt').limitToLast(10)` bound to `onChildAdded`, `onChildChanged`, `onChildMoved` and `onChildRemoved`; the list is placed with `previousChildKey`, and the oldest note leaves through `onChildRemoved` when a new one enters | `initState`, `_place`, `_replace`, `_drop` in `lib/notes_page.dart` |
| Edit of a note with `update({'text': ...})`, which fires `onChildChanged` | `_edit` |
| A text field that pushes a note with `push()`, `set` and `ServerValue.timestamp` | `_push` |
| Delete of a note with `remove()` | `_remove` |
| A counter changed by `runTransaction` | `_increment` |
| Presence: an `onDisconnect().set(...)` registered on every (re)connection, then `set` of the online entry; the list of entries under `presence` | `_onConnected`, `initState` |
| Integration test: connect, push through the field, count, see the presence entry | `integration_test/app_test.dart` |

## Dependencies

```yaml
dependencies:
  firebase_core: ^5.1.0
  firebase_database: ^13.1.0
  firebase_database_dart_platform: ^0.0.1   # registers itself on Linux
```

`firebase_database_dart_platform` is not on pub.dev yet, so `pubspec.yaml` has a `dependency_overrides` section
that takes it, `firebase_database_dart` and `firebase_app_dart` from this repository. Outside the repository,
remove that section and use the versions on pub.dev. The dependencies need Dart 3.12, so Flutter 3.44 or later.

The app does not call `FirebaseDatabaseDart.use()`: on Linux the registration is automatic, and the emulator needs
no signed-in user. The adapter's README says how to pass a token provider, persistence or App Check.

## Settings (`--dart-define`)

| Name | Default | What it does |
| --- | --- | --- |
| `EMULATOR_HOST` | `127.0.0.1` | Host of the Database emulator |
| `EMULATOR_PORT` | `9100` | Port of the Database emulator |
| `ROOT` | `ffdb` | The node of the database the app reads and writes under |

The project id is `demo-test` and the database `demo-test-default-rtdb` (open rules), the ones of
`tool/start_database_emulator.sh`. The app always calls `useDatabaseEmulator`, so it never talks to a real
project; to use one, replace `demoOptions` in `lib/bootstrap.dart` with your own options and remove that call.

## Running it on Linux

You need Flutter with the Linux desktop toolchain (`clang`, `cmake`, `ninja`, `pkg-config`, GTK 3 headers; see
`flutter doctor`) and the Database emulator. From the root of the repository, on a machine with Java and the
Firebase CLI (see `tool/README.md`):

```sh
./tool/start_database_emulator.sh 9100
cd examples/flutterfire_database_on_linux
flutter pub get
flutter run -d linux --dart-define=EMULATOR_PORT=9100
```

On a machine without a display, start a virtual one first (`Xvfb :61 -screen 0 1280x800x24 -nolisten tcp &`,
`export DISPLAY=:61`). If the emulator runs on another machine, forward the port over SSH instead of exposing it.
To see the presence entry change, run a second copy of the app (each run has its own `linux-<number>` id) and
close one.

### Integration test

```sh
flutter test integration_test/app_test.dart -d linux --dart-define=EMULATOR_PORT=9100 --dart-define=ROOT=ffdb-test
```

It empties the node, waits for **Connected**, types a note and taps **Push**, edits it, pushes 10 more (the first, edited note leaves the window of 10), taps **Count with a transaction**,
checks the counter with `get()`, and checks that the presence entry of the run is `online`.

## Status

- `flutter analyze` reports no issues (Flutter 3.44.9, macOS). The list code was written for the child events
  of a `limitToLast` query as the JS SDK delivers them; how the adapter orders them was not run.
- **Not built or run on Linux.** The build was not tried (it needs a Linux machine), the integration test was not
  run, and the app has not been seen on screen. Treat the code as written against the API, not as observed
  behaviour.
- Not run against a real project.
