# Browser tests

`web_opener_test.dart` runs the browser opener in Chrome against a private Firestore emulator.
`setup_checks_test.dart` runs the checks of the opener (a `sqlite3` version that can lose writes in
IndexedDB, a `sqlite3.wasm` that is missing or of another release); it needs no emulator. They load
these files from this folder, which are not in the repository (see `../../.gitignore`):

| File | How to get it |
| --- | --- |
| `sqlite3.wasm` | The build of the `sqlite3` version in `pubspec.lock`; `dart run cloud_firestore_dart_sqlite:setup_web test/browser` prints the URL. `tool/build_web_test_assets.sh` of the repository downloads the build of the version that `cloud_firestore_dart` locks (3.9.1, with a pinned checksum) to `cloud_firestore/cloud_firestore_dart/test/browser/`. |
| `sqlite_opfs_worker.js` | `dart run cloud_firestore_dart_sqlite:setup_web test/browser` |
| `emulator_port.txt` | The port of the emulator, e.g. `echo 8090 > test/browser/emulator_port.txt` (default 8090). |
| `other_sqlite3.wasm` | Optional, for `setup_checks_test.dart`: the `sqlite3.wasm` of another release (2.9.4 with a 3.x lock, 3.9.1 with a 2.x lock). |

`setup_checks_test.dart` reads the `sqlite3` version from `pubspec.lock` and expects the refusal
with 3.4.0 to 3.5.2 only. To try a version, add it to `pubspec_overrides.yaml` for the run
(`  sqlite3: 3.5.2` under `dependency_overrides:`), `dart pub get`, put that version's
`sqlite3.wasm` here, run the test with both compilers, and restore `pubspec_overrides.yaml` and
`pubspec.lock`. Tried with 2.9.4, 3.5.2 and 3.9.1. The sha256 of the 3.5.2 build (release
`sqlite3-3.5.2`) is `13d3f11d05b39ba0618a7115fb41640a5d48b6300f5d3f325f554b42bd6688a4`.

```sh
../../tool/start_private_emulator.sh 8090
dart test -p chrome -c dart2js test/browser/web_opener_test.dart
dart test -p chrome -c dart2wasm test/browser/web_opener_test.dart
../../tool/stop_private_emulator.sh 8090
```

Without `sqlite3.wasm` the tests skip themselves; without the worker the OPFS test does.
