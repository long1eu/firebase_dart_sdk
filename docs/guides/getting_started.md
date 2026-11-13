# Getting started

This guide takes you from an empty Dart project to a first read and write with
`cloud_firestore_dart`, on the Dart VM (servers, command line tools, Flutter apps) and in the
browser. It assumes you have a Firebase project with a Firestore database, or that you use the
[emulator](emulator_and_testing.md).

`cloud_firestore_dart` is an unofficial port of the Firebase Android SDK. It has been verified
against the Firestore emulator only; nothing has been run against production Firestore yet.
See [Features and limits](features.md) for what is done and what is not.

## Install

```shell
dart pub add cloud_firestore_dart firebase_app_dart
```

`firebase_app_dart` holds the `FirebaseApp` and its `FirebaseOptions`; Firestore needs one to
know the project. For signed-in users or server credentials, also add
[`firebase_auth_providers_dart`](../../firebase_auth/firebase_auth_providers_dart/README.md).

## Create the app and the Firestore instance

```dart
import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';

final FirebaseApp app = FirebaseApp.withOptions(
  const FirebaseOptions(
    apiKey: '<the Web API key of the project>',
    applicationId: '1:1234567890:web:0123456789abcdef',
    projectId: 'my-project',
  ),
);

// Returns at once: the client opens its cache and connects in the background,
// and every operation waits for that.
final Firestore firestore = Firestore.instanceFor(app: app);
```

- The options are those of a Firebase app of the project. The values of a web app (Firebase
  console, *Project settings*, *Your apps*) work on every platform. The
  [`firebase_app_dart` README](../../firebase_core/firebase_app_dart/README.md) explains how to
  make an application id for a desktop platform.
- `Firestore.instanceFor` returns the same instance for the same app and database until that
  instance is terminated. Settings and the cache opener are only used by the call that creates
  it. Use `database: 'my-database'` for a named database.
- Without a token provider the requests are not authenticated, so the security rules see no
  user. See [Authentication](authentication.md).

## Read and write

```dart
final CollectionReference<Map<String, Object?>> cities = firestore.collection('cities');

// Writes complete when the backend has acknowledged them.
await cities.doc('SF').set({'name': 'San Francisco', 'state': 'CA', 'population': 870000});
await cities.doc('SF').update({'population': FieldValue.increment(1)});
final DocumentReference<Map<String, Object?>> added = await cities.add({'name': 'Tokyo'});

// One read.
final DocumentSnapshot<Map<String, Object?>> sf = await cities.doc('SF').get();
print(sf.data);

// A query.
final QuerySnapshot<Map<String, Object?>> californian = await cities
    .where('state', isEqualTo: 'CA')
    .orderBy('population', Direction.descending)
    .limit(10)
    .get();
for (final QueryDocumentSnapshot<Map<String, Object?>> city in californian.docs) {
  print('${city.id}: ${city.data}');
}

// Changes in real time, until the subscription is cancelled.
final subscription = cities.where('state', isEqualTo: 'CA').snapshots.listen(
  (QuerySnapshot<Map<String, Object?>> snapshot) {
    for (final DocumentChange<Map<String, Object?>> change in snapshot.docChanges) {
      print('${change.type}: ${change.document.id}');
    }
  },
);
await subscription.cancel();
await added.delete();
```

The package [`example/`](../../cloud_firestore/cloud_firestore_dart/example/README.md) folder
has a runnable program for each topic: queries, aggregations, typed converters, transactions,
bundles, snapshot JSON, offline persistence, the emulator, the lifecycle, Firestore Lite and
Pipelines.

## End the program

On the Dart VM the instance keeps network connections and timers open, so a command line
program does not exit while an instance is alive. Terminate it when you are done:

```dart
// Writes that the backend has not acknowledged yet are kept in a persistent
// cache and sent by the next instance; with a memory cache they are lost.
await firestore.waitForPendingWrites();
await firestore.terminate();
```

After `terminate()` the instance cannot be used again; `Firestore.instanceFor` creates a new one.
See [the lifecycle](transactions_and_lifecycle.md#lifecycle-terminate) for what
happens to work in progress.

## Flutter

Use the package as a plain Dart package: there is no plugin to register. Create the app and the
instance once, for example in `main()` before `runApp`. To keep the cache across restarts, give
the instance a SQLite opener and a directory from `path_provider` (see
[Offline persistence](offline_persistence.md)); add `sqlite3_flutter_libs` so that the native
SQLite library is bundled with the app.

Two Flutter specifics:

- **Hot restart** starts a new isolate while the old one may still hold the cache open. The new
  client takes the cache over (see [Several clients on one cache](multiple_clients.md)).
- **Connectivity**: on the VM the client notices a new network address by itself while it is
  offline. You can also feed it the connectivity events of a plugin through
  `PlatformDependencies.onNetworkConnected`; see
  [Connectivity](offline_persistence.md#connectivity).

## The web

The same code runs in the browser (experimental: tested in Chrome, against the emulator only).
Browsers have no sockets, so there the client talks to Firestore the way the JS SDK does: REST
for one-shot calls, WebChannel for listeners and writes.

- Build the app as any Dart web app. Prefer dart2wasm (`dart compile wasm`): compiled to
  JavaScript, integers above 2^53 lose precision.
- Do not compile with `-Dprotobuf.omit_field_names=true` or `-Dprotobuf.omit_enum_names=true`;
  the web transport needs those names and refuses to start without them.
- The cache is in memory unless you pass the web opener (IndexedDB or OPFS); see
  [Offline persistence on the web](offline_persistence.md#on-the-web).
- If listeners or writes never complete behind a proxy that buffers streamed responses, use
  long polling:

```dart
final Firestore firestore = Firestore.instanceFor(
  app: app,
  settings: FirestoreSettings(experimentalForceLongPolling: true),
);
```

For a smaller program that only reads and writes, without cache or listeners, see
[Firestore Lite](lite.md). [Platforms](platforms.md) has the details of the web transport, its
measurements and its limits.

## Next steps

- [Queries, data and the API](queries_and_data.md)
- [Transactions and the lifecycle](transactions_and_lifecycle.md)
- [Authentication and App Check](authentication.md)
- [Offline persistence and cache settings](offline_persistence.md)
- [Several clients on one cache](multiple_clients.md)
- [The emulator and testing](emulator_and_testing.md)
- [Firestore Lite](lite.md)
- [Pipelines (preview, Enterprise only)](pipelines.md)
- [Platforms](platforms.md)
- [Features and limits](features.md)
- [Migrating from the `_vm` packages](../migrating_from_vm_packages.md)
