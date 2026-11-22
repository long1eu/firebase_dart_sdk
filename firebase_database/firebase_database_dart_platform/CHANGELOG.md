## 0.0.1

- Work in progress, not published: an implementation of `DatabasePlatform` (the platform interface of the
  official `firebase_database` plugin, 13.1.0) on top of `firebase_database_dart`, so that an app keeps the
  official API.
- Registers itself on Linux and, as a direct dependency, on Windows in place of FlutterFire's C++ plugin (run on
  Windows 11 x64, Flutter 3.47.8, debug); `FirebaseDatabaseDart.use()` selects it on any other platform.
- One instance and client per app and database: `instance` and `instanceFor` with the same database share them.
- A token provider's change events reach the connection with the token itself, also from
  `FlutterFireAuthTokenProvider`, whose events hold a marker.
- `FirebaseApp.delete()` closes the app's clients on every platform; an app created again under the same name gets
  a new client.
- The emulator only through `useDatabaseEmulator` (no environment variable); client warnings and errors are printed
  also with logging off; an event stream creates the client when it is listened to, not when it is made.
- `FirebaseDatabaseDart.use` takes `tokenProviderFor`, `appCheckProviderFor`, `persistenceFor` (a factory from
  the cache size to the client's persistence) and `useDartCore`; `FirebaseDatabaseDart.clientFor(app)` returns the
  client behind an instance.
- Transactions: the handler gets a fresh mutable copy of the value on each run, its exception is rethrown
  unchanged, an abort completes with `committed: false` and the snapshot it saw.
- `onDisconnect()`: `set`, `setWithPriority`, `update`, `remove` and `cancel`.
- Fixed on purpose against FlutterFire: child snapshots keep their priority, the snapshot of a child event has
  the child's reference, and a null cursor stays null.
