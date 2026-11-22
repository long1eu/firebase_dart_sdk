# firebase_database_dart_platform

An unofficial implementation of the platform interface of the official
[`firebase_database`](https://pub.dev/packages/firebase_database) Flutter plugin (13.1.0,
`firebase_database_platform_interface` 0.4.3+10), on top of `firebase_database_dart`, a pure-Dart client of the
Firebase Realtime Database over its WebSocket protocol. An app keeps the official API
(`FirebaseDatabase.instance.ref('notes').onValue`, `set`, `runTransaction`, `onDisconnect()`, ...) and the Dart
client does the work underneath, without the native Firebase SDKs.

It is for a Flutter app on Linux desktop, where `firebase_database` and `firebase_core` have no implementation of
their own: FlutterFire has no Linux plugin for `firebase_database`, so this package is the only implementation there,
and adding the dependency registers it. On Windows FlutterFire has its own plugin (built on the Firebase C++ SDK); an
app that lists this package as a direct dependency gets this package in its place. On the other platforms it is an
opt-in through `FirebaseDatabaseDart.use()`. It is not affiliated with or endorsed by Google or Firebase.

> **Status: 0.0.1, not published, work in progress.** What is and is not verified:
>
> - The client underneath, `firebase_database_dart`, passes its own suites (2,437 tests on the Dart VM) and its tests
>   against the Database emulator.
> - This package has 133 tests, 5 of them skipped without the emulator (another session's run). The unit tests run
>   against the client's fake server (`package:firebase_database_dart/testing.dart`).
> - FlutterFire's own `firebase_database` integration suite (77 tests) is the acceptance gate
>   (`tool/test_flutterfire_database_gate.sh`, against the Database emulator): 76 pass and 1 skips itself, on
>   macOS with the host test runner. It has **not run** on Linux or Windows.
> - On Windows 11 x64 (Flutter 3.47.8, debug) the Windows example app, written against `firebase_database` alone,
>   builds with this package (the generated plugin registrant calls `FirebaseDatabaseDart.registerWith()`) and passes
>   its 4 integration tests against the Database emulator.
> - On Linux x64 (a Debian 13 container) the Linux example app builds and passes its 4 integration tests under a
>   virtual display.
> - An independent review of the adapter found 2 high, 4 medium and 6 low findings; all were fixed with a test each.
> - Not run: a release build of a desktop app, a real display, a production project.

## How to enable it

```yaml
dependencies:
  firebase_core: ^5.1.0
  firebase_database: ^13.1.0
  firebase_database_dart_platform: ^0.0.1
```

**On Linux** nothing else is needed for the emulator or open rules: Flutter calls `FirebaseDatabaseDart.registerWith()`
before `main()`. Pass the options to `Firebase.initializeApp` (there is no native configuration file to read them
from), with a `databaseURL`, or at least a `projectId`, from which the client derives
`https://<projectId>-default-rtdb.firebaseio.com` as the native SDKs do:

```dart
await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
await FirebaseDatabase.instance.ref('notes/today').set('Hello');
```

**On Windows**, list the package as a direct dependency (as above): it then replaces FlutterFire's native
`firebase_database` plugin (the C++ SDK), which leaves the build, and registers before `main()` as on Linux: the
generated plugin registrant calls `FirebaseDatabaseDart.registerWith()`. `firebase_core` stays native.

**On any other platform**, call `FirebaseDatabaseDart.use()` at the start of `main()`, before the first use of
`Firebase` or `FirebaseDatabase`. There `firebase_core` keeps its native implementation, and the native Realtime
Database SDK is still built into the app, unused.

### The signed-in user

The connection authenticates with the user that `tokenProviderFor` returns, as with the Firestore and Storage
platform packages of this repository. With `firebase_auth_dart_platform`:

```dart
FirebaseDatabaseDart.use(
  tokenProviderFor: (FirebaseApp app) => FirebaseAuthDart.userAuthFor(app),
);
```

With the official `firebase_auth` (its native implementation), through `cloud_firestore_dart_flutterfire`:

```dart
FirebaseDatabaseDart.use(
  tokenProviderFor: (FirebaseApp app) =>
      FlutterFireAuthTokenProvider(FirebaseAuth.instanceFor(app: app)),
);
```

A sign-in, a switch of users and a token refresh re-authenticate the open connection without dropping it. A change
event of the provider is a signal: the client fetches the token from the provider, and an empty token means signed out.
The change events of `FlutterFireAuthTokenProvider` do not hold the token, so the provider is installed behind a
wrapper that answers each change with the token of `getAccessToken`; the adapter never forwards a placeholder as a
token.

Without it the connection carries no user, which is enough for the emulator and for open rules. When another platform
package of this repository already set up the app (a `firebase_app_dart` app with the name of the FlutterFire app), that
app keeps its token provider and `tokenProviderFor` is not called; when that app has no token provider, it gets the one
of `tokenProviderFor`. The wrapper is installed only on a provider of `tokenProviderFor`; for a provider that another
package installed on the shared app, the client fetches the token itself on each change event.

### App Check

Pass `appCheckProviderFor` with the `FlutterFireAppCheckProvider` of
[`cloud_firestore_dart_flutterfire`](https://pub.dev/packages/cloud_firestore_dart_flutterfire), built on the official
`firebase_app_check`, as for the Storage platform package:

```dart
FirebaseDatabaseDart.use(
  appCheckProviderFor: (FirebaseApp app) {
    final FirebaseAppCheck appCheck = FirebaseAppCheck.instanceFor(app: app);
    return FlutterFireAppCheckProvider(
      getToken: appCheck.getToken,
      onTokenChange: appCheck.onTokenChange,
    );
  },
);
```

Without it, or when it returns null, the connection sends no App Check token.

### Options of `use`

| Argument | Default | What it does |
| --- | --- | --- |
| `tokenProviderFor` | none: no user | Returns the token provider of a FlutterFire app; called once per app. |
| `appCheckProviderFor` | none: no App Check token | Returns the App Check token provider of a FlutterFire app; called once per app. |
| `persistenceFor` | none: memory only | A `DatabasePersistenceFactory`: returns the client's `DatabasePersistence` for the cache size the app set (below). |
| `useDartCore` | Linux only | Installs a small pure-Dart `firebase_core` in place of its method-channel implementation; a core another package installed is kept. Pass `true` for any platform (tests), `false` to never do it. |

`use()` throws a `StateError` once an instance has created its client, because the configuration is read then.
`FirebaseDatabaseDart.clientFor(app)` returns the client behind an instance, for what the official API does not
have: `onConnected`, `isConnected`, `serverTimeOffset`, `onChildEvents`, `close`.

### Persistence

The clients keep their data in memory unless `use` was given `persistenceFor`, a function from the cache size to a
`DatabasePersistence`. The disk one comes from `firebase_database_dart_sqlite` (this package does not depend on it).
The function is called once per instance (app and database URL), when the instance creates its client, with the size
of `FirebaseDatabase.setPersistenceCacheSizeBytes`, 10 MiB when the app set none. The client keys the cache by app
name and database URL, so one directory serves every app.

- `setPersistenceEnabled(false)` turns it off for an instance; `setPersistenceEnabled(true)` without
  `persistenceFor` prints a warning and stays in memory.
- With persistence, pending writes survive a restart and are sent again (at least once). Transactions and
  `onDisconnect` registrations do not: they are memory only. Register `onDisconnect` writes again when the client
  reconnects (`clientFor(app).onConnected`).

### Emulator, logging, deleting an app

- The emulator is used only when the app calls `useDatabaseEmulator`. The `FIREBASE_DATABASE_EMULATOR_HOST`
  environment variable is not read, as with the Firestore and Storage platform packages and FlutterFire's own
  plugins.
- The client's warnings and errors (for example that persistence could not be opened and the client runs in memory)
  are printed with `debugPrint` always; its debug and info lines only after `setLoggingEnabled(true)`.
- `FirebaseApp.delete()` closes the clients of that app on every platform (through `firebase_core`'s
  `registerService`). The `FirebaseDatabase` objects of the app keep working once an app of the same name is created
  again: the next call creates a new client with the settings the object had.

## What is implemented

| Official API | Underneath | Notes |
| --- | --- | --- |
| `FirebaseDatabase.instanceFor(app:, databaseURL:)` | one `firebase_database_dart` client per app and database, created at the first I/O | `instance` and `instanceFor` with the same database (the app's URL, a trailing slash, another case of the host) share it, as on Android |
| `useDatabaseEmulator`, `setPersistenceEnabled`, `setPersistenceCacheSizeBytes`, `setLoggingEnabled` | the client's constructor arguments | captured before the client exists; see "How it differs" |
| `goOnline`, `goOffline`, `purgeOutstandingWrites` | the same client calls | pending writes fail with `write-cancelled` |
| `ref`, `refFromURL`, `child`, `parent`, `root`, `key`, `path` | the location's keys | no client, no I/O |
| `set`, `setWithPriority`, `update`, `setPriority`, `remove`, `push` | `set`, `update`, `setPriority`, `push` | map keys are stringified (as FlutterFire does) |
| `onValue`, `onChildAdded`, `onChildChanged`, `onChildRemoved`, `onChildMoved`, `once`, `get` | the client's streams and `get` | |
| `orderBy*`, `startAt`, `startAfter`, `endAt`, `endBefore`, `equalTo`, `limitToFirst`, `limitToLast`, `keepSynced` | the client's `Query` | |
| `runTransaction(handler, applyLocally:)` | `runTransaction` | the handler gets a fresh mutable copy on each run; it may run several times |
| `onDisconnect()`: `set`, `setWithPriority`, `update`, `remove`, `cancel` | `onDisconnect` | |
| `ServerValue.timestamp`, `ServerValue.increment` | resolved by the server, and by the client for local events | |
| `DataSnapshot`: `key`, `value`, `priority`, `exists`, `child`, `hasChild`, `children`, `ref` | the client's `DataSnapshot` | `value` is a mutable copy |

Errors are `FirebaseException`s of `firebase_core` with the plugin `firebase_database` and FlutterFire's codes:
`permission-denied`, `disconnected`, `max-retries`, `overridden-by-set`, `unavailable`, `network-error`,
`index-not-defined`, `write-cancelled`, `failure`, `unknown`, plus the client's `database-closed`, `too-big` and
`read-only`, which FlutterFire does not have.

### Transactions

The handler is synchronous and may run several times: first on the value the client holds (null when it holds
none), then again on the server's value each time the server says the local one was stale. Each run gets its own
mutable copy (`Map<Object?, Object?>`, `List<Object?>`), so changing it and returning it is safe. Return
`Transaction.success(value)` to write or `Transaction.abort()` to stop: an abort completes with `committed: false`
and the snapshot the handler saw, and writes nothing. An exception the handler throws fails `runTransaction` with
that same object. With `applyLocally: false`, listeners see no local event before the server's answer.

### Not supported

- **Web**: use the official plugin.
- **Long polling**: the client speaks only the WebSocket protocol.
- **`DatabasePlatform.getChannelArguments`** is not overridden and throws `UnimplementedError`, as in FlutterFire's
  web implementation: only the method-channel implementation builds channel arguments, and the official
  `firebase_database` never calls it.

## How it differs from the official plugin

- **Streams are not broadcast streams.** Each listen of `onValue` (or another event stream) is its own registration
  with its own initial event, and cancelling it removes only that registration, as the client's streams do.
- **Settings are captured when the client is created**, at the first I/O of an instance (a read, a write, the first
  listen of an event stream, `push`, `goOnline`...). `push()` makes no request, but it needs the client for the
  server time offset of the key, so call `useDatabaseEmulator` before it. After the client is created,
  `useDatabaseEmulator` with the same host does nothing and with another one throws a `StateError` (ignoring it would
  send the traffic to production); `setPersistenceEnabled` and `setPersistenceCacheSizeBytes` are ignored with a
  debug message, as on Android; `setLoggingEnabled` takes effect at once.
- **Persistence is injected** as a factory from the cache size (`persistenceFor`), not switched on by the native SDK.
- **References are made without the client**: `ref`, `child`, `parent`, `root`, `key`, `path` and `onDisconnect()`
  only build a location. So an invalid key, `ref('a.b')`, is reported at the first read or write of it (an
  `ArgumentError`), not when the reference is made.
- **Values are mutable copies**, typed `Map<Object?, Object?>` and `List<Object?>` as the native plugins type them,
  made once per snapshot; two listeners never share one. `snapshot.child(...)` and `snapshot.children` make their own
  copies from the client's data, and `children` makes new ones on each iteration: a change to the parent's `value`
  map, or to the value of a child taken from an earlier iteration, is not seen through them. The native plugins derive
  children from the parent's `value` map, so there they see it.
- **A stream ends after the server cancels its listen** (`permission-denied`, then done), as the client's streams do;
  on Android the stream reports the error and stays open, so an `await for` loop ends here and waits there.
- **A child snapshot keeps its priority** (`snapshot.child('a').priority`, `children`); the native plugins give null.
- **The snapshot of a child event has the child's reference** (`event.snapshot.ref` of `onChildAdded` is the child,
  as in the JS and native SDKs); FlutterFire gives the query's reference. Code that used `event.snapshot.ref` as the
  list's reference must use the query's reference instead.
- **A null cursor stays null**: `startAt(null)` is a bound at null (which sorts first), as in JS; on Android
  FlutterFire sends the string `"null"`.
- **`path` has a leading slash** (`'/notes/a'`, `'/'` at the root), as on the web; native has none.
- **Modifiers are applied in one order** (orderBy, start, end, limit) whatever the call order, so
  `startAt(1).orderByChild('x')` works; an invalid combination is an error of the stream or of `get`, not of the call.
- **Error codes**: the client's `write-canceled` is reported as `write-cancelled` and `operation-failed` as `failure`,
  FlutterFire's spellings; `database-closed` (the instance was closed or its app deleted) is not in FlutterFire.
- **Programmer errors stay Dart errors**: a bad path, key, value or query is an `ArgumentError` or a `StateError`,
  and a transaction handler's exception is rethrown as itself, where the native plugins report
  `FirebaseException('unknown')`.
- **`keepSynced`** is a flag per query, not a counter.
- **On Windows**, `ServerValue.increment`, `startAfter` and `endBefore` work, and a rejected transaction is
  `permission-denied`; the native C++ plugin gets these wrong (FlutterFire's own tests skip them there).

## Platforms

| Platform | Selected by | Notes |
| --- | --- | --- |
| Linux | automatic (`dartPluginClass`) | `firebase_core` is installed too, unless another package did it first. FlutterFire has no Linux plugin for `firebase_database`. Run on Linux x64 (Debian 13 container): the example app builds and passes its 4 integration tests under a virtual display |
| Windows | automatic when a direct dependency (`dartPluginClass`) | replaces FlutterFire's native plugin (C++ SDK); `firebase_core` stays native. Run on Windows 11 x64, Flutter 3.47.8, debug: the example app passes its 4 integration tests against the emulator |
| macOS, Android, iOS | `FirebaseDatabaseDart.use()` | `firebase_core` and the native SDK stay in the build |
| Web | not supported | use the official plugin |

Under `flutter test`, the registration on Linux leaves `firebase_core` alone, so that `setupFirebaseCoreMocks` keeps
working; call `use()` to choose otherwise.

## Example

[`example/main.dart`](example/main.dart) writes, listens, runs a transaction and registers an `onDisconnect` write
against the Database emulator.
