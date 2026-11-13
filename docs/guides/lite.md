# Firestore Lite

`package:cloud_firestore_dart/lite.dart` is a second entry point: a client without a local
cache, without listeners and without the sync engine. Every call is one request to the backend
and one response. It is the counterpart of `firebase/firestore/lite` of the JS SDK. The API is
**experimental** and may change in any release.

## When to use it

- Servers, command line tools and functions that read and write but never listen.
- Web apps that care about size: a program that only imports `lite.dart` contains no sync
  engine, local store, SQLite layer or WebChannel. The same small web app compiles to about
  416 KB of JavaScript (128 KB gzipped) with Lite and 641 KB (196 KB gzipped) with the main
  library and a memory cache.

Use the main library when you need listeners, offline behaviour, a cache, bundles, vector
queries or pipelines.

## Usage

Import it *instead of* `cloud_firestore_dart.dart`:

```dart lite
import 'package:cloud_firestore_dart/lite.dart';

// Synchronous, and nothing is sent until the first call.
final Firestore firestore = Firestore.instanceFor(app: app);

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
print(count.getCount());

await firestore.terminate();
```

Both libraries declare `Firestore`, `DocumentReference`, `CollectionReference`, `Query`, the
snapshot classes, `WriteBatch`, `Transaction`, `FirestoreDataConverter` and `FirestoreSettings`;
to use both in one file, import one with a prefix. The value types (`Timestamp`, `GeoPoint`,
`Blob`, `FieldValue`, `FieldPath`, `Filter`, `SetOptions`, `AggregateField`, the BSON classes,
`FirestoreError`, ...) are the same classes in both.

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

Differences from the main library that are not just missing features:
`Firestore.instanceFor` is synchronous; `FirestoreDataConverter.fromFirestore` takes only the
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
