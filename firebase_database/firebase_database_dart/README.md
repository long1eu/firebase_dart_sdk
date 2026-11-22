# firebase_database_dart

Unofficial client for the [Firebase Realtime Database](https://firebase.google.com/docs/database), written in Dart,
for the Dart VM and the web. The official Flutter plugin `firebase_database` declares Android, iOS, macOS, Windows and
web, and no Linux. So on Linux this client (through the adapter) is the only implementation; on Windows and macOS the
official plugin exists (on Windows through the Firebase C++ SDK) and this client is an alternative written in Dart, with
no native SDK in the build; for servers and command line tools in Dart there is no official client at all. It speaks
the WebSocket protocol of the Firebase JS SDK, with Dart names (`DatabaseReference`, `onValue`, `runTransaction`) and
Dart streams. It is not affiliated with or supported by Google or Firebase.

> **Status: 0.0.1, work in progress, not published.** What has run (the maintainer's runs; the record is in
> [docs/database_decisions.md](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/database_decisions.md),
> section 23):
>
> - macOS: 2,137 tests on the Dart VM; in Chrome 1,997 with dart2js and 2,000 with dart2wasm (the whole test tree).
> - Windows 11 x64 (Dart 3.14.1): 2,126 tests on the Dart VM pass.
> - Linux x64, at an earlier commit: 2,058 on the VM, 1,125 with dart2js, 1,128 with dart2wasm.
> - 33 tests against the Firebase Database emulator (v4.11.2).
> - The SQLite cache package: 225 tests on macOS, 221 of 222 on Windows before a test-only fix whose file then passed.
> - FlutterFire's `firebase_database` integration suite through the adapter: 76 pass, 1 skips itself (macOS host test
>   runner, emulator). A Flutter Windows debug app written against `package:firebase_database` built with the adapter
>   and did a write, a read and a transaction against the emulator.
>
> What has **not** run: a production project (nothing here was measured against one), a release build of a desktop
> app, and Safari and Firefox. One person maintains it.

## Use it when

- You write a Flutter desktop app for Linux, where `firebase_database` has no implementation, or for Windows or macOS
  and want a client written in Dart with no native SDK in the build (see
  [Flutter apps](#flutter-apps-that-keep-package-firebase_database)).
- You write a server or a command line tool in Dart that reads and writes the database with a user's rules, or
  listens for changes.
- You write a Dart web app and want a client without the JS SDK or JS interop.
- You test against the Database emulator and want the same client on every platform.

## Do not use it when

- You need a production-proven client today. Use the official SDK where it exists.
- Your network blocks WebSocket upgrades. There is no long polling.
- You need a Flutter app on Android or iOS and have no reason to leave `firebase_database`: that plugin is the
  maintained path there.
- You need the Admin SDK's database features (the client runs as a user or with no user; see
  [Authentication](#authentication-and-app-check)).
- You need disk persistence on the web. The SQLite cache is for the VM and Flutter only.

## Install

```shell
dart pub add firebase_database_dart firebase_app_dart
dart pub add firebase_database_dart_sqlite   # only for the offline cache
dart pub add firebase_auth_providers_dart    # only when the rules look at auth
```

Dart 3.8 or later; no Flutter dependency. The `pubspec.yaml` of 0.0.1 still says `publish_to: none`: publishing is
the maintainer's step, so until then depend on the packages from the repository.

## Quick start with the emulator

In the repository, start a private emulator (it needs Java and the Firebase CLI, see
[tool/README.md](https://github.com/long1eu/firebase_dart_sdk/blob/main/tool/README.md)):

```shell
tool/start_database_emulator.sh          # 127.0.0.1:9100, project demo-test, in the background
tool/stop_database_emulator.sh           # stops the one it started
```

```dart before
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart';

Future<void> main() async {
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'demo-key',
      appId: '1:1234567890:dart:example',
      projectId: 'demo-test',
    ),
  );
  final FirebaseDatabase database = FirebaseDatabase(
    app,
    emulatorHost: FirebaseDatabase.emulatorHostFromEnvironment ?? '127.0.0.1:9100',
  );
  try {
    await database.ref('greetings/first').set('hello');
    final DataSnapshot snapshot = await database.ref('greetings').get();
    print(snapshot.value); // {first: hello}
  } finally {
    await database.close();
  }
}
```

`emulatorHost` is `host:port`, reached over plain WebSocket. `emulatorHostFromEnvironment` reads
`FIREBASE_DATABASE_EMULATOR_HOST` and is `null` on the web; nothing reads that variable unless you ask for it. With an
emulator and no `databaseUrl`, the database is `<projectId>-default-rtdb`; the rules file given to the emulator applies
to that namespace only. An open `FirebaseDatabase` keeps a command line program alive: call `close()`.

The programs in [example/](example/README.md) run against the same emulator.

## Against a real project

```dart
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart';

final FirebaseApp projectApp = FirebaseApp.withOptions(
  const FirebaseOptions(
    apiKey: '<the Web API key of the project>',
    appId: '1:1234567890:dart:example',
    projectId: 'my-project',
  ),
);
// https://my-project-default-rtdb.firebaseio.com
final FirebaseDatabase db = FirebaseDatabase(projectApp);
// A database in another region, or a second database, has its own URL.
final FirebaseDatabase other = FirebaseDatabase(
  projectApp,
  databaseUrl: 'https://my-project-other.europe-west1.firebasedatabase.app',
);
await other.close();
await db.close();
```

A `FirebaseDatabase` is immutable: every setting is a constructor argument, there is no global instance and no
instance cache, and two instances on one URL are two connections. A `databaseUrl` must be `https://`: plain text is
refused outside the emulator, and the message says to use an https URL or the `emulatorHost` argument. The constructor
also refuses, with an `ArgumentError` before any connection, a URL with a path, a custom domain without `?ns=`, a port
other than 443 on a host that is not loopback, and an invalid project id; a start that fails fails every pending and
later call instead of hanging. `close()` is idempotent; afterwards every asynchronous call fails with the code
`database-closed`, and `ref()` still works because it makes no request. Nothing was run against a production project yet
(see Status).

## Read and write

```dart
import 'package:firebase_database_dart/firebase_database_dart.dart';

final DatabaseReference ada = database.ref('users/ada');

await ada.set(<String, Object?>{'name': 'Ada', 'age': 36, 'city': 'London'});
await ada.update(<String, Object?>{'age': 37, 'city': null}); // null removes the child

final DataSnapshot snapshot = await ada.get();
if (snapshot.value case {'name': String name, 'age': num age}) {
  print('$name is $age');
}
print(snapshot.exists); // false for a location with no data

final DatabaseReference message = database.ref('messages').push(); // a new key, ordered by time
await message.set(<String, Object?>{'text': 'hello', 'at': ServerValue.timestamp});
print(message.key);

await ada.remove(); // set(null)
```

`set` replaces what is at the location, `update` changes only the keys you name, and a location either has data or it
does not: there is no stored `null`. A write's Future completes on the server's answer. Offline it stays pending, which
is not an error, and the local events fire at once. A rejected write rolls back with events and fails the Future with
`permission-denied`.

`DataSnapshot.value` is plain Dart data: `null`, `bool`, `int`, `double`, `String`, `List<Object?>` and
`Map<String, Object?>`, so patterns work without casts. It is built once and unmodifiable; copy it to change it. An
integral number within 2^53 reads as an `int` even if you wrote `5.0`. A map whose keys are `0..n` with more than half
present reads as a `List`, so iterate `snapshot.children` when the shape can vary. Bad keys, paths, depths and numbers
throw an `ArgumentError` or `StateError` at the call, before anything is sent.

`set` and `OnDisconnect.set` take an optional `priority:`, and `setPriority` changes only the priority.
`DatabaseReference.key`, `parent`, `root` and `child` build paths without a request; `FirebaseDatabase.refFromUrl` takes
a full URL of this database (it throws for another one), `FirebaseDatabase.app` is the app and `databaseUrl` the URL in
use. A `DataSnapshot` also has `priority`, `child`, `hasChild`, `hasChildren`, `childrenCount`, `ref` and `toJson`.

More: [read_write.dart](example/read_write.dart), [push_and_keys.dart](example/push_and_keys.dart),
[multi_path_update.dart](example/multi_path_update.dart),
[priority_and_ordering.dart](example/priority_and_ordering.dart).

## Listening

```dart
import 'package:firebase_database_dart/firebase_database_dart.dart';

final DatabaseReference items = database.ref('items');

final subscription = items.onValue.listen((DatabaseEvent event) {
  print('${event.snapshot.children.length} children');
});
items.onChildAdded.listen((e) => print('added ${e.snapshot.key} after ${e.previousChildKey}'));
items.onChildChanged.listen((e) => print('changed ${e.snapshot.key}'));
items.onChildMoved.listen((e) => print('moved ${e.snapshot.key}'));
items.onChildRemoved.listen((e) => print('removed ${e.snapshot.key}'));

// One stream of all four child events, in the order they happened.
items.onChildEvents.listen((e) => print('${e.type.name} ${e.snapshot.key}'));

final DatabaseEvent first = await items.once(); // first value event, then the listener is gone
print(first.snapshot.value);

await subscription.cancel();
```

`onValue` first gives the current data and then fires after every change. The child streams fire once for each child
that already exists, then for each change. A stream can be listened to more than once, and each listener has its own
initial events; two streams on equal queries share one listen on the server. Events are delivered from one queue per
database, in a microtask, never inside the call that caused them.

Inside one change the order is: removed, added, moved, changed, then value. Four separate streams keep that order only
while none of them is paused, and `await for` pauses its subscription after every event. `onChildEvents` is the form
whose order survives that. A server refusal (a rule) ends a stream with an error; losing the connection never does,
and a listener simply gets its data again after the reconnect. Closing the database ends streams with
`database-closed`.

More: [listeners.dart](example/listeners.dart).

## Queries

```dart
import 'package:firebase_database_dart/firebase_database_dart.dart';

final Query players = database.ref('players');

// Results are ascending; for a top three take the last three and reverse them.
final Query top = players.orderByChild('score').limitToLast(3);
final DatabaseEvent event = await top.once();
for (final DataSnapshot child in event.snapshot.children.toList().reversed) {
  print('${child.key}: ${child.value}');
}

final Query middle = players.orderByChild('score').startAt(20).endAt(30);
final Query after = players.orderByChild('score').startAfter(20);
final Query red = players.orderByChild('team').equalTo('red');
final Query keys = players.orderByKey().startAt('b').endAt('c');
for (final Query query in <Query>[middle, after, red, keys]) {
  print((await query.once()).snapshot.children.map((DataSnapshot c) => c.key).toList());
}

// Order-only queries need no index in the rules, so get() works.
final DataSnapshot sorted = await players.orderByKey().get();
print(sorted.children.length);
```

A query is immutable: each modifier returns a new one. Modifiers are checked when you build the query (one `orderBy`,
one start, one end, one limit; `equalTo` is a start and an end), and a violation throws at the call. `startAt` and
`endAt` include the bound, `startAfter` and `endBefore` leave it out; each of them, and `equalTo`, takes an optional
`key:` that breaks ties between children with equal values. `orderByValue`, `orderByPriority` and `limitToFirst` work as
in the JS SDK; `Query.ref`, `path` and `url` say where a query points, and `once()` takes the event type to wait for
(`DatabaseEventType.value` by default; the others are `childAdded`, `childChanged`, `childMoved` and
`childRemoved`). Two queries are equal when they belong to the same database and have the same path and modifiers. The
query decides the order of
`snapshot.children`, not of `snapshot.value` as a `Map`.

`get()` answers from an active listener that covers the query, else from the server. A query that only orders (no
range, no limit) is sent as the default query and ordered in the client, so it needs no `.indexOn` rule. A **filtered
or limited** `get()` on `orderByChild` or `orderByValue` is sent with its index and fails with `index-not-defined`
where the rules have no `.indexOn` for it. A listener or `once()` has no such limit: without the index the client
downloads the location, filters it itself and logs a warning ("Using an unspecified index", the server's `no_index`
warning). When the client is not connected, `get()` waits 3 s for a connection and then answers from the cache, only
when the cache holds the complete value for that query (its limit applied; a cached empty location answers null), or
fails with `unavailable`; a refusal by the rules is `permission-denied`, never a cached answer.

More: [queries.dart](example/queries.dart).

## Transactions

```dart
import 'package:firebase_database_dart/firebase_database_dart.dart';

final TransactionResult result = await database.ref('seats').runTransaction((Object? current) {
  if (current == null) {
    return Transaction.success(null); // the first run often sees null, the client has no data yet
  }
  final num seats = current as num;
  return seats > 0 ? Transaction.success(seats - 1) : const Transaction.abort();
});
print('committed: ${result.committed}, value: ${result.snapshot.value}');
```

The handler is synchronous and may run several times, so it must have no side effects. It receives a fresh mutable copy
of the current local value. It is sent as a put with the hash of the data it was computed from; when the server answers
that the data changed, the handler runs again, up to 25 times, then the Future fails with `max-retries`. A transaction
that was sent and loses its connection before the answer is not run again and not re-sent: its local write is rolled
back and the Future fails with `disconnected`. An abort completes with `committed: false` and the snapshot the handler
saw. An exception in the handler aborts the transaction and fails the Future with that same exception. Transactions are
never persisted: one pending when the app quits is lost. `Transaction.success(value, priority:)` can also set the
priority, and `runTransaction(applyLocally: false)` raises no local event for the intermediate runs; the handler's type
is `TransactionHandler`.

More: [transactions.dart](example/transactions.dart), [cookbook/counter.dart](example/cookbook/counter.dart).

## onDisconnect and presence

```dart
import 'package:firebase_database_dart/firebase_database_dart.dart';

final DatabaseReference status = database.ref('status/ada');
// Register again at every connection: the server forgets the registrations when the
// connection ends, and the client does not keep them across a restart.
final presence = database.onConnected.listen((bool connected) async {
  if (!connected) {
    return;
  }
  await status.onDisconnect.set(<String, Object?>{'state': 'offline', 'at': ServerValue.timestamp});
  await status.set(<String, Object?>{'state': 'online', 'at': ServerValue.timestamp});
});
// ... later, to stop:
await presence.cancel();
```

`onDisconnect` has `set`, `update`, `remove` and `cancel`. A path under `.info` is refused by `set`, `update` and
`remove` and `cancel`. The server runs the operation when it sees the connection
end, also after a crash; the Future completes when the server has registered it, not when it ran. Register the offline
write first and write "online" second, so a crash between them cannot leave a user stuck online. A request that was sent
and whose connection drops before the answer completes with `disconnected` and is not replayed; the app registers again
when `onConnected` says it is connected.

More: [on_disconnect.dart](example/on_disconnect.dart), [cookbook/presence.dart](example/cookbook/presence.dart).

## Server values

```dart
import 'package:firebase_database_dart/firebase_database_dart.dart';

await database.ref('post').set(<String, Object?>{
  'title': 'Hello',
  'createdAt': ServerValue.timestamp, // milliseconds since the epoch, on the server
});

await database.ref('views').set(ServerValue.increment(1)); // a missing or non-number value counts as 0

print('offset: ${database.serverTimeOffset}, now on the server: ${database.estimatedServerTime}');
```

Until the server answers, local events show an estimate from the device clock corrected by `serverTimeOffset`; the real
value follows as another event. `ServerValue.increment` adds on the server without a transaction round trip.
**Writes are delivered at least once** (see [Limits](#limits)): for an exact count use a transaction.

More: [server_values.dart](example/server_values.dart), [cookbook/counter.dart](example/cookbook/counter.dart).

## Connection state

```dart
import 'package:firebase_database_dart/firebase_database_dart.dart';

database.onConnected.listen((bool connected) => print('connected: $connected'));
await database.onConnected.firstWhere((bool connected) => connected);

database.goOffline(); // synchronous; listeners keep their data, writes wait in a queue
final Future<void> queued = database.ref('queued').set('written offline');
database.goOnline(); // sends the queue in order
await queued;
```

`onConnected` is `.info/connected`; its first event is the current state, `false` until the first connection is up.
`isConnected`, `serverTimeOffset` and `estimatedServerTime` are plain getters. `purgeOutstandingWrites()` rolls back
every pending write, fails their Futures with `write-canceled`, aborts transactions and completes queued
`onDisconnect` operations with `write-canceled`, as the Android SDK does. An `onDisconnect` operation already sent to
the server is not undone by it, and neither is a transaction already sent if the server accepts it. A transaction the server
accepted completes as committed with the server's value.

A new instance does not connect: the first read, listener (also on `.info`), write, transaction, `get`, onDisconnect
call, `keepSynced(true)` or `goOnline()` does. `goOffline()` before that is kept, so the first operation stays offline.

The client reconnects with a delay that starts at 1 s, grows by 1.3 per failure up to 30 s, with jitter, and resets
after a connection that stayed healthy for 30 s. When the link has had no inbound frame for 30 s it sends a protocol
ping, and after 45 s with nothing sent or received it sends the JS SDK's `0` keep-alive frame; if nothing arrives in
the next 15 s after the ping it closes the connection and reconnects. It resets the delay and reconnects
at once on a hint from the app's network source (`app.onNetworkConnected`). It never closes an idle connection by
itself.

More: [connection_state.dart](example/connection_state.dart), [lifecycle.dart](example/lifecycle.dart).

## Authentication and App Check

The ID token comes from `app.authProvider` and the App Check token from `app.appCheckProvider`; this package does not
depend on the Auth package. `FirebaseDatabase` reads the providers when it is constructed, so set them first. A token
is refreshed on the live connection without a reconnect, and a sign-out sends `unauth`. Without a provider the
connection has no user, which is enough for open rules and for the emulator.

```dart
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart';

// Before the FirebaseDatabase is constructed: it reads the app's providers then.
final FirebaseUserAuth auth = await FirebaseUserAuth.forApp(app);
await auth.signInAnonymously();
final FirebaseDatabase signedIn = FirebaseDatabase(app);
await signedIn.close();
```

Tokens go only over TLS or to the exact `host:port` you gave as `emulatorHost`. The App Check token
is sent in an upgrade header on the VM and in the WebSocket URL on the web, where a socket has no headers; the ID token
never goes in a URL. The
[authentication guide](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/guides/authentication.md) describes
the providers.

### The emulator's mock user

```dart
import 'package:firebase_database_dart/firebase_database_dart.dart';

final FirebaseDatabase asAda = FirebaseDatabase(
  app,
  emulatorHost: '127.0.0.1:9100',
  mockUserToken: mockUserTokenFor(
    'ada',
    projectId: 'demo-test',
    claims: <String, Object?>{'role': 'editor'},
  ),
);
await asAda.close();
```

`mockUserTokenFor` builds an unsigned token that the emulator reads as the signed-in user `ada`, so the rules run for
that user. **Do not pass a plain string as `mockUserToken`.** The emulator treats a string that is not a JWT, the
literal `'owner'` included, as an admin credential, and the rules are then bypassed. `mockUserToken` without an
emulator is refused.

More: [auth_and_rules.dart](example/auth_and_rules.dart), which needs the rules in its header.

## Offline persistence

By default nothing is written to disk. The package
[`firebase_database_dart_sqlite`](../firebase_database_dart_sqlite/README.md) adds a SQLite cache for the Dart VM and
Flutter.

```dart
import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:firebase_database_dart_sqlite/firebase_database_dart_sqlite.dart';

const String supportDirectory = '/path/to/app/support';
final FirebaseDatabase cached = FirebaseDatabase(
  app,
  persistence: sqlitePersistence(
    '$supportDirectory/firebase_database',
    cacheSizeBytes: 20 * 1024 * 1024, // 1 MiB to 100 MiB, 10 MiB by default
  ),
);
print(cached.persistenceEnabled); // false when another instance owns the file

// Only the pending writes are stored; no server data is kept on disk:
final FirebaseDatabase writesOnly = FirebaseDatabase(
  app,
  persistence: sqlitePersistence('$supportDirectory/writes', cacheServerData: false),
);

await cached.close();
await writesOnly.close();
await clearSqlitePersistence(
  '$supportDirectory/firebase_database',
  appName: app.name,
  databaseUrl: cached.databaseUrl,
);
```

Pending writes survive a restart and are sent again; cached server data answers listeners and `get()` while offline.
`cacheServerData: false` (the default is `true`) keeps the pending writes across a restart and caches no server data.
`package:firebase_database_dart/storage_engine.dart` is the library for writing a persistence engine of your own
(`databasePersistence`, the engine interface and `InMemoryPersistenceStorageEngine`).
The cache is kept per app and normalised database URL (two `?ns=` values on one host are two caches), not per signed-in
user: on a shared machine call `clearSqlitePersistence` at sign-out. One process or isolate owns a cache file at a time;
see [Limits](#limits).

## Errors

Server and connection failures are a `FirebaseDatabaseException`, which extends `FirebaseException` (`plugin` is
`'firebase_database'`):

```dart
import 'package:firebase_database_dart/firebase_database_dart.dart';

try {
  await ref.get();
} on FirebaseDatabaseException catch (e) {
  switch (e.code) {
    case 'permission-denied':
      print('the rules refused the request (${e.serverStatus})');
    case 'unavailable' || 'network-error':
      print('no connection');
    default:
      print('${e.code}: ${e.message}');
  }
}
```

`FirebaseDatabaseException.cause` holds the underlying error when it came from outside the package; it is never part of
the message. The codes are `permission-denied`, `disconnected`, `max-retries`, `overridden-by-set`, `unavailable`,
`network-error`, `write-canceled`, `index-not-defined`, `operation-failed`, `too-big`, `read-only`, `database-closed`
and `unknown`. `serverStatus` is the raw status and reason from the server. A message never contains a token or a URL
query. A rejected or expired token is not a code of its own: the server answers `permission-denied` and the connection
retries the token itself. A bad path, key, value or query is an `ArgumentError` or `StateError` at the call, not an
exception through a Future; fix the code instead of catching it. Offline is not an error: writes stay pending and
listeners keep their data.

More: [error_handling.dart](example/error_handling.dart).

## Logging

Logging is off. Pass a callback to turn it on:

```dart
import 'package:firebase_database_dart/firebase_database_dart.dart';

final FirebaseDatabase logged = FirebaseDatabase(
  app,
  logger: (DatabaseLogLevel level, String message) {
    if (level.index >= DatabaseLogLevel.warning.index) {
      print('[${level.name}] $message');
    }
  },
);
await logged.close();
```

`DatabaseLogger` is the type of the callback, `void Function(DatabaseLogLevel level, String message)`. The levels are
`debug`, `info`, `warning` and `error`. Warnings include the missing-index one ("Using an unspecified
index": a query that is filtered on the client because the rules have no `.indexOn`), a cache that runs memory-only and
failed persisted writes. Requests that carry credentials are logged as `<action> (contents hidden)`, URLs without their
query, and snapshot data appears at the debug level only; it is your users' data.

## How it differs from the JS SDK

The 17 you notice are below. The full table, 22 rows with the test that pins each, is section 25 of
[docs/database_decisions.md](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/database_decisions.md).

| Topic | JS SDK | This client |
|---|---|---|
| Configuration | cached instance, setters | constructor arguments only, no cache |
| `get()` of an order-only query | index sent, refused without it | default query, ordered in the client |
| `get()` while offline | queues with no limit | waits 3 s, then cache or `unavailable` |
| Snapshot value | `val()` builds a mutable value | one memoised, unmodifiable value |
| Event delivery | listeners can run inside `set()` | one queue, a microtask, never inside the call |
| Child events | four callbacks | four getters, plus `onChildEvents` and `once()` |
| Transaction result | return `undefined` to abort | `Transaction.success(value)` or `Transaction.abort()` |
| Error codes | upper-case status string | kebab-case codes, none for tokens |
| Plain text | `http://host:443` is accepted | refused outside the emulator, and no token goes over plain text |
| Reconnect delay | cap 5 min, reset on browser events | cap 30 s, reset when healthy |
| Dead link | `0` frame every 45 s, no answer expected | ping after 30 s of silence, close after 15 s more |
| Request timeout | none | a silence timer re-armed by every frame |
| Logging | request bodies logged, tokens too | off; callback; credentials hidden |
| Disk persistence | none | optional SQLite cache with a lease owner |
| Browser storage | writes `firebase:*` keys | writes nothing |
| Writes under `.info` | `update` and `cancel` accepted | `set`, `update`, `remove`, `cancel` refused |
| Long polling | present | absent |

## Limits

- **Writes are delivered at least once.** A put whose answer was lost is sent again after the reconnect, and a re-sent
  `ServerValue.increment` can apply twice. The protocol has no idempotency key and the official SDKs behave the same.
  A transaction is the exact way to count. Persisted writes are at-least-once too.
- **A hung TLS handshake cannot be closed on the Dart VM.** `dart:io` has no way to close a connection attempt stuck
  inside the handshake. The client gives up on it after its 30 s connect timeout and tries again; the socket stays
  until the peer or the system ends it.
- **A dead socket after a wake takes time to notice.** A laptop that wakes with a dead socket gives no signal of its
  own. The dead-link probe closes the socket after 30 s of silence plus 15 s for the answer to its ping, then the
  client reconnects. Usually that is about 46 s (30 s, 15 s and 1 s of backoff after a healthy connection) plus the
  connect. At worst it is about 75 s plus the connect, when the connection had not been healthy for 30 s and the
  backoff may be up to 30 s. Both figures are computed from the timing constants, not measured. When the app signals
  connectivity (`app.onNetworkConnected`), the client reconnects at once; it reads no wake or app-lifecycle event
  from the operating system itself.
- **An increment that leaves the double range is a local infinity.** If the sum of a `ServerValue.increment` goes
  beyond the range of a double, the local value is infinity until the server's value replaces it.
- **One owner per cache file.** A second process or isolate on the same file watches its lease for about 7.5 s, then
  runs memory-only with one logged warning (`persistenceEnabled` is false); its writes are not durable. After a
  storage error an instance is memory-only for the rest of the session, and the file keeps what was committed before
  it. The cache is clear text, and a cache that cannot be used (damaged, or of a newer major version) is moved aside.
- **The SQLite cache runs on the caller's isolate**, which in Flutter is the UI isolate. Measured on one Mac mini
  (macOS, AOT, medians of 5, rows of about 100 bytes): a point read takes 0.1 to 0.2 ms and one pending write 0.1 ms,
  whatever the size of the cache. Loading a whole subtree takes 56.2 ms for 1 MB, 615.2 ms for 10 MB and 2,968.3 ms
  for 50 MB; writing it takes 51.9, 483.8 and 2,123.7 ms; reopening the file takes 3.4, 12.7 and 55.5 ms. macOS
  `fsync` does not force the drive cache, so the write cost on Linux and Windows is not measured.
- **Proxies.** On the Dart VM a secure connection honours `HTTPS_PROXY` and `NO_PROXY` (and the lower-case forms), as
  Dart's `HttpClient` does. Loopback addresses and the emulator are always reached directly. There is no option in the
  API. A proxy that refuses the tunnel fails the connection attempt with an error that names the proxy and the status.
- **Transactions and `onDisconnect` registrations are not persisted.** After a restart, register them again.
- **The server's behaviour was measured on the emulator only.** Token refresh, revocation, ping answers and the
  size limits of a production server are not measured; the three connection timeouts (30 s, 15 s, 60 s) are chosen,
  not measured.
- **Not in this version:**
  - long polling: networks that block the WebSocket upgrade cannot use the client;
  - web disk persistence: the web build is memory only;
  - a REST client, read-only or writing: the WebSocket is the only transport;
  - an instance cache per app and URL: every `FirebaseDatabase(...)` is a new connection;
  - `.info/authenticated` as a typed member (it can be read as the path `.info/authenticated`), and a hook that goes
    offline when an app is sent to the background;
  - typed converters (patterns on the typed value are the typed read), a configurable `get()` wait, the compat
    (namespaced) API, admin-only authentication paths and the idle disconnect.

  There is no parity page for the Database yet; the decisions document is the record of what differs.

## Platforms

| Platform | Client | What ran |
|---|---|---|
| macOS | Dart VM | 2,137 tests; 33 emulator tests; FlutterFire's suite through the adapter (76 pass, 1 skips) |
| Linux x64 | Dart VM | 2,058 tests, at an earlier commit |
| Windows 11 x64 | Dart VM | 2,126 tests; a Flutter debug app with the adapter did a write, a read and a transaction |
| Web, dart2js | Chrome on macOS | 1,997 tests (whole test tree); 1,125 on Linux x64 at an earlier commit |
| Web, dart2wasm | Chrome on macOS | 2,000 tests (whole test tree); 1,128 on Linux x64 at an earlier commit |

No release build of a desktop app has run, and Safari and Firefox are untested. The main library imports no `dart:io`
and no native code. The SQLite cache needs `package:sqlite3` and is not available on the web; it ran 225 tests on macOS
and 221 of 222 on Windows (before a test-only fix whose file then passed). It declares Android, iOS, macOS, Windows and
Linux; no run is recorded on Android or iOS.

## Flutter apps that keep `package:firebase_database`

An app can keep the official API and let this client do the work underneath, by adding
[`firebase_database_dart_platform`](../firebase_database_dart_platform/README.md) next to `firebase_database`:

```yaml
dependencies:
  firebase_database: ^13.1.0
  firebase_database_dart_platform: ^0.0.1
```

On Linux it registers itself; on Windows when it is a direct dependency; elsewhere with
`FirebaseDatabaseDart.use()` at the start of `main()`. The adapter's README has the details.

## Testing your own code

`package:firebase_database_dart/testing.dart` has a scripted in-memory server (`FakeDatabaseServer`), a database
connected to it (`databaseWithFakeServer`) and in-memory persistence (`fakePersistence`). It has no stability promise
beyond the package's contract tests. A test steers the server with `acceptConnections` (set it to false and call
`dropConnection` to keep the client offline), `serverTime`, `ackLastWrite`, `failLastWrite`, `ackLastOnDisconnect`,
`answerGet`, `failGet`, `revokeAuth` and `kill`, and reads `connectionAttempts` and `receivedAuthTokens`.

Events are delivered in batches of 1000, with a turn of the event loop between batches so a long burst does not block
the page. In a browser that turn is a message task, not a timer (a hidden tab delays timers), so a fake clock such as
`package:fake_async` does not drive it: a browser test that queues more than 1000 events at once needs a real `await`
to see the rest. On the VM the turn is `Timer.run`, which a fake clock does drive.

## More

- Decisions, what was measured and what was not:
  [docs/database_decisions.md](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/database_decisions.md).
- [17 programs in example/](example/README.md), one per topic, and the complete apps `examples/rtdb_cli`,
  `examples/rtdb_server_shelf`, `examples/rtdb_presence_worker`, `examples/rtdb_web_app` and
  `examples/rtdb_playground` in the repository.
- The Storage client, laid out the same way:
  [firebase_storage_dart](../../firebase_storage/firebase_storage_dart/README.md).

## License

Apache License 2.0, as the rest of the repository.
