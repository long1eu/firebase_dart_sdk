# Writes, offline behaviour, lifecycle and errors

How `cloud_firestore_dart` 0.1.x behaves where code most often goes wrong. It follows the
Firebase Android SDK.

## Writes

- `set`, `update`, `delete`, `add` and `WriteBatch.commit()` are applied to the local cache at
  once, so listeners report them immediately with `metadata.hasPendingWrites == true`.
- Their futures complete when the backend has acknowledged the write. Offline that does not
  happen until the client is back online. In UI code, do not await the write before showing the
  change; attach an error handler instead:

  ```dart
  firestore
      .doc('cities/SF')
      .update(<String, Object?>{'visited': true})
      .then((_) {}, onError: (Object error) => print('write failed: $error'));
  ```

- On a server, await the write before answering the request, so the caller only sees writes the
  backend accepted.
- Writes are re-sent after a broken connection. A relative transform such as
  `FieldValue.increment` can then be applied twice if the acknowledgement was lost.
- Firestore Lite (`package:cloud_firestore_dart/lite.dart`, experimental) is different: no
  queue, no retry; a write fails with `unavailable` without a connection.

## Reads and listeners

- `ref.get()` asks the backend and falls back to the cache when offline; `get(const GetOptions(source: Source.cache))` only
  the cache (fails with `unavailable` if the document is not cached); `get(const GetOptions(source: Source.server))` only the
  backend (fails offline).
- Listeners are streams: `ref.snapshots()`, `query.snapshots()`, `snapshots(includeMetadataChanges: true)`
  for metadata-only changes, `snapshots(source: ListenSource.cache)` for the cache only. Cancel the `StreamSubscription` to stop. Errors (for
  example `permissionDenied`) arrive on the stream's `onError`.
- `snapshot.metadata.isFromCache` and `hasPendingWrites` tell where a snapshot came from.
- `disableNetwork()` / `enableNetwork()` take the client offline and back on purpose.

## The cache

| `instanceFor` gets | Cache |
|---|---|
| no `openDatabase` | memory, gone on `terminate()` (whatever `persistenceEnabled` says) |
| `openDatabase: sqliteOpener(directory: dir)` (VM, Flutter; `cloud_firestore_dart_sqlite`) | SQLite file, kept across restarts |
| `openDatabase: sqliteOpener()` (web) | SQLite in WebAssembly, in IndexedDB or OPFS, one tab at a time |

```dart
final Settings persistent = Settings(
  cacheSettings: PersistentCacheSettings(sizeBytes: 100 * 1024 * 1024), // the default size
);
final Settings eager = Settings(
  cacheSettings: const MemoryCacheSettings(), // eager GC: drops what no listener needs
);
final Settings lru = Settings(
  cacheSettings: MemoryCacheSettings(
    gcSettings: MemoryLruGcSettings(sizeBytes: 40 * 1024 * 1024),
  ),
);
```

- The size is a garbage collection threshold, minimum 1 MB (smaller throws `ArgumentError`);
  `Settings.cacheSizeUnlimited` never collects. Pending writes are never collected.
- Settings are fixed at creation: a later `instanceFor` with different settings throws
  `StateError`.
- The cache files hold every document read, in clear text. Put them in a per-user application
  directory (`getApplicationSupportDirectory()` in Flutter), never in `/tmp`.
- Two clients on one SQLite file (a hot restart, a background isolate, a second process) keep
  it consistent, but only one is online; the other answers from the cache and keeps its writes
  pending. Give a background isolate its own app name or database.

## Lifecycle

- `await firestore.terminate()` closes the connection, timers and cache. On the VM a program does
  not exit while an instance is open.
- After `terminate()`: write futures that were not acknowledged never complete (with a memory
  cache those writes are lost; a persistent cache sends them from the next instance); calls fail
  with `failedPrecondition`; `FirebaseFirestore.instanceFor` creates a new instance.
- Call `waitForPendingWrites()` before `terminate()` when the writes matter; it completes when
  the backend has acknowledged them, so offline it waits.
- `clearPersistence()` deletes the persistent cache of a terminated instance; on a running
  instance it fails with `failedPrecondition`.
- In tests: await every operation and terminate every instance before the test ends; a call
  still in flight when its instance is terminated fails later, in another test.

## Errors

```dart
try {
  await firestore.doc('private/x').get(const GetOptions(source: Source.server));
} on FirestoreException catch (e) {
  if (e.errorCode == FirestoreErrorCode.permissionDenied) {
    print('not allowed: ${e.message}');
  } else if (e.errorCode == FirestoreErrorCode.unavailable) {
    print('offline or backend unreachable');
  } else {
    rethrow;
  }
}
```

- A failed operation reports `FirestoreException` with `errorCode` (a `FirestoreErrorCode`: `cancelled`,
  `unknown`, `invalidArgument`, `deadlineExceeded`, `notFound`, `alreadyExists`,
  `permissionDenied`, `resourceExhausted`, `failedPrecondition`, `aborted`, `outOfRange`,
  `unimplemented`, `internal`, `unavailable`, `dataLoss`, `unauthenticated`), `code` (the same as
  FlutterFire's string, `'permission-denied'`) and `message`.
- `FirestoreException` extends `FirebaseException` and implements `Exception`.
- Invalid data (unsupported values, field names that begin and end with `__`) and invalid
  arguments throw `ArgumentError`.
- `instanceFor` with changed settings throws `StateError`.
- `firebase_auth_providers_dart` reports `FirebaseAuthException` with string codes such
  as `wrong-password`, `user-not-found`, `network-request-failed`.
- `FirebaseFirestore.setLogLevel(LogLevel.debug)` logs what the client does.

## Transactions

```dart
final int next = await firestore.runTransaction<int>((Transaction transaction) async {
  final DocumentReference<Map<String, Object?>> ref = firestore.doc('counters/a');
  final DocumentSnapshot<Map<String, Object?>> snapshot = await transaction.get(ref);
  final int value = (snapshot.data()?['n'] as int?) ?? 0;
  transaction.set(ref, <String, Object?>{'n': value + 1});
  return value + 1;
}, maxAttempts: 5);
```

- Reads before writes. The callback runs again when a document it read changed (up to
  `maxAttempts`, 5 by default), so it must not have side effects of its own.
- A commit whose answer was lost can be applied twice; make such transactions idempotent.
- `readOnly: true` (optionally `readTime:`) reads a consistent snapshot of
  the backend and allows `transaction.getQuery(query)` and `transaction.getAggregate(...)`; in a
  read-write transaction those fail with `invalidArgument`. Read-only transactions fail offline.
- No `timeout` parameter.

## What is not supported

No federated sign-in, no device attestation for App Check, no cache shared across browser tabs,
no real-time Pipelines, no `findNearest` against the cache. The web was tested in Chrome only;
Windows is untested. Full list:
<https://raw.githubusercontent.com/long1eu/firebase_dart_sdk/main/docs/guides/features.md>.
