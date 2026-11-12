# cloud_firestore_vm

An unofficial, pure-Dart Cloud Firestore client (gRPC, no Flutter plugin), ported from the
open-source Firebase Android SDK and brought forward to roughly current upstream `main`
behaviour. It is not affiliated with or endorsed by Google or Firebase.

## Status

Unreleased work in progress (the pubspec still says `0.0.7`; nothing is published from this
branch).

- Unit tests and the local-emulator integration suite are the only verification. See the
  [repository README](../../README.md) for how to run them.
- **Everything was verified against the Firestore emulator only. Nothing has been run against
  production Firestore.** Behaviour that the emulator does not enforce (security rules in
  production, quotas, App Check enforcement, real index requirements, real latency and
  connectivity changes) is untested.

## Platforms

Pure Dart on the VM (`dart:io`, `package:grpc`, SQLite through `package:sqlite3`). Targets
Dart `^3.0.0`. Developed and tested on macOS; Linux and Windows are expected to work but are
not tested. Flutter apps can use it as a plain Dart package. Web is not supported (no
`dart:io`, no native SQLite).

## Features

- Documents, collections, collection groups, set/update/delete, `SetOptions` merge.
- Queries: `where` filters including `!=` and `not-in`, `arrayContains(Any)`, `in`; composite
  `Filter.or` / `Filter.and` (OR queries, multiple inequality filters); `orderBy`, cursors,
  `limit` and `limitToLast`.
- Real-time listeners with `MetadataChanges`, and `ListenSource.cache` to listen to the local
  cache only.
- Aggregations: `Query.count()`, `Query.aggregate([...])` with `AggregateField.count/sum/average`.
- Vector values (`FieldValue.vector`) and `Query.findNearest` (server only; no local evaluation).
- Transactions with `TransactionOptions(maxAttempts)` and retry with exponential backoff; write
  batches.
- Field transforms: server timestamp, increment, `FieldValue.maximum` / `minimum`, array union
  and remove. Transforms are folded into set/patch writes (the old `TransformMutation` is gone).
- Data bundles: `loadBundle`, `loadBundleStream`, `getNamedQuery`.
- Offline cache in SQLite with LRU garbage collection; `FirestoreSettings.cacheSettings`
  (`PersistentCacheSettings`, `MemoryCacheSettings` with eager or LRU GC).
- `Firestore.waitForPendingWrites()`, `terminate()`, `snapshotsInSync` stream,
  `enableNetwork` / `disableNetwork`.
- Bloom-filter existence-filter handling on reconnect (server `expected_count`).
- gRPC keepalive, connect timeout, backoff reset on connectivity change, streams closed after
  one minute idle.
- App Check token plumbing: an `InternalAppCheckTokenProvider` set on the `FirebaseApp` makes
  every RPC carry the `x-firebase-appcheck` header (see `docs/app_check_design.md`). This
  package does not attest a device; you supply the provider.

## Usage

```dart
import 'package:cloud_firestore_vm/cloud_firestore_vm.dart';
import 'package:firebase_core_vm/firebase_core_vm.dart';

// `app` is a FirebaseApp created with firebase_core_vm.
final firestore = await Firestore.instanceFor(app: app);
final users = firestore.collection('users');
await users.doc('ada').set({'name': 'Ada', 'age': 36});
final adults = await users.whereGreaterThanOrEqualTo('age', 18).get();
```

(Filters are the Java-style `whereEqualTo`, `whereGreaterThan`, ... family, plus
`where(Filter)`. See `test/integration/` for working calls of every feature below.)

Emulator (the settings must be passed when the instance is created):

```dart
final firestore = await Firestore.instanceFor(
  app: app,
  settings: FirestoreSettings().withEmulator('127.0.0.1', 8080),
);
```

Aggregation, OR queries, vector search, `limitToLast`:

```dart
final count = await users.count().get();                 // AggregateQuerySnapshot
final agg = await users.aggregate([
  AggregateField.sum('age'),
  AggregateField.average('age'),
]).get();
final either = await users
    .where(Filter.or([
      Filter.equalTo('city', 'Paris'),
      Filter.equalTo('city', 'Rome'),
    ]))
    .get();
final last3 = await users.orderBy('age').limitToLast(3).get();
final near = await users
    .findNearest('embedding', FieldValue.vector([0.1, 0.2, 0.3]), 5,
        DistanceMeasure.cosine)
    .get();
```

Cache settings, bundles, lifecycle:

```dart
final settings = FirestoreSettings(
    cacheSettings: PersistentCacheSettings(sizeBytes: 100 * 1024 * 1024));
final task = firestore.loadBundle(bundleBytes);          // LoadBundleTask
await firestore.waitForPendingWrites();
firestore.snapshotsInSync.listen((_) {});
await firestore.terminate();
```

The exact signatures are pinned in `test/unit/api/public_api.golden.txt`; if a snippet above
disagrees with the golden file, the golden file is right (the snippets are illustrative and were
not compiled).

The public entry point is `package:cloud_firestore_vm/cloud_firestore_vm.dart` (class
`Firestore`). It needs a `FirebaseApp` from `firebase_core_vm`. To run the integration tests
against the emulator set `FIRESTORE_EMULATOR_HOST` (see `test/util/integration_test_util.dart`).

## Not supported or not done

- BSON-specific value types (for example `MinKey`, `MaxKey`, `Decimal128`, `BsonObjectId`,
  `BsonTimestamp`, `BsonBinaryData`, regex, int32): not implemented.
- Index-free queries, document overlays, the client-side index engine and persistent-cache
  auto-indexing: not implemented. Queries run against the local cache as in the 2019 design
  (SQLite schema version 8 lineage, plus the changes listed in the CHANGELOG).
- Clearing persistence (`clearPersistence`): not available; the API shape is still to be decided.
- Pipelines, `Query.findNearest` evaluation against the local cache, Android-specific pieces.
- Auth, Storage, Realtime Database: see
  [appsup-dart/firebase_dart](https://github.com/appsup-dart/firebase_dart).

## Design notes

`docs/api_modernization_plan.md` (status of the Dart-idiom API work),
`docs/app_check_design.md`, and `docs/update_transforms_design.md` at the repository root.

Issues and pull requests: https://github.com/long1eu/firebase_dart_sdk
