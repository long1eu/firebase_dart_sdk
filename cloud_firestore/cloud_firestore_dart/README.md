# cloud_firestore_dart

An unofficial Cloud Firestore client written only in Dart: real-time listeners, queries, transactions and an
offline cache, with FlutterFire's API names (`FirebaseFirestore.instanceFor`, `collection`, `snapshots()`)
and no native code. It is not affiliated with or endorsed by Google or Firebase.

Use it for a Dart server, worker or command-line tool that needs listeners, an offline cache, or to act as a
signed-in Firebase user under security rules; for a Firestore listener on a background isolate of a Flutter
app; or to test Firestore code with `dart test` against the emulator, running the real client. For a Flutter
app on Linux that uses the official `cloud_firestore` API, add
[`cloud_firestore_dart_platform`](https://pub.dev/packages/cloud_firestore_dart_platform), which runs on this
package. On Android, iOS and the web, where the official plugin works, prefer it.

It is a port of the open-source Firebase Android SDK, kept close to its current behaviour. Start with
`dart pub add cloud_firestore_dart firebase_app_dart` and the [Quickstart](#quickstart).

> **Status: 0.3.1.** Most of it was verified against the Firestore emulator
> only. Against production Firestore, a short verification kit was run on a Standard edition
> database (see [Not done](#not-done)). Test against your own project before relying on it.

## Features

| Feature | Status |
| --- | --- |
| Documents, collections, collection groups, set / update / delete, write batches, field transforms | stable |
| Queries: filters, `Filter.or` / `Filter.and`, `orderBy`, cursors, `limit`, `limitToLast` | stable |
| Real-time listeners, snapshot metadata, `snapshotsInSync()` | stable |
| Aggregations (`count`, `sum`, `average`), vector search (`findNearest`, server only) | stable |
| Transactions, read-only transactions with point-in-time reads | stable |
| Typed converters (`withConverter`), snapshots as JSON, data bundles | stable |
| Offline cache in SQLite (you supply the opener) or in memory; LRU garbage collection; cache indexes | stable |
| Several clients on one SQLite cache: consistent file, one primary client | stable, coordination not done |
| Merging repeated offline writes to a document into one pending write (`mergeUnsentWrites`, off by default): not in the official SDKs, the backend ends with the same documents but rules and functions see fewer writes ([guide](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/guides/offline_persistence.md#merging-repeated-offline-writes-opt-in-extension)) | supported, opt-in extension |
| BSON value types of Enterprise edition databases | stable |
| Pipelines (`package:cloud_firestore_dart/pipelines.dart`), Enterprise edition only | **preview** |
| Firestore Lite (`package:cloud_firestore_dart/lite.dart`): no cache, one request per call | stable |
| The web: REST and WebChannel over `fetch`, cache in memory, IndexedDB or OPFS | **supported in Chrome** |
| The web: a cache in the official JS SDK's own IndexedDB database (`package:cloud_firestore_dart/indexeddb_cache.dart`), no SQLite | **supported in Chrome**, one tab; several tabs with `multiTab: true` (**preview**, new in the next version) |
| A cache in your own storage: any ordered key-value store you implement (`package:cloud_firestore_dart/cache_store.dart`, [guide](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/guides/custom_cache_store.md)) | stable, one client per store |

*Stable* means the API is not expected to change; a *preview* API may change in
any release. Authentication is in the companion package
[`firebase_auth_providers_dart`](https://pub.dev/packages/firebase_auth_providers_dart); App Check
tokens can be supplied through the app.

**Platforms.** The Dart VM on macOS (developed and tested there) and Linux (tested in CI);
Windows is expected to work but is not tested. Flutter on Android, iOS and desktop, as a plain
Dart package. The web: supported in Chrome, tested against the emulator; Firefox, Safari and Edge are untested. Dart 3.8 or later.

Inside the package, every call goes through one queue to the local cache and to the network; the
transport depends on the platform, and Firestore Lite skips the cache:

![Layers of cloud_firestore_dart: the public API; the client with its event manager and sync engine on one serial queue; the local store (memory or SQLite cache) next to the network layer (listen stream, write stream, one-shot calls); the transport, gRPC on the VM and in Flutter or REST and WebChannel in the browser; then Cloud Firestore or the emulator. Firestore Lite sends one request per call without cache or listeners.](https://raw.githubusercontent.com/long1eu/firebase_dart_sdk/main/docs/images/readme/firestore_layers.svg)

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
      apiKey: '<API key>', appId: '1:1234567890:web:abc', projectId: 'my-project'));
  final firestore = FirebaseFirestore.instanceFor(app: app);
  await firestore.doc('cities/SF').set({'name': 'San Francisco', 'state': 'CA'});
  final cities = await firestore.collection('cities').where('state', isEqualTo: 'CA').get();
  print(cities.docs.map((city) => city.data()));
  await firestore.terminate(); // a VM program exits once its instances are terminated
}
```

## Documentation

- **Guides** ([all guides](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/guides/README.md)):
  [getting started](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/guides/getting_started.md),
  [queries, data and the API](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/guides/queries_and_data.md),
  [transactions and the lifecycle](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/guides/transactions_and_lifecycle.md),
  [offline persistence and cache settings](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/guides/offline_persistence.md),
  [a cache in your own storage](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/guides/custom_cache_store.md),
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
  clients on one SQLite file keep it consistent and elect a primary, but do not share listeners or
  writes; the SQLite caches of the web stay at one tab. Only the IndexedDB cache of the web
  shares them, between tabs, with `multiTab: true` (a preview). Sharing them (stage 3 of the multi-client plan: shared state
  in SQLite between isolates and processes, and the tab manager settings of the JS SDK) is
  deferred until after 0.1.0.
- **Pipelines** beyond the preview: evaluation against the local cache, and real-time pipelines.
- **The web** beyond the experiment: browsers other than Chrome, and a cache shared between tabs other than the IndexedDB cache (a preview).
- `findNearest` evaluation against the local cache, and cache indexes for queries with
  inequalities on several fields.
- A full Firebase Auth SDK: sign-in with email and password, email links, anonymously, with custom tokens
  or with a federated provider's token, and server credentials, are in `firebase_auth_providers_dart`;
  popup and redirect flows, phone sign-in and multi-factor are not.

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
