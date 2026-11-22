# firebase_database_dart_platform

An unofficial implementation of the platform interface of the official
[`firebase_database`](https://pub.dev/packages/firebase_database) Flutter plugin (13.1.0,
`firebase_database_platform_interface` 0.4.3+10), on top of `firebase_database_dart`, a pure-Dart client of the
Firebase Realtime Database over its WebSocket protocol. An app keeps the official API
(`FirebaseDatabase.instance.ref('notes').onValue`, `set`, `runTransaction`, `onDisconnect()`, ...) and the Dart
client does the work underneath, without the native Firebase SDKs.

It is for a Flutter app on Linux desktop, where `firebase_database` and `firebase_core` have no implementation of
their own: adding the dependency registers it. On Windows, an app that lists it as a direct dependency gets it in
place of the native plugin. On the other platforms it is an opt-in through `FirebaseDatabaseDart.use()`. It is not
affiliated with or endorsed by Google or Firebase.

> **Status: 0.0.1, not published, work in progress.** What is and is not verified:
>
> - The client underneath, `firebase_database_dart`, is complete, and its tests pass against the Database emulator.
> - The unit tests of this package have run, against the client's fake server
>   (`package:firebase_database_dart/testing.dart`).
> - FlutterFire's own `firebase_database` integration suite (78 tests) is the acceptance gate
>   (`tool/test_flutterfire_database_gate.sh`, against the Database emulator); it has **not run yet**.
> - The Windows registration is verified with stand-in plugins; a real Windows build has **not run yet** and is run
>   before release.
> - Nothing has run against a production project.

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

**On Windows**, list the package as a direct dependency (as above): it then replaces the native `firebase_database`
plugin, which leaves the build, and registers before `main()` as on Linux. `firebase_core` stays native.

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

Without it the connection carries no user, which is enough for the emulator and for open rules. When another
platform package of this repository already set up the app (a `firebase_app_dart` app with the name of the
FlutterFire app), that app and its token provider are used, and `tokenProviderFor` is not called.

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
| `useDartCore` | Linux only, when `firebase_core` has no other implementation | Installs a small pure-Dart `firebase_core`. Pass `true` to force it (tests), `false` to never do it. |

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

## What is implemented

| Official API | Underneath | Notes |
| --- | --- | --- |
| `FirebaseDatabase.instanceFor(app:, databaseURL:)` | one `firebase_database_dart` client per app and URL, created at the first I/O | |
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

## How it differs from the official plugin

- **Streams are not broadcast streams.** Each listen of `onValue` (or another event stream) is its own registration
  with its own initial event, and cancelling it removes only that registration, as the client's streams do.
- **Settings are captured when the client is created**, at the first I/O of an instance (a read, a write, `push`,
  `goOnline`...). After that `useDatabaseEmulator` with the same host does nothing and with another one throws a
  `StateError` (ignoring it would send the traffic to production); `setPersistenceEnabled` and
  `setPersistenceCacheSizeBytes` are ignored with a debug message, as on Android; `setLoggingEnabled` takes effect at
  once.
- **Persistence is injected** as a factory from the cache size (`persistenceFor`), not switched on by the native SDK.
- **References are made without the client**: `ref`, `child`, `parent`, `root`, `key`, `path` and `onDisconnect()`
  only build a location. So an invalid key, `ref('a.b')`, is reported at the first read or write of it (an
  `ArgumentError`), not when the reference is made.
- **Values are mutable copies**, typed `Map<Object?, Object?>` and `List<Object?>` as the native plugins type them,
  made once per snapshot; two listeners never share one.
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
| Linux | automatic (`dartPluginClass`) | `firebase_core` is installed too, unless another package did it first |
| Windows | automatic when a direct dependency (`dartPluginClass`) | replaces the native plugin; `firebase_core` stays native. Verified with stand-in plugins; a real Windows build is run before release |
| macOS, Android, iOS | `FirebaseDatabaseDart.use()` | `firebase_core` and the native SDK stay in the build |
| Web | not supported | use the official plugin |

Under `flutter test`, the registration on Linux leaves `firebase_core` alone, so that `setupFirebaseCoreMocks` keeps
working; call `use()` to choose otherwise.

## Example

[`example/main.dart`](example/main.dart) writes, listens, runs a transaction and registers an `onDisconnect` write
against the Database emulator.
