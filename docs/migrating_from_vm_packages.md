# Migrating from `cloud_firestore_vm` / `firebase_core_vm`

`cloud_firestore_vm` 0.0.7 and `firebase_core_vm` 0.0.4 (April 2020) continue as
`cloud_firestore_dart` 0.1.0 and `firebase_app_dart` 0.1.0. It is the same code base, moved to
Dart 3 with null safety and synced with newer versions of the official SDKs. This guide lists
what you have to change, in the order you will hit it. Each item is a breaking change from the
0.1.0 CHANGELOG of one of the two packages.

0.1.0 is prepared for pub.dev but not published yet. It was verified with unit tests and the
Firestore emulator. Against production Firestore only the verification kit
(`tool/verify_production`) was run, on a Standard edition database (13 of 15 checks passed, 2
were skipped); the Enterprise edition features and long-running load were not.

The code blocks marked "after" are compiled by
`cloud_firestore/cloud_firestore_dart/test/unit/api/readme_snippets_test.dart`. They assume an
`app` (`FirebaseApp`), a `firestore` (`Firestore`) and a `users` collection in scope. All the
changes of this guide are also in one compiled file, section by section, with the 0.0.7 code as
comments:
[`test/readme/migration_example.dart`](../cloud_firestore/cloud_firestore_dart/test/readme/migration_example.dart).

Runnable programs for everything mentioned here are in
[`cloud_firestore/cloud_firestore_dart/example/`](../cloud_firestore/cloud_firestore_dart/example/README.md).

## 1. Packages and imports

| Before | After |
|---|---|
| `cloud_firestore_vm` | `cloud_firestore_dart` |
| `firebase_core_vm` | `firebase_app_dart` |
| `_firebase_internal_vm` | part of `firebase_app_dart` (`package:firebase_app_dart/internal.dart`, not public API) |
| `_firebase_database_collection_vm` | part of `cloud_firestore_dart` (not exported) |

`pubspec.yaml`, before:

```yaml
environment:
  sdk: ">=2.7.0 <3.0.0"
dependencies:
  cloud_firestore_vm: ^0.0.7
  firebase_core_vm: ^0.0.4
```

After:

```yaml
environment:
  sdk: ^3.8.0
dependencies:
  cloud_firestore_dart: ^0.1.0
  firebase_app_dart: ^0.1.0
```

Imports, before:

```dart before
import 'package:cloud_firestore_vm/cloud_firestore_vm.dart';
import 'package:firebase_core_vm/firebase_core_vm.dart';
```

After:

```dart
import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
```

Class names are unchanged (`Firestore`, `FirebaseApp`, `FirebaseOptions`,
`PlatformDependencies`, ...). If you imported files under `src/` of the old packages, the paths
moved with the package name; most of what was reachable that way is now internal (section 8).

## 2. Dart 3 and null safety

`cloud_firestore_dart` and `firebase_app_dart` need Dart `^3.8.0` (the minimum of `grpc` 5, and the lowest SDK the CI runs); both are null safe. Values that could always be missing are now
typed as nullable:

- `DocumentSnapshot.data` is `null` for a document that does not exist, and field values are
  `Object?`.
- `FirebaseOptions.projectId`, `databaseUrl`, `storageBucket`, `gcmSenderId`, `gaTrackingId`
  are nullable; `apiKey` and `applicationId` are required.

Before:

```dart before
final DocumentSnapshot snapshot = await users.document('ada').get();
final Map<String, Object> data = snapshot.data;
final int age = data['age'];
```

After:

```dart
final DocumentSnapshot<Map<String, Object?>> snapshot =
    await users.doc('ada').get();
final Map<String, Object?>? data = snapshot.data; // null if it does not exist
final int? age = data?['age'] as int?;
```

## 3. Creating the app

`FirebaseApp.withOptions` is unchanged. Two members of `FirebaseApp` changed:

- `setDataCollectionDefaultEnabled` takes a required named `enabled` (it had a default of
  `false`).
- `persistenceKey` is now URL-safe base64 without padding. If you used it to name your own
  files, files named by the old version are not found under the new key.

Before:

```dart before
app.setDataCollectionDefaultEnabled();              // meant "disable"
```

After:

```dart
app.setDataCollectionDefaultEnabled(enabled: false);
```

## 4. Creating the Firestore instance

`Firestore.getInstance` still works but is deprecated; use `Firestore.instanceFor`, where the
app is a named argument. Both now return the instance at once instead of a `Future`, as the
other Firebase SDKs do: the cache is opened in the background and every operation waits for it.
An `await` in front of the call still compiles (the analyzer suggests removing it). If opening
the cache fails (for example your opener throws), the operations of the instance fail with that
error instead of the call itself.

Before:

```dart before
final Firestore firestore = await Firestore.getInstance(
  app,
  openDatabase: myOpener,
  settings: FirestoreSettings(persistenceEnabled: true),
);
```

After:

```dart
final Firestore firestore = Firestore.instanceFor(
  app: app,
  settings: FirestoreSettings(cacheSettings: PersistentCacheSettings()),
  // openDatabase: yourOpener, see section 5
);
```

`persistenceEnabled` and `cacheSizeBytes` still exist; `cacheSettings`
(`PersistentCacheSettings` or `MemoryCacheSettings`) is the newer way to say the same and cannot
be combined with non-default values of the other two.

For the emulator, build the settings with `withEmulator` instead of setting `host` and
`sslEnabled` by hand:

```dart
final Firestore emulated = Firestore.instanceFor(
  app: app,
  settings: FirestoreSettings().withEmulator('127.0.0.1', 8080),
);
```

## 5. The SQLite opener (`OpenDatabase` / `Database`)

You still pass your own opener. The contract is now documented on the `OpenDatabase` typedef,
and one member of `Database` changed: the `File get file` getter is replaced by
`String get path`, so the interface no longer needs `dart:io`. Arguments are typed
`List<Object?>?` instead of `List<dynamic>`.

Before:

```dart before
class MyDatabase extends Database {
  @override
  File get file => _file;

  @override
  Future<void> execute(String statement, [List<dynamic> arguments]) async { /* ... */ }
  // ...
}
```

After:

```dart
class MyDatabase implements Database {
  MyDatabase(this.path);

  @override
  final String path; // the file Firestore.clearPersistence() deletes

  @override
  Future<void> execute(String statement, [List<Object?>? arguments]) async {}

  @override
  Future<List<Map<String, dynamic>>> query(String statement,
          [List<Object?>? arguments]) async =>
      <Map<String, dynamic>>[];

  @override
  Future<int> delete(String statement, [List<Object?>? arguments]) async => 0;

  @override
  void close() {}
}
```

A complete implementation on top of `package:sqlite3` that you can copy is
[`example/sqlite_database.dart`](../cloud_firestore/cloud_firestore_dart/example/sqlite_database.dart).

New and optional: your `Database` may throw `TransientDatabaseException` for an error after
which the statement stored nothing and a retry can work (SQLite's busy, locked, I/O or full-disk
errors). Firestore then keeps the client running, offline if needed, and retries with a backoff
instead of failing. Throw it only when nothing was stored. The example opener shows the mapping.

### An existing cache file is kept

The database name passed to the opener is built the same way as in 0.0.7
(`firestore.<app name>.<project id>.<database>`), so an opener that maps names to files the same
way finds the existing cache. 0.0.7 wrote schema version 8 and this version is at 18 (bundle
tables, read times on cached documents, document overlays, persistent cache indexes, the
client lease, the globals table, the type of each cached document, the client of each pending write); the first open with the new package
runs the newer migrations through your opener's `onUpgrade` callback (it must call it when the
stored `user_version` is lower than the requested one, see the contract on `OpenDatabase`), and
pending writes are converted to overlays the first time the client starts.

After the upgrade:

- Cached documents, including known-deleted ones, are read as before.
- Listen targets are reused. The canonical id that identifies a query in the cache has the same
  format as in 0.0.7, so listening to a query again finds its stored target with its resume token
  and the backend only sends what changed since. Nothing is orphaned.
- Pending writes that were not sent yet are kept and sent. 0.0.7 stored field transforms
  (`serverTimestamp`, `increment`, array union and remove) as a separate write after the set or
  update; those are folded into the write they belong to when the batch is loaded.
- Collection group queries keep working (the collection parents index is kept).

This is tested with a schema 8 database built from the 0.0.7 sources
(`test/unit/firebase/firestore/local/legacy_cache_upgrade_test.dart`; the file was reconstructed
from the sources, 0.0.7 itself does not run on Dart 3). Going back to 0.0.7 on an upgraded file
is not supported.

`ConflictAlgorithm` is no longer exported; nothing in the SDK used it.

## 6. Renamed members (old names deprecated, still working)

| Before | After |
|---|---|
| `Firestore.getInstance(app, ...)` | `Firestore.instanceFor(app: app, ...)` |
| `firestore.document(path)`, `collection.document(id)` | `firestore.doc(path)`, `collection.doc(id)` |
| `snapshot.reference` | `snapshot.ref` |
| `querySnapshot.documents` | `querySnapshot.docs` |
| `querySnapshot.documentChanges` | `querySnapshot.docChanges` |
| `FieldPath.documentId()` | `FieldPath.documentIdField` |
| `Source.defaultSource` | `Source.serverAndCache` |
| `firestore.shutdown()` | `firestore.terminate()` |

Before:

```dart before
final QuerySnapshot result = await firestore
    .collection('users')
    .whereEqualTo(FieldPath.documentId(), 'ada')
    .get(Source.defaultSource);
for (final DocumentSnapshot doc in result.documents) {
  print(doc.reference.path);
}
await firestore.shutdown();
```

After:

```dart
final QuerySnapshot<Map<String, Object?>> result = await firestore
    .collection('users')
    .where(FieldPath.documentIdField, isEqualTo: 'ada')
    .get(Source.serverAndCache);
for (final QueryDocumentSnapshot<Map<String, Object?>> doc in result.docs) {
  print(doc.ref.path);
}
await firestore.terminate();
```

The `whereEqualTo`, `whereGreaterThan`, ... methods are unchanged and not deprecated; `where`
with named arguments and `where(Filter)` are additions.

## 7. Generic references and snapshots

`DocumentReference`, `CollectionReference`, `Query`, `DocumentSnapshot`,
`QueryDocumentSnapshot`, `QuerySnapshot` and `DocumentChange` have a type parameter for the
document data. What `Firestore` returns is typed `<Map<String, Object?>>`, so code that lets the
types be inferred keeps compiling. A type annotation without the type argument now means
`dynamic` data, which silently turns off type checking for `data`.

Before:

```dart before
final DocumentReference ref = firestore.collection('users').document('ada');
final DocumentSnapshot snapshot = await ref.get();
```

After:

```dart
final DocumentReference<Map<String, Object?>> ref =
    firestore.collection('users').doc('ada');
final DocumentSnapshot<Map<String, Object?>> snapshot = await ref.get();
```

## 8. Members that are no longer public

These were reachable in 0.0.7 only because nothing hid them. They are not part of the public
library any more. The classes of the API have no public constructor either: instances come from
`Firestore` and from other API objects, and a test double has to use `implements`.

| Before | After |
|---|---|
| `firestore.databaseId.projectId` | `firestore.projectId` |
| `firestore.databaseId.databaseId` | `firestore.databaseId` (now the database name as a `String`) |
| `Firestore.newInstance(...)`, `Firestore(...)` | `Firestore.instanceFor(...)`; an auth or App Check provider comes from the `FirebaseApp` (`PlatformDependencies.authProvider` / `appCheckProvider`) |
| `firestore.client`, `scheduler`, `dataConverter`, `validateReference` | no replacement (implementation) |
| `query.query`, `querySnapshot.snapshot`, `snapshot.document`, `reference.key` | no replacement (core model types); use `path`, `id`, `data`, `metadata` |
| `FieldPath(...)` unnamed constructor, `internalPath`, `documentIdInstance` | `FieldPath.of([...])`, `FieldPath.fromDotSeparatedPath('a.b')`, `FieldPath.documentIdField` |
| `fieldValue.isDelete`, `isServerTimestamp`, ..., `elements`, `methodName` | no replacement (implementation) |
| `SetOptions.fieldMask` | no replacement; `SetOptions.merge` stays |
| `LoadBundleTask()` constructor, `setResult`, `setException`, `updateProgress` | tasks come from `firestore.loadBundle(...)` |
| `FirestoreErrorCode.fromValue(grpcError)` | no replacement; `FirestoreError.code` |
| `Timestamp.validateRange` | no replacement |
| `maxVectorQueryLimit`, `maxVectorQueryDimensions`, `ConflictAlgorithm` | not exported |

Before:

```dart before
print(firestore.databaseId.projectId);
```

After:

```dart
print('${firestore.projectId} / ${firestore.databaseId}');
```

## 9. Behaviour changes without a compile error

- **Transactions that only read a document.** 0.0.7 failed with "Every document read in a
  transaction must also be written". Now a document that was read but not written is verified
  at commit, and the transaction is retried if it changed. Code that wrote a document back
  unchanged only to satisfy the old rule can stop doing so.

  Before:

  ```dart before
  await firestore.runTransaction((Transaction tx) async {
    final DocumentSnapshot config = await tx.get(configRef);
    tx.set(configRef, config.data); // only to satisfy the rule
    tx.update(userRef, <String, Object>{'plan': config.data['plan']});
  });
  ```

  After:

  ```dart
  final configRef = firestore.doc('config/plans');
  final userRef = users.doc('ada');
  await firestore.runTransaction<void>((Transaction tx) async {
    final config = await tx.get(configRef);
    tx.update(userRef, <String, Object?>{'plan': config.data!['plan']});
  });
  ```

- **A read after a write in a transaction** fails with `invalidArgument` and the message of the
  other SDKs ("Firestore transactions require all reads to be executed before all writes."; it
  was "Transactions lookups are invalid after writes."). As in the JS SDK the transaction then
  fails to commit even if the update function caught the error, so do every read first.
- **Transaction attempts.** The default went from 6 to 5
  (`TransactionOptions.defaultMaxAttempts`). To keep 6:

  ```dart
  await firestore.runTransaction<void>(
    (Transaction tx) async {},
    options: TransactionOptions(maxAttempts: 6),
  );
  ```

- **Idle streams.** The listen and write streams are closed after 1 minute without activity
  (was 10 seconds), as in the Android SDK. Nothing to change.
- **Server closing a stream.** A clean close of a stream by the server is reported as
  `unavailable` and retried, instead of being ignored. Nothing to change; a start-up hang is
  gone.
- **Field transforms.** `FieldValue.serverTimestamp()`, `increment`, `arrayUnion` and
  `arrayRemove` are sent inside the set or update write instead of a separate transform write.
  The public API is the same. Pending writes stored by 0.0.7 in an existing SQLite cache are
  converted when they are loaded.
- **Locally changed documents** have no version until the backend acknowledges the write. This
  is not visible through the public API.
- **Using an instance after `terminate()`** fails with a `FirestoreError` with the code
  `failedPrecondition` ("The client has already been terminated."), delivered through the
  returned `Future` or `Stream`. 0.0.7 threw an `ArgumentError` ("The client has already been
  shutdown"). Code that caught `ArgumentError` for this has to catch `FirestoreError`:

  ```dart
  await firestore.terminate();
  try {
    await users.doc('ada').get();
  } on FirestoreError catch (e) {
    print(e.code == FirestoreErrorCode.failedPrecondition); // true
  }
  ```

- **`Timestamp.fromDate` / `toDate`** keep microseconds (they truncated to milliseconds).
  Results for millisecond inputs are unchanged.
- **Array transforms on top of newer server data.** The local view of a document with pending
  writes is now stored as an overlay. A pending `arrayUnion` / `arrayRemove` keeps the result it
  had when it was written until the backend acknowledges it, instead of being applied again on
  top of data that arrived from the server in the meantime (as in the official SDKs).
- **`Blob.bytes`** returns a copy, so changing the returned list no longer changes the blob.
- **Out-of-range `Timestamp`s** (before year 1 or after year 9999) are rejected with an
  `ArgumentError` when they are written, also in builds without asserts.

- **Arguments are checked in release builds too.** Checks that were asserts now throw an
  `ArgumentError` in every build: a collection path with an even number of segments, a
  `cacheSizeBytes` below 1 MB with persistence, a `GeoPoint` outside its range when it is
  written, an empty application id in `FirebaseOptions`. `firestore.doc('')` and
  `collectionGroup('')` throw as well; they were accepted.
- **Settings.** `FirestoreSettings.host` must be a plain host name or IP address (no `/`, `@`,
  `?`, `#`, `\`, whitespace), and `sslEnabled: false` with the production host throws in every
  build.
- **Numbers in `whereIn`, `whereNotIn`, the array filters and array transforms** are compared
  by value against the local cache, as the backend does: `whereIn('n', [1])` matches a
  document with `1.0`, and `arrayUnion([1])` adds nothing to an array that holds `1.0`.
  0.0.7 compared them by type as well.
- **A write that is sent again** (after its acknowledgement was lost) and changes nothing on the
  backend is applied to the cached document, so the cache no longer keeps the old value without
  a pending write.
- **Range filters do not match `null` and `NaN`** in the local cache (`a < 1` does not match a
  `NaN` value), as on the backend.
- **A cached document that only the client matches for a query** is removed from that query's
  results once the backend confirms that the document exists but is not a result, instead of
  keeping the listener at `isFromCache` for ever.
- **Bundles** are parsed as untrusted input: an element larger than 64 MiB, or values nested
  more than 100 levels deep, make `loadBundle` fail.
- **`toString()` of token results** (`GetTokenResult`, `InternalTokenResult`) no longer
  contains the token.

## 10. The example app

The Flutter example app of `cloud_firestore_vm` is gone. The package now ships command-line
examples that run against the Firestore emulator, including offline persistence with
`package:sqlite3`.
