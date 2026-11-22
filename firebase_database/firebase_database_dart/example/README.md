# firebase_database_dart examples

Small command-line programs, one per topic. They run against the local Realtime Database emulator, never
against a real project. Start an emulator (the Firebase CLI, port 9000 by default), then from this package:

```sh
firebase emulators:start --only database --project demo-example
dart pub get
FIREBASE_DATABASE_EMULATOR_HOST=127.0.0.1:9000 dart run example/main.dart
```

Each program writes under the key `example-<name>-<timestamp>` and removes it at the end, then closes the
database. Without `FIREBASE_DATABASE_EMULATOR_HOST` they stop with a message. The project is `demo-example`.

| File | Shows |
|---|---|
| `main.dart` | The quick start: connect, `set`, `push`, `get`, `onValue`, cleanup. |
| `read_write.dart` | `set` replaces, `update` merges, `null` removes; plain Dart values, lists, invalid keys. |
| `listeners.dart` | `onValue`, `onChildAdded` / `Changed` / `Moved` / `Removed`, `onChildEvents`, `once`, cancelling. |
| `queries.dart` | `orderByChild` / `Key` / `Value`, `startAt`, `endAt`, `startAfter`, `endBefore`, `equalTo`, `limitToFirst` / `Last`. |
| `transactions.dart` | `runTransaction`, `Transaction.success` / `abort`, retries, concurrent updates. |
| `push_and_keys.dart` | `push`, `key`, `child`, `parent`, `root`, `url`; the order of push ids and integer-like keys. |
| `priority_and_ordering.dart` | Priorities with `set` and `setPriority`, `orderByPriority`, the order of mixed value types. |
| `multi_path_update.dart` | One atomic `update` over several paths, `null` to delete, overlapping paths. |
| `on_disconnect.dart` | `OnDisconnect.set` / `update` / `remove` / `cancel` with a second client watching. |
| `connection_state.dart` | `onConnected`, `isConnected`, `goOffline` / `goOnline`, a write queued while offline. |
| `server_values.dart` | `ServerValue.timestamp` and `increment`, the local estimate, `estimatedServerTime`. |
| `auth_and_rules.dart` | `mockUserToken` and a rule that refuses (`permission-denied`); needs the rules in its header. |
| `error_handling.dart` | `FirebaseDatabaseException` (`code`, `serverStatus`) against `ArgumentError` and `StateError`. |
| `lifecycle.dart` | Independent instances, `close()`, the `database-closed` error on streams and calls. |
| `cookbook/presence.dart` | Online and offline with `onConnected` and `onDisconnect`. |
| `cookbook/counter.dart` | A shared counter: read-then-set (wrong), `ServerValue.increment`, a transaction. |
| `cookbook/chat.dart` | A chat room: push keys, a `limitToLast` window, a typing flag cleared on disconnect. |

`common.dart` holds the shared setup: the `demo-example` app, `emulatorDatabase()` (reads
`FIREBASE_DATABASE_EMULATOR_HOST`, adds port 9000 when the value has none), `freshKey()` and `runExample()`
(a database plus a fresh key, removed and closed afterwards).

Every program was run against the Database emulator; none against a real database. Limits to know:

- A `get()` with a range or a limit on `orderByChild` or `orderByValue` needs an `.indexOn` rule
  (`index-not-defined` without it). The programs read such queries with a listener, see `once` in
  `common.dart`.
- On the Dart VM a `wss` connection that hangs inside its TLS handshake cannot be closed (`dart:io`
  has no way to do it): the client gives up on it after its timeout and tries again, and the
  socket stays until the peer or the system ends it.

Not yet here: offline persistence and a server that shares one instance.
