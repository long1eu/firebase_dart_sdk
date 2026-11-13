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

What Lite does not have: snapshot streams, persistence and cache settings, bundles, vector
queries, pipelines, and the `whereEqualTo(...)` family of query methods (use `where`). The
[Firestore Lite section](../../cloud_firestore/cloud_firestore_dart/README.md#firestore-lite-experimental)
of the package README has the full list, and
[`example/lite.dart`](../../cloud_firestore/cloud_firestore_dart/example/lite.dart) is a runnable
program.
