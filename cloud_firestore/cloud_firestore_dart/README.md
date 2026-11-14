# cloud_firestore_dart

An unofficial, pure-Dart client for [Cloud Firestore](https://firebase.google.com/docs/firestore):
real-time listeners, queries, transactions and an offline cache, without a Flutter plugin or
native code of its own. It is for Dart servers and command line tools, Flutter apps that want one
Dart implementation on every platform (including desktop), and, experimentally, the web.

It is a port of the open-source Firebase Android SDK, kept close to its current behaviour, with
parts of the API following the JS SDK and FlutterFire. It is not affiliated with or endorsed by
Google or Firebase.

> **Status: 0.1.0.** Most of it was verified against the Firestore emulator
> only. Against production Firestore, a short verification kit was run on a Standard edition
> database (see [Not done](#not-done)). Test against your own project before relying on it.

## Features

| Feature | Status |
| --- | --- |
| Documents, collections, collection groups, set / update / delete, write batches, field transforms | stable |
| Queries: filters, `Filter.or` / `Filter.and`, `orderBy`, cursors, `limit`, `limitToLast` | stable |
| Real-time listeners, snapshot metadata, `snapshotsInSync` | stable |
| Aggregations (`count`, `sum`, `average`), vector search (`findNearest`, server only) | stable |
| Transactions, read-only transactions with point-in-time reads | stable |
| Typed converters (`withConverter`), snapshots as JSON, data bundles | stable |
| Offline cache in SQLite (you supply the opener) or in memory; LRU garbage collection; cache indexes | stable |
| Several clients on one SQLite cache: consistent file, one primary client | stable, coordination not done |
| BSON value types of Enterprise edition databases | stable |
| Pipelines (`package:cloud_firestore_dart/pipelines.dart`), Enterprise edition only | **preview** |
| Firestore Lite (`package:cloud_firestore_dart/lite.dart`): no cache, one request per call | **experimental** |
| The web: REST and WebChannel over `fetch`, cache in memory, IndexedDB or OPFS | **experimental** |

*Stable* means the API is not expected to change; a *preview* or *experimental* API may change in
any release. Authentication is in the companion package
[`firebase_auth_providers_dart`](https://pub.dev/packages/firebase_auth_providers_dart); App Check
tokens can be supplied through the app.

**Platforms.** The Dart VM on macOS (developed and tested there) and Linux (tested in CI);
Windows is expected to work but is not tested. Flutter on Android, iOS and desktop, as a plain
Dart package. The web, experimentally: tested in Chrome only. Dart 3.8 or later.

## Install

```shell
dart pub add cloud_firestore_dart firebase_app_dart
```

## Quickstart

```dart
import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';

Future<void> main() async {
  final app = FirebaseApp.withOptions(const FirebaseOptions(
      apiKey: '<API key>', applicationId: '1:1234567890:web:abc', projectId: 'my-project'));
  final firestore = Firestore.instanceFor(app: app);
  await firestore.doc('cities/SF').set({'name': 'San Francisco', 'state': 'CA'});
  final cities = await firestore.collection('cities').where('state', isEqualTo: 'CA').get();
  print(cities.docs.map((city) => city.data));
  await firestore.terminate(); // a VM program exits once its instances are terminated
}
```

## Documentation

- **Guides** ([all guides](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/guides/README.md)):
  [getting started](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/guides/getting_started.md),
  [queries, data and the API](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/guides/queries_and_data.md),
  [transactions and the lifecycle](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/guides/transactions_and_lifecycle.md),
  [offline persistence and cache settings](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/guides/offline_persistence.md),
  [several clients on one cache](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/guides/multiple_clients.md),
  [authentication and App Check](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/guides/authentication.md),
  [Pipelines](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/guides/pipelines.md),
  [Firestore Lite](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/guides/lite.md),
  [platforms](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/guides/platforms.md),
  [the emulator and testing](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/guides/emulator_and_testing.md),
  and [features and limits](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/guides/features.md).
- **API reference**: [pub.dev/documentation/cloud_firestore_dart](https://pub.dev/documentation/cloud_firestore_dart/latest/).
- **Examples**: one runnable program per topic in
  [`example/`](https://github.com/long1eu/firebase_dart_sdk/blob/main/cloud_firestore/cloud_firestore_dart/example/README.md).
- **Coming from FlutterFire** (`cloud_firestore`):
  [migration guide](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/guides/migrating_from_flutterfire.md).
- **Parity with the Android and JS SDKs**: [docs/parity.md](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/parity.md).
- **How it is tested**: [docs/how_we_test.md](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/how_we_test.md);
  supported SDKs and platforms: [docs/support_policy.md](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/support_policy.md).

**Coming from `cloud_firestore_vm`?** This package was published as
[`cloud_firestore_vm`](https://pub.dev/packages/cloud_firestore_vm), and its app layer as
[`firebase_core_vm`](https://pub.dev/packages/firebase_core_vm). The
[migration guide](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/migrating_from_vm_packages.md)
has the changes with before and after code.

## Not done

- **Production.** Most of the testing is against the emulator. The production verification kit
  (`tool/verify_production` in the repository) was run against a real Firestore database in
  Standard edition: 13 of its 15 checks passed in one run and 2 were skipped (one needs an
  Enterprise edition database, the other a Web API key with anonymous sign-in). An earlier run
  found one bug of this SDK, which is fixed (-0.0 read over the web transport lost its sign). Not
  verified against
  production: the Enterprise edition features (only against the Enterprise edition emulator),
  Firebase Auth user sign-in, the integration suite as a whole and long-running load.
- **Coordination between clients that share one cache** (the multi-tab support of the JS SDK):
  clients keep the file consistent and elect a primary, but do not share listeners or writes;
  in a browser, one tab at a time. Sharing them (stage 3 of the multi-client plan: shared state
  in SQLite between isolates and processes, and the tab manager settings of the JS SDK) is
  deferred until after 0.1.0.
- **Pipelines** beyond the preview: evaluation against the local cache, and real-time pipelines.
- **The web** beyond the experiment: browsers other than Chrome, and a cache shared between tabs.
- `findNearest` evaluation against the local cache, and cache indexes for queries with
  inequalities on several fields.
- A Firebase Auth SDK: sign-in with email and password, anonymously or with custom tokens, and
  server credentials, are in `firebase_auth_providers_dart`; federated sign-in is not.

The full list, with the known gaps of what is done, is in
[features and limits](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/guides/features.md).

## Package history

This is the same package as `cloud_firestore_dart` 0.0.1 on pub.dev, published in April 2020
from the same repository (then under the fluttercommunity organisation on GitHub). Development
of that early port went on under the name `cloud_firestore_vm` (0.0.1 to 0.0.7, April 2020); its
last change was in August 2020. Version 0.1.0 is the revived port, rebuilt on Dart 3 with sound null safety and
brought forward to the current upstream Firestore SDKs; it goes back to this name. Code written
for 0.0.1 or for `cloud_firestore_vm` needs the changes in the
[migration guide](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/migrating_from_vm_packages.md).

## License

Apache License 2.0; see `LICENSE` and `NOTICE`. `cloud_firestore_vm` was licensed under BSD-3-Clause.

Issues and pull requests: https://github.com/long1eu/firebase_dart_sdk
