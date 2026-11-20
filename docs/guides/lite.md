# Firestore Lite

`package:cloud_firestore_dart/lite.dart` is a second entry point: a client without a local
cache, without listeners and without the sync engine. Every call is one request to the backend
and one response. It is the counterpart of `firebase/firestore/lite` of the JS SDK, and supported
like the main library (see [what was verified](#what-was-verified)).

## When to use it

- Servers, command line tools and functions that read and write but never listen.
- Web apps that care about size: a program that only imports `lite.dart` contains no sync
  engine, local store, SQLite layer or WebChannel. The same small web app compiles to about
  416 KB of JavaScript (128 KB gzipped) with Lite and 641 KB (196 KB gzipped) with the main
  library and a memory cache.

Use the main library when you need listeners, offline behaviour, a cache, bundles, vector
queries or pipelines.

The two libraries side by side, layer by layer: Lite keeps the public API, the unary calls and the
transport, and leaves out the five layers in between that hold the cache and the listeners.

![Two stacks of layers. The main library has the public API, the client and serial queue, the event manager
and views, the sync engine, the local store and persistence, the remote store, a datastore with streams and
unary calls, and a transport of gRPC or REST and WebChannel. Firestore Lite has only the public API, a
datastore with unary calls and transactions, and a transport of gRPC or REST. The same small web app is
641,418 characters of JavaScript with the main library and 415,850 with
Lite.](../images/flows/lite_vs_main.svg)

## Usage

Import it *instead of* `cloud_firestore_dart.dart`:

```dart lite
import 'package:cloud_firestore_dart/lite.dart';

// Synchronous, and nothing is sent until the first call.
final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(app: app);

final CollectionReference<Map<String, Object?>> cities = firestore.collection('cities');
await cities.doc('LA').set({'name': 'Los Angeles', 'state': 'CA', 'population': 3900000});

final QuerySnapshot<Map<String, Object?>> californian =
    await cities.where('state', isEqualTo: 'CA').get();
print(californian.docs.map((QueryDocumentSnapshot<Map<String, Object?>> doc) => doc.id).toList());

final WriteBatch batch = firestore.batch()
  ..update(cities.doc('LA'), {'population': FieldValue.increment(1000)})
  ..delete(cities.doc('old'));
await batch.commit();

final AggregateQuerySnapshot count = await cities.count().get();
print(count.count);

await firestore.terminate();
```

Both libraries declare `Firestore`, `DocumentReference`, `CollectionReference`, `Query`, the
snapshot classes, `WriteBatch`, `Transaction`, `FirestoreDataConverter` and `Settings`;
to use both in one file, import one with a prefix. The value types (`Timestamp`, `GeoPoint`,
`Blob`, `FieldValue`, `FieldPath`, `Filter`, `SetOptions`, `AggregateField`, the BSON classes,
`FirestoreException`, ...) are the same classes in both.

## Behaviour to know

- **Writes are not queued or retried.** A write completes when the backend has applied it, and
  fails with the error of the backend (for example `unavailable` without a connection). Only
  transactions are retried.
- **No snapshot metadata, no `Source`.** Every read goes to the backend.
- **Transport**: gRPC on native platforms, REST over `fetch` on the web.
- **`limitToLast`** sends the query with its orderings reversed and reverses the result, as the
  JS SDK does.
- **`terminate()`** lets the calls in flight finish and closes the connection. On native
  platforms a program has to terminate its instances to exit.
- `FirestoreDataConverter.fromFirestore` takes only the snapshot (there are no snapshot
  options), and `DocumentReference.parent` keeps the converter of the reference.
- Authentication, App Check and the emulator settings work as in the main library.

## What it has and what it does not

- **What it has:** `ref.get()`, `set` / `update` / `delete`,
  `collection.add`, `firestore.batch()`, `runTransaction` (with `maxAttempts` and `readOnly`; read-only
  transactions with `Transaction.getQuery` and `getAggregate`), queries
  with `where` (named arguments or `Filter`), `orderBy`, `limit`, `limitToLast`, cursors and
  collection groups, `count()` / `aggregate` / `aggregateWithAliases`, `withConverter`,
  `DocumentReference.toJson` / `fromJson`, `terminate()`, the emulator settings with
  `mockUserToken`, Firebase Auth and App Check tokens of the `FirebaseApp`.
- **What it does not have:** snapshot streams, `Source`, snapshot metadata
  (`hasPendingWrites`, `isFromCache`), persistence and cache settings, bundles, offline
  behaviour of any kind, vector queries (`findNearest`) and pipelines. The JS SDK has a
  separate `firebase/firestore/lite/pipelines` entry point; this package has Pipelines only in
  the main library (preview, `package:cloud_firestore_dart/pipelines.dart`), not for Lite.

### Compared with `firebase/firestore/lite`

Every export of the JS entry point (`packages/firestore/lite/index.ts`, checked on 2026-11-20)
has a counterpart here, except the ones below. All of them are deliberate.

| JS | Here | Why |
|---|---|---|
| `firebase/firestore/lite/pipelines` (`execute`, the stages and expressions) | none in Lite | Pipelines are a preview of the main library; not ported to Lite |
| `Settings.ignoreUndefinedProperties` | none | Dart has no `undefined` |
| `connectFirestoreEmulator(db, host, port, {mockUserToken})` | `useFirestoreEmulator(host, port, {sslEnabled})`; the mock token through `Settings().withEmulator(host, port, mockUserToken: ...)` | The FlutterFire signature, as in the main library |
| `updateDoc(ref, 'a', 1, 'b', 2)` (field and value pairs) | `update({'a': 1, 'b': 2})` only | The FlutterFire and Android form, as in the main library |
| Free functions (`getDoc`, `setDoc`, `query(q, where(...))`, `writeBatch`, `getCount`, `getAggregate`, `refEqual`, `queryEqual`, `snapshotEqual`, `aggregateQuerySnapshotEqual`, `aggregateFieldEqual`, `documentId`, `deleteField`, `vector`, ...) and the `Query...Constraint` classes | Methods and constructors: `ref.get()`, `ref.set()`, `query.where(...)`, `firestore.batch()`, `query.count().get()`, `query.aggregate(...)`, `==`, `FieldPath.documentId`, `FieldValue.delete()`, `VectorValue(...)` | The API of the main library and FlutterFire |
| `Bytes`, `FirestoreError`, `snapshot.exists()`, `snapshot.ref`, `querySnapshot.empty`, `querySnapshot.forEach` | `Blob`, `FirestoreException`, `snapshot.exists`, `snapshot.reference`, `isEmpty`, `docs.forEach` | The names of the main library and FlutterFire |
| `snapshot.get('missing')` is `undefined` | `null` | Dart has no `undefined` |
| `Firestore.toJSON()`, `Firestore.type` and the TypeScript helper types (`DocumentData`, `UpdateData`, `WithFieldValue`, `AggregateSpec`, ...) | none | Not needed in Dart |

Beyond the JS entry point, Lite here has: read-only transactions (`readOnly`, `readTime`) with
`Transaction.getQuery` and `getAggregate`, a transaction `timeout`, `Filter(isNull: ...)`,
`DocumentSnapshot.contains` and `[]`, the BSON value types with their names of the main library,
`FirebaseFirestore.instance` and a `settings` setter that works until the first request.

Differences from the main library that are not just missing features:
`FirebaseFirestore.instanceFor` is synchronous; `FirestoreDataConverter.fromFirestore` takes only the
snapshot (a `QueryDocumentSnapshot`, there are no snapshot options); `DocumentReference.parent`
keeps the converter of the reference, as in the JS SDK; `firestore.doc('')` throws; two
`AggregateQuerySnapshot`s are equal when they hold the same results under the same names, in
any order.

## Size

A program that only imports `lite.dart` does not contain the sync engine, the local
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

[`example/lite.dart`](../../cloud_firestore/cloud_firestore_dart/example/lite.dart) is a runnable
program.

## What was verified

- **The Firestore emulator only.** `test/integration/firebase/firestore/lite_test.dart` (a port
  of the JS SDK's Lite integration tests, with additions) runs on the Dart VM over gRPC and over
  REST (`FIRESTORE_TEST_TRANSPORT=rest`): reads, writes, merges, transforms, batches (several
  writes, all or nothing), transactions (retries, `maxAttempts`, read-only), queries with
  filters, orders, limits, `limitToLast`, cursors from values and from document snapshots,
  collection groups, `count`, `sum` and `average` (also over cursors), converters (on
  references, queries, batches and transactions), vectors and mock user tokens.
- **Chrome only.** `test/browser/web_lite_test.dart` runs the same areas in Chrome, compiled
  with dart2js and dart2wasm, against the emulator. Firefox and Safari were not tried.
- **Never against a production backend.** Lite was not run against a real Firebase project.

