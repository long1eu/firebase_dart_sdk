## 0.1.0

- First version. An implementation of the platform interface of the official `firebase_database` plugin (13.1.0,
  `firebase_database_platform_interface` 0.4.3+10) on top of `firebase_database_dart`, so that an app keeps the
  official API. It is not affiliated with or endorsed by Google or Firebase.
- It registers itself on Linux, where FlutterFire has no plugin for `firebase_database`, and on Windows when it is a
  direct dependency, in place of FlutterFire's C++ plugin. On other platforms `FirebaseDatabaseDart.use()` selects
  it. Web is not supported.
- Where it ran. Windows 11 x64 (Flutter 3.47.8, debug): the example app passes its 4 integration tests against the
  Database emulator. Linux x64 (Debian 13 container): the example app builds and passes its 4 integration tests under a
  virtual display. macOS with the host test runner: FlutterFire's own `firebase_database` integration suite (77 tests)
  through the adapter, against the emulator, 76 pass and 1 skips itself. The package has 328 tests, 5 of them skipped
  without the emulator. That suite has not run on Linux or Windows. Not run: a release build of a desktop app, a real
  display, anything on Android, iOS or the web.
- Verified against production. Not through this adapter. The client underneath, `firebase_database_dart`, ran its
  verification kit (41 checks; all 41 ran as one run on 2026-11-27 against a dedicated database instance of one
  Firebase project, and all 41 passed; earlier runs, checks 1 to 39 and checks 40 and 41 each alone, passed too).
- Known limits:
  - Settings are captured when the client is created, at the first read, write or listen of an instance. After that
    `useDatabaseEmulator` with another host throws a `StateError`, and `setPersistenceEnabled` and
    `setPersistenceCacheSizeBytes` are ignored with a debug message.
  - An instance is never replaced and never released. After an app is deleted and created again under the same name
    with other options while an instance of the earlier app is kept, each call that needs a new client throws a
    `StateError` for the rest of the process, unless the app is created again with the earlier options; use another
    app name or restart. (README, "Emulator, logging, deleting an app", and "How it differs from the official
    plugin".)
  - A client made while `FirebaseApp.delete()` runs is not closed by that delete, nor by a later one, on the native and
    web cores (the Dart core of Linux closes it); the object keeps using it after the app is created again. (README,
    "Emulator, logging, deleting an app".)
  - Persistence is injected as a factory (`persistenceFor`), not switched on by the native SDK.
  - Long polling is not supported.
  - `DatabasePlatform.getChannelArguments` is not overridden and throws `UnimplementedError`.
  - On platforms other than Linux and Windows the native SDK stays in the build, unused.
- Differences from the official plugin are in the README, "How it differs from the official plugin". Differences of
  the client from the JS SDK are in section 25 of `docs/database_decisions.md` and in the client's README, "How it
  differs from the JS SDK".
- One instance and client per app and database: `instance` and `instanceFor` with the same database share them.
- A change event of the token provider is a signal for the client, which fetches the token from the provider (an
  empty token means signed out); the adapter never forwards a placeholder as a token, also from
  `FlutterFireAuthTokenProvider`, whose events hold a marker.
- `FirebaseApp.delete()` closes the app's clients on every platform, except a client made while the delete runs (see
  the limits). An app created again under the same name with the same options keeps its `FirebaseDatabase` objects
  working: the next call creates a new client with the settings the object had.
- Closing the client or deleting the app is not an error: every stream ends with done and no error event. A stream
  also ends, after the error, when the server cancels its listen. A pending `once()` then fails with `StateError`
  "No element", and `get()` and the other Futures with `database-closed`.
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
