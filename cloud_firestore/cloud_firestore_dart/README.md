# cloud_firestore_dart

An unofficial, pure-Dart Cloud Firestore client (gRPC, no Flutter plugin), ported from the
open-source Firebase Android SDK and brought forward to roughly current upstream `main`
behaviour, with parts of the public API following the JS SDK. It is not affiliated with or
endorsed by Google or Firebase.

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

First release of the revived port (0.1.0). It is prepared for pub.dev but **not published
yet**, so the `dart pub add` command above only works once it is.

- Unit tests, the spec tests shared with the official SDKs and the local-emulator integration
  suite are the only verification. See [Testing](#testing) for how to run them.
- **Everything was verified against the Firestore emulator only. Nothing has been run against
  production Firestore.** Behaviour that the emulator does not enforce (security rules in
  production, quotas, App Check enforcement, real index requirements, real latency and
  connectivity changes) is untested.
- Features of the Enterprise edition (BSON value types, Pipelines) were verified against the
  emulator in Enterprise edition only, never against a production Enterprise database.
- Web support is experimental: tested in Chrome only, against the emulator only, with a
  memory cache only. See [Platforms](#platforms).

## Platforms

Pure Dart on the VM (`dart:io`, `package:grpc`, SQLite through an `OpenDatabase` function you
supply, for example with `package:sqlite3`). Targets Dart `^3.8.0` (the minimum of `grpc` 5). Developed and tested on
macOS; Linux and Windows are expected to work but are not tested. Flutter apps (Android, iOS,
desktop) can use it as a plain Dart package.

Web support is experimental. Browsers have no sockets, so there the client talks to
Firestore the way the JS SDK does: REST/JSON for the one-shot calls and WebChannel for the
listen and write streams, over `fetch`. What to know:

- The cache is in memory only on the web (no SQLite persistence there yet).
- It was verified against the emulator only: 16 tests in Chrome
  (`dart test -p chrome -c dart2wasm test/browser`; with `-c dart2js` 15 pass and 1 is skipped),
  and the whole standard integration suite on the VM over the web transport
  (`tool/test_integration.sh standard --transport=webchannel`). Other browsers and the
  production backend are untested.
- Prefer dart2wasm. Compiled to JavaScript, integers above 2^53 lose precision.

## Features

- Documents, collections, collection groups, set/update/delete, `SetOptions` merge.
- Typed data converters: `withConverter<T>` on references and queries, generic snapshots.
- Queries: `where` filters including `!=` and `not-in`, `arrayContains(Any)`, `in`, as
  `whereEqualTo(...)`-style methods, `where('age', isGreaterThan: 18)` named arguments or
  `Filter` objects; composite `Filter.or` / `Filter.and` (OR queries, multiple inequality
  filters); `orderBy`, cursors, `limit` and `limitToLast`.
- Real-time listeners with `MetadataChanges`, and `ListenSource.cache` to listen to the local
  cache only.
- Aggregations: `Query.count()`, `Query.aggregate([...])` with `AggregateField.count/sum/average`,
  `Query.aggregateWithAliases({...})`.
- Vector values (`FieldValue.vector`) and `Query.findNearest` (server only; no local evaluation).
- BSON value types of Enterprise edition databases: `MinKey`, `MaxKey`, `Int32Value`,
  `Decimal128Value`, `BsonObjectId`, `BsonTimestamp`, `RegexValue` and `Blob.bsonBinary`.
- Pipelines (**preview**, Enterprise edition databases, server only): see
  [Pipelines](#pipelines-preview).
- Transactions with `TransactionOptions(maxAttempts)` and retry with exponential backoff,
  read-only transactions (`TransactionOptions(readOnly: true)`); write batches.
- Field transforms: server timestamp, increment, `FieldValue.maximum` / `minimum`, array union
  and remove. Transforms are folded into set/patch writes (the old `TransformMutation` is gone).
- Data bundles: `loadBundle`, `loadBundleStream`, `getNamedQuery`.
- Snapshots and references as JSON (`toJson` / `fromJson`, in the format of the JS SDK), and
  listeners resumed from a serialized snapshot.
- Offline cache in SQLite with LRU garbage collection; `FirestoreSettings.cacheSettings`
  (`PersistentCacheSettings`, `MemoryCacheSettings` with eager or LRU GC). Queries against the
  cache use the results of earlier listens instead of scanning the collection (index-free
  queries), and pending writes are kept as per-document overlays.
- Persistent cache indexes: `Firestore.persistentCacheIndexManager` lets the SDK create
  indexes for cache queries on its own (`enableIndexAutoCreation`), and the deprecated
  `Firestore.setIndexConfiguration` takes a `firestore.indexes.json` definition. See
  [Persistent cache indexes](#persistent-cache-indexes).
- `Firestore.waitForPendingWrites()`, `terminate()`, `clearPersistence()`, `snapshotsInSync`
  stream, `enableNetwork` / `disableNetwork`.
- Emulator support with a mock user token; `Firestore.setLogLevel`.
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
`where('age', isGreaterThanOrEqualTo: 18)` with named arguments and `where(Filter)`. See
`example/` and `test/integration/` for working calls of every feature below.)

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

```dart
import 'package:cloud_firestore_dart/pipelines.dart';

// An existing query as a pipeline: the same documents in the same order.
final Query<Map<String, Object?>> italian = users
    .where('country', isEqualTo: 'IT')
    .orderBy('age', Direction.descending)
    .limit(20);
final PipelineSnapshot same =
    await firestore.pipeline().createFrom(italian).execute();

// A subquery: every author with the number of their books.
await firestore
    .pipeline()
    .collection('authors')
    .define([field('name').as('author')])
    .select([
      'name',
      firestore
          .pipeline()
          .collection('books')
          .where(field('author').equal(variable('author')))
          .aggregate([countAll().as('count')])
          .toScalarExpression()
          .as('books'),
    ])
    .execute();

// A lambda over an array.
await firestore
    .pipeline()
    .collection('books')
    .select([field('tags').arrayFilter((tag) => tag.startsWith('sci')).as('tags')])
    .execute();

// A write stage, applied in one transaction.
final PipelineSnapshot written = await firestore
    .pipeline()
    .collection('books')
    .where(field('published').lessThan(1900))
    .update(transformedFields: [constant(true).as('classic')])
    .execute(atomic: true);
print(written.results.single.get('documents_modified'));
```

`example/pipelines.dart` is a runnable program.

- **Requirements**: a Firestore **Enterprise edition** database. A Standard edition database
  (and the emulator in its default edition) answers `invalid-argument: ExecutePipeline requires
  the Database Edition to be enterprise`. The emulator supports pipelines when it is started
  with `--database-edition enterprise`.
- **Server only**: a pipeline is sent to the server with the `ExecutePipeline` RPC. It does not
  read or update the local cache, does not see pending writes, fails with `unavailable` while
  offline and cannot be listened to.
- **Sources**: `collection`, `collectionGroup`, `database`, `documents`, `literals`, and the
  converters of existing queries described below.
- **Existing queries**: `createFrom(query)` converts a `Query` (filters with named arguments or
  `Filter.or` / `Filter.and`, orderings, cursors, `limit`, `limitToLast`, collection groups, BSON
  operands), `createFromAggregateQuery` an `AggregateQuery` and `createFromVectorQuery` a
  `findNearest` query. The integration tests compare each shape with `query.get(Source.server)`.
  Known difference: a cursor (`startAt`, `endBefore`, ...) on a field that holds values of
  several types only returns the documents whose value has the type of the cursor value; a
  classic cursor is a position in the order of all types. The converter of a query is ignored:
  pipeline results are maps (as in the JS and Android SDKs, which have no typed pipeline results
  either).
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
- **Explain**: there is no typed option, because its name could not be verified (the JS and
  Android SDKs do not have one and the emulator ignores every option). Send it with
  `execute(rawOptions: {...})`; whatever the server then reports is in
  `PipelineSnapshot.explainStats`.
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

To run the pipeline tests in `test/integration_enterprise`, start the Enterprise edition emulator
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

## Lifecycle: `terminate()`

`await firestore.terminate()` stops the instance: listeners stop receiving events, the streams and
the local cache are closed, and `Firestore.instanceFor` returns a new instance from then on. What
happens to work that was in progress, as in the Android and JS SDKs:

- A write whose future has not completed (it was not acknowledged by the backend yet) **never
  completes**: its future neither succeeds nor fails. With persistence the write is still in the
  local cache and is sent by the next instance; with a memory cache it is lost. Call
  `waitForPendingWrites()` before `terminate()` if the writes matter, and do not `await` a write
  after terminating the instance.
- A transaction, an aggregate query or a server read that is in flight fails with the error of the
  closed connection; a transaction is not retried once the instance is terminated.
- Calls made after `terminate()` fail (`terminate()` itself can be called again).
- A call that the client had finished with but the backend had not closed yet (a stopped
  listener, for example) is cancelled.

In tests, terminate every instance and `await` every operation before the test ends: an operation
that is still in flight when its instance is terminated fails afterwards, and an unhandled error
then fails whichever test is running.

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

## Persistent cache indexes

Queries against the SQLite cache (offline, `Source.cache`, and the first results of a
listener) normally scan the cached documents of the collection, or start from the result of an
earlier listen. A persistent cache index lets them read only the matching documents. The index
only exists inside the SDK, on the device; it is not a Cloud Firestore index and it never
changes what a query returns.

```dart
final indexes = firestore.persistentCacheIndexManager; // null with a memory cache
await indexes?.enableIndexAutoCreation();
```

- **Automatic creation** (off by default, not stored: turn it on after creating the instance).
  When a cache query was run as a collection scan that read at least 100 cached documents and
  more than twice as many as it returned, the SDK creates an index for that query. Only
  documents that came from the backend are counted, not pending writes.
- **Filling.** An index is filled in the background while the app runs: 50 documents per run,
  the first run 15 seconds after the instance was created and then one per minute. A query uses
  an index as far as it is filled and reads the rest, so results are complete at every moment.
- `disableIndexAutoCreation()` stops creating indexes (existing ones stay in use);
  `deleteAllIndexes()` removes them all.
- `Firestore.setIndexConfiguration(json)` (deprecated, as in the other SDKs) configures the
  indexes from a definition in the format of `firestore.indexes.json`; `queryScope` and
  `fieldOverrides` are ignored. It replaces the previous configuration.
- All query forms can be served: comparison operators, `in` / `not-in`, `array-contains(-any)`,
  `Filter.or` / `Filter.and`, `orderBy`, cursors, `limit` and `limitToLast`, also with BSON
  values. Queries with inequalities on several fields are scanned, as upstream.
- The index state is kept per signed-in user; the list of indexes is shared.

`example/cache_indexes.dart` is a runnable example. The stored index entries are not
byte-compatible with the ones of the Android SDK (they are never exchanged); the differences
are listed in `docs/ARCHITECTURE.md` in the repository.

## Testing

Run everything from this directory. The scripts are in `tool/` at the repository root (see
`tool/README.md`).

| Tests | Command | Backend |
| --- | --- | --- |
| Unit | `dart test test/unit` | none |
| Integration | `FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart test test/integration` | standard emulator (`tool/start_emulator.sh`) |
| Enterprise | `FIRESTORE_ENTERPRISE_EMULATOR_HOST=127.0.0.1:8181 dart test test/integration_enterprise` | Enterprise edition emulator (`tool/start_enterprise_emulator.sh`) |
| Browser | `dart test -p chrome -c dart2wasm test/browser` | standard emulator on 127.0.0.1:8080, Chrome |
| Integration over the web transport | `tool/test_integration.sh standard --transport=webchannel` (repository root) | standard emulator; runs on the VM |
| Standard suite on Enterprise | `FIRESTORE_EMULATOR_HOST=127.0.0.1:8181 FIRESTORE_EMULATOR_EDITION=enterprise dart test test/integration` | Enterprise edition emulator |

The environment variables are read by `test/util/test_backend.dart`:

- `FIRESTORE_EMULATOR_HOST` (`host:port`): the standard edition emulator, used by
  `test/integration`.
- `FIRESTORE_ENTERPRISE_EMULATOR_HOST` (`host:port`): a second emulator started in Enterprise
  edition, for the tests that need Enterprise features. Those tests live in
  `test/integration_enterprise`, get their instance from
  `IntegrationTestUtil.testEnterpriseFirestore()` and are skipped with a reason
  (`skip: IntegrationTestUtil.enterpriseEmulatorSkipReason`) while the variable is not set. Both
  emulators can run at the same time and both variables can be set together.

`tool/test_integration.sh [standard|enterprise|both]` (repository root) runs these against
emulators that are already up; `enterprise` runs `test/integration` against the Enterprise
edition emulator first and then `test/integration_enterprise`.

### Enterprise edition

The whole standard suite also runs against the Enterprise edition emulator
(`tool/test_integration.sh enterprise`). With emulator v1.22.0 the client behaves the same on
both editions except for the points below; the ten tests that expect the Standard behaviour are
skipped there with a reason, and `test/integration_enterprise/edition_differences_test.dart`
pins the Enterprise behaviour. These were observed with the emulator only, not with a production
Enterprise database.

- **`null` and `NaN` in equality filters.** `whereIn`, `whereArrayContains` and
  `whereArrayContainsAny` match fields (or array elements) that are `null` or `NaN` when the
  filter value is `null` or `NaN`. On Standard they never match.
- **`sum` over no documents** is `null` on Enterprise and `0` on Standard (`average` is `null`
  on both).
- **Number of aggregations.** Standard rejects more than 5 aggregations in one query;
  Enterprise accepts them.
- **Integer `sum` overflow.** When an integer sum leaves the 64-bit range, also only while
  accumulating, the Enterprise emulator fails with `invalid-argument` ("Long overflow"); Standard
  returns a double.
- **Emulator bug:** a listener (and so `get()`, which listens) on a query with `!=` or `not-in`
  on the document id fails with "`__key__` filter value must be a Key" on the Enterprise
  emulator. The request is correct: the same query succeeds through RunQuery on that emulator
  and through Listen on the Standard one.

No test failed because of index requirements, result ordering or size limits: the emulator
does not require indexes in either edition, and it orders document ids the same way in both.
(The JS SDK notes that a production Enterprise database does not sort numeric document ids
before string ids; the emulator does not show that.)

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

Not done:

- **Production.** Nothing has been run against production Firestore, and the Enterprise edition
  features only against the Enterprise edition emulator. The opt-in real-project test mode
  exists but has not been run.
- **Web beyond the experiment**: persistence on the web (the cache is in memory only there) and
  any browser other than Chrome.
- **Pipelines** beyond the [preview](#pipelines-preview) described above: full-text search,
  window functions, pipelines in a `Transaction`, local evaluation and real-time pipelines.
- `Query.findNearest` evaluation against the local cache.
- **Sharing one cache between running clients** (the multi-tab support of the JS SDK): see
  [Persistence and connectivity](#persistence-and-connectivity).
- Android-specific pieces of the Android SDK.
- Auth, Storage, Realtime Database: see
  [appsup-dart/firebase_dart](https://github.com/appsup-dart/firebase_dart).

Known gaps in what is done:

- **BSON numbers in membership filters.** `in`, `not-in`, `array-contains` and
  `array-contains-any` match a number against the local cache only if it has the same type
  (`Int32Value(5)` does not match `5`), while the backend compares numbers by value; the JS SDK
  has the same gap. Comparisons and ordering compare numbers by value, as the backend does.
- **Plain maps with a reserved key.** A plain `Map` with one of the reserved keys (for example
  `{'__int__': 5}`) is rejected in document data, like every field name that begins and ends
  with `__`; as a query value or an `arrayUnion` / `arrayRemove` element it is read as the BSON
  value, like the backend does.
- **`Decimal128Value` aggregates.** The sum and the average of an aggregation that includes a
  `Decimal128Value` are a `Decimal128Value` (`getDouble` and `getInt` convert it).
- **Increments on BSON numbers.** The emulator (v1.22.0) replaces an `Int32Value` or
  `Decimal128Value` field with the operand of `FieldValue.increment` instead of adding to it, so
  the local result (which adds) could not be compared with a backend.
- **Transactions** can be applied twice when the answer to a commit is lost; see
  [Transactions](#transactions).
- **App Check** tokens are sent, but enforcement cannot be tested on the emulator.
- The Enterprise edition differences listed under [Testing](#enterprise-edition) and the
  emulator gaps listed under [Pipelines](#pipelines-preview).

## Design notes

In the [GitHub repository](https://github.com/long1eu/firebase_dart_sdk):
`cloud_firestore/cloud_firestore_dart/docs/api_modernization_plan.md` (status of the Dart-idiom
API work), `cloud_firestore/cloud_firestore_dart/docs/app_check_design.md`, and
`docs/update_transforms_design.md`.

Issues and pull requests: https://github.com/long1eu/firebase_dart_sdk
