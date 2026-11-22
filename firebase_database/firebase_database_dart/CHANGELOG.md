## 0.0.1

Work in progress, not published. A client of the Firebase Realtime Database in Dart for the VM and the web, tested
against the Database emulator.

- `FirebaseDatabase(app, databaseUrl:, emulatorHost:, mockUserToken:, persistence:, logger:)`: one instance is one
  connection; configuration is constructor-only and there is no instance cache.
- Reads and writes: `get`, `once`, `set`, `update`, `push`, `setPriority`, `remove`; `DataSnapshot.value` is plain,
  unmodifiable Dart data. A filtered or limited `get()` needs `.indexOn` in the rules; an order-only one does not.
- Listening: `onValue`, `onChildAdded`, `onChildChanged`, `onChildMoved`, `onChildRemoved` and `onChildEvents`, one
  ordered stream of the four child events.
- Queries: `orderByChild`, `orderByKey`, `orderByValue`, `orderByPriority`, `startAt`, `startAfter`, `endAt`,
  `endBefore`, `equalTo`, `limitToFirst`, `limitToLast`, `keepSynced`.
- `runTransaction` with `Transaction.success` and `Transaction.abort`; `onDisconnect` with `set`, `update`, `remove`
  and `cancel`; `ServerValue.timestamp` and `ServerValue.increment`.
- Connection state: `onConnected`, `isConnected`, `serverTimeOffset`, `estimatedServerTime`, `goOffline`, `goOnline`,
  `purgeOutstandingWrites`; a dead-link probe, and reconnect with a 30 s cap.
- ID and App Check tokens from the app's providers, sent only over TLS or to the emulator; `mockUserTokenFor` for the
  emulator.
- `FirebaseDatabaseException` with the codes `permission-denied`, `disconnected`, `max-retries`, `overridden-by-set`,
  `unavailable`, `network-error`, `write-canceled`, `index-not-defined`, `operation-failed`, `too-big`, `read-only`,
  `database-closed` and `unknown`.
- Logging through a callback, off by default; credentials are never logged.
- Optional disk persistence through `firebase_database_dart_sqlite`.
- `package:firebase_database_dart/testing.dart`: a fake server for tests of your own code.
- Writes are delivered at least once: a re-sent `ServerValue.increment` can apply twice.
- Not included: long polling, typed converters, a writing REST client, web disk persistence, the compat API.
