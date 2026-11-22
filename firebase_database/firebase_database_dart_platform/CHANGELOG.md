## 0.0.1

- Work in progress, not published: an implementation of `DatabasePlatform` (the platform interface of the
  official `firebase_database` plugin, 13.1.0) on top of `firebase_database_dart`, so that an app keeps the
  official API. FlutterFire's integration suite and a real Windows build have not run yet.
- Registers itself on Linux and, as a direct dependency, on Windows (verified with stand-in plugins; a real
  Windows build is run before release); `FirebaseDatabaseDart.use()` selects it on any other platform.
- `FirebaseDatabaseDart.use` takes `tokenProviderFor`, `appCheckProviderFor`, `persistenceFor` (a factory from
  the cache size to the client's persistence) and `useDartCore`; `FirebaseDatabaseDart.clientFor(app)` returns the
  client behind an instance.
- Transactions: the handler gets a fresh mutable copy of the value on each run, its exception is rethrown
  unchanged, an abort completes with `committed: false` and the snapshot it saw.
- `onDisconnect()`: `set`, `setWithPriority`, `update`, `remove` and `cancel`.
- Fixed on purpose against FlutterFire: child snapshots keep their priority, the snapshot of a child event has
  the child's reference, and a null cursor stays null.
