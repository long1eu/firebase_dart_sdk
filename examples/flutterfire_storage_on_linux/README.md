# flutterfire_storage_on_linux

A Flutter Linux desktop app written against the **official FlutterFire API** (`firebase_core` and
`firebase_storage`), for Linux, where FlutterFire has no Storage implementation of its own. The work
is done by [`firebase_storage_dart`](../../firebase_storage/firebase_storage_dart) through
[`firebase_storage_dart_platform`](../../firebase_storage/firebase_storage_dart_platform), which
Flutter registers before `main()` on Linux. The app code does not import it; the only sign of it is
one line in `pubspec.yaml`.

| What | Where |
| --- | --- |
| `Firebase.initializeApp(options: FirebaseOptions(...))` with placeholder `demo-` values and a `storageBucket`, `useStorageEmulator(host, port)` from `--dart-define` | `lib/bootstrap.dart` |
| An upload of a generated PNG (about 1 MB, so several chunks) with `putData` and a `SettableMetadata` content type | `_upload` in `lib/images_page.dart`, `lib/sample_image.dart` |
| A progress bar from `task.snapshotEvents`, and buttons for `pause()`, `resume()` and `cancel()` | `_upload`, `build` |
| The folder listing with `listAll()` | `_listing` |
| Each image shown by `getDownloadURL()` with `Image.network`, its size from `getMetadata()` | `_ImageTile` |
| Delete with `Reference.delete()` | `_delete` |
| Integration test: upload through the button, find it in the list and in the bucket, delete it | `integration_test/app_test.dart` |

## Dependencies

```yaml
dependencies:
  firebase_core: ^5.1.0
  firebase_storage: ^14.1.0
  firebase_storage_dart_platform: ^0.1.0   # registers itself on Linux
```

`firebase_storage_dart_platform` is not on pub.dev yet, so `pubspec.yaml` has a
`dependency_overrides` section that takes it, `firebase_storage_dart` and `firebase_app_dart` from
this repository. Outside the repository, remove that section and use the versions on pub.dev. The
dependencies need Dart 3.12, so Flutter 3.44 or later.

## Settings (`--dart-define`)

| Name | Default | What it does |
| --- | --- | --- |
| `EMULATOR_HOST` | `127.0.0.1` | Host of the Storage emulator |
| `EMULATOR_PORT` | `9199` | Port of the Storage emulator |
| `FOLDER` | `images` | The folder of the bucket the app lists and writes |

The project id is `demo-test` and the bucket `demo-test.appspot.com` (open rules), the ones of
`tool/start_storage_emulator.sh`.

## Running it on Linux

You need Flutter with the Linux desktop toolchain (`clang`, `cmake`, `ninja`, `pkg-config`, GTK 3
headers; see `flutter doctor`) and the Storage emulator. From the root of the repository, on a
machine with Java and the Firebase CLI (see `tool/README.md`):

```sh
./tool/start_storage_emulator.sh 9199
cd examples/flutterfire_storage_on_linux
flutter pub get
flutter run -d linux --dart-define=EMULATOR_PORT=9199
```

On a machine without a display, start a virtual one first (`Xvfb :61 -screen 0 1280x800x24
-nolisten tcp &`, `export DISPLAY=:61`). If the emulator runs on another machine, forward the port
over SSH instead of exposing it.

### Integration test

```sh
flutter test integration_test/app_test.dart -d linux --dart-define=EMULATOR_PORT=9199 --dart-define=FOLDER=ffs-test
```

It empties the folder, taps **Upload a sample image**, waits for the status line, checks the bucket
with `listAll()` and `getMetadata()` (content type `image/png`, more than 256 KiB), then deletes the
image through its button.

## Status

- `flutter analyze` reports no issues (Flutter 3.44.9, macOS).
- **Not built or run on Linux.** The integration test was not run, and the app has not been seen on
  screen. Treat the code as written against the API, not as observed behaviour.
- Not run against a real project.
