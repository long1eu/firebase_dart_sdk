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
- Web support is experimental: tested in Chrome only, against the emulator only. The cache is
  in memory unless you opt in to SQLite in IndexedDB. See [Platforms](#platforms).

## Platforms

Pure Dart on the VM (`dart:io`, `package:grpc`, SQLite through an `OpenDatabase` function you
supply, for example with `package:sqlite3`). Targets Dart `^3.8.0` (the minimum of `grpc` 5). Developed and tested on
macOS; Linux and Windows are expected to work but are not tested. Flutter apps (Android, iOS,
desktop) can use it as a plain Dart package.

Web support is experimental. Browsers have no sockets, so there the client talks to
Firestore the way the JS SDK does: REST/JSON for the one-shot calls and WebChannel for the
listen and write streams, over `fetch`. What to know:

- The cache is in memory by default. To keep it across page loads, pass the `OpenDatabase` of
  [`example/sqlite_database_web.dart`](example/sqlite_database_web.dart) (copy the file into
  your app): SQLite compiled to WebAssembly by `package:sqlite3`, with the database in
  IndexedDB. It needs the `sqlite3.wasm` file of that package next to your page. One tab at a
  time: a second tab that opens the same cache gets a `FirestoreError` with
  `failedPrecondition` (a Web Lock guards the database) and should use a memory cache;
  `openWithMemoryFallback` in that file does this. `clearPersistence()` deletes the IndexedDB
  database. Cost, measured for a small app compiled with `dart compile js -O2`: 588 KB (180 KB
  gzipped) with a memory cache, 807 KB (239 KB gzipped) with the persistent cache, plus
  `sqlite3.wasm`, 731 KB (349 KB gzipped).
  - Crash safety: what a write future acknowledged is stored, and a tab that dies in the middle
    of a transaction loses only that transaction (SQLite's rollback journal is stored too and
    is applied on the next open). Tested by killing a worker at random moments, 2700 times.
    A crash of the browser itself or a power cut is not covered.
  - Memory and speed: the whole database is read into memory when it is opened. Measured in
    Chrome with documents of about 1 KB (database size; time to open; full scan from the
    cache; one write):

    | Cached documents | Database | dart2wasm | dart2js |
    |---|---|---|---|
    | 1,000 | 2 MB | 19 ms; 39 ms; 17 ms | 13 ms; 24 ms; 13 ms |
    | 10,000 | 17 MB | 0.13 s; 0.39 s; 21 ms | 0.08 s; 0.27 s; 17 ms |
    | 100,000 | 160 MB | 1.2 s; 4.1 s; 18 ms | 0.6 s; 2.5 s; 12 ms |

    With 100,000 documents the JavaScript heap was about 0.5 GB once open (dart2js). Treat
    some tens of thousands of documents as the practical limit; the default cache size limit
    of 100 MB starts evicting unused documents before that.
  - The opener works around a slowness of `sqlite3` 2.9.4 compiled with dart2wasm, where
    every read of the database cost a copy of the whole file (0.7 s to open and 2.4 s to scan
    the 1,000 documents above, and worse with the size). Use the opener as it is in
    `example/`; an older copy without `_ReadCopyFileSystem` is that slow.
- Against the emulator, a query that returns more than about 10,000 documents fails on the
  web with `unavailable` (the emulator's WebChannel endpoint drops the stream; over gRPC the
  same query works). Read such collections in pages there. Whether the production backend
  has such a limit was not checked.
- It was verified against the emulator only: 41 tests in Chrome (`tool/test_browser.sh both`
  from the repository root; 40 pass and 1 is skipped with each compiler: under dart2wasm the
  crash harness of the persistent cache, under dart2js the test of 64 bit integers), and the
  whole standard integration suite on the VM over the web transport
  (`tool/test_integration.sh standard --transport=webchannel`). Other browsers and the
  production backend are untested.
- Prefer dart2wasm. Compiled to JavaScript, integers above 2^53 lose precision.
- If listeners or writes never complete on some network (a proxy or antivirus that buffers
  streamed responses), set `FirestoreSettings(experimentalForceLongPolling: true)`. The
  client also tries to detect this by itself (`experimentalAutoDetectLongPolling`, on by
  default).
- Do not compile with `-Dprotobuf.omit_field_names=true` or `-Dprotobuf.omit_enum_names=true`:
  the web transport needs those names, and refuses to start without them.

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
- Firestore Lite (**experimental**): a second entry point without cache, listeners and sync
  engine, where every call is one request. See [Firestore Lite](#firestore-lite-experimental).
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
`example/` and, in the repository,
[`test/integration/`](https://github.com/long1eu/firebase_dart_sdk/tree/main/cloud_firestore/cloud_firestore_dart/test/integration) for working calls of every feature below.)

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

## Firestore Lite (experimental)

`package:cloud_firestore_dart/lite.dart` is a second entry point: a client without a local cache,
without listeners and without the sync engine, the counterpart of `firebase/firestore/lite` of
the JS SDK. Every call is one request to the backend and one response. The API is
**experimental** and may change in any release.

```dart lite
import 'package:cloud_firestore_dart/lite.dart';

// Synchronous: there is no cache to open. Nothing is sent until the first call.
final Firestore firestore = Firestore.instanceFor(app: app);

final CollectionReference<Map<String, Object?>> cities = firestore.collection('cities');
await cities.doc('SF').set({'name': 'San Francisco', 'population': 808000});
await cities.doc('SF').update({'visits': FieldValue.increment(1)});

final DocumentSnapshot<Map<String, Object?>> sf = await cities.doc('SF').get();
print(sf.data);

final QuerySnapshot<Map<String, Object?>> largest = await cities
    .where('population', isGreaterThan: 100000)
    .orderBy('population')
    .limitToLast(2)
    .get();
print(largest.docs.map((doc) => doc.id).toList());

final AggregateQuerySnapshot totals = await cities.aggregateWithAliases({
  'cities': AggregateField.count(),
  'people': AggregateField.sum('population'),
}).get();
print(totals.data());

await firestore.runTransaction<void>((Transaction transaction) async {
  final DocumentSnapshot<Map<String, Object?>> city = await transaction.get(cities.doc('SF'));
  transaction.update(cities.doc('SF'), {'population': (city.get('population')! as int) + 1});
});

await firestore.terminate();
```

Import it *instead of* `cloud_firestore_dart.dart`. Both libraries declare `Firestore`,
`DocumentReference`, `CollectionReference`, `Query`, the snapshot classes, `WriteBatch`,
`Transaction`, `FirestoreDataConverter` and `FirestoreSettings` (use an import prefix to have
both in one file); the lite classes have the same members with the same names, minus everything
that needs a cache. The value types (`Timestamp`, `GeoPoint`, `Blob`, `VectorValue`, the BSON
classes, `FieldValue`, `FieldPath`, `Filter`, `SetOptions`, `AggregateField`,
`TransactionOptions`, `FirestoreError`) are the same classes in both. `example/lite.dart` is a
runnable program.

- **What it has:** `ref.get()`, `set` / `update` / `updateFromList` / `delete`,
  `collection.add`, `firestore.batch()`, `runTransaction` (with `TransactionOptions`; read-only
  transactions with `Transaction.getQuery` and `getAggregate`), queries
  with `where` (named arguments or `Filter`), `orderBy`, `limit`, `limitToLast`, cursors and
  collection groups, `count()` / `aggregate` / `aggregateWithAliases`, `withConverter`,
  `DocumentReference.toJson` / `fromJson`, `terminate()`, the emulator settings with
  `mockUserToken`, Firebase Auth and App Check tokens of the `FirebaseApp`.
- **What it does not have:** snapshot streams, `Source`, snapshot metadata
  (`hasPendingWrites`, `isFromCache`), persistence and cache settings, bundles, offline
  behaviour of any kind, vector queries (`findNearest`), pipelines, and the
  `whereEqualTo(...)`-style query methods (use `where`).
- **Writes are not queued or retried:** a write completes when the backend has applied it and
  fails with the error of the backend (for example `unavailable` without a connection). Only
  transactions are retried, as in the main library.
- **`limitToLast`** sends the query with its orderings flipped and reverses the result, as the
  JS SDK does.
- **Transport:** gRPC on native platforms, and REST over `fetch` on the web (no WebChannel).
- **`terminate()`** lets the calls in flight finish, then closes the connection; later calls
  fail with `failedPrecondition`. On native platforms a program has to terminate its instances
  to exit, like with the main library.

Differences from the main library that are not just missing features:
`Firestore.instanceFor` is synchronous; `FirestoreDataConverter.fromFirestore` takes only the
snapshot (a `QueryDocumentSnapshot`, there are no snapshot options); `DocumentReference.parent`
keeps the converter of the reference, as in the JS SDK; `firestore.doc('')` throws; two
`AggregateQuerySnapshot`s are equal when they hold the same results under the same names, in
any order.

**Size.** A program that only imports `lite.dart` does not contain the sync engine, the local
store, the SQLite layer or WebChannel. `tool/check_size.sh` (repository root) compiles the same
small web application (writes, a read, a query, an aggregation, a batch and a transaction) with
both libraries, `dart compile js -O2`, Dart 3.12.2:

| | JavaScript | gzipped | of it code of this package |
|---|---|---|---|
| Firestore Lite | 415,850 | 128,303 | 129,045 |
| main library, memory cache | 641,418 | 196,065 | 294,546 |

Most of the rest is the Dart runtime and `package:protobuf`. The script fails when the lite
program grows past 450,000 characters (140,000 bytes gzipped) or when the compiler's
`--dump-info` output lists code from `src/firebase/firestore/local/`, the sync engine, the
views, the event manager, the remote store or the WebChannel transport in it. CI runs it as a
job that is allowed to fail.

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

### Read-only transactions

`TransactionOptions(readOnly: true)` runs a read-only transaction **of the backend** (the server
SDKs have these; the Android and JS client SDKs do not):

```dart
final total = await firestore.runTransaction((transaction) async {
  final account = await transaction.get(firestore.doc('accounts/a'));
  final orders = await transaction.getQuery(
      firestore.collection('orders').where('account', isEqualTo: 'a'));
  final count = await transaction.getAggregate(firestore.collection('orders').count());
  return (account.data, orders.docs.length, count.getCount());
}, options: TransactionOptions(readOnly: true));
```

- Every read of the transaction sees the database as it was at one point in time: documents
  (`get`), queries (`getQuery`) and aggregations (`getAggregate`) are consistent with each other,
  also while other clients write. `getQuery` and `getAggregate` only exist for read-only
  transactions; in a read-write transaction they fail with `invalidArgument`, because such a
  transaction verifies its reads at commit and the result of a query cannot be verified.
- `TransactionOptions(readOnly: true, readTime: timestamp)` reads the database as it was at
  `timestamp`. The backend keeps old versions for a limited time and rejects read times before that.
- Writes in the transaction throw. Nothing is committed and no locks are taken, so there are no
  conflicts: the callback is not run again when documents change. It is only run again (up to
  `maxAttempts` times) when the connection fails.
- The reads go to the backend: they never use the cache, do not include local writes that the
  backend has not seen, and fail when the client is offline.
- Until this change a read-only transaction read documents one by one and asked the backend at the
  end whether they had changed, running again if so. Code that relied on the callback running
  again now sees the snapshot instead.

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
- Connectivity: a failed stream is the only thing that makes the client consider itself
  offline, and it retries with an exponential backoff (up to one minute). Two things can make
  it retry at once instead of waiting for the backoff:
  - **Built in, on the VM** (not on the web, which uses the `online` / `offline` events of the
    browser): while a stream is failing, and only then, the client reads the addresses of the
    network interfaces every 2 seconds (`NetworkInterface.list`). When an address appears (Wi-Fi
    joined again, a cable, a VPN, a new DHCP lease), or when the clock shows that the machine
    was asleep, it restarts its streams right away. This is a hint only: it never declares the
    client offline, a wrong hint costs one connection attempt, and a client whose streams work
    has no timer. In a test, after a 16 second outage a listener received a change 40 to 140 ms
    after such a hint, and 2 to 8 seconds after the network was back without one (the rest of
    the backoff, which is random). Only tested on macOS; the hint itself was simulated.
  - **From your app**: subclass `PlatformDependencies`, override `onNetworkConnected` and feed
    it from your own source (for example the `connectivity_plus` plugin in a Flutter app).
    Firestore restarts its streams, resetting the backoff, on every `true` event (after a 5
    second debounce); `false` is ignored. The first event from the app switches the built-in
    detector off for that instance, so there is nothing to configure to replace it.

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

The tests are not part of the published package: every `test/`, `tool/` and `docs/` path in
this README refers to a checkout of the
[repository](https://github.com/long1eu/firebase_dart_sdk/tree/main/cloud_firestore/cloud_firestore_dart) (`tool/` and `docs/` are at its
root). Run everything from this directory of the checkout. The scripts are in `tool/` at the
repository root (see `tool/README.md`).

| Tests | Command | Backend |
| --- | --- | --- |
| Unit | `dart test test/unit` | none |
| Integration | `FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart test test/integration` | standard emulator (`tool/start_emulator.sh`) |
| Enterprise | `FIRESTORE_ENTERPRISE_EMULATOR_HOST=127.0.0.1:8181 dart test test/integration_enterprise` | Enterprise edition emulator (`tool/start_enterprise_emulator.sh`) |
| Browser | `tool/test_browser.sh [dart2wasm\|dart2js\|both]` (repository root) | a private emulator on 127.0.0.1:8090 that the script starts, Chrome |
| Integration over the web transport | `tool/test_integration.sh standard --transport=webchannel` (repository root; also `--transport=webchannel-longpolling`) | the private emulator on 127.0.0.1:8090; runs on the VM |
| Chaos tests | part of `test/integration` (`firebase/firestore/chaos/`) | standard emulator behind a TCP proxy that cuts and stalls connections |
| Firestore Lite size check | `tool/check_size.sh` (repository root) | none; compiles two programs with `dart compile js` |
| Production verification kit | `FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 tool/verify_production/run.sh --backend=emulator` (repository root) | standard emulator; a real project only with `--backend=production --yes` and your credentials (not run yet) |
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
both editions except for the points below; the eleven tests that expect the Standard behaviour are
skipped there with a reason, and `test/integration_enterprise/edition_differences_test.dart`
pins the Enterprise behaviour. These were observed with the emulator only, not with a production
Enterprise database.

- **`null` and `NaN` in equality filters.** `whereIn`, `whereArrayContains` and
  `whereArrayContainsAny` match fields (or array elements) that are `null` or `NaN` when the
  filter value is `null` or `NaN`. On Standard they never match.
  The client evaluates these filters like Enterprise (as the JS and Android SDKs do: null is
  null, NaN is NaN; the same holds for `<=` and `>=` with a `null` or `NaN` operand). On
  Standard this means that a cached `null` or `NaN` document is first part of the local result
  of such a query, although the backend does not return it. Once the backend has confirmed
  that the document exists and that it is not a result, the client takes it out of the result
  of that query: a listener reports it with `isFromCache: true` and then its removal with
  `isFromCache: false`, and `get(Source.server)` returns what the backend returns. (The JS and
  Android SDKs keep such a document in limbo: the listener never leaves `isFromCache` and a get
  from the server does not complete.) The same mechanism covers any other query on which the
  client and the backend disagree about a cached document.
  `test/integration/firebase/firestore/property_query_test.dart` checks this.
- **`!=` and `not-in`** also return documents in which the field is `null` or missing on
  Enterprise (seen with RunQuery). The client drops them, as on Standard, but a `limit` counts
  them on the backend, so a page can come back with fewer documents than the limit although
  more match.
- **`sum` over no documents** is `null` on Enterprise and `0` on Standard (`average` is `null`
  on both).
- **Documents an aggregation covers.** On Standard, `sum`, `average` and `count` in one
  aggregation only see the documents that have every aggregated field; on Enterprise they see
  every document of the query.
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

Nothing in this repository has been run against a real project yet. There are two ways to do it,
both opt-in. The production verification kit (`tool/verify_production`, see its README) is the
smaller one: 14 named checks that make at most 80 writes below one document of their own,
print a plan first and only run with `--yes`. It passes against both emulators, with
the known emulator differences listed in its README.

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
  features only against the Enterprise edition emulator. The production verification kit and
  the opt-in real-project test mode exist but have not been run. The packages are not
  published.
- **Web beyond the experiment**: OPFS storage, and any browser other than Chrome.
- **Pipelines** beyond the [preview](#pipelines-preview) described above: full-text search,
  window functions, pipelines in a `Transaction`, local evaluation and real-time pipelines.
- `Query.findNearest` evaluation against the local cache.
- **Sharing one cache between running clients** (the multi-tab support of the JS SDK): one
  process, or one browser tab, at a time. See
  [Persistence and connectivity](#persistence-and-connectivity).
- **Persistent cache indexes** for queries with inequalities on several fields (they are
  scanned, as upstream), and with a memory cache.
- **A Firebase Auth client.** The app supplies the ID token through `PlatformDependencies`.
- Android-specific pieces of the Android SDK.
- Auth, Storage, Realtime Database: see
  [appsup-dart/firebase_dart](https://github.com/appsup-dart/firebase_dart).

Known gaps in what is done:

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
