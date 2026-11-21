# For AI coding agents

This page is for a coding agent (or a person) that writes Dart or Flutter code against
`cloud_firestore_dart`, `firebase_app_dart` and `firebase_auth_providers_dart`. After reading it
you can pick the packages, write the imports and the setup, avoid the FlutterFire and JS SDK
names that do not exist here, and check your code against the Firestore emulator.

**Read this first.** This is not FlutterFire's `cloud_firestore` and not the Firebase JS SDK. It
is an unofficial pure-Dart port of the Firebase Android SDK: no Flutter plugin, no platform
channels, no native SDK, no `firebase_core`, no `Firebase.initializeApp()`, no
`google-services.json` or `firebase_options.dart` step. Code you remember from those SDKs will
often not compile here. The exact public API of the main library is the listing in
`cloud_firestore/cloud_firestore_dart/test/unit/api/public_api.golden.txt` in the repository;
when in doubt, search it.

## Which package for what

| You need | Add | Import |
|---|---|---|
| Firestore (always) | `cloud_firestore_dart: ^0.3.2` | `package:cloud_firestore_dart/cloud_firestore_dart.dart` |
| The `FirebaseApp` (always) | `firebase_app_dart: ^0.2.0` | `package:firebase_app_dart/firebase_app_dart.dart` |
| End users signed in (email/password, anonymous, custom token) or a service account key | `firebase_auth_providers_dart: ^0.3.0` | `package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart` |
| Application Default Credentials (servers, CLIs; needs `dart:io`) | `firebase_auth_providers_dart: ^0.3.0` | `package:firebase_auth_providers_dart/adc.dart` |
| Cloud Storage for Firebase (uploads, downloads, listing; unreleased, 0.1.0) | `firebase_storage_dart` | `package:firebase_storage_dart/firebase_storage_dart.dart`; `io.dart` for `putFile` and `writeToFile` (needs `dart:io`) |
| A disk cache (VM, Flutter, web) | `cloud_firestore_dart_sqlite: ^0.1.3` | `package:cloud_firestore_dart_sqlite/cloud_firestore_dart_sqlite.dart` |
| Firestore Lite, no cache and no listeners | `cloud_firestore_dart` | `package:cloud_firestore_dart/lite.dart` instead of the main library |
| Pipelines (preview, Enterprise edition databases only) | `cloud_firestore_dart` | `package:cloud_firestore_dart/pipelines.dart` in addition to the main library |

```shell
dart pub add cloud_firestore_dart firebase_app_dart
dart pub add firebase_auth_providers_dart   # only for signed-in users or server credentials
```

All three packages need Dart `^3.8.0` and do not depend on Flutter. Do not add `firebase_core`,
`cloud_firestore` or `firebase_auth` for this client; if the project already has them, see
"Using both in one app" in [Coming from FlutterFire](migrating_from_flutterfire.md).

## A Dart CLI or server against the emulator

```dart
import 'dart:io';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';

Future<void> main() async {
  // Synchronous. A `demo-` project id keeps the emulator away from real projects; the emulator
  // accepts any API key and application id.
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'demo-key',
      appId: '1:1234567890:dart:demo',
      projectId: 'demo-my-app',
    ),
  );

  // The package does not read FIRESTORE_EMULATOR_HOST itself.
  final String emulator = Platform.environment['FIRESTORE_EMULATOR_HOST'] ?? '127.0.0.1:8080';
  final int colon = emulator.lastIndexOf(':');
  final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
    app: app,
    settings: Settings().withEmulator(
      emulator.substring(0, colon),
      int.parse(emulator.substring(colon + 1)),
    ),
  );

  try {
    final CollectionReference<Map<String, Object?>> users = firestore.collection('users');
    await users.doc('ada').set(<String, Object?>{'name': 'Ada', 'age': 36});
    await users.doc('ada').update(<String, Object?>{'age': FieldValue.increment(1)});

    final DocumentSnapshot<Map<String, Object?>> ada = await users.doc('ada').get();
    print('${ada.id}: ${ada.data()}');

    final QuerySnapshot<Map<String, Object?>> adults = await users
        .where('age', isGreaterThanOrEqualTo: 18)
        .orderBy('age', descending: true)
        .limit(10)
        .get();
    for (final QueryDocumentSnapshot<Map<String, Object?>> doc in adults.docs) {
      print('${doc.id} ${doc.data()['name']}');
    }
  } on FirestoreException catch (e) {
    stderr.writeln('Firestore failed: ${e.code} ${e.message}');
    exitCode = 1;
  } finally {
    // Without this the open gRPC channel keeps the process alive.
    await firestore.terminate();
  }
}
```

Run it with `FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run bin/main.dart` while an emulator
runs (see [Run and test against the emulator](#run-and-test-against-the-emulator)).

## A server with Application Default Credentials

```dart
import 'dart:io';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/adc.dart'; // needs dart:io

Future<void> main() async {
  final FirebaseApp app = FirebaseApp.withOptions(
    FirebaseOptions(
      apiKey: '', // an empty key is not sent
      appId: '1:1234567890:dart:server', // any unique id works on a server
      projectId: Platform.environment['FIREBASE_PROJECT_ID'] ?? 'my-project',
    ),
  );

  // Before FirebaseFirestore.instanceFor. GOOGLE_APPLICATION_CREDENTIALS, then gcloud's application
  // default login, then the metadata server (Cloud Run, Compute Engine, GKE).
  // These credentials bypass security rules; IAM decides (role Cloud Datastore User).
  app.authProvider = applicationDefaultCredentials();

  // One instance for the whole process, shared by every request. No openDatabase: nothing is
  // written to disk, and eager garbage collection drops documents no listener needs.
  final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
    app: app,
    settings: Settings(
      cacheSettings: const MemoryCacheSettings(gcSettings: MemoryEagerGcSettings()),
    ),
  );

  // Source.server: never answer a request from a stale cache.
  final DocumentSnapshot<Map<String, Object?>> config = await firestore
      .doc('config/app')
      .get(const GetOptions(source: Source.server));
  print(config.exists ? config.data() : 'no config');

  await firestore.terminate();
}
```

With a service account key instead (also bypasses rules), from the main library of
`firebase_auth_providers_dart`, which works without `dart:io`:
`app.authProvider = OAuthTokenProvider.serviceAccount(jsonDecode(keyJson));`. Never put a key
or ADC in an app that end users run; use `FirebaseUserAuth` there.

## A Flutter app with the SQLite cache

```shell
flutter pub add cloud_firestore_dart firebase_app_dart path_provider cloud_firestore_dart_sqlite
```

`cloud_firestore_dart_sqlite` brings `sqlite3`; on Flutter 3.38 or later that is 3.x, which
bundles SQLite itself. On an older Flutter add `sqlite3_flutter_libs: ^0.5.0` too. Do not copy
any opener file. This program uses `dart:io` (`Directory`), so it is not for the web.

```dart flutter
import 'dart:io';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'package:cloud_firestore_dart_sqlite/cloud_firestore_dart_sqlite.dart';

late final FirebaseFirestore firestore;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The values of a web app of the project work on every platform
  // (Firebase console, Project settings, Your apps).
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: '<the Web API key of the project>',
      appId: '1:1234567890:web:0123456789abcdef',
      projectId: 'my-project',
    ),
  );
  final Directory directory = await getApplicationSupportDirectory();
  // Once, before runApp. Without openDatabase the cache would be in memory.
  firestore = FirebaseFirestore.instanceFor(
    app: app,
    openDatabase: sqliteOpener(directory: '${directory.path}/firestore'),
    settings: Settings(cacheSettings: PersistentCacheSettings()),
  );
  runApp(const NotesApp());
}

class NotesApp extends StatelessWidget {
  const NotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    final CollectionReference<Map<String, Object?>> notes = firestore.collection('notes');
    return MaterialApp(
      home: Scaffold(
        body: StreamBuilder<QuerySnapshot<Map<String, Object?>>>(
          // A getter, not a method. Local writes appear at once, also offline.
          stream: notes.orderBy('createdAt').snapshots(),
          builder: _buildList,
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            // Not awaited: the future completes when the backend acknowledges the write,
            // which does not happen while the device is offline.
            notes
                .add(<String, Object?>{'text': 'A note', 'createdAt': Timestamp.now()})
                .then(
                  (DocumentReference<Map<String, Object?>> _) {},
                  onError: (Object error) => debugPrint('write failed: $error'),
                );
          },
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  static Widget _buildList(
    BuildContext context,
    AsyncSnapshot<QuerySnapshot<Map<String, Object?>>> snapshot,
  ) {
    if (snapshot.hasError) {
      return Center(child: Text('${snapshot.error}'));
    }
    final List<QueryDocumentSnapshot<Map<String, Object?>>> docs =
        snapshot.data()?.docs ?? <QueryDocumentSnapshot<Map<String, Object?>>>[];
    return ListView(
      children: <Widget>[
        for (final QueryDocumentSnapshot<Map<String, Object?>> doc in docs)
          ListTile(title: Text('${doc.data()['text']}')),
      ],
    );
  }
}
```

On the Android emulator the host machine is `10.0.2.2`; nothing maps `localhost` for you. For
the web, use a memory cache or `sqliteOpener()` without a directory, with `sqlite3.wasm` next to
the page (see
[Offline persistence](offline_persistence.md#on-the-web)). No test in this repository runs a
Flutter app on a device.

## This, not that

Left: what you may remember from FlutterFire `cloud_firestore` (FF) or the JS modular SDK (JS).
Right: the name in this client, or "not available".

| FlutterFire / JS | Here |
|---|---|
| `import 'package:cloud_firestore/cloud_firestore.dart'`, `firebase_core` | `package:cloud_firestore_dart/cloud_firestore_dart.dart`, `package:firebase_app_dart/firebase_app_dart.dart` |
| FF `await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)`; JS `initializeApp(config)` | `await Firebase.initializeApp(options: const FirebaseOptions(apiKey: ..., appId: ..., projectId: ...))`, or the synchronous `FirebaseApp.withOptions(...)` |
| FF `FirebaseFirestore.instance` (creates it); JS `getFirestore(app)` | `FirebaseFirestore.instance` (creates the instance of the default app), or `FirebaseFirestore.instanceFor(app: app)` |
| FF `instanceFor(app: app, databaseId: 'db')`; JS `getFirestore(app, 'db')` | `FirebaseFirestore.instanceFor(app: app, databaseId: 'db')` |
| FF `firestore.settings = Settings(...)`; JS `initializeFirestore(app, {...})` | `firestore.settings = Settings(...)` before the first use, or `FirebaseFirestore.instanceFor(app: app, settings: Settings(...))` |
| FF `useFirestoreEmulator('localhost', 8080)`; JS `connectFirestoreEmulator(db, host, port)` | `firestore.useFirestoreEmulator('127.0.0.1', 8080)` before the first use, or `settings: Settings().withEmulator('127.0.0.1', 8080)` |
| FF `Settings(persistenceEnabled: true)`; JS `persistentLocalCache()`, `enableIndexedDbPersistence` | `openDatabase: sqliteOpener(directory: dir)` (`cloud_firestore_dart_sqlite`) plus `PersistentCacheSettings()`; without `openDatabase` the cache is in memory |
| JS `persistentMultipleTabManager()` | not available (one client per cache in a browser) |
| FF `Settings.CACHE_SIZE_UNLIMITED`; JS `CACHE_SIZE_UNLIMITED` | `Settings.cacheSizeUnlimited` |
| JS `doc(db, 'a/b')`, `collection(db, 'a')` | `firestore.doc('a/b')`, `firestore.collection('a')` |
| JS `getDoc`, `getDocFromCache`, `getDocFromServer` | `ref.get()`, `ref.get(const GetOptions(source: Source.cache))`, `ref.get(const GetOptions(source: Source.server))` |
| FF `get(const GetOptions(source: Source.cache))` | the same; `GetOptions` has only `source` |
| FF `set(data, SetOptions(merge: true))`; JS `setDoc(ref, data, {merge: true})` | `set(data, const SetOptions(merge: true))` |
| FF `SetOptions(mergeFields: [...])` | `SetOptions(mergeFields: ['a'])`, `SetOptions(mergeFields: [FieldPath(['a', 'b'])])` |
| FF `update({FieldPath(...): v})`; JS `updateDoc(ref, field, value, ...)` | `update(<Object, Object?>{'a.b': v, FieldPath(['c.d']): w})` (keys `String` or `FieldPath`) |
| JS `addDoc`, `deleteDoc` | `collection.add(data)`, `ref.delete()` |
| JS `deleteField()`, `serverTimestamp()`, `increment(n)`, `arrayUnion(a, b)` | `FieldValue.delete()`, `FieldValue.serverTimestamp()`, `FieldValue.increment(n)`, `FieldValue.arrayUnion([a, b])` (a list) |
| FF `snapshot.data()`; JS `snap.data()`, `snap.exists()` | `snapshot.data()` (a method), `snapshot.exists` (a getter) |
| FF `snapshot.reference` | `snapshot.reference` |
| FF `snapshot.get(FieldPath(...))` | `snapshot.get(FieldPath([...]))` |
| FF `ref.snapshots()`; JS `onSnapshot(ref, cb)` | `ref.snapshots().listen(cb)`; cancel the subscription to stop |
| FF `snapshots(includeMetadataChanges: true)` | `snapshots(includeMetadataChanges: true)` |
| FF `snapshots(source: ListenSource.cache)` | `snapshots(source: ListenSource.cache)` |
| FF `querySnapshot.size`; JS `snap.size`, `snap.empty` | `querySnapshot.size`, `isEmpty` |
| JS `snap.docChanges()` | `snap.docChanges` (a getter) |
| FF/JS `change.doc` | `change.doc` |
| JS `query(col, where('a', '==', 1), orderBy('a', 'desc'), limit(5))` | `col.where('a', isEqualTo: 1).orderBy('a', descending: true).limit(5)` |
| FF `orderBy('a', descending: true)` | `orderBy('a', descending: true)`, also with a `FieldPath` |
| FF `Filter('a', isEqualTo: 1)`; JS `where('a', '==', 1)` inside `or(...)` | `Filter('a', isEqualTo: 1)` |
| FF `Filter.or(f1, f2)`; JS `or(f1, f2)` | `Filter.or([f1, f2])`, `Filter.and([...])` (a list) |
| FF `FieldPath(['a', 'b'])`, `FieldPath.documentId`; JS `documentId()` | `FieldPath(['a', 'b'])`, `FieldPath.documentId` |
| FF `count().get()` then `.count`; JS `getCountFromServer(q)` then `.data().count` | `q.count().get()` then `.count` |
| FF `aggregate(sum('a'), average('a'))`; JS `getAggregateFromServer(q, {...})` | `q.aggregate([AggregateField.sum('a'), AggregateField.average('a')])` then `getSum('a')`, `getAverage('a')`, `get(field)`; named: `aggregateWithAliases({...})` then `data()` |
| FF `get(source: AggregateSource.server)` | the same |
| FF `runTransaction(fn, timeout: ..., maxAttempts: 5)`; JS `runTransaction(db, fn)` | `firestore.runTransaction(fn, maxAttempts: 5)`; no timeout |
| JS `writeBatch(db)` | `firestore.batch()` (writes chain), or `firestore.runBatch((batch) async {...})` |
| FF `Timestamp.millisecondsSinceEpoch`, `fromMillisecondsSinceEpoch` | the same |
| JS `Bytes` | `Blob` |
| FF `withConverter(fromFirestore: ..., toFirestore: ...)`; JS `withConverter(converter)` | `withConverter<T>(fromFirestore: ..., toFirestore: ...)`; `withoutConverter()` |
| FF `FirebaseException` with `e.code == 'permission-denied'`; JS `FirestoreException.code` string | `FirestoreException` (a `FirebaseException`) with `e.code == 'permission-denied'`, or `e.errorCode == FirestoreErrorCode.permissionDenied` |
| FF `snapshotsInSync()`; JS `onSnapshotsInSync` | `firestore.snapshotsInSync()` (a stream) |
| FF `namedQueryGet(name)`; JS `namedQuery(db, name)` | `firestore.namedQueryGet(name)`, or `firestore.namedQuery(name)` for the `Query` |
| FF `loadBundle(Uint8List)` | `loadBundle(List<int>)`, `loadBundleStream(stream)` |
| FF `persistentCacheIndexManager()` | `persistentCacheIndexManager` (a getter, null with a memory cache) |
| FF `FirebaseFirestore.setLoggingEnabled(true)`; JS `setLogLevel('debug')` | `FirebaseFirestore.setLogLevel(LogLevel.debug)` |
| JS `clearIndexedDbPersistence(db)`, `terminate(db)` | `firestore.terminate()`, then `firestore.clearPersistence()` |
| FF `FirebaseAuth.instance.signInWithEmailAndPassword(email: ..., password: ...)` | `final auth = await FirebaseUserAuth.forApp(app);` then `auth.signInWithEmailAndPassword(email: ..., password: ...)` |
| FF `FirebaseAuth.instance.currentUser?.uid`, `authStateChanges()`, `idTokenChanges()`, `userChanges()` | `auth.uid`, `auth.currentUser`, `auth.authStateChanges()`, `auth.idTokenChanges()`, `auth.userChanges()` |
| FF `signInWithCredential(GoogleAuthProvider.credential(idToken: ...))` and the other providers, `linkWithCredential`, `unlink`, email link sign-in | the same names on `FirebaseUserAuth` (the app gets the provider's token itself) |
| `signInWithPopup`, `signInWithProvider`, phone, multi-factor | not available |
| FF `webExperimentalForceLongPolling` | `Settings(webExperimentalForceLongPolling: true)` |
| FF `ignoreUndefinedProperties`, JS `Temporal` conversion | not available (not applicable to Dart) |
| Storage, Messaging, Realtime Database, Analytics, Remote Config | not available in these packages |

Names that are the same here: `collection`, `doc`, `collectionGroup`, `add`, `delete`,
`where(field, isEqualTo: ..., isGreaterThan: ..., arrayContains: ..., whereIn: ...)`, `limit`,
`limitToLast`, `startAt` / `startAfter` / `endAt` / `endBefore` (a `List`) and their
`...Document` forms, `docs`, `metadata.isFromCache`, `metadata.hasPendingWrites`, `GeoPoint`,
`Timestamp(seconds, nanoseconds)`, `Timestamp.now()`, `toDate()`, `VectorValue`,
`enableNetwork`, `disableNetwork`, `waitForPendingWrites`, `terminate`, `clearPersistence`.
`FirebaseFirestore` and `Settings` exist only as typedefs of `Firestore` and
`Settings`; write the real names.

## Rules

1. **One instance per app and database.** `FirebaseFirestore.instanceFor(app: app)` returns the same
   instance on every call until it is terminated. Create it once at startup and share it; a
   server must not create one per request.
2. **Settings only at creation.** Pass `settings:` (and `openDatabase:`) to the `instanceFor` call
   that creates the instance. A later call with different settings throws `StateError`; a later
   `openDatabase` is ignored. To change them, `terminate()` first.
3. **Token provider before the instance.** Set `app.authProvider = ...` or call
   `FirebaseUserAuth.forApp(app)` before `FirebaseFirestore.instanceFor`. Without one, requests carry no
   user and the security rules see none.
4. **A write future completes when the backend acknowledges the write.** Offline it does not
   complete until the client is back online. Do not `await` a write before updating a UI; the
   cache and the listeners show it at once. Attach an error handler instead.
5. **`terminate()` on exit.** On the VM an open instance keeps the process alive. Call
   `waitForPendingWrites()` first if unacknowledged writes matter: after `terminate()` their
   futures never complete, and with a memory cache they are lost. A terminated instance cannot
   be used again; `instanceFor` then creates a new one.
6. **Memory cache by default.** Without `openDatabase` the cache is in memory, whatever
   `persistenceEnabled` says. The SQLite opener is in the companion package
   `cloud_firestore_dart_sqlite` (`sqliteOpener`, VM, Flutter and web); do not copy the old
   `example/sqlite_database*.dart` files.
7. **What needs `dart:io`.** `package:firebase_auth_providers_dart/adc.dart` and any
   `Platform.environment` you read. `cloud_firestore_dart_sqlite` compiles everywhere. The main
   libraries of the three packages also compile for the web.
8. **Preview.** Pipelines (`pipelines.dart`, Enterprise edition only). It, and
   `package:firebase_app_dart/internal.dart`, are outside any compatibility promise. Firestore
   Lite (`lite.dart`) is supported like the main library.
9. **Errors.** A failed operation reports a `FirestoreException`; compare
   `FirestoreErrorCode` values through `e.errorCode` (`e.code` is FlutterFire's string, such as
   `'not-found'`). `FirestoreException` extends `FirebaseException`, an `Exception`: use
   `on FirestoreException catch`. Invalid arguments throw
   `ArgumentError`. Listener errors arrive on the stream's `onError`.
10. **Transactions may run their callback more than once** (up to `maxAttempts`, 5 by default).
    Keep side effects out of it. A commit whose answer is lost can be applied twice; make such
    writes idempotent. `getQuery` and `getAggregate` only work in
    `readOnly: true` transactions.
11. **Server credentials bypass security rules.** `applicationDefaultCredentials()` and
    `OAuthTokenProvider.serviceAccount` are for machines you control, never for apps end users
    run. Do not commit key files.
12. **A second isolate or process** on the same cache file gets its own app name or database;
    clients that share a cache do not share listeners or pending writes
    ([Several clients on one cache](multiple_clients.md)).
13. **Do not invent API.** If a name is not in the golden listing, it does not exist. No
    `GetOptions`, no `Firestore.settings` setter, no `snapshots()` method, no `size` on a query
    snapshot. Do not write deprecated names either: `FieldPath.documentId` (use
    `FieldPath.documentId`), `document()` (use `doc()`), `shutdown()` (use `terminate()`),
    `documents` and `documentChanges` (use `docs` and `docChanges`), `Source.defaultSource`.

## Run and test against the emulator

Start an emulator with the Firebase CLI (Java required):

```shell
firebase emulators:start --only firestore --project demo-my-app
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run bin/main.dart
```

A test with `package:test` (add `test` as a dev dependency):

```dart
import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';

void main() {
  late FirebaseFirestore db;
  int instances = 0;

  setUp(() {
    // A new app name per test gives each test its own instance and cache.
    final FirebaseApp app = FirebaseApp.withOptions(
      const FirebaseOptions(
        apiKey: 'demo-key',
        appId: '1:1234567890:dart:test',
        projectId: 'demo-my-app',
      ),
      name: 'test-${instances++}',
    );
    db = FirebaseFirestore.instanceFor(
      app: app,
      settings: Settings().withEmulator('127.0.0.1', 8080),
    );
  });

  tearDown(() async {
    await db.terminate();
    await db.clearPersistence();
  });

  test('writes and reads a document', () async {
    final DocumentReference<Map<String, Object?>> doc = db
        .collection('test-${DateTime.now().microsecondsSinceEpoch}')
        .doc('a');
    await doc.set(<String, Object?>{'n': 1});
    expect((await doc.get()).data(), <String, Object?>{'n': 1});
  });
}
```

- Await every operation and terminate every instance before a test ends; an operation still in
  flight when its instance is terminated fails later and breaks another test.
- Security rules as a user without the Auth emulator:
  `Settings().withEmulator('127.0.0.1', 8080, mockUserToken: {'sub': 'alice'})`.
- Offline behaviour: `disableNetwork()` and `enableNetwork()`.
- Reset the emulator's data: `DELETE http://127.0.0.1:8080/emulator/v1/projects/<project>/databases/(default)/documents`.
- `FirebaseFirestore.setLogLevel(LogLevel.debug)` prints what the client does.
- The Auth emulator: `FirebaseUserAuth.forApp(app, emulatorHost: '127.0.0.1:9099')`.

The emulator does not enforce composite indexes, quotas or App Check; check those against a test
project of your own before relying on them.

## Where to look next

Guides, by topic:

- Setup and a first read and write: [Getting started](getting_started.md)
- The `FirebaseApp`, its options, platform dependencies: [Configuring the FirebaseApp](firebase_app.md)
- Queries, aggregations, converters, bundles, snapshot JSON: [Queries and data](queries_and_data.md)
- Transactions, `terminate()`: [Transactions and the lifecycle](transactions_and_lifecycle.md)
- Cache settings, SQLite, the web cache, connectivity: [Offline persistence](offline_persistence.md)
- Hot restart, background isolates: [Several clients on one cache](multiple_clients.md)
- Users, service accounts, ADC, App Check: [Authentication](authentication.md)
- The emulator and tests: [The emulator and testing](emulator_and_testing.md)
- Platforms and the web: [Platforms](platforms.md)
- Lite and Pipelines: [Firestore Lite](lite.md), [Pipelines](pipelines.md)
- What is missing: [Features and limits](features.md), [Parity with the JS SDK](../parity.md)
- The FlutterFire API side by side: [Coming from FlutterFire](migrating_from_flutterfire.md)

Runnable programs in
[`cloud_firestore/cloud_firestore_dart/example/`](../../cloud_firestore/cloud_firestore_dart/example/README.md),
by task:

| Task | File |
|---|---|
| Quick start: write, read, query, listen, batch, transaction, count | `main.dart` |
| A backend process with one shared instance | `server.dart` |
| Set, add, update, delete, transforms, listeners | `crud_and_listeners.dart` |
| Filters, `Filter.or`, ordering, cursors | `queries.dart` |
| `count`, `sum`, `average`, aliases | `aggregations.dart` |
| Typed data with `withConverter` | `converters.dart` |
| Batches and transactions | `transactions_and_batches.dart` |
| A disk cache, offline reads and writes | `offline_persistence.dart`; the opener: `cloud_firestore_dart_sqlite` |
| The web cache | the README of `cloud_firestore_dart_sqlite` |
| Log level, pending writes, `terminate`, `clearPersistence` | `lifecycle.dart` |
| Mock users on the emulator | `emulator_mock_user_token.dart` |
| Bundles, snapshot JSON | `bundles.dart`, `snapshot_json.dart` |
| Firestore Lite, Pipelines | `lite.dart`, `pipelines.dart` |

Complete example packages (a `shelf` server, a CLI, a Cloud Run job) are in
[`examples/`](../../examples/README.md); their `lib/firestore_from_env.dart` picks the emulator or
Application Default Credentials from the environment.
