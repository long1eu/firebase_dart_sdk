# flutter_notes

A small Flutter notes app on `cloud_firestore_dart` and `firebase_app_dart` from pub.dev. It keeps
its cache in SQLite, so the notes are there without a network, and edits made offline are sent
when the connection is back.

What it shows:

| What | Where |
| --- | --- |
| The `FirebaseApp` and the `FirebaseFirestore` instance created in `main()` before `runApp`, from `--dart-define` values | `lib/firestore_setup.dart`, `lib/main.dart` |
| The persistent cache: a SQLite file in the application support directory, opened by `sqliteOpener(directory: ...)` of `cloud_firestore_dart_sqlite`; the build hook of `sqlite3` 3.x bundles SQLite with the app | `lib/firestore_setup.dart` |
| Connectivity events of `connectivity_plus` fed to `PlatformDependencies.onNetworkConnected` | `AppDependencies` in `lib/firestore_setup.dart` |
| A real-time listener in a `StreamBuilder`, with `snapshots(includeMetadataChanges: true)` | `lib/notes_page.dart` |
| An offline indicator from `isFromCache` and `hasPendingWrites` of the snapshot metadata, and a mark on each note that is not on the server yet | `_StatusLine` and `_buildList` in `lib/notes_page.dart` |
| Add, edit and delete without awaiting the write (the future completes only when the server acknowledged it) | `_write` in `lib/notes_page.dart` |
| A typed model with `withConverter` and a server timestamp | `lib/note.dart` |
| The app lifecycle: `disableNetwork()` on pause and `enableNetwork()` on resume (Android, iOS), `terminate()` when a desktop app is asked to quit | `lib/main.dart` |

The state is plain Flutter: `StatefulWidget`s and a `StreamBuilder`, no state management package.
The notes are in the collection `notes`, as `{title, body, updatedAt}`.

This is the app on macOS against a private emulator, with three notes. Look at the status line
under the title:

![The flutter_notes window on macOS: the status line says "Up to date" and three notes are listed, each with a delete button, and an add button at the bottom right](../../docs/images/examples/flutter_notes_online.png)

How `main()` wires the pieces together before `runApp`, and what the widgets use afterwards:

```mermaid
flowchart TD
  connectivity["connectivity_plus events"] --> deps["AppDependencies, onNetworkConnected"]
  deps -- "dependencies:" --> app["FirebaseApp.withOptions, from --dart-define"]
  app --> firestore["FirebaseFirestore.instanceFor"]
  sqlite["sqliteOpener: SQLite file in the application support directory"] -- "openDatabase:" --> firestore
  settings["PersistentCacheSettings, withEmulator"] -- "settings:" --> firestore
  firestore -- "gRPC" --> backend["Firestore emulator or project"]
  firestore --> notesPage["NotesPage: StreamBuilder over snapshots()"]
  lifecycle["AppLifecycleListener"] -- "disableNetwork, enableNetwork, terminate" --> firestore
```

## Run it against the Firestore emulator on macOS

Needs Flutter (3.32 or later for Dart 3.8; built with 3.44.9), Xcode, and the Firebase CLI. From
this directory:

```sh
firebase emulators:start --only firestore --project demo-notes    # in another terminal

flutter pub get
flutter run -d macos
```

The app talks to the emulator on `127.0.0.1:8080` with the project `demo-notes`. To change it:

```sh
flutter run -d macos --dart-define=EMULATOR_HOST=127.0.0.1 --dart-define=EMULATOR_PORT=8104
```

To see the offline behaviour, stop the emulator while the app runs: the status line turns to
"Offline: showing the saved notes", and a note you add or edit is shown at once with an upload mark.

This is the same window about 20 seconds after the emulator was stopped. Look at the status line:
the notes stay, served from the SQLite cache.

![The flutter_notes window with the status line "Offline: showing the saved notes" on a tinted background with a crossed-out cloud icon, and the same three notes](../../docs/images/examples/flutter_notes_offline.png)

Start the emulator again: within a few seconds (up to a minute, the client's backoff) the write
is sent and the line says "Up to date". The emulator keeps its data in memory, so after a restart
it has only what the app sent again. Quit with Cmd-Q and start the app with the emulator stopped:
the notes come from the SQLite file.

On the Android emulator the host machine is `10.0.2.2`, not `127.0.0.1`:
`--dart-define=EMULATOR_HOST=10.0.2.2`.

## Point it at a real project

Pass the values of a web app of your project (Firebase console, *Project settings*, *Your apps*;
they work on every platform):

```sh
flutter run -d macos \
  --dart-define=USE_EMULATOR=false \
  --dart-define=PROJECT_ID=my-project \
  --dart-define=API_KEY=<YOUR_API_KEY> \
  --dart-define=APP_ID=1:1234567890:web:0123456789abcdef
```

The app does not sign in, so its requests are unauthenticated: the security rules of the database
must allow reads and writes of `notes` without a user, which is only acceptable for a test
project. To add sign-in, see [Authentication](../../docs/guides/authentication.md). The ordering by
`updatedAt` needs no composite index. This app has not been run against a real project.

## Platforms

| Platform | Status |
| --- | --- |
| macOS | Built (`flutter build macos --debug`) and run against the emulator by hand: the listener, an edit offline, the sync when the emulator came back, the cache across a restart, and `terminate()` on Cmd-Q. Again with 0.2.0 and `cloud_firestore_dart_sqlite` 0.1.0 (`sqlite3` 3.5.2): the notes loaded, a note added and deleted in the app reached the emulator, the app quit from its menu, and started again with the emulator stopped it showed the notes from its SQLite file (a file first created by the 0.1 build with the copied opener) |
| macOS, screenshots | Taken with the 0.1 build; the UI did not change in 0.2. `flutter build macos --debug --dart-define=EMULATOR_PORT=8141`, the built app run against a private emulator with three notes written through the emulator's REST API, captured with `screencapture -l` |
| Android, iOS, Linux, Windows | Not built and not run. The platform folders are those of `flutter create` with the changes below |

Changes to the generated platform projects:

- macOS: `com.apple.security.network.client` in `macos/Runner/DebugProfile.entitlements` and
  `Release.entitlements`. Without it the sandbox blocks the connection to Firestore. The
  deployment target is 12.0 (the template's 10.15 is below what current Xcode builds).
- Android: the `INTERNET` permission in `android/app/src/main/AndroidManifest.xml` (debug builds
  get it from `src/debug`, release builds need it here).

## Notes

- `pubspec.yaml` depends on the versions on pub.dev (`cloud_firestore_dart` and
  `firebase_app_dart` `^0.2.0`, `cloud_firestore_dart_sqlite` `^0.1.0`). `pubspec.lock` records
  the versions it was run with.
- The app has no `sqlite3` dependency of its own and no `sqlite3_flutter_libs`: with Flutter 3.44
  pub picks `sqlite3` 3.x for `cloud_firestore_dart_sqlite` (3.5.2 here: 3.6.0 and later need
  `meta` 1.19, and Flutter 3.44 pins 1.18), and its build hook downloads a SQLite build and
  bundles it with the app (`sqlite3.framework` in the macOS app). The build needs network access
  to GitHub for that download, unless `hooks: user_defines: sqlite3:` in `pubspec.yaml` points it
  at another SQLite. On a Flutter older than 3.38 pub picks `sqlite3` 2.x; then add
  `sqlite3_flutter_libs: ^0.5.40` (see the README of `cloud_firestore_dart_sqlite`).
- `connectivity_plus` uses the packages `nm` and `dbus` on Linux, which are under the Mozilla
  Public License 2.0. Every other dependency is under MIT, BSD or Apache-2.0.
- The guide [Flutter](../../docs/guides/flutter.md) explains the code of this app step by step.
