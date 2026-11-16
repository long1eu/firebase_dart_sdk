# Browser tests

`web_opener_test.dart` runs the browser opener in Chrome against a private Firestore emulator.
It loads three files from this folder that are not in the repository (see `../../.gitignore`):

| File | How to get it |
| --- | --- |
| `sqlite3.wasm` | The build of the `sqlite3` version in `pubspec.lock`; `dart run cloud_firestore_dart_sqlite:setup_web test/browser` prints the URL. For 2.9.4, `tool/build_web_test_assets.sh` of the repository downloads it (with a pinned checksum) to `cloud_firestore/cloud_firestore_dart/test/browser/`. |
| `sqlite_opfs_worker.js` | `dart run cloud_firestore_dart_sqlite:setup_web test/browser` |
| `emulator_port.txt` | The port of the emulator, e.g. `echo 8090 > test/browser/emulator_port.txt` (default 8090). |

```sh
../../tool/start_private_emulator.sh 8090
dart test -p chrome -c dart2js test/browser/web_opener_test.dart
dart test -p chrome -c dart2wasm test/browser/web_opener_test.dart
../../tool/stop_private_emulator.sh 8090
```

Without `sqlite3.wasm` the tests skip themselves; without the worker the OPFS test does.
