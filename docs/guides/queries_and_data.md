# Queries, data and the API

Reads, writes, queries, aggregations, typed converters and the other everyday calls, and how
the API compares with FlutterFire and the JS SDK. The snippets assume an `app`, `firestore`,
`users`, `query` and `bundleBytes` in scope; [Getting started](getting_started.md) shows how to
create them.

## Basics

```dart
import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';

// `app` is a FirebaseApp created with firebase_app_dart.
final firestore = Firestore.instanceFor(app: app);
final users = firestore.collection('users');
await users.doc('ada').set({'name': 'Ada', 'age': 36});
final adults = await users.whereGreaterThanOrEqualTo('age', 18).get();
```

(Filters are the Java-style `whereEqualTo`, `whereGreaterThan`, ... family, plus
`where('age', isGreaterThanOrEqualTo: 18)` with named arguments and `where(Filter)`. See
`example/` and, in the repository,
[`test/integration/`](https://github.com/long1eu/firebase_dart_sdk/tree/main/cloud_firestore/cloud_firestore_dart/test/integration) for working calls of every feature below.)

For the emulator, mock users and debug logging see [The emulator and testing](emulator_and_testing.md).

## Aggregations, OR queries and vector search

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

## Typed data converters

Modelled after the JS `withConverter`:

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

## Bundles, snapshot JSON and synchronisation

See [Offline persistence](offline_persistence.md) for the cache settings and
[Transactions and the lifecycle](transactions_and_lifecycle.md) for `terminate()`.

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

## Coming from FlutterFire or the JS SDK

The API follows the Android SDK, with FlutterFire's spelling where the two differ only in name
(`Firestore.instanceFor`, `doc`, `docs`, `docChanges`, `where(field, isEqualTo: ...)`,
`databaseId`). Where the shapes differ, there is one way, not both:

| FlutterFire / JS | This package |
|---|---|
| `ref.get(const GetOptions(source: Source.cache))` | `ref.get(Source.cache)` (same `Source` values) |
| `GetOptions(serverTimestampBehavior: ...)` / JS `data({serverTimestamps: ...})` | `snapshot.getData(ServerTimestampBehavior.estimate)`, or `get(field, behavior)` per field |
| JS `getDocFromCache(ref)` / `getDocFromServer(ref)` | `ref.get(Source.cache)` / `ref.get(Source.server)` |
| `snapshot.data()` | `snapshot.data` (a getter) |
| `SetOptions(merge: true)` | `SetOptions.mergeAllFields` |
| `SetOptions(mergeFields: ['a', FieldPath(...)])` | `SetOptions.mergeFields(['a'])` / `SetOptions.mergeFieldPaths([...])` |

A `GetOptions` class would only add the server timestamp default of FlutterFire, which is a
property of reading the data rather than of fetching it; `SnapshotOptions` (with
`serverTimestamps`, as in JS) is what a `FirestoreDataConverter` receives.

## The supported API

The main library exposes no implementation members: what the golden listing shows is the
supported API. (The Firestore Lite and Pipelines listings still mark a few members of their own
classes `@internal`; the analyzer warns when you use those and they may change in any release.)

The exact signatures are pinned in `test/unit/api/public_api.golden.txt` in the repository.

The public entry point is `package:cloud_firestore_dart/cloud_firestore_dart.dart` (class
`Firestore`). It needs a `FirebaseApp` from `firebase_app_dart`. Runnable programs, one per topic
(a quick start, queries, transactions, offline persistence, a backend process, Lite, Pipelines and
more), are in [`example/`](../../cloud_firestore/cloud_firestore_dart/example/README.md). See
[The emulator and testing](emulator_and_testing.md) for how to run the tests.
