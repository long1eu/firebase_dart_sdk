# Firebase Dart SDK: Cloud Firestore for pure Dart

A pure-Dart client for Cloud Firestore: no Flutter plugin, no native SDK, just `dart:io`, gRPC and
SQLite. Use it from Dart servers, CLIs and Flutter apps.

It is an unofficial port of the open-source
[Firebase Android SDK](https://github.com/firebase/firebase-android-sdk), including its offline
cache, listeners with local-write snapshots, transactions and retry logic. It is not affiliated
with or endorsed by Google or Firebase.

```dart
import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

final firestore = await Firestore.instanceFor(app: app);
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
dart pub add cloud_firestore_dart firebase_app_dart
```

## What it does

- Documents, collections, collection groups, queries with `!=`, `not-in`, OR / AND filters,
  `limitToLast`, cursors and aggregations (count, sum, average).
- Real-time listeners, offline persistence in SQLite, write queue with pending-write snapshots,
  `waitForPendingWrites`, `snapshotsInSync`, `terminate`.
- Transactions (read-write and read-only) with retry and backoff, write batches, field transforms
  (server timestamp, increment, min/max, array union/remove).
- Data bundles and named queries, vector values with `findNearest`, App Check token plumbing.

## Status

Revival of the original port, which stopped at the 2019 Android SDK; it now follows the Android
SDK's behaviour up to late 2026 on Dart 3 with sound null safety.

- **Tested against the Firestore emulator only. Nothing has been run against production Firestore.**
  Treat it as untested there, and test against your own project before relying on it.
- Version 0.1.0 is prepared for pub.dev as `cloud_firestore_dart` and `firebase_app_dart`. They
  replace the packages published as `cloud_firestore_vm` and `firebase_core_vm` (and the internal
  `_firebase_internal_vm` and `_firebase_database_collection_vm`, now folded in).
- Not implemented: BSON value types, index-free queries and overlays, the client-side index engine,
  clearing persistence (API undecided), Pipelines. Web is not supported yet (the transport uses native gRPC from `dart:io`; web
  support is planned).
- The JS SDK is the reference for the public API of other Firebase clients. A comparison and a
  roadmap are in `docs/` notes; typed converters (`withConverter`) are the main API gap.

This repository ports Firestore and the Firebase Core pieces it needs. There is no Auth, Storage or
Realtime Database client here; for those see
[appsup-dart/firebase_dart](https://github.com/appsup-dart/firebase_dart). The `firebase_auth`,
`firebase_storage_dart` and `google_sign_in_dart` directories are older code from the original project and
are not part of the migrated, tested set.

## Packages

| Package | Path | Purpose |
|---|---|---|
| `cloud_firestore_dart` | `cloud_firestore/cloud_firestore_dart` | The Firestore client (formerly `cloud_firestore_vm`) |
| `firebase_app_dart` | `firebase_core/firebase_app_dart` | `FirebaseApp` and options (formerly `firebase_core_vm`) |

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

    ./tool/start_emulator.sh        # emulator on 127.0.0.1:8080, project demo-test
    cd cloud_firestore/cloud_firestore_dart
    FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart test test/integration
    cd ../..
    ./tool/stop_emulator.sh

See `tool/README.md` for details.

## Regenerating protos

    dart pub global activate protoc_plugin 21.1.2
    cloud_firestore/cloud_firestore_dart/tool/gen_protos.sh

If the installed `protoc` is unusable, set up the Python wrapper (instructions at the top of
`tool/protoc_wrap.sh`) and run:

    PROTOC="$PWD/tool/protoc_wrap.sh" cloud_firestore/cloud_firestore_dart/tool/gen_protos.sh

## Upstream sync

[`docs/upstream_sync/UPSTREAM_PLAN.md`](docs/upstream_sync/UPSTREAM_PLAN.md) lists the
upstream Android SDK commits since the sync point, triaged per commit (`analysis_0.md` to
`analysis_4.md`), and the order in which they are being ported. Rows the analysis did not read in
depth are marked unverified there. The top of that file has the current done/deferred status. Behaviour is ported in Dart, not copied verbatim.

## Contributing

Issues and pull requests are welcome. Before opening a pull request, run `./tool/test_all.sh`
and, for changes that touch networking or the local store, the emulator integration tests. Do not
weaken or remove assertions to get a test passing; report flaky tests instead.

## License

Apache License 2.0, as upstream. See the `LICENSE` file in each package.
