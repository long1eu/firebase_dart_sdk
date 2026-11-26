# Moving a FlutterFire `firebase_database` app to Linux, Windows or pure Dart

This guide is for a Flutter developer whose app uses `package:firebase_database` (the FlutterFire plugin, 13.1.0)
and who wants it to run on Linux or Windows desktop, or on one Dart implementation on every platform, without
rewriting it. There are two routes. **Route A** keeps `package:firebase_database` and adds the adapter
`firebase_database_dart_platform`, which plugs the pure-Dart client `firebase_database_dart` in underneath. **Route B**
moves the code to the client's own Dart API.

It does not cover Firestore or Storage (see [The official cloud_firestore API on
cloud_firestore_dart](flutterfire_platform.md) and
[Coming from FlutterFire's cloud_firestore](migrating_from_flutterfire.md)),
the web (the adapter does not support it: keep the official plugin there), or a server or command line
program (use the client directly, see its README). Both packages are at 0.0.1 and not published; until they
are, depend on them from the repository.

## Which route

| | Route A: the adapter | Route B: the client's API |
|---|---|---|
| Code changes | none in the app, a pubspec line and, on some platforms, one call in `main()` | every `package:firebase_database` call site |
| Keeps | `FirebaseDatabase.instance`, `firebase_core`, `firebase_options.dart`, the generated plugins | nothing of FlutterFire |
| Platforms | Linux and Windows by themselves, others by one call; not the web | every platform the Dart client runs on, the web included |
| Cost | the native SDK stays in the build where it exists; a few behaviours differ (below) | a rewrite, and two `FirebaseApp` classes if you keep `firebase_core` for other plugins |
| Gains | the app works where the plugin has no implementation | one ordered event stream, unmodifiable values, settings as constructor arguments |

Route A is the way to take when the code is large or other FlutterFire plugins stay in the app. Route B is for new
code, for apps that already leave FlutterFire, and for the web.

## Route A: keep `package:firebase_database`

### Step 1: the pubspec

```yaml
dependencies:
  firebase_core: ^5.1.0
  firebase_database: ^13.1.0
  firebase_database_dart_platform: ^0.0.1
```

The adapter lists `implements: firebase_database` with the plugin class `FirebaseDatabaseDart` for `linux` and
`windows` (its `pubspec.yaml`). It needs Dart 3.12 and Flutter 3.44 or later, the versions that
`firebase_database_platform_interface` 0.4.3+10 requires.

### Step 2: what registers by itself, and where a call is needed

| Platform | How the adapter is chosen | What you write |
|---|---|---|
| Linux | automatically: Flutter calls `FirebaseDatabaseDart.registerWith()` before `main()`. Neither `firebase_database` nor `firebase_core` has a Linux implementation, so the adapter also installs a small pure-Dart `firebase_core` | nothing |
| Windows | automatically, but only when the adapter is a **direct** dependency of the app: Flutter then builds it instead of the native plugin. `firebase_core` stays native | nothing |
| macOS, Android, iOS | not automatic | `FirebaseDatabaseDart.use()` first in `main()` |
| Web | not supported | keep the official plugin |

On macOS, Android and iOS, `firebase_core` and the native Realtime Database SDK stay in the build; the adapter only
replaces the platform object that the official package asks for. Use it there when you want the same Dart
implementation everywhere, for example to test it:

```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database_dart_platform/firebase_database_dart_platform.dart';
import 'package:flutter/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseDatabaseDart.use(); // not needed on Linux and Windows
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await FirebaseDatabase.instance.ref('notes/today').set('Hello');
}
```

`DefaultFirebaseOptions` is your generated `firebase_options.dart`. On Linux there is no native configuration file
to read, so pass the options to `Firebase.initializeApp`, with a `databaseURL` or at least a `projectId`, from which
the client derives `https://<projectId>-default-rtdb.firebaseio.com`. `use()` must run before the first use of
`Firebase` or `FirebaseDatabase`; once an instance has created its client it throws a `StateError`.

### Step 3: the signed-in user, persistence, the emulator

**The user.** Without a token provider the connection carries no user, which is enough for open rules and the
emulator. For rules that look at `auth`, pass `tokenProviderFor` to `use` (the adapter's README shows it with
`firebase_auth_dart_platform` and with the official `firebase_auth` through `cloud_firestore_dart_flutterfire`);
`appCheckProviderFor` does the same for App Check.

**Persistence.** The data is in memory unless `use` gets `persistenceFor`. The disk cache is in
`firebase_database_dart_sqlite`, which the adapter does not depend on:

```dart
import 'package:firebase_database_dart_platform/firebase_database_dart_platform.dart';
import 'package:firebase_database_dart_sqlite/firebase_database_dart_sqlite.dart';

void usePersistence(String directory) {
  FirebaseDatabaseDart.use(
    persistenceFor: (int cacheSizeBytes) =>
        sqlitePersistence(directory, cacheSizeBytes: cacheSizeBytes),
  );
}
```

Your existing `FirebaseDatabase.instance.setPersistenceEnabled(true)` then turns it on, and
`setPersistenceCacheSizeBytes` sets the size (1 MiB to 100 MiB, 10 MiB when unset; outside the range it throws an
`ArgumentError`). `setPersistenceEnabled(true)` without `persistenceFor` prints a warning and stays in memory. The
factory runs once per app and database URL, when the instance creates its client. Pending writes survive a
restart and are sent again; transactions and `onDisconnect` registrations do not.

**The emulator.** Your `useDatabaseEmulator('127.0.0.1', 9100)` works as before, and the adapter also reads
`FIREBASE_DATABASE_EMULATOR_HOST`. Start an emulator with `tool/start_database_emulator.sh 9100` (see
[Testing](#testing-an-app-on-the-adapter)).

### What behaves differently from the official plugin

"Can break" means that correct FlutterFire code can behave differently. The code of each row is in
`firebase_database/firebase_database_dart_platform/lib/src/`.

| Difference | Official plugin | Adapter | Can break an app? |
|---|---|---|---|
| A child snapshot keeps its priority (fixed quirk) | `snapshot.child('a').priority` and `children` give null | the child's priority | rarely: code that relied on null |
| `snapshot.ref` of a child event (fixed quirk) | the query's reference | the child's reference, as in the JS and native SDKs | yes, if code used it as the list's reference |
| A null cursor (fixed quirk) | `startAt(null)` is dropped; Android queries the string `"null"` | a real bound at null, which sorts first | rarely |
| `path` | `'notes/a'` (native) | `'/notes/a'`, `'/'` at the root, as on the web | yes, if code compares paths |
| Map keys that are not strings | stringified on write | stringified on write, the later entry wins on a collision; a key invalid after that (`1.5`) is an `ArgumentError` | no |
| Values handed to the app | mutable `Map<Object?, Object?>` and `List<Object?>` | the same types, a deep copy made once per snapshot, so two listeners never share one | no |
| Event streams | broadcast | not broadcast: each `listen` is its own registration with its own initial event | yes, if two parts of the app share one stream object and expect one initial event |
| Error codes | `write-cancelled`, `failure` | the same spellings; plus `database-closed` and `too-big`, which FlutterFire does not have | no |
| Programmer errors and handler exceptions | reported as `FirebaseException` | a bad path, key, value or query is an `ArgumentError` or `StateError`; an exception thrown in a transaction handler fails `runTransaction` as itself | yes, if code catches only `FirebaseException` |
| Where a bad reference is reported | at the call | `ref('a.b')` makes no client, so it fails at the first read or write | yes, if a test expects a throw from `ref` |
| Modifier order | `startAt(1).orderByChild('x')` accepted | accepted: applied in one order whatever the call order; an invalid combination fails the stream or `get`, not the call | no |
| Settings | `useDatabaseEmulator` and the others before first use | captured when the client is created, at the first read, write, `push`, `goOnline`... | yes: another emulator host afterwards throws a `StateError`; `setPersistenceEnabled` and `setPersistenceCacheSizeBytes` are ignored with a debug message |
| Persistence | on by `setPersistenceEnabled(true)` on the native SDKs | memory unless `persistenceFor` is given | yes, if the app counted on a cache after a restart |
| `keepSynced` | a flag per query | a flag per query, not a counter | no |
| Windows | the C++ SDK: `ServerValue.increment` is unresolved, `startAfter` and `endBefore` are inclusive, a rejected transaction is not `permission-denied` | all three work | the adapter's side is the correct one |
| `getChannelArguments` | method channel | the one member of the platform interface not overridden: it throws `UnimplementedError`, and only the method-channel class calls it | no |

Nothing else of the interface throws `unimplemented`: every member of the database, reference, query, snapshot,
event, `onDisconnect` and transaction classes is implemented (`remove()` of `onDisconnect` is inherited and is
`set(null)`).

### What has been run, and where

- FlutterFire's own `firebase_database` integration suite (77 tests) through the adapter, against the emulator:
  76 pass and 1 skips itself. It ran on macOS with the host test runner, with the target platform set to Linux
  (`tool/test_flutterfire_database_gate.sh`), not on a device.
- A Flutter Windows debug app written against `package:firebase_database` was built with the adapter on Windows 11
  x64 with Flutter 3.47.8, and did a write, a read and a transaction against the emulator.
- Not run: a release build, a Linux desktop app, anything on Android, iOS or the web, and any production
  project through the adapter (the client underneath ran its verification kit against production once).

Treat 0.0.1 as a first version: test your own app on the target platform before you ship it.

## Route B: the client's own Dart API

Add `firebase_database_dart` and `firebase_app_dart` (and `firebase_database_dart_sqlite` for a disk cache), and
remove `firebase_database`. The app is made from the same values as your `firebase_options.dart`:

```dart
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart';

final FirebaseApp app = FirebaseApp.withOptions(
  const FirebaseOptions(
    apiKey: '<the apiKey of your options>',
    appId: '<the appId>',
    projectId: '<the projectId>',
  ),
);
final FirebaseDatabase database = FirebaseDatabase(app, emulatorHost: '127.0.0.1:9100');
```

`FirebaseApp` and `FirebaseOptions` here are `firebase_app_dart`'s own classes, not those of `firebase_core`
([Configuring the FirebaseApp](firebase_app.md)). There is no global instance and no instance cache: keep one
`FirebaseDatabase` for the app, because two on one URL are two connections. `close()` ends it.

### What you gain

- **One ordered stream of child events.** `ref.onChildEvents` delivers added, changed, moved and removed events in
  the order they happened, with `event.type`. Four separate streams lose that order when one of them is paused,
  and `await for` pauses after every event.
- **Unmodifiable values.** `snapshot.value` is plain Dart data (`Map<String, Object?>`, `List<Object?>`), built
  once, so patterns work without casts and one reader cannot change what another reads. Copy it to change it.
- **Configuration in the constructor.** The emulator, the persistence and the logger are arguments, so there is
  no call order to get wrong.
- Extras on the snapshot (`hasChildren`, `childrenCount`, `toJson`), `onConnected`, `isConnected`,
  `estimatedServerTime`, and `mockUserToken` for emulator tests.

### The mapping

| FlutterFire (`package:firebase_database`) | `firebase_database_dart` |
|---|---|
| `FirebaseDatabase.instance`, `instanceFor(app:, databaseURL:)` | `FirebaseDatabase(app, databaseUrl: ...)`, kept by you |
| `useDatabaseEmulator('127.0.0.1', 9100)` | `emulatorHost: '127.0.0.1:9100'` (no Android `10.0.2.2` mapping: pass it yourself) |
| `setPersistenceEnabled`, `setPersistenceCacheSizeBytes` | `persistence: sqlitePersistence(directory, cacheSizeBytes: ...)` |
| `setLoggingEnabled(true)` | `logger:` (a `DatabaseLogger`; silent without one) |
| `goOnline()`, `goOffline()`, `purgeOutstandingWrites()` | the same names |
| `ref([path])`, `refFromURL(url)` | `ref([path])`, `refFromUrl(url)` |
| `child`, `parent`, `root`, `key`, `path`, `push()` | the same names; `path` has the leading slash |
| `set(value)`, `setWithPriority(value, p)` | `set(value)`, `set(value, priority: p)` |
| `update`, `setPriority`, `remove` | the same names |
| `onDisconnect()` with `set`, `setWithPriority`, `update`, `remove`, `cancel` | `onDisconnect` (a getter) with `set(value, priority: p)`, `update`, `remove`, `cancel` |
| `runTransaction(handler, applyLocally: true)` | the same; `Transaction.success(value)` and `const Transaction.abort()` |
| `onValue`, `onChildAdded`, `onChildChanged`, `onChildMoved`, `onChildRemoved` | the same, plus `onChildEvents` |
| `once([type])`, `get()` | the same |
| `orderByChild`, `orderByKey`, `orderByValue`, `orderByPriority`, `startAt`, `startAfter`, `endAt`, `endBefore`, `equalTo`, `limitToFirst`, `limitToLast`, `keepSynced` | the same names; modifiers are checked when you build the query, so a bad combination throws at the call |
| `DataSnapshot`: `key`, `value`, `priority`, `exists`, `child`, `hasChild`, `children`, `ref` | the same; `value` is unmodifiable |
| `ServerValue.timestamp`, `ServerValue.increment(n)` | the same |
| `FirebaseException` of `firebase_core` | `FirebaseDatabaseException` (extends `FirebaseException` of `firebase_app_dart`), with `serverStatus` |
| `write-cancelled`, `failure` | `write-canceled`, `operation-failed` |

A query, translated. FlutterFire:

```dart before
final DataSnapshot top = await FirebaseDatabase.instance
    .ref('players')
    .orderByChild('score')
    .limitToLast(3)
    .get();
final Map<Object?, Object?>? players = top.value as Map<Object?, Object?>?;
await FirebaseDatabase.instance.ref('players/ada').onDisconnect().remove();
```

The client:

```dart
final DataSnapshot top = await database.ref('players').orderByChild('score').limitToLast(3).get();
for (final DataSnapshot child in top.children.toList().reversed) {
  print('${child.key}: ${child.value}');
}
await database.ref('players/ada').onDisconnect.remove();
```

A filtered or limited `get()` is sent with its index and fails with `index-not-defined` where the rules have no
`.indexOn`; a listener or `once()` does not. Order-only queries need no index. If you take route B for the
platforms where the official plugin exists, keep both packages out of one file: both export `FirebaseDatabase`,
`DatabaseReference`, `DataSnapshot` and `ServerValue`, so import one with a prefix.

## Testing an app on the adapter

Start an emulator from the repository (it needs Java and the Firebase CLI):

```shell
tool/start_database_emulator.sh 9100   # 127.0.0.1:9100, project demo-test, open rules
tool/stop_database_emulator.sh 9100
```

Then, before any other use of the database in your app or test:

```dart
FirebaseDatabase.instance.useDatabaseEmulator('127.0.0.1', 9100);
```

With the options of `demo-test` (a `databaseURL` of `https://demo-test-default-rtdb.firebaseio.com`) the database is the
namespace `demo-test-default-rtdb`, to which the rules file given to the emulator applies. The adapter's
`example/main.dart` writes, listens, runs a transaction and registers an `onDisconnect` write against this emulator.
Under `flutter test` the Linux registration leaves `firebase_core` alone so that `setupFirebaseCoreMocks` keeps
working; call `FirebaseDatabaseDart.use(useDartCore: true)` in a test that wants the Dart core. The client's own
fake server for unit tests is `package:firebase_database_dart/testing.dart`.

## Troubleshooting

- **`useDatabaseEmulator` throws a `StateError`.** The instance had already created its client, which then talked to
  another host (production by default). Call it before the first read, write, `push` or `goOnline`, also in tests.
- **`FirebaseDatabaseDart.use` throws a `StateError`.** An instance has already created its client. Call `use` first
  in `main()`.
- **The app still uses the native plugin on Windows.** The adapter is a transitive dependency (another package of
  yours depends on it): Flutter then keeps the native plugin. List it in the app's own `pubspec.yaml`. On Windows
  you can check the generated `windows/flutter/generated_plugins.cmake`.
- **Nothing changes on macOS, Android or iOS.** The adapter is not automatic there: call `FirebaseDatabaseDart.use()`.
  `FirebaseDatabaseDart.isRegistered` says whether it is in place.
- **`Firebase.initializeApp` fails with `no-options` on Linux.** There is no native configuration file to read: pass
  `options`.
- **The data is gone after a restart.** Persistence is memory only without `persistenceFor`; a call to
  `setPersistenceEnabled(true)` alone only prints a warning.
- **`setPersistenceEnabled` or `setPersistenceCacheSizeBytes` seems ignored.** It was called after the client was
  created; the adapter ignores it and prints a debug message. Call it before the first use.
- **A list that follows `onChildAdded` shows the wrong item.** The code uses `event.snapshot.ref` as the list's
  reference; on the adapter it is the child's. Use the query's reference.
- **`permission-denied` with correct rules.** The connection has no user: pass `tokenProviderFor` to `use`.
- **`A firebase_app_dart app named ... exists with other options`.** Another package of this repository set up the
  `firebase_app_dart` app of that name with different options than the FlutterFire app; make them equal.
- **The client behind an instance.** `FirebaseDatabaseDart.clientFor(app)` returns it, for `onConnected`,
  `isConnected`, `serverTimeOffset`, `onChildEvents` and `close`. It creates the client if there is none yet, which
  fixes the settings.
