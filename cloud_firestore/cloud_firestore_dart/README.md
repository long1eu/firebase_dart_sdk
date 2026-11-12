# cloud_firestore_dart

An unofficial, pure-Dart Cloud Firestore client (gRPC, no Flutter plugin), ported from the
open-source Firebase Android SDK and brought forward to roughly current upstream `main`
behaviour. It is not affiliated with or endorsed by Google or Firebase.

## Install

```shell
dart pub add cloud_firestore_dart firebase_app_dart
```

Renamed: this package was published as
[`cloud_firestore_vm`](https://pub.dev/packages/cloud_firestore_vm) and its app layer as
[`firebase_core_vm`](https://pub.dev/packages/firebase_core_vm). Replace the dependencies with
`cloud_firestore_dart` and `firebase_app_dart` and the imports with
`package:cloud_firestore_dart/cloud_firestore_dart.dart` and
`package:firebase_app_dart/firebase_app_dart.dart`; class names did not change. See the
CHANGELOG for the API changes since 0.0.7 and the
[migration guide](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/migrating_from_vm_packages.md)
for before/after code.

## Status

First release of the revived port (0.1.0).

- Unit tests and the local-emulator integration suite are the only verification. See the
  [repository README](https://github.com/long1eu/firebase_dart_sdk#running-the-tests) for how
  to run them.
- **Everything was verified against the Firestore emulator only. Nothing has been run against
  production Firestore.** Behaviour that the emulator does not enforce (security rules in
  production, quotas, App Check enforcement, real index requirements, real latency and
  connectivity changes) is untested.

## Platforms

Pure Dart on the VM (`dart:io`, `package:grpc`, SQLite through an `OpenDatabase` function you
supply, for example with `package:sqlite3`). Targets Dart `^3.0.0`. Developed and tested on
macOS; Linux and Windows are expected to work but are not tested. Flutter apps (Android, iOS,
desktop) can use it as a plain Dart package.

Web is not supported yet: the transport uses native gRPC over HTTP/2 from `dart:io`, which
browsers do not offer. Web support is planned and needs a different transport (gRPC-Web or
the REST/WebChannel protocol).

## Features

- Documents, collections, collection groups, set/update/delete, `SetOptions` merge.
- Queries: `where` filters including `!=` and `not-in`, `arrayContains(Any)`, `in`; composite
  `Filter.or` / `Filter.and` (OR queries, multiple inequality filters); `orderBy`, cursors,
  `limit` and `limitToLast`.
- Real-time listeners with `MetadataChanges`, and `ListenSource.cache` to listen to the local
  cache only.
- Aggregations: `Query.count()`, `Query.aggregate([...])` with `AggregateField.count/sum/average`.
- Vector values (`FieldValue.vector`) and `Query.findNearest` (server only; no local evaluation).
- BSON value types of Enterprise edition databases: `MinKey`, `MaxKey`, `Int32Value`,
  `Decimal128Value`, `BsonObjectId`, `BsonTimestamp`, `RegexValue` and `Blob.bsonBinary`.
- Pipelines (**preview**, Enterprise edition databases, server only): see
  [Pipelines](#pipelines-preview).
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
  every RPC carry the `x-firebase-appcheck` header (see `docs/app_check_design.md` in the repository). This
  package does not attest a device; you supply the provider.

## Usage

```dart
import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';

// `app` is a FirebaseApp created with firebase_app_dart.
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

To test security rules as a user, pass `mockUserToken` (a token string, or the claims of a
Firebase ID token that are encoded as an unsigned JWT, as `connectFirestoreEmulator` does in
the JS SDK): `FirestoreSettings().withEmulator('127.0.0.1', 8080, mockUserToken: {'sub': 'alice'})`.

`await firestore.terminate(); await firestore.clearPersistence();` deletes the local cache
(useful between tests). `Firestore.setLogLevel(LogLevel.debug)` turns on debug logging
(`error` and `silent` are the other levels).

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

Typed data converters (model after the JS `withConverter`; this snippet compiles against the
library):

```dart
class City {
  const City(this.name, this.population);
  factory City.fromMap(Map<String, Object?> m) =>
      City(m['name']! as String, m['population']! as int);
  final String name;
  final int population;
  Map<String, Object?> toMap() => {'name': name, 'population': population};
}

final converter = FirestoreDataConverter<City>.from(
  fromFirestore: (snapshot, options) => City.fromMap(snapshot.data!),
  toFirestore: (city, options) => city.toMap(),
);

final cities = firestore.collection('cities').withConverter<City>(converter);
await cities.doc('sf').set(const City('San Francisco', 870000));   // CollectionReference<City>
final City sf = (await cities.doc('sf').get()).data!;               // DocumentSnapshot<City>
final big = await cities.whereGreaterThan('population', 500000).get();
final names = [for (final c in big.docs) c.data.name];              // QueryDocumentSnapshot<City>
final raw = cities.withoutConverter();                              // back to Map<String, Object?>
```

`withConverter` exists on `DocumentReference`, `CollectionReference` and `Query`; `update` and
`updateFromList` always take raw field maps. A bare `DocumentSnapshot` or `Query` annotation (no
type argument) means `dynamic` data, so annotate as `DocumentSnapshot<Map<String, Object?>>`
when you want static typing for raw maps (values returned by `firestore.collection(...)` etc. are
already `Map<String, Object?>`).

Cache settings, bundles, lifecycle:

```dart
final settings = FirestoreSettings(
    cacheSettings: PersistentCacheSettings(sizeBytes: 100 * 1024 * 1024));
final task = firestore.loadBundle(bundleBytes);          // LoadBundleTask
final json = (await query.get()).toJson();               // e.g. sent from a server to a client
final snapshot = QuerySnapshot.fromJson(firestore, json);
firestore.querySnapshotsFromJson(json).listen((_) {});   // resumes listening from that snapshot
await firestore.waitForPendingWrites();
firestore.snapshotsInSync.listen((_) {});
await firestore.terminate();
```

Members marked `@internal` in the golden listing are implementation details that are still
reachable for technical reasons; the analyzer warns when you use them and they may change or
disappear in any release.

The exact signatures are pinned in `test/unit/api/public_api.golden.txt`. The snippets above are
compiled against the library by `test/unit/api/readme_snippets_test.dart` (they assume an `app`,
`firestore`, `users`, `query` and `bundleBytes` in scope).

The public entry point is `package:cloud_firestore_dart/cloud_firestore_dart.dart` (class
`Firestore`). It needs a `FirebaseApp` from `firebase_app_dart`. Runnable programs, one per topic
(queries, aggregations, converters, transactions, bundles, snapshot JSON, offline persistence,
emulator, lifecycle), are in [`example/`](example/README.md). See [Testing](#testing) for how
to run the tests.

## Pipelines (preview)

Pipeline queries are in a separate library, `package:cloud_firestore_dart/pipelines.dart`. The
API is **experimental**: it follows the JS and Android SDKs, which are still changing, and it may
change in any release.

```dart
import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/pipelines.dart';

final PipelineSnapshot snapshot = await firestore
    .pipeline()
    .collection('books')
    .where(field('rating').greaterThan(4).and(field('genre').equal('Fantasy')))
    .addFields([field('title').toUpper().as('upperTitle')])
    .sort([field('rating').descending()])
    .limit(10)
    .execute();

for (final PipelineResult result in snapshot.results) {
  print('${result.id}: ${result.data()}');
}

// One row per genre.
await firestore
    .pipeline()
    .collection('books')
    .aggregate([countAll().as('count'), field('rating').average().as('avg')],
        groups: ['genre'])
    .execute();
```

- **Requirements**: a Firestore **Enterprise edition** database. A Standard edition database
  (and the emulator in its default edition) answers `invalid-argument: ExecutePipeline requires
  the Database Edition to be enterprise`. The emulator supports pipelines when it is started
  with `--database-edition enterprise`.
- **Server only**: a pipeline is sent to the server with the `ExecutePipeline` RPC. It does not
  read or update the local cache, does not see pending writes, fails with `unavailable` while
  offline and cannot be listened to.
- **Sources**: `collection`, `collectionGroup`, `database`, `documents`, `literals`, and
  `createFrom(query)`, which converts an existing `Query`.
- **Stages**: `where`, `select`, `addFields`, `removeFields`, `sort`, `limit`, `offset`,
  `aggregate` (with `groups`), `distinct`, `findNearest`, `sample`, `union`, `unnest`,
  `replaceWith`.
- **Expressions**: `field(...)`, `constant(...)`, `array(...)`, `map(...)` and methods on them for
  comparisons, `and` / `or` / `not` / `xor` / `conditional`, arithmetic and math, strings and
  regular expressions, arrays, maps, timestamps, vector distances, types and missing values
  (`ifAbsent`, `ifError`, `ifNull`, `coalesce`), and the aggregates `count`, `countAll`,
  `countIf`, `countDistinct`, `sum`, `average`, `minimum`, `maximum`, `first`, `last`, `arrayAgg`,
  `arrayAggDistinct`. `test/unit/api/pipelines_api.golden.txt` has the full list.
- **Anything else**: `FunctionExpression('server_name', [args])`,
  `AggregateFunction('server_name', [args])`, `Pipeline.rawStage(name, args)` and the `rawOptions`
  parameter of every stage send functions, stages and options this package has no helper for yet.
- **Write stages**: `update`, `delete`, `insert` and `upsert` end a pipeline and change the
  documents on the server; the result is one row with `documents_modified`. With
  `execute(atomic: true)` the pipeline runs in a transaction that is committed at the end. The
  server demands that for `insert` and `upsert` of documents read from a collection, and after
  an aggregation, `unnest`, `union` or a subquery. These writes bypass the local cache and the
  write queue: they fail while offline, and cached copies are stale until the server reports the
  change. The emulator (v1.22.0) never reports it: listeners and `get(Source.server)` return the
  old version until a regular write touches the document, while pipelines read the new one.
- **Variables and subqueries**: `define([...])` with `variable(name)`, `currentDocument()`,
  `getField`, `firestore.pipeline().subcollection(path)`, and `toArrayExpression()` /
  `toScalarExpression()` to use a pipeline inside a stage of another one.
- **Lambdas**: `arrayFilter((e) => e.greaterThan(1))`, `arrayTransform`,
  `arrayTransformWithIndex`; the callback builds the expression once, from a variable that
  stands for the element (name it with `alias` when lambdas are nested).
- **Explain**: `execute(explainOptions: PipelineExplainOptions())` and
  `PipelineSnapshot.explainStats`. Not verified: the JS and Android SDKs have no such option yet
  and the emulator ignores it (it accepts any option), so the option names have not been checked
  against a real backend.
- **Not done yet**: full-text search (the emulator has no `document_matches` function, so the
  `search` stage could not be checked; `rawStage('search', [], options: {...})` can send it),
  window functions, pipelines inside a `Transaction`, and evaluation against the local cache or
  real-time pipelines.
- **Emulator gaps** (v1.22.0): `geoDistance`, `search` and window functions are rejected, and the
  `literals` source is denied for clients that are subject to security rules.
- A result is a document (`ref`, `id`, `createTime`, `updateTime`) only while the pipeline filters,
  sorts and limits; after `select`, `aggregate`, `distinct`, `unnest` and similar it is a plain
  map. BSON values come back as their value classes.
- The helper functions have short names (`field`, `and`, `or`, `not`, ...); import the library
  with a prefix if they clash with yours.

To run `test/integration_enterprise/pipeline_test.dart`, start the Enterprise edition emulator
(`tool/start_enterprise_emulator.sh`) and set `FIRESTORE_ENTERPRISE_EMULATOR_HOST` (host:port);
without it the tests are skipped.

## Transactions

Transactions are optimistic, as in the Android and JS SDKs: `transaction.get` reads the current
version of a document, and the commit sends every write with a precondition on the version that was
read (documents that were only read are verified). When a precondition fails the whole callback is
run again, up to `TransactionOptions.maxAttempts` times (5 by default), so the callback must not
have side effects of its own.

**A commit whose answer is lost can be applied twice.** A commit is retried when it fails with
`aborted`, `failedPrecondition` or `alreadyExists`, which the backend only returns when nothing was
applied, but also on connection-level errors (`unavailable`, `unknown`, `cancelled`,
`deadlineExceeded`, `internal`, `resourceExhausted`), the same rule as upstream. If the connection
breaks after the backend applied the commit but before the client received the answer, the client
cannot tell, runs the callback again, reads the result of its own first attempt and applies the
change a second time (a counter is incremented twice). This is rare, and the Android and JS SDKs
have the same exposure. If a transaction must not be applied twice, make it idempotent: write a
value that identifies the operation (for example an operation id that the callback checks before
writing) instead of relying on a relative change.

Writes outside transactions (`set`, `update`, `delete`, `WriteBatch`) go through the write stream.
When the stream breaks, the writes that were not acknowledged are sent again on the new stream, as
upstream does. Overwrites and deletes are harmless to repeat; whether the backend recognises a
repeated write that carries a relative transform such as `FieldValue.increment` was not verified.

## Persistence and connectivity

- The package does not open SQLite files itself: you pass an `OpenDatabase` function to
  `Firestore.instanceFor(openDatabase: ...)` (without one the cache is in memory only). This is
  the only public part of the SQLite layer: implement `Database` (`execute`, `query`, `delete`,
  `close`, `path`) over the binding of your choice, and make the opener call `onConfigure`, then
  `onCreate` (new file) or `onUpgrade` / `onDowngrade` (stored `user_version` differs), store the
  requested version, then call `onOpen` (see the doc comment on `OpenDatabase`). The tests use
  `package:sqlite3`; a complete opener you can copy is `example/sqlite_database.dart`, used by
  `example/offline_persistence.dart`. The persistence layer never switches
  the connection to `PRAGMA locking_mode = EXCLUSIVE` (the Android SDK does, and fails with
  "Failed to gain exclusive lock" when a second process opens the same file). This is deliberate:
  after a Flutter hot restart the old isolate's handle is still open and the new isolate must be
  able to open the same file (issue #1). SQLite's normal file locking keeps the file consistent
  and is covered by `test/unit/firebase/firestore/local/sqlite_shared_file_test.dart`.
  Two live clients on the same file do not share their in-memory state (target ids, mutation
  batch ids), so do not run two active clients on one persistence key; use different app names
  or databases. Handles inside one process are serialized per database name.
- Instances are independent: each `Firestore` has its own scheduler and work queue, and the
  persistence lock is per database, so an instance never waits for another one (issue #2).
- Connectivity: `firebase_app_dart` has no built-in monitor on any OS. `FirebaseApp.onNetworkConnected`
  is seeded with `true` and Firestore restarts its streams (resetting backoff) on every `true`
  event. To react to real connectivity changes, subclass `PlatformDependencies`, override
  `onNetworkConnected` and feed it from your own source (for example the `connectivity_plus`
  plugin in a Flutter app, or a periodic reachability probe in a server process).

## Testing

Run everything from this directory. The scripts are in `tool/` at the repository root (see
`tool/README.md`).

| Tests | Command | Backend |
| --- | --- | --- |
| Unit | `dart test test/unit` | none |
| Integration | `FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart test test/integration` | standard emulator (`tool/start_emulator.sh`) |
| Enterprise | `FIRESTORE_ENTERPRISE_EMULATOR_HOST=127.0.0.1:8181 dart test test/integration_enterprise` | Enterprise edition emulator (`tool/start_enterprise_emulator.sh`) |

The environment variables are read by `test/util/test_backend.dart`:

- `FIRESTORE_EMULATOR_HOST` (`host:port`): the standard edition emulator, used by
  `test/integration`.
- `FIRESTORE_ENTERPRISE_EMULATOR_HOST` (`host:port`): a second emulator started in Enterprise
  edition, for the tests that need Enterprise features. Those tests live in
  `test/integration_enterprise`, get their instance from
  `IntegrationTestUtil.testEnterpriseFirestore()` and are skipped with a reason
  (`skip: IntegrationTestUtil.enterpriseEmulatorSkipReason`) while the variable is not set. Both
  emulators can run at the same time and both variables can be set together.

### Against a real Firebase project (opt-in)

The integration suite can also run against a real project. Nothing does this by default: it
only happens when you set `FIRESTORE_TEST_PROJECT_ID` yourself and `FIRESTORE_EMULATOR_HOST` is
not set (the emulator always wins, so an emulator run can never reach a real project).

    # Either a service-account key file...
    export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
    # ...or the credentials of: gcloud auth application-default login

    export FIRESTORE_TEST_PROJECT_ID=my-test-project
    export FIRESTORE_TEST_DATABASE_ID=my-database   # optional, default: (default)
    dart test test/integration/firebase/firestore/smoke_test.dart

- Credentials are Application Default Credentials, resolved by `package:grpc`: the file named
  by `GOOGLE_APPLICATION_CREDENTIALS`, else the gcloud application-default file, else the
  metadata server. The test code only passes the resulting access token to the gRPC calls; it
  does not store or print it. Do not commit key files.
- A service account needs the `Cloud Datastore User` role (`roles/datastore.user`). Its requests
  bypass security rules. With gcloud user credentials the Firestore API may ask for a quota
  project; a service account avoids that.
- **Use a throwaway project.** The tests create many documents in collections with random names
  and do not delete them; the suite makes thousands of reads and writes, which are billed.
- The suite is written for the emulator. Against production expect failures in tests that rely
  on emulator behaviour (open security rules and unauthenticated users, emulator-only limits,
  queries that need composite indexes you have not created). Start with single files.
- This path has only been exercised up to the token plumbing (unit tests with a fake
  authenticator); it has not been run against a real project.

## Not supported or not done

- BSON value types (`MinKey`, `MaxKey`, `Int32Value`, `Decimal128Value`, `BsonObjectId`,
  `BsonTimestamp`, `RegexValue`, `Blob.bsonBinary`) are supported, with one known gap. `in`,
  `not-in`, `array-contains` and `array-contains-any` match a number against the local cache
  only if it has the same type (`Int32Value(5)` does not match `5`), while the backend compares
  numbers by value; the JS SDK has the same gap. A plain `Map` with one of the reserved keys (for
  example `{'__int__': 5}`) is rejected in document data, like every field name that begins and
  ends with `__`; as a query value or an `arrayUnion` / `arrayRemove` element it is read as the
  BSON value, like the backend does. The sum and the average of an aggregation that includes a
  `Decimal128Value` are a `Decimal128Value` (`getDouble` and `getInt` convert it).
- Index-free queries, document overlays, the client-side index engine and persistent-cache
  auto-indexing: not implemented. Queries run against the local cache as in the 2019 design
  (SQLite schema version 8 lineage, plus the changes listed in the CHANGELOG).
- Clearing persistence (`clearPersistence`): not available; the API shape is still to be decided.
- Pipelines beyond the [preview](#pipelines-preview) described above (no local evaluation, no
  real-time pipelines), `Query.findNearest` evaluation against the local cache, Android-specific
  pieces.
- Auth, Storage, Realtime Database: see
  [appsup-dart/firebase_dart](https://github.com/appsup-dart/firebase_dart).

## Design notes

In the [GitHub repository](https://github.com/long1eu/firebase_dart_sdk):
`cloud_firestore/cloud_firestore_dart/docs/api_modernization_plan.md` (status of the Dart-idiom
API work), `cloud_firestore/cloud_firestore_dart/docs/app_check_design.md`, and
`docs/update_transforms_design.md`.

Issues and pull requests: https://github.com/long1eu/firebase_dart_sdk
