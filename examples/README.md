# Examples

Small, complete programs that use `cloud_firestore_dart`, `firebase_storage_dart` and `firebase_database_dart`: servers and tools, a worker, a Flutter
app and a browser app. Each directory is a package of its own with a `pubspec.yaml` and a README.

| Directory | What it is |
| --- | --- |
| [`server_shelf/`](server_shelf/) | Two HTTP APIs on `package:shelf`: tasks in Firestore, with the changes of one real-time listener sent to every client as server-sent events; and files in Cloud Storage, with the request body streamed into a resumable upload and the object streamed to the response (ranges included). |
| [`cli/`](cli/) | A command-line tool on `package:args`: imports a JSON file with batched writes, exports a query to JSON, watches a query. |
| [`storage_cli/`](storage_cli/) | A command-line tool on `package:args` and `firebase_storage_dart`: `ls`, `put` (resumable, with a progress line), `get` (streamed to a file), `cat`, `stat`, `rm`, `url`; optional email/password sign-in so rules with `request.auth` pass. Run against the Storage emulator. |
| [`cloud_run_job/`](cloud_run_job/) | A one-shot job: an aggregation query, a transaction that writes once per execution, retries with backoff, and a `Dockerfile` for a native binary. |
| [`worker_queue/`](worker_queue/) | A long-running worker: a listener to wake up, a transaction that claims each job once, results in a batch, a clean stop on `SIGTERM`. |
| [`flutter_notes/`](flutter_notes/) | A Flutter notes app: a real-time list, offline edits in a SQLite cache, an offline indicator, connectivity events and a clean shutdown. Built and run on macOS, and on Windows from an SSH session (no window drawn). |
| [`flutterfire_on_linux/`](flutterfire_on_linux/) | A Flutter Linux desktop app written only against the official `cloud_firestore` and `firebase_core` API; `cloud_firestore_dart_platform` registers itself, with no code: a live list, add/edit/delete, a batch, a transaction, a query, an optional SQLite cache, and integration tests. Run on Debian 13 x86_64 and, in release, in an Ubuntu 24.04 arm64 container, against the emulator. |
| [`flutterfire_storage_on_linux/`](flutterfire_storage_on_linux/) | A Flutter Linux desktop app written only against the official `firebase_storage` and `firebase_core` API; `firebase_storage_dart_platform` registers itself, with no code: an upload of a generated image with a progress bar and pause, resume and cancel, a folder listing, images by download URL, delete, and an integration test. Against the Storage emulator; **not yet built or run on Linux**. |
| [`flutterfire_on_windows/`](flutterfire_on_windows/) | A Flutter Windows app on the official `cloud_firestore` API, with `cloud_firestore_dart` selected by `CloudFirestoreDart.use()` instead of the native plugin: a live list, add/edit/delete, a batch, a transaction, a query, a sum and average aggregation, an optional SQLite cache, and integration tests. Run on Windows 11 against the emulator. |
| [`web_app/`](web_app/) | A browser app in plain Dart (`package:web`): a real-time list, offline writes, a memory or SQLite (IndexedDB/OPFS) cache, and a Firestore Lite page to compare sizes, and a Storage page: a file picker, an upload with a progress bar and pause, resume and cancel, a folder listing and images by download URL. Supported in Chrome, untested elsewhere. |
| [`flutter_web_two_users/`](flutter_web_two_users/) | A Flutter web page with two signed-in users side by side (Auth emulator), each with its own `FirebaseApp` and Firestore client: each sees the other's writes, the security rules refuse the guest what the owner may do, and a SQLite cache in IndexedDB answers before the network after a reload. `run.sh` starts the emulators and serves the build on another port. Built with dart2js and dart2wasm, tried in Chrome. |
| [`rtdb_cli/`](rtdb_cli/) | A command-line tool for the Realtime Database on `firebase_database_dart`: `get` (with order, range and limit), `set`, `update`, `push`, `remove`, `import`, `export`, `watch`. Run against the Database emulator. |
| [`rtdb_server_shelf/`](rtdb_server_shelf/) | An HTTP API on `package:shelf` over the Realtime Database: notes with create, read, patch and delete, a list, and one listener sent to every client as server-sent events. Run against the Database emulator. |
| [`rtdb_presence_worker/`](rtdb_presence_worker/) | A worker that keeps a presence record with a heartbeat and an `onDisconnect` write, and a watcher that lists who is online. Run against the Database emulator, including a killed worker. |
| [`rtdb_web_app/`](rtdb_web_app/) | A browser app in plain Dart (`package:web`) on the Realtime Database: a live list of items (child events), a form that pushes an item, a connection indicator, a go offline / go online button, and a panel to connect an emulator or a project (`?emulator=127.0.0.1:9100`). Needs an emulator or a project; loaded through `bootstrap.js` with dart2wasm and a dart2js fallback. I could not verify that it was used against an emulator. |
| [`rtdb_playground/`](rtdb_playground/) | A browser playground for the Realtime Database with no backend: the client runs against a fake server in the page. Static files only. Loads in Chrome with dart2js and dart2wasm. |
| [`flutterfire_database_on_linux/`](flutterfire_database_on_linux/) | A Flutter Linux desktop app written only against the official `firebase_database` and `firebase_core` API; `firebase_database_dart_platform` registers itself, with no code: the connection state, a query bound to a live list, push, delete, a transaction on a counter, presence with `onDisconnect`, and integration tests. Against the Database emulator. Built on Linux x64 (Debian 13); the integration tests in their current form have **not yet passed in full there**. |
| [`flutterfire_database_on_windows/`](flutterfire_database_on_windows/) | The Windows sibling of the Linux app, on the same official `firebase_database` API with `firebase_database_dart_platform` replacing the native plugin: the same list by child events, push, edit, delete, a counter, presence, an offline write, an optional disk cache, and integration tests. Run on Windows 11 against the emulator. |
| [`playground/`](playground/) | A browser playground with no backend: the client runs with its network disabled on a memory cache, and the page shows each snapshot event, the writes waiting for a server and a timeline. Static files only, ready for any static host. Supported in Chrome, untested elsewhere. |

To pick one, start from where your code runs and follow the arrows:

```mermaid
flowchart TD
  start{"Where does your code run?"}
  start -- "a server or a container" --> serverKind{"How does it run?"}
  serverKind -- "answers HTTP requests" --> serverShelf["server_shelf"]
  serverKind -- "runs once and exits" --> cloudRunJob["cloud_run_job"]
  serverKind -- "runs until stopped, takes jobs" --> workerQueue["worker_queue"]
  start -- "a terminal" --> cli["cli"]
  start -- "a terminal, Cloud Storage" --> storageCli["storage_cli"]
  start -- "a Flutter app" --> flutterNotes["flutter_notes"]
  start -- "a Flutter web page" --> flutterWeb["flutter_web_two_users"]
  start -- "a browser, without Flutter" --> webApp["web_app"]
  start -- "I want one Firestore API topic" --> apiExamples["cloud_firestore_dart/example/"]
  start -- "I want a live tree, not documents" --> rtdbKind{"Where does your code run?"}
  rtdbKind -- "a server, one shared client" --> rtdbShelf["rtdb_server_shelf"]
  rtdbKind -- "a long-running worker" --> rtdbWorker["rtdb_presence_worker"]
  rtdbKind -- "a terminal" --> rtdbCli["rtdb_cli"]
  rtdbKind -- "a browser, without Flutter" --> rtdbWeb["rtdb_web_app"]
  rtdbKind -- "a browser, no backend" --> rtdbPlayground["rtdb_playground"]
  rtdbKind -- "a Flutter app on Linux" --> flutterDatabase["flutterfire_database_on_linux"]
  rtdbKind -- "a Flutter app on Windows" --> flutterDatabaseWindows["flutterfire_database_on_windows"]
  rtdbKind -- "I want one Database API topic" --> rtdbExamples["firebase_database_dart/example/"]
  start -- "I want files, not documents" --> storageKind{"Where does your code run?"}
  storageKind -- "a server, streaming bodies" --> serverShelf
  storageKind -- "a browser, without Flutter" --> webApp
  storageKind -- "a Flutter app on Linux" --> flutterStorage["flutterfire_storage_on_linux"]
  storageKind -- "a terminal" --> storageCli
  storageKind -- "I want one Storage API topic" --> storageExamples["firebase_storage_dart/example/"]
```

For the API one topic at a time, see
the programs in [`cloud_firestore/cloud_firestore_dart/example/`](../cloud_firestore/cloud_firestore_dart/example/README.md)
and, for Cloud Storage, those in
[`firebase_storage/firebase_storage_dart/example/`](../firebase_storage/firebase_storage_dart/example/README.md).
For the Realtime Database, the programs per topic (reads and writes, listeners, queries, transactions, `onDisconnect`,
server values, rules, and a cookbook) are in
[`firebase_database/firebase_database_dart/example/`](../firebase_database/firebase_database_dart/example/README.md).

## Running them

`server_shelf`, `cli`, `cloud_run_job` and `worker_queue` read the backend from the environment,
through the same `lib/firestore_from_env.dart` (`flutter_notes` and `web_app` have their own
READMEs):

- `FIRESTORE_EMULATOR_HOST=host:port`: the Firestore emulator. No credentials; the project
  is `demo-example` unless `FIREBASE_PROJECT_ID` says otherwise.
- Otherwise `FIREBASE_PROJECT_ID` (required), `FIRESTORE_DATABASE` (optional) and Application
  Default Credentials (`GOOGLE_APPLICATION_CREDENTIALS`, `gcloud auth application-default
  login`, or the metadata server on Google Cloud). These credentials bypass security rules.

No project id, key or token is in any file. `server_shelf`, `cli`, `cloud_run_job`, `storage_cli`,
`rtdb_cli`, `rtdb_server_shelf` and `playground` have a `test/` folder (`playground`'s needs no emulator); start an
emulator, then, in the example's directory:

```sh
dart pub get
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart test
```

The Realtime Database examples (`rtdb_*`, `flutterfire_database_on_linux` and `flutterfire_database_on_windows`) read the Database emulator from
`FIREBASE_DATABASE_EMULATOR_HOST=host:port`; the project is `demo-example`. Start one from the repository root on
port 9100 (it refuses the Firebase CLI's own 9000) and stop it when you are done:

```sh
tool/start_database_emulator.sh              # 127.0.0.1:9100
cd examples/rtdb_cli && dart pub get
FIREBASE_DATABASE_EMULATOR_HOST=127.0.0.1:9100 dart test
cd ../.. && tool/stop_database_emulator.sh
```

`rtdb_cli` and `rtdb_presence_worker` take `--emulator-host host:port` as well (`rtdb_cli` still accepts the older `--emulator`); `rtdb_server_shelf` and
`rtdb_presence_worker` take `FIREBASE_DATABASE_URL` for a real database (`rtdb_server_shelf` also accepts the older
`DATABASE_URL`), and `rtdb_cli` takes `--database-url`. None of them reaches a real database without it. The
no-backend exit code is `78` in all three.

## Status

- Run against the Firestore emulator (v1.22.0) on macOS with Dart 3.12.2, by their tests and
  by hand.
- The `rtdb_*` examples were run against the Database emulator, by hand (see each README); `rtdb_web_app` and `flutterfire_database_on_linux` are
  described in their READMEs (the Linux one builds on Linux x64; its integration tests have not yet passed in full there).
  `flutterfire_database_on_windows` passed its four integration tests on Windows 11.
- **Not run against a real Firebase project.** The Docker image of `cloud_run_job/` has not
  been built.
- `server_shelf`, `cli` and `cloud_run_job` take the three packages from this repository, with
  path dependencies and `dependency_overrides` in their `pubspec.yaml`, so they run against the
  code next to them. To use one outside the repository, replace both with the versions on pub.dev
  (`^0.2.0`). `worker_queue`, `flutter_notes`, `web_app` and `playground` depend on the versions on
  pub.dev (`^0.2.0`, and `cloud_firestore_dart_sqlite` `^0.1.0` for the SQLite cache of
  `flutter_notes` and `web_app`) and can be copied out as they are; they have no tests, except
  `playground`, which has a smoke test that needs no emulator.
- The `rtdb_*` packages take `firebase_app_dart` and `firebase_database_dart` from this repository (path
  dependencies or `dependency_overrides`); `rtdb_web_app` and `rtdb_presence_worker` declare `^0.2.0` and `^0.0.1`
  with overrides, so they also run against the code next to them.
- CI: `tool/test_all.sh` runs `dart pub get` and `dart analyze` for every `examples/*/pubspec.yaml`, and does not
  run their tests. `tool/build_gallery.sh` builds the web gallery (`playground`, `web_app`, `rtdb_web_app`,
  `rtdb_playground`) with dart2wasm and dart2js; no file in `.github/workflows/` calls it, and
  `.github/workflows/playground-pages.yml` publishes `playground` only.
- `firestore_from_env.dart` is copied, not shared, so that each directory can be copied out on
  its own.
