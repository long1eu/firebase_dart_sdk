# firebase_database_dart examples

Small command-line programs, one per topic. They run against the local Realtime Database emulator, never
against a real project. Start the emulator with the repository's script (port 9100; it refuses the Firebase CLI's own default, 9000), then
from this package:

```sh
../../tool/start_database_emulator.sh
dart pub get
FIREBASE_DATABASE_EMULATOR_HOST=127.0.0.1:9100 dart run example/main.dart
../../tool/stop_database_emulator.sh         # when you are done
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
| `auth_and_rules.dart` | `mockUserToken` and a rule that refuses (`permission-denied`); loads the rules it needs and restores open ones. |
| `error_handling.dart` | `FirebaseDatabaseException` (`code`, `serverStatus`) against `ArgumentError` and `StateError`. |
| `lifecycle.dart` | Independent instances, `close()`, the `database-closed` error on streams and calls. |
| `cookbook/presence.dart` | Online and offline with `onConnected` and `onDisconnect`. |
| `cookbook/counter.dart` | A shared counter: read-then-set (wrong), `ServerValue.increment`, a transaction. |
| `cookbook/chat.dart` | A chat room: push keys, a `limitToLast` window, a typing flag cleared on disconnect. |

`common.dart` holds the shared setup: the `demo-example` app, `emulatorDatabase()` (reads
`FIREBASE_DATABASE_EMULATOR_HOST`, adds port 9100 when the value has none), `freshKey()` and `runExample()`
(a database plus a fresh key, removed and closed afterwards).

`auth_and_rules.dart` loads its own rules into the `demo-example` namespace when it starts (a `PUT` to the
emulator's `/.settings/rules.json?ns=demo-example-default-rtdb`, see `setEmulatorRules` in `common.dart`) and puts open
rules back when it ends, also after an error. It refuses to do this against anything but a local emulator.

Every program was run against the Database emulator; none against a real database. Limits to know:

- A `get()` with a range or a limit on `orderByChild` or `orderByValue` needs an `.indexOn` rule
  (`index-not-defined` without it). The programs read such queries with a listener, see `once` in
  `common.dart`.
- On the Dart VM a `wss` connection that hangs inside its TLS handshake cannot be closed (`dart:io`
  has no way to do it): the client gives up on it after its timeout and tries again, and the
  socket stays until the peer or the system ends it.

Complete apps are in [`examples/`](../../../examples/README.md): `rtdb_cli`, `rtdb_server_shelf` (one shared
instance behind an HTTP API), `rtdb_presence_worker`, `rtdb_web_app`, `rtdb_playground` and
`flutterfire_database_on_linux`. The FlutterFire adapter has its own program in
[`firebase_database_dart_platform/example/`](../../firebase_database_dart_platform/example/main.dart).
Not yet here: a program for offline persistence (`firebase_database_dart_sqlite`).
