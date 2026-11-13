# Firebase Dart SDK: Cloud Firestore for pure Dart

A pure-Dart client for Cloud Firestore: no Flutter plugin, no native SDK, just `dart:io`, gRPC and
SQLite. Use it from Dart servers, CLIs and Flutter apps. (Web support is experimental.)

It is an unofficial port of the open-source
[Firebase Android SDK](https://github.com/firebase/firebase-android-sdk), including its offline
cache, listeners with local-write snapshots, transactions and retry logic. It is not affiliated
with or endorsed by Google or Firebase.

```dart
import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

final firestore = Firestore.instanceFor(app: app);
await firestore.collection('users').doc('ada').set({'name': 'Ada', 'age': 36});

firestore
    .collection('users')
    .where(Filter.or([
      Filter.equalTo('role', 'admin'),
      Filter.greaterThan('age', 40),
    ]))
    .limit(10)
    .snapshots
    .listen((snapshot) => print(snapshot.docs.length));
```

(`app` is a `FirebaseApp` from `firebase_app_dart`; see the
[package README](cloud_firestore/cloud_firestore_dart/README.md) for current examples and
`cloud_firestore/cloud_firestore_dart/example/main.dart` for a runnable program.)

```shell
dart pub add cloud_firestore_dart firebase_app_dart   # once 0.1.0 is published; it is not yet
```

## What it does

- Documents, collections, collection groups, typed data converters (`withConverter`), queries
  with `!=`, `not-in`, OR / AND filters, `limitToLast`, cursors and aggregations (count, sum,
  average).
- Real-time listeners, offline persistence in SQLite (index-free queries, document overlays),
  write queue with pending-write snapshots, `waitForPendingWrites`, `snapshotsInSync`,
  `terminate`, `clearPersistence`.
- Transactions (read-write and read-only) with retry and backoff, write batches, field transforms
  (server timestamp, increment, min/max, array union/remove).
- Data bundles and named queries, snapshots as JSON (in the format of the JS SDK), vector values
  with `findNearest`, App Check token plumbing, emulator support with a mock user token.
- Persistent cache indexes (`persistentCacheIndexManager`, `setIndexConfiguration`), and a
  built-in detector of connectivity changes on the VM.
- For Enterprise edition databases: the BSON value types, and Pipelines as a preview library
  (executed by the server).
- Two clients on the same SQLite cache file (a hot restart, a background isolate) keep it
  consistent.
- Authentication through a token provider on the `FirebaseApp`; ready-made ones (Firebase Auth
  sign-in over REST, service accounts, Application Default Credentials) are in
  `firebase_auth_providers_dart`.
- Firestore Lite (experimental, `package:cloud_firestore_dart/lite.dart`): a client without
  cache and listeners where every call is one request.

## Status

Revival of the original port, which stopped at the 2019 Android SDK; it now follows the Android
SDK's behaviour up to late 2026 on Dart 3 (`cloud_firestore_dart` needs Dart 3.8) with sound
null safety, and parts of its public API follow the JS SDK.

- **Tested against the Firestore emulator only. Nothing has been run against production Firestore.**
  Treat it as untested there, and test against your own project before relying on it. The
  Enterprise edition features (BSON value types, Pipelines) were tested against the emulator in
  Enterprise edition only.
- Version 0.1.0 is prepared for pub.dev as `cloud_firestore_dart` and `firebase_app_dart`, and is
  **not published yet**. They replace the packages published as `cloud_firestore_vm` and
  `firebase_core_vm` (and the internal `_firebase_internal_vm` and
  `_firebase_database_collection_vm`, now folded in). See
  [docs/migrating_from_vm_packages.md](docs/migrating_from_vm_packages.md).
- Web support is experimental. In a browser the client uses REST and WebChannel over `fetch`
  instead of gRPC, with a memory cache or an opt-in SQLite cache in IndexedDB. The browser tests
  pass in Chrome against the emulator (dart2wasm and dart2js), and the whole standard
  integration suite passes on the VM over the web transport. No other browser and no production backend was
  tried.
- A production verification kit exists (`tool/verify_production`) and passes against the
  emulators; **it has not been run against a real project**.
- Not implemented: coordination between clients that share one cache (the multi-tab support of
  the JS SDK), a full Firebase Auth SDK (no federated sign-in), and Pipelines beyond the preview
  (no search stage, no window functions, no real-time pipelines; a local evaluator exists but
  is internal and not used yet). The package README lists the known gaps.

This repository ports Firestore and the Firebase Core pieces it needs, plus token providers for
Firestore in `firebase_auth/firebase_auth_providers_dart`. There is no full Auth SDK, no Storage
and no Realtime Database client here; for those see
[appsup-dart/firebase_dart](https://github.com/appsup-dart/firebase_dart). The other directories
under `firebase_auth`, and `firebase_storage_dart` and `google_sign_in_dart`, are older code from
the original project and are not part of the migrated, tested set.

## Packages

| Package | Path | Purpose |
|---|---|---|
| `cloud_firestore_dart` | `cloud_firestore/cloud_firestore_dart` | The Firestore client (formerly `cloud_firestore_vm`) |
| `firebase_app_dart` | `firebase_core/firebase_app_dart` | `FirebaseApp` and options (formerly `firebase_core_vm`) |
| `firebase_auth_providers_dart` | `firebase_auth/firebase_auth_providers_dart` | Optional token providers: Firebase Auth users over REST, service accounts, Application Default Credentials (not published) |

The former internal packages are folded in: `_firebase_database_collection_vm` into
`cloud_firestore_dart` (`lib/src/database_collection`) and `_firebase_internal_vm` into
`firebase_app_dart` (`package:firebase_app_dart/internal.dart`, not public API).
`cloud_firestore_dart` depends on the hosted `firebase_app_dart`; inside this repository its
`pubspec_overrides.yaml` points it at the sibling directory.

## Running the tests

Unit tests (pub get, analyze `lib`, and tests for both packages; only `test/unit` for
Firestore):

    ./tool/test_all.sh

Integration tests need the Firestore emulator. Java and Node are required. Install the Firebase
CLI locally once:

    mkdir -p .emulator && cd .emulator && npm init -y && npm install firebase-tools && cd ..

Then:

    ./tool/start_emulator.sh              # emulator on 127.0.0.1:8080, project demo-test
    ./tool/test_integration.sh standard   # dart test test/integration against it
    ./tool/stop_emulator.sh

Tests that need the Enterprise edition of Firestore use a second emulator on port 8181. The
same command also runs the standard suite against it:

    ./tool/start_enterprise_emulator.sh
    ./tool/test_integration.sh enterprise # test/integration, then test/integration_enterprise
    ./tool/stop_enterprise_emulator.sh

`./tool/test_integration.sh both` runs the two when both emulators are up. To run tests by
hand, from `cloud_firestore/cloud_firestore_dart`:

    FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart test test/integration
    FIRESTORE_ENTERPRISE_EMULATOR_HOST=127.0.0.1:8181 dart test test/integration_enterprise

The web transport and the browser tests use a private emulator on port 8090, which the scripts
start themselves:

    ./tool/test_integration.sh standard --transport=webchannel   # the suite on the VM, over REST and WebChannel
    ./tool/test_browser.sh both                                  # test/browser in Chrome, dart2wasm and dart2js

Two more checks:

    ./tool/check_size.sh                                         # Firestore Lite stays small and free of the sync engine
    FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 ./tool/verify_production/run.sh --backend=emulator

The last one is the production verification kit run against the emulator. Against a real project
it only runs with your own credentials and `--yes` (see `tool/verify_production/README.md`); that
has not been done yet.

See `tool/README.md` for details, and the Testing section of
`cloud_firestore/cloud_firestore_dart/README.md` for the opt-in run of the integration suite
against a real project.

## Regenerating protos

    dart pub global activate protoc_plugin 25.1.0   # generates code for protobuf 6.x
    cloud_firestore/cloud_firestore_dart/tool/gen_protos.sh

If the installed `protoc` is unusable, set up the Python wrapper (instructions at the top of
`tool/protoc_wrap.sh`) and run:

    PROTOC="$PWD/tool/protoc_wrap.sh" cloud_firestore/cloud_firestore_dart/tool/gen_protos.sh

## Upstream sync

[`docs/upstream_sync/UPSTREAM_PLAN.md`](docs/upstream_sync/UPSTREAM_PLAN.md) lists the
upstream Android SDK commits since the sync point, triaged per commit (`analysis_0.md` to
`analysis_4.md`), and the order in which they are being ported. Rows the analysis did not read in
depth are marked unverified there. The top of that file has the current status. Behaviour is ported in Dart, not copied verbatim.

## Architecture

[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) maps the layers of the client to the upstream code,
describes the test suites and lists the deliberate deviations from upstream with the tests that
pin them.

## Contributing

Issues and pull requests are welcome. Before opening a pull request, run `./tool/test_all.sh`
and, for changes that touch networking or the local store, the emulator integration tests. Do not
weaken or remove assertions to get a test passing; report flaky tests instead.

`lib` and `example` of both packages are kept formatted with `dart format lib example` (run it in
the package directory; CI checks it with
`dart format --output=none --set-exit-if-changed lib example` on a pinned Dart SDK,
currently 3.8.0, the lowest supported one). Do not format
`test/readme/readme_snippets.dart`, which is generated from the README.

## License

Apache License 2.0, as upstream. See the `LICENSE` file in each package.
