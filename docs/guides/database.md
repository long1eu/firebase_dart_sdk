# Realtime Database

The Realtime Database client of this repository is three packages: `firebase_database_dart` (the client, pure Dart, the
WebSocket protocol of the Firebase JS SDK), `firebase_database_dart_sqlite` (a disk cache for the Dart VM) and
`firebase_database_dart_platform` (the API of the official `firebase_database` plugin on top of the client). This guide
is the entry point: which package to add, what a connection carries, rules and errors, what surprises people who know
the JS SDK or FlutterFire, offline behaviour, the connection on a desktop or a server, and tests. The [client
README](../../firebase_database/firebase_database_dart/README.md) has the install steps and one example of each call;
this guide does not repeat them. The client is at 0.0.1. It has run against the Database emulator and, once, against a
production database (the verification kit, 39 checks); where a statement below depends on the server, it says what was
measured. What has run, and what never ran against production, is in section 23 of the [decisions
document](../database_decisions.md). It includes the client's test suite on the Dart VM (2,456 tests) and in Chrome on
dart2js (2,411) and dart2wasm (2,415), the SQLite package (249 tests), the adapter (136 tests, 5 skipped without the
emulator), and example apps on Windows 11 and Linux x64 (4 integration tests each). CI runs on GitHub Actions
(`.github/workflows/ci.yml`) and passes. Not run: a release build of a desktop app, Safari, Firefox and a real display.

## Which package do I add

| You build | Add | You get | Not included |
| --- | --- | --- | --- |
| Dart server, CLI, desktop or web | `firebase_database_dart` | The whole API, memory cache | Disk |
| The same, disk cache on the VM | `firebase_database_dart_sqlite` | Writes kept, offline reads | Web |
| Flutter app on `firebase_database` | `firebase_database_dart_platform` | Official API on the client | Mobile |

The official Flutter plugin `firebase_database` declares Android, iOS, macOS, Windows and web, and no Linux. On Linux
this client, through the adapter, is the only implementation. On Windows and macOS the official plugin exists (on
Windows through the Firebase C++ SDK) and this client is an alternative written in Dart, with no native SDK in the
build. For servers and command line tools in Dart there is no official client at all.

The first has no disk cache and no long polling (networks that block the WebSocket upgrade cannot use it).
The second has no web persistence and no cache shared by two processes. The third is for desktop: on Android and
iOS the native plugin is the maintained path, and the adapter is an opt-in there.

The client depends on `firebase_app_dart` only: tokens come from the `FirebaseApp`, so it has no Auth dependency (the
[Firebase app guide](firebase_app.md) and the [authentication guide](authentication.md) cover the app and the
providers). The adapter's README has the registration details and the options of `FirebaseDatabaseDart.use`.

## How a connection is made and what it carries

A `FirebaseDatabase` is one WebSocket to one database. There is no instance cache: two instances on one URL are two
connections, and every setting is a constructor argument. A new instance opens no connection: the first read, listener
(`.info/connected` included), write, transaction, `onDisconnect` call or `keepSynced(true)`, or `goOnline()`, does, so a
database that is created and closed without use opens no socket. The URL is the `databaseURL` of the app's options, else
`https://<projectId>-default-rtdb.firebaseio.com`; another region or a second database needs its own `databaseUrl`. The
constructor refuses, with an `ArgumentError` before any connection, a URL with a path, a custom domain without `?ns=`, a
port other than 443 on a host that is not loopback, an invalid project id, and plain `http://` outside the emulator; a
start that fails fails every pending and later call. `refFromUrl` refuses user info, plain http, other ports and extra
query keys. The disk cache is keyed by the app name and the normalised database URL: every spelling of one URL shares
one cache, and two `?ns=` values on one host are two caches.

After the hello of the server, the client sends the credentials and then the listens and writes, without waiting for
the answers:

- The ID token of `app.authProvider` goes in an `auth` request (`gauth` when the token is not a JWT with an `iat`
  claim). The App Check token of `app.appCheckProvider` goes in an `appcheck` request. The providers are read when the
  `FirebaseDatabase` is constructed, so sign in or set them first. With no provider the connection has no user, which
  is what open rules and the emulator need.
- On the Dart VM the App Check token and the app id also travel in the headers of the upgrade request
  (`X-Firebase-AppCheck`, `X-Firebase-GMPID`). A browser socket cannot set headers, so on the web they are the `ac` and
  `p` query parameters of the WebSocket URL, visible in the network panel. The ID token is never in a URL, on either.
- Tokens go only over TLS or to the exact `host:port` given as `emulatorHost`. A plain-text `databaseUrl` is refused
  outside the emulator (the message says to use an https URL or `emulatorHost`), so a real token cannot go over plain
  text. The server may
  name another host in its hello or in a reset; the client follows it only if it is on `firebaseio.com` or
  `firebasedatabase.app` (or the configured host).

A token change reaches the server on the live socket, without a reconnect: a new token is a new `auth` request, a
sign-out is `unauth`, and a token that changes while the connection is down is used by the next connection. A change
event of the app's auth provider is a signal: the client fetches the token from the provider, and an empty token means
signed out. The FlutterFire adapter never forwards a placeholder as a token. When the
server refuses a token or revokes it later, the client closes the connection and reconnects with a refreshed token, at
most one forced refresh per provider per 60 s. The error you see is the `permission-denied` of the operation that the
server refused; there is no code for tokens.

## Rules and errors

The security rules run on the server. What a refusal looks like depends on what you were doing:

- **A write** is rolled back locally, with events, and its Future fails with `permission-denied`.
- **A listen** that the rules refuse ends its stream with a `FirebaseDatabaseException` (`permission-denied`), then
  done. The same happens when the rules revoke a listen later, for example after a rules change: the stream ends with
  the error, and the app listens again once it can read. A server cancel applies to every listen at that path.
  Losing the connection is never a stream error.
- **A `get()`** fails with `permission-denied` and never falls back to the cache, so a rules change cannot hide behind
  old data.

```dart
import 'package:firebase_database_dart/firebase_database_dart.dart';

ref.child('private').onValue.listen(
  (DatabaseEvent event) => print(event.snapshot.value),
  onError: (Object error) {
    if (error is FirebaseDatabaseException && error.code == 'permission-denied') {
      print('the rules refused or revoked this listen; the stream has ended');
    }
  },
);
try {
  await ref.child('private/note').set('hello');
} on FirebaseDatabaseException catch (e) {
  print('write refused: ${e.code} (${e.serverStatus})');
}
```

`index-not-defined` is about queries. A query with a range or a limit needs an `.indexOn` rule for its order at that
location. A `get()` of such a query is sent with its index and fails with `index-not-defined` where the rules have none.
A `get()` that only orders (`orderByChild('score').get()`, no range, no limit) is sent as the default query and ordered
in the client, so it needs no index. A listener or `once()` never fails for a missing index: the client downloads the
location, filters it itself and logs a `no_index` warning to the `logger`. In production add the index, or the filter
downloads more than you asked for.

The codes are listed in the [README](../../firebase_database/firebase_database_dart/README.md#errors) and in the
documentation of `FirebaseDatabaseException`. A bad path, key, value or query is an `ArgumentError` or `StateError` at
the call, before anything is sent, not an exception through a Future. One limit only the emulator has: in one `set`,
a value whose longest chain of keys together with the path is longer than 768 bytes is refused there with `unknown`
(`invalid_parameters` in `serverStatus`), while a flat multi-path `update` is checked path by path. The production
server accepted the same `set` (measured once on each).

## What surprises people from the JS SDK or FlutterFire

- **Events are never delivered inside the call that caused them.** A local write queues its events before its Future
  completes, and they are delivered from one queue per database, in a microtask. A listener that writes does not run
  nested. Do not expect a listener to have run when `set()` returns; await a stream event instead.
- **Snapshot values are unmodifiable.** `snapshot.value` is built once and shared; changing it throws
  `UnsupportedError`. Copy it (`Map.of`, `List.of`) before you edit. A transaction handler gets a fresh mutable copy.
- **Writes are delivered at least once.** A put whose answer was lost is sent again after the reconnect, and with a
  persistent cache also after a restart. The protocol has no idempotency key, and the official SDKs behave the same. A
  repeated `set` changes nothing, but a repeated `ServerValue.increment` adds twice. Count with a transaction when the
  number must be exact.
- **`get()` offline waits 3 s, then answers from the cache (only when it holds the complete value for that query, limit
  applied; a cached empty location answers null) or fails with `unavailable`.** The JS SDK queues the request with no
  limit. After `goOffline()` there is no wait. The 3 s is not configurable; use `.timeout()` for another bound. A `get`
  that fails or is answered offline does not leave its query marked active.
- **Numbers.** An `int` stays an `int`. An integral value within 2^53 reads back as an `int` even if you wrote `5.0`,
  and anything else is a `double`; read numbers as `num`. On the web, integers beyond 2^53 lose precision. Keys that
  look like integers sort first, numerically, as the server orders them; other keys sort by UTF-16 code unit. A map
  whose keys are `0..n` with more than half present reads as a `List`, so iterate `snapshot.children` when the shape
  can vary. `snapshot.children` follows the query's order; the `Map` in `snapshot.value` does not.
- **`onDisconnect` requests whose connection drops.** The server forgets the registrations of a connection when it
  ends. A request that was sent, and whose connection drops before the answer, completes with `disconnected` and is not
  sent again; only requests queued while offline are sent after the next connect. Register again whenever
  `onConnected` says true, and do not expect a registration to survive a restart.
- **Transactions run their handler more than once**, up to 25 times, then fail with `max-retries`. The first run
  happens synchronously inside `runTransaction`, as in the JS SDK, and often sees `null`, because the client has no data
  yet; its events are still queued and never delivered inside the call, and the handler returns a `Transaction`, not a
  Future. A transaction that was sent and loses its connection before the answer is not run again: its local write is
  rolled back and it fails with `disconnected`. They are never persisted.

The full list is the table in [section 25 of the decisions document](../database_decisions.md), with the test that pins
each row and the reason.

## Offline behaviour and the cache

Without `firebase_database_dart_sqlite` nothing is written to disk. Listened data is cached in memory while a listener
exists, pending writes are in memory, and a program that quits loses its pending writes.
A listener gets its data again after a reconnect.

With `sqlitePersistence(directory)` the client stores each write when you make it and removes it in one SQLite
transaction when the server acknowledges it, so pending writes are sent again after a restart. It also keeps server
data of the queries you listened to, which answers listeners and `get()` while offline (only data under a listener or
`keepSynced` is written to disk), and prunes the least recently
used queries above `cacheSizeBytes` (1 MiB to 100 MiB, 10 MiB by default). Queries with a listener and pending writes
are never pruned. `cacheServerData: false` stores pending writes only: after a restart a listener waits for the
server. Transactions and `onDisconnect` registrations are not stored in any mode.

The cache belongs to the app and the database URL, not to a user. On a shared machine call `clearSqlitePersistence`
at sign-out, or the next user can read the previous user's cached data from the file (which is clear text).

**One owner per cache file.** The owner holds a lease row and refreshes it every 5 s. A second process or isolate on
the same file watches the lease for about 7.5 s, then runs memory-only with one logged warning;
`FirebaseDatabase.persistenceEnabled` is `false` for it and its writes are not durable. Check that flag if two copies of
your app can run, or a command line tool shares the directory.

**A storage error never deletes pending writes.** The failed transaction rolls back, the instance stops writing and
reads as empty for the rest of the session, and the file keeps what was committed before the error. A write made after
the error is not durable. The app never receives a `SqliteException`; a row that does not decode is skipped and logged
once. A file that cannot be trusted (damaged, foreign, or of a newer major version) is renamed aside and an empty cache
starts.

**The engine runs on the calling isolate**, which is the UI isolate in Flutter. Measured on one Mac (these are one
machine's numbers: macOS, AOT, medians of 5, rows of about 100 bytes): a point read takes 0.1 to 0.2 ms and one
pending write 0.1 ms, whatever the size of the cache. Loading a whole subtree takes 56.2 ms for 1 MB, 615.2 ms for
10 MB and 2,968.3 ms for 50 MB; writing it takes 51.9, 483.8 and 2,123.7 ms; reopening the file takes 3.4, 12.7 and
55.5 ms. macOS `fsync` does not force the drive cache, so the write cost on Linux and Windows is not measured. A
listener loads the subtree below its path, so listen below the root of a large cache, or loading 50 MB at the root
takes about 3 s on the calling isolate.

```dart
import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:firebase_database_dart_sqlite/firebase_database_dart_sqlite.dart';

final FirebaseDatabase cached = FirebaseDatabase(
  app,
  persistence: sqlitePersistence('/var/lib/my-app/rtdb', cacheSizeBytes: 50 * 1024 * 1024),
);
final DatabaseReference notes = cached.ref('users/ada/notes');
notes.onValue.listen((DatabaseEvent event) => print(event.snapshot.children.length));
print('durable: ${cached.persistenceEnabled}');
await cached.close();
```

## The connection on a desktop or a server

`database.onConnected` is `.info/connected`. Its first event is the current state, and it is `false` until the first
connection is up. `isConnected`, `serverTimeOffset` and `estimatedServerTime` are plain getters.

`goOffline()` and `goOnline()` are synchronous. Offline, listeners keep their data and writes wait in a queue that
`goOnline()` sends in order. `purgeOutstandingWrites()` rolls back every pending write and fails their Futures with
`write-canceled`, aborts transactions and completes the `onDisconnect` operations still queued locally with
`write-canceled`, as Android's does. An `onDisconnect` operation the server has registered is not undone by it, and
neither is a transaction the server has already accepted.

**Reconnecting.** After a failure the client waits a random time between zero and a delay that starts at 1 s and grows
by a factor of 1.3 per failure to a cap of 30 s (the JS SDK caps at 5 minutes). The delay goes back to 1 s after a
connection that stayed healthy for 30 s. When the app reports connectivity (`app.onNetworkConnected` going to `true`),
the delay is reset and the client reconnects at once. The default app is always connected and reports nothing; a
desktop or Flutter app that wants this signal supplies it through its `PlatformDependencies`
(see the [Firebase app guide](firebase_app.md)). A message from the server that the client cannot accept (malformed, a
non-finite number, an invalid key in an answer it must check, or an `ok` answer whose data is refused) closes the
connection, logs once, and reconnects with the delay raised to its cap. JSON deeper than 64 levels is refused by a scan
before decoding, which leaves 61 levels of data.

**The idle probe.** The client never closes an idle connection by itself. When no frame has arrived for 30 s it sends a
protocol ping, and if nothing arrives within 15 s more it closes the connection and reconnects. A request that waits for
an answer while the link is silent for 60 s also closes it; writes are never failed by that, they are sent again.

**After a laptop wakes**, a socket that died during sleep gives no signal of its own. Computed from the timing
constants, not measured: the probe closes it after 30 s of silence plus 15 s for the ping, then the first retry waits
about 1 s, so usually about 46 s plus the connect. At worst it is about 75 s plus the connect, when the connection had
not been healthy for 30 s and the backoff was up to 30 s. When the app signals connectivity it is immediate. The three
timeouts (30 s, 15 s, 60 s) are chosen, not measured against production.

**The TLS handshake.** `dart:io` cannot close a connection attempt that is stuck inside the handshake. The client gives
up on it after its 30 s connect timeout and tries again, but the socket stays until the peer or the system ends it.

**Proxies.** On the Dart VM a secure connection honours `HTTPS_PROXY` and `NO_PROXY` (and the lower-case forms), as
Dart's `HttpClient` does. Loopback addresses and the emulator are always reached directly, and there is no option in the
API. A proxy that refuses the tunnel fails the connection attempt with an error that names the proxy and the status.

**Shutting down.** An open `FirebaseDatabase` keeps a command line program alive. `close()` ends every stream with
`database-closed`, fails the Futures of writes that are still pending with `database-closed`, releases the cache lease
and closes the socket; the server then runs the `onDisconnect` operations you registered. Await your writes before
`close()` in a server that handles `SIGTERM`; with no SQLite cache an unacknowledged write is lost.

```dart
import 'dart:io';

import 'package:firebase_database_dart/firebase_database_dart.dart';

database.onConnected.listen((bool connected) => print('connected: $connected'));
ProcessSignal.sigterm.watch().first.then((ProcessSignal _) async {
  await database.close();
  exit(0);
});
```

`ProcessSignal.sigterm` is not available on Windows; use `sigint` there.

## Testing your own code

**The emulator.** `tool/start_database_emulator.sh [port]` starts a private Realtime Database emulator (it needs Java
and the Firebase CLI, see [tool/README.md](../../tool/README.md)) on `127.0.0.1:9100` for the project `demo-test`;
`tool/stop_database_emulator.sh [port]` stops only the one it started. The default is 9100 because 9000 is the port of
the CLI's own emulator: the script refuses that one and the other shared defaults (8080, 8181, 9099, 9199, 4400 and
4500), so a private emulator never meets a shared one. Pass `emulatorHost: '127.0.0.1:9100'` (or
`FirebaseDatabase.emulatorHostFromEnvironment`, which reads `FIREBASE_DATABASE_EMULATOR_HOST` only when you ask for it).

Facts measured on the emulator (v4.11.2): the rules file you give it (`DATABASE_RULES=<file>`) applies only to
`<projectId>-default-rtdb`, and every other namespace starts with open rules; namespaces never see each other's data, so
a database URL with `?ns=<name>` per test isolates tests without a restart. The emulator never enforces token expiry
and never revokes a token, so token refresh cannot be tested there.

**A mock user, and the admin trap.** `mockUserTokenFor` builds an unsigned token that the emulator reads as a signed-in
user, so the rules run for that user:

```dart
import 'package:firebase_database_dart/firebase_database_dart.dart';

final FirebaseDatabase asAda = FirebaseDatabase(
  app,
  emulatorHost: '127.0.0.1:9100',
  mockUserToken: mockUserTokenFor('ada', projectId: 'demo-test', claims: <String, Object?>{'role': 'editor'}),
);
await asAda.ref('private/ada').set('hello');
await asAda.close();
```

Do not pass a plain string as `mockUserToken`. The emulator treats a string that is not a JWT, the literal `'owner'`
included, as an admin credential, and the rules are bypassed, so a test that expects `permission-denied` passes
silently with the wrong result. A bearer header or an `access_token` is an administrator on the emulator too, which is
why the ID token goes in the `auth` request. `mockUserToken` without an `emulatorHost` is refused.

**Without a network.** `package:firebase_database_dart/testing.dart` has `FakeDatabaseServer`, a scripted server at the
connection seam, `databaseWithFakeServer(app, server)` and `fakePersistence()`. The test answers what the client asks:
`answerListen`, `failListen`, `cancelListen`, `push`, and `dropConnection` to test your reconnect handling. The server
records `requests` (for example `'q /a'` for a listen) and the tokens it received. Time is controlled with
`package:fake_async`, because the first connection is made in a timer after the database's first operation (or
`goOnline`), not when it is created. Events are delivered in batches of 1,000 with a turn of the event loop between
them; in a browser that turn is a message task that a fake clock does not drive, so a test that queues more than 1,000
events at once needs a real `await` to see the rest. It has no stability promise beyond the
contract tests of the package. Tests of the rules themselves are better run against the emulator with the Firebase rules
unit-testing library.

## Where to read more

- The three READMEs: [`firebase_database_dart`](../../firebase_database/firebase_database_dart/README.md),
  [`firebase_database_dart_sqlite`](../../firebase_database/firebase_database_dart_sqlite/README.md) and
  [`firebase_database_dart_platform`](../../firebase_database/firebase_database_dart_platform/README.md).
- [docs/database_decisions.md](../database_decisions.md): 26 sections of decisions with the reason for each, what was
  measured on the emulator and on production, and the table of deliberate differences from the JS SDK (section 25).
- Programs: [`example/`](../../firebase_database/firebase_database_dart/example/README.md) (one per topic, against the
  emulator) and the apps `examples/rtdb_cli`, `examples/rtdb_server_shelf`, `examples/rtdb_presence_worker`,
  `examples/rtdb_web_app` and `examples/rtdb_playground`.
- [docs/database_benchmarks.md](../database_benchmarks.md): the benchmark report, which a corrected run is replacing.
  The cache numbers above come from a separate load measurement,
  `firebase_database/firebase_database_dart_sqlite/tool/bench_load.dart`.
