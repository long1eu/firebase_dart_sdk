# Firebase Dart SDK: Cloud Firestore for pure Dart

[![CI](../../actions/workflows/ci.yml/badge.svg)](../../actions/workflows/ci.yml)
[![Nightly](../../actions/workflows/nightly.yml/badge.svg)](../../actions/workflows/nightly.yml)

An unofficial Cloud Firestore client written only in Dart, with real-time listeners, queries, transactions and
an offline cache, for the places the official FlutterFire plugins do not reach. It is not affiliated with or
endorsed by Google or Firebase.

**Use it when**, most proven first ([the evidence](docs/why_this_library.md)):

1. **You build a Flutter app for Linux desktop.** FlutterFire has no Linux implementation and says it is not
   on its roadmap. Add `cloud_firestore_dart_platform` and keep the official `cloud_firestore` API. Caveat:
   one app was built and run on Debian 13 x86_64, a debug build against the emulator only.
2. **You write a Dart server, worker or CLI that needs listeners, an offline cache, or to act as a signed-in
   Firebase user under security rules.** The official Dart Admin SDK has no listeners and always bypasses
   rules. Caveat: it has draft PRs for listeners since 2026-11-09, so that part of the gap may close.
3. **You need a Firestore listener on a background isolate of a Flutter app.** FlutterFire does not support it
   and closed the request as not planned. Caveat: tested in isolates on the Dart VM, not in a Flutter app.
4. **You want to test Firestore code with `dart test` or `flutter test` against the emulator, running a real
   client instead of a fake.** Caveat: the test runs this engine, not the Android or iOS SDK your app ships.

**Do not use it when**

- FlutterFire already works for you on Android, iOS or the web: Google's SDKs come with support and years of
  production use. This client was checked against a real database only by a 15-check kit.
- You ship a Windows app and cannot test it yourself first: it was run on one Windows 11 VM against the
  emulator only (the Dart VM suites and two Flutter debug apps, no window drawn), not in CI, not in a
  release build and not against production.
- You need federated, phone or email-link sign-in, multi-factor, Storage, Messaging or the other Firebase
  services, or admin jobs such as bulk writes and recursive deletes (use `firebase_admin_sdk`).
- You need a vendor to call: one person maintains it, with no SLA.

**Start** with the emulator (`firebase emulators:start --only firestore --project demo-my-app`):

```shell
dart pub add cloud_firestore_dart firebase_app_dart
```

```dart
import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';

final FirebaseApp app = FirebaseApp.withOptions(
  const FirebaseOptions(apiKey: 'demo-key', appId: '1:1234567890:dart:demo', projectId: 'demo-my-app'),
);
final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
  app: app,
  settings: Settings().withEmulator('127.0.0.1', 8080), // drop this line for a real project
);

await firestore.collection('users').doc('ada').set({'name': 'Ada', 'age': 36});
firestore
    .collection('users')
    .where('age', isGreaterThan: 30)
    .snapshots()
    .listen((snapshot) => print(snapshot.docs.length));
```

In a Flutter app that already uses `cloud_firestore`, add `cloud_firestore_dart_platform` instead: on Linux
it registers itself, elsewhere one call turns it on ([guide](docs/guides/flutterfire_platform.md)). Coming
from 0.1? The 0.2 API took FlutterFire's names: [what changed](docs/api_migration_0_2.md).

| Package | pub.dev | Who needs it |
|---|---|---|
| [`cloud_firestore_dart`](cloud_firestore/cloud_firestore_dart/) | 0.2.0 | Any Dart program, server or Flutter app that calls Firestore through this client |
| [`firebase_app_dart`](firebase_core/firebase_app_dart/) | 0.2.0 | Every user of `cloud_firestore_dart`: the `FirebaseApp` and its options |
| [`firebase_auth_providers_dart`](firebase_auth/firebase_auth_providers_dart/) | 0.2.1 | Apps with signed-in users, and servers with a service account or Application Default Credentials |
| [`cloud_firestore_dart_sqlite`](cloud_firestore/cloud_firestore_dart_sqlite/) | 0.1.1 | Anyone who wants the offline cache on disk instead of in memory |
| [`cloud_firestore_dart_platform`](cloud_firestore/cloud_firestore_dart_platform/) | 0.1.0 | Flutter apps written against the official `cloud_firestore` API, on Linux or by choice elsewhere |
| [`cloud_firestore_dart_flutterfire`](cloud_firestore/cloud_firestore_dart_flutterfire/) | 0.1.0 | Flutter apps that sign in with `firebase_auth` and want `cloud_firestore_dart` to use that user |
| [`firebase_admin_dart`](firebase_admin/firebase_admin_dart/) | 0.1.0 | Servers, tools and integration tests that mint custom tokens, manage users or verify ID tokens |

## How it fits together

It is a port of the open-source [Firebase Android SDK](https://github.com/firebase/firebase-android-sdk),
including its offline cache, listeners with local-write snapshots, transactions and retry logic, on Dart 3
with `dart:io`, gRPC and SQLite; no Flutter plugin and no native SDK. Your program creates a `FirebaseApp`, an
optional token provider plugs into it, and `cloud_firestore_dart` talks to Firestore over gRPC on the Dart VM
and in Flutter, or over REST and WebChannel in the browser (supported in Chrome).

![Your Dart program, Flutter app or browser app uses three packages: firebase_auth_providers_dart sets the token provider of the FirebaseApp from firebase_app_dart, and cloud_firestore_dart is created from that app. cloud_firestore_dart reaches Cloud Firestore or the emulator over gRPC on the VM and in Flutter, and over REST and WebChannel in the browser.](https://raw.githubusercontent.com/long1eu/firebase_dart_sdk/main/docs/images/readme/overview.svg)

See the [guides](docs/guides/README.md) for more and `cloud_firestore/cloud_firestore_dart/example/main.dart`
for a runnable program.

## Start here

- [Parity with upstream Firestore](docs/parity.md): what matches the Android and JS SDKs, and
  what does not.
- [Migrating from FlutterFire](docs/guides/migrating_from_flutterfire.md) (`cloud_firestore`), and
  [what changed in 0.2](docs/api_migration_0_2.md).
- [Why this library](docs/why_this_library.md): where it is the better or the only choice, with the
  evidence, and when not to use it.
- [Example apps](examples/README.md): an HTTP server with a live change feed, a command-line
  import, export and watch tool, a Cloud Run job, a worker queue, a Flutter app and a browser app.
- [`examples/playground/`](examples/playground/): try the client in a browser with no backend and no
  Firebase project, and see its snapshot events and pending writes.
- [For AI coding agents](docs/guides/for_ai_agents.md), [llms.txt](llms.txt) and an
  [Agent Skill](skills/README.md).
- [API examples](cloud_firestore/cloud_firestore_dart/example/): short runnable programs, listed
  in [example/README.md](cloud_firestore/cloud_firestore_dart/example/README.md).
- [How we test](docs/how_we_test.md): the suites, how to run them, and bugs they caught.
- [Support policy](docs/support_policy.md): supported Dart SDKs and platforms, how upstream
  changes are tracked, versioning.

## What it does

- Documents, collections, collection groups, typed data converters (`withConverter`), queries
  with `!=`, `not-in`, OR / AND filters, `limitToLast`, cursors and aggregations (count, sum,
  average).
- Real-time listeners, offline persistence in SQLite (index-free queries, document overlays),
  write queue with pending-write snapshots, `waitForPendingWrites`, `snapshotsInSync()`,
  `terminate`, `clearPersistence`.
- Transactions (read-write and read-only) with retry and backoff, write batches, field transforms
  (server timestamp, increment, min/max, array union/remove).
- Data bundles and named queries, snapshots as JSON (in the format of the JS SDK), vector values
  with `findNearest`, App Check token plumbing, emulator support with a mock user token.
- Persistent cache indexes (`persistentCacheIndexManager`, `setIndexConfigurationFromJSON`), and a
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

Without a connection, the client answers from its cache and queues writes; what needs the backend
fails until it is reachable again:

![Works offline: get() and listeners from the cache, Source.cache and ListenSource.cache, set, update, delete and batches queued and sent later, pending writes kept across restarts with the SQLite cache, loadBundle and named queries. Needs the backend: transactions, count, sum and average, findNearest, Pipelines, get(Source.server) and Firestore Lite.](https://raw.githubusercontent.com/long1eu/firebase_dart_sdk/main/docs/images/readme/offline.svg)

## Guides

[docs/guides](docs/guides/README.md): getting started (VM, Flutter, web), queries and data,
transactions and the lifecycle, offline persistence and cache settings, several clients on one
cache, authentication and App Check, Pipelines (preview, Enterprise only), Firestore Lite,
platforms, the emulator and testing, configuring the `FirebaseApp`, features and limits, and
migrating from the `_vm` packages.

## Status

The original port stopped at the 2019 Android SDK and the repository was archived in 2021. Since
November 2026 it follows the Android SDK's behaviour up to late 2026, on Dart 3.8 or later, and
its public API follows FlutterFire and the JS SDK. It has about 5,900 unit tests and about 880
integration tests per transport (gRPC, WebChannel, WebChannel with long polling) against the
Firestore emulator ([how we test](docs/how_we_test.md)).

**Issues:** <https://github.com/long1eu/firebase_dart_sdk/issues>.

**Maintenance:** _[MAINTAINER: one sentence on who maintains this project and how. Not written
yet.]_

- **Tested mostly against the Firestore emulator.** Against production, only the production
  verification kit (`tool/verify_production`) was run, on a real Firestore database in Standard
  edition: 13 of its 15 checks passed in one run and 2 were skipped (one needs an Enterprise
  edition database, the other a Web API key with anonymous sign-in). An earlier run found one bug
  of this SDK, which is fixed (-0.0 read over the web transport lost its sign). Not verified
  against production: the Enterprise edition features (BSON value types, Pipelines; tested
  against the emulator in Enterprise edition only), Firebase Auth user sign-in, the integration
  suite as a whole and long-running load. Test against your own project before relying on it.
- Platforms: the Dart VM on macOS and Linux (CI on Ubuntu x64, a Debian arm64 container). In
  Flutter: an app with this client was built and run on macOS, and an app on the official
  `cloud_firestore` API with `cloud_firestore_dart_platform` on Debian 13 x86_64, both against
  the emulator only. On Windows 11 x64 (one VM, against the emulator): the unit and standard
  integration suites on the Dart VM, and two Flutter debug apps (`flutter_notes`, and
  `flutterfire_on_windows` on the official `cloud_firestore` API), driven from an SSH session
  without a drawn window. Never run: Android or iOS (devices or emulators), embedded Linux, a
  Linux or Windows release build, Windows in CI.
- `cloud_firestore_dart` 0.0.1 on pub.dev (2020) is an early release of the same package. The
  packages replace the ones published as `cloud_firestore_vm` and `firebase_core_vm` (and the
  internal `_firebase_internal_vm` and `_firebase_database_collection_vm`, now folded in). See
  [docs/migrating_from_vm_packages.md](docs/migrating_from_vm_packages.md).
- Web is supported in Chrome. In a browser the client uses REST and WebChannel over `fetch`
  instead of gRPC, with a memory cache or an opt-in SQLite cache in IndexedDB. The browser tests
  pass in Chrome against the emulator (dart2wasm and dart2js), and the whole standard
  integration suite passes on the VM over the web transport. A Flutter web app with two signed-in
  users in one page ([`examples/flutter_web_two_users`](examples/flutter_web_two_users/)) is built
  with dart2js and dart2wasm in CI and was driven in headless Chrome against the emulators. No
  other browser was tried, and no browser was run against a production backend (the verification
  kit used the web transport against production from the VM).
- Not implemented: coordination between clients that share one cache (the multi-tab support of
  the JS SDK; deferred until after 0.1.0), a full Firebase Auth SDK (no federated sign-in), and
  Pipelines beyond the preview (no real-time pipelines and no offline evaluation; a local
  evaluator exists but is internal and not used yet; search, window functions and explain
  options are only checked for their encoding, since the emulator rejects them).
  [docs/guides/features.md](docs/guides/features.md) lists the known gaps.

This repository ports Firestore and the Firebase Core pieces it needs, plus token providers for
Firestore in `firebase_auth/firebase_auth_providers_dart` and a few Firebase Auth admin calls in
`firebase_admin/firebase_admin_dart`. There is no full Auth SDK, no Storage
and no Realtime Database client here; for those see
[appsup-dart/firebase_dart](https://github.com/appsup-dart/firebase_dart). The other directories
under `firebase_auth`, and `firebase_storage_dart` and `google_sign_in_dart`, are older code from
the original project and are not part of the migrated, tested set.

## Packages

The table at the top lists the packages. `cloud_firestore_dart` was formerly `cloud_firestore_vm` and
`firebase_app_dart` was `firebase_core_vm`. `firebase_admin_dart` 0.1.0 is checked with unit
tests and the Auth emulator; on 2026-11-18 its main path also passed against one real project, keyless
(Application Default Credentials of a person, custom tokens signed by IAM `signBlob`). Local signing with
a key file, `findUserByEmail`, `updateUser`, `deleteUsers` and tenants were not run against a real
project. The former internal packages are folded in:
`_firebase_database_collection_vm` into `cloud_firestore_dart` (`lib/src/database_collection`) and
`_firebase_internal_vm` into `firebase_app_dart` (`package:firebase_app_dart/internal.dart`, not public API).
`cloud_firestore_dart` depends on the hosted `firebase_app_dart`; inside this repository its
`pubspec_overrides.yaml` points it at the sibling directory.

## Running the tests

Unit tests (pub get, analyze `lib`, and tests for the three packages, only `test/unit` for
Firestore; then pub get and analyze for each example in `examples/`, whose tests need an
emulator):

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
was done on a Standard edition database (the results are in that README).

See `tool/README.md` for details, [docs/how_we_test.md](docs/how_we_test.md) for an overview of
all the suites, and "Against a real Firebase project" in
[docs/guides/emulator_and_testing.md](docs/guides/emulator_and_testing.md) for the opt-in run of
the integration suite against a real project.

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
depth are marked unverified there. The top of that file has the current status. Behaviour is
ported in Dart, not copied verbatim.

## Architecture

[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) maps the layers of the client to the upstream code,
describes the test suites and lists the deliberate deviations from upstream with the tests that
pin them.

## Contributing

Issues and pull requests are welcome. Before opening a pull request, run `./tool/test_all.sh`
and, for changes that touch networking or the local store, the emulator integration tests. Do not
weaken or remove assertions to get a test passing; report flaky tests instead.

`lib` and `example` of the three packages are kept formatted with `dart format lib example`
(run it in the package directory; CI checks it with
`dart format --output=none --set-exit-if-changed lib example` on a pinned Dart SDK,
currently 3.8.0, the lowest supported one). Do not format
`test/readme/readme_snippets.dart`, which is generated from the README.

## License

`cloud_firestore_dart`, `firebase_app_dart`, `firebase_auth_providers_dart`, `cloud_firestore_dart_sqlite`,
`cloud_firestore_dart_flutterfire`, `cloud_firestore_dart_platform` and `firebase_admin_dart` are licensed under
the Apache License 2.0, as upstream; see the `LICENSE` and `NOTICE` files of each package. The
`_vm` packages they replace were licensed under BSD-3-Clause. The packages of this repository
that were not migrated keep their own `LICENSE` files.
