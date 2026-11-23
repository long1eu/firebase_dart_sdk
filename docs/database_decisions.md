# Realtime Database decisions

The decisions behind `firebase_database_dart` (`firebase_database/firebase_database_dart`), its SQLite cache
(`firebase_database_dart_sqlite`) and its FlutterFire adapter (`firebase_database_dart_platform`): what was
decided, why, what it costs, and where to check it. The code is built; each section says what it does. Where a
review or a measurement changed an earlier plan, the section states the rule that holds now. Every section
ends with a status line:

- **built**: the code does this and tests pin it, on the VM, in the browser, or both (section 23 says what has
  run where);
- **measured on the emulator (v4.11.2)**: observed on the Firebase Database emulator
  (`firebase-database-emulator-v4.11.2.jar`, firebase-tools 15.18.0); production was not measured;
- **not measured**: a number or a behaviour that no run has settled yet.

Nothing here was run against a production project. [storage_decisions.md](storage_decisions.md) is the model
of this document; [contributing_a_product.md](contributing_a_product.md) has the rules every product client
follows. "Pinned by" names the test files that pin each decision. Test paths are relative to
`firebase_database/firebase_database_dart` unless they start with `docs/`, `tool/`, `.github/` or a package
name.

Path shorthand for upstream code, read at these commits on 2026-11-22:

| Short | Meaning |
|---|---|
| `J:` | JS `firebase-js-sdk/packages/database/src/` at `a086865` |
| `A:` | Android `firebase-database/src/main/java/com/google/firebase/database/` at `2cfdd03` |
| `JT:` | JS `firebase-js-sdk/packages/database/test/` |
| `I:` | iOS `firebase-ios-sdk/FirebaseDatabase/Sources/` at `cef246f` |
| `IH:` | iOS public headers, `I:Public/FirebaseDatabase/` |
| `Cd:` | C++ `firebase-cpp-sdk/database/src/desktop/` at `09d2e7a` |
| `F:` | `cloud_firestore/cloud_firestore_dart/lib/src/firebase/firestore/local/sqlite/` of this repository |

## 1. An idiomatic Dart client first

**Decision.** The client is a Dart library, not a port of any one SDK's API. Configuration is immutable and goes to the
constructor: `FirebaseDatabase(app, databaseUrl:, emulatorHost:, mockUserToken:, persistence:, logger:)`, plus a clock
and a random source that are for tests only (`@visibleForTesting`); there is no `delay` parameter. There are no setters
and no instance cache: two instances on one URL are two connections. `close()` is idempotent; afterwards anything
asynchronous fails with the code `database-closed`, and `ref()` still works because it does no I/O. Construction opens
no socket (section 14); persistence, when given, opens at construction. FlutterFire's shape
(`FirebaseDatabase.instance`, `setPersistenceEnabled`, `setLoggingEnabled`) lives in `firebase_database_dart_platform`,
which maps onto the client (section 22).

**Why.** The same split exists for Firestore and Storage. Android and iOS need setters that throw once the
instance is in use (`A:FirebaseDatabase.java:284,302,330-338`; `I:Api/FIRDatabase.m:215-248`), and JS fails
when `connectDatabaseEmulator` runs after the instance started (`J:api/Database.ts:350-400`). A constructor
makes the wrong order impossible. Firestore fails pending work after `terminate()` and Storage throws a
`StateError`; failing through the Future or Stream with a product code is the Firestore rule, and the write
Futures of a closed database fail instead of hanging.

**What we gave up.** A program written for `firebase_database` does not compile against the client; it needs
the adapter. The adapter has to hold the settings that FlutterFire allows before first use (section 22).

**Pinned by.** `test/api/public_surface_test.dart` (the constructor's parameters, `database-closed`);
`test/api/scenarios_test.dart` (pending operations fail with `database-closed` after `close()`);
`docs/contributing_a_product.md`, design rules 1 and 4.

Status: built.

## 2. The JS SDK is the reference; Android and iOS fill the gaps

**Decision.** The client ports the behaviour of the JS SDK (WebSocket protocol version 5) and uses Android and
iOS where JS has nothing (disk persistence) or does something odd. It is written from scratch in this
repository. It does not build on the existing pure-Dart `firebase_database` implementation (`firebase_dart`
2.0.0-dev.9).

**Why.** One reference, and its tests to port, as for Auth and Storage. The JS core is about 21,400 lines
without tests (`docs/spikes/realtime_database_scope.md`). The hardest part, the layer that applies local
writes on top of server data and raises events, comes with an oracle in every SDK: a data file of sync-point
specifications that needs no database (112 specs in `JT:test/helpers/syncPointSpec.json`; Android and iOS ship
the same file with 108 specs, 8,203 lines). The existing Dart package brings its own Auth and a set of
dependencies (Hive, rxdart, quiver and more), which this repository's packages avoid.

**What we gave up.** Upstream releases have to be followed by hand. The code is new and has no production
history.

**Pinned by.** `test/spec/sync_point_spec_test.dart` (the specification file, run through
`test/spec/sync_point_spec_runner.dart`); `test/conformance/` and `test/core/` (ports of the upstream unit
tests of the data layer and the sync tree); `test/oracle/` (Android's persistence suites).

Status: built.

## 3. Where the SDKs differ on the wire, what we chose

**Decision.** Where JS and Android disagree, the client takes the behaviour that suits a desktop client:

- **Reconnect.** Delay starts at 1 s, grows by 1.3 per failure to a cap of **30 s**, with JS's full jitter (a
  random value in `[0, delay]`); it resets after a connection that stayed healthy for 30 s and on a network
  change hint. JS caps at 5 minutes and resets only on browser events
  (`J:core/PersistentConnection.ts:45-49,742-770,785-817`); Android caps at 30 s with a different jitter
  (`A:connection/util/RetryHelper.java:121-124`, `A:connection/PersistentConnectionImpl.java:344-350`).
- **Auth before listens.** `auth`, `appcheck`, the listens and the puts go out back to back, as JS does
  (`J:core/PersistentConnection.ts:1035-1069`); Android waits for the `auth` answer first
  (`A:connection/PersistentConnectionImpl.java:1034-1088`).
- **Idle disconnect.** None. Android closes after 60 s without work
  (`A:connection/PersistentConnectionImpl.java:277,1435-1476`); it changes what `.info/connected` means.
- **Paths** in requests are `/a/b`, as JS; Android sends `a/b`.
- **Hash on listen.** The simple hash `h`, and, as Android and iOS do, a compound hash `ch` when the cached
  data of the query is estimated above 1,024 bytes (`sizeThresholdForCompoundHash` in `lib/src/core/sync_tree.dart`),
  and `rm` range merges are applied (`A:core/SyncTree.java:82,100-140`;
  `A:connection/PersistentConnectionImpl.java:947-967`); JS sends the simple hash only
  (`J:core/PersistentConnection.ts:289`). The emulator has not been shown to accept a two-range hash of ours
  (section 19).
- **Clearing App Check** sends `unappcheck` to the emulator, which knows only that spelling, and `unappeck`,
  the JS spelling (`J:core/PersistentConnection.ts:371`), to a production host
  (`lib/src/realtime/connection_timings.dart`, `unappCheck`). Production's answer to `unappeck` is not
  measured.
- **A server `c` (listen cancelled)** cancels every listen at that path, which is safe whichever query it
  names.
- **A control message `e`** is logged and ignored; it has no request id, so the request it refers to is
  answered only by the link-silence rule (section 14).
- **A server shutdown** ends reconnecting, as in JS and Android
  (`A:connection/PersistentConnectionImpl.java:539-555`).
- **App id and App Check token** go in upgrade headers on the VM (Android,
  `A:connection/WebsocketConnection.java:188-191`) and in the URL on the web, where a socket has no headers
  (JS, `J:realtime/WebSocketConnection.ts:140-141`).
- **Statistics (`s`)** are not sent.

**Why.** The first connection of a desktop client often happens right after a wake, and a 5 minute cap or an
unreset delay leaves the app offline for minutes. The emulator probe settled several points: it processes
requests strictly in order, so pipelining after `auth` is safe (an unauth sent in the same burst cancelled the
next listen and denied the next read, in order); it accepts `unappcheck` and rejects `unappeck` with an `e`
control message; it ignores the app id and App Check token in both forms; and a session that never sends `s`
reads and writes normally.

**What we gave up.** If a server does not accept our compound hash, a large cache is re-sent in full after each
reconnect, as in JS. Production was not measured for the `unappeck` spelling, for the compound hash or for
pipelining.

**Pinned by.** `test/realtime/reconnect_backoff_test.dart` (delay sequence with injected random and clock);
`test/realtime/replay_test.dart` and `test/realtime/persistent_connection_test.dart` (replay order, request
bodies including `ch`); `test/realtime/auth_session_test.dart` (the App Check removal action);
`test/integration/connection_emulator_test.dart` (pipelined auth).

Status: built; measured on the emulator (v4.11.2) for the accepted spellings, ordering and ignored headers;
production not measured.

## 4. Tokens from the app, and where they may go

**Decision.** The ID token comes from `app.authProvider` and the App Check token from `app.appCheckProvider`;
the package does not depend on the Auth package. Tokens are sent only over TLS, to the exact `host:port` given
as `emulatorHost`. A `databaseUrl` must be `https://` (or `wss://`); plain text is refused outside the emulator, and
the message says to use an https URL or the `emulatorHost` argument.
The environment variable `FIREBASE_DATABASE_EMULATOR_HOST` is
read only by the explicit helper `FirebaseDatabase.emulatorHostFromEnvironment`, never by default.
`mockUserToken` without an emulator is refused. A plain-text target that is not the emulator is refused too:
`RealtimeTarget` throws `ArgumentError` for it (`lib/src/realtime/realtime_target.dart`), and the connection
checks `mayReceiveTokens` again before it hands over a token, so a token never goes over plain text. A token
is refreshed on the live connection (a new `auth` request, no reconnect; `unauth` after a sign-out); a token
that arrives while the connection is down is used on the next one. A change event of the provider
(`onTokenChanged`) is a signal, not a carrier: the connection fetches the token from the provider
(`forceRefresh: false`), and an empty token in the event means signed out. The adapter never forwards a placeholder
as a token (section 22). Token changes are versioned: a token
fetched for a connection attempt is dropped when the token changed during the fetch, so a sign-out during a
fetch wins. The fetch is bounded by the connect timeout and counts as a failed attempt when it runs over.

**Mock tokens.** `mockUserToken` is sent to the emulator as given. A string that is not a JWT, the literal
`'owner'` included, is an admin credential on the emulator (`gauth`) and bypasses the rules.
`mockUserTokenFor(uid, projectId:, claims:)` builds the unsigned user token the emulator reads as a signed-in
user (`lib/src/api/mock_user_token.dart`).

**Why.** JS gives the scheme to the port: `http://x.firebaseio.com:443` sets `secure = false`, so a real ID
token would go over `ws://` (`J:core/util/libs/parser.ts:121-124,153-157`; `J:api/Database.ts:154`), and
`connectDatabaseEmulator` uses `ws://` to any host (`J:api/Database.ts:94-107`). Storage's rule applies word
for word (`docs/storage_decisions.md`, section 3). On the emulator, a bearer header or an `access_token` is a
service account and bypasses the rules, so the ID token of a signed-in user goes in the `auth` action (or
`auth=` on REST), never in a bearer header, if rules are to be exercised.

**What we gave up.** A database reached over plain `ws://` through a name other than the configured emulator
cannot be used.

**Pinned by.** `test/security/hosts_test.dart` (group "token scope": URLs `http://x.firebaseio.com:443`,
`http://x.firebaseio.com`, `ws://...` are refused; an emulator on a non-loopback host gets the tokens;
`127.0.0.1.evil.example` and another port of the emulator host get nothing); `test/realtime/realtime_target_test.dart`
(the `ArgumentError`); `test/realtime/persistent_connection_review_test.dart` (the `RealtimeTarget` refusal under the
name "no token can reach a plain-text WebSocket", and a sign-out during a fetch; the second `mayReceiveTokens` check
in `PersistentConnection` has no test that fails without it); `test/realtime/auth_session_test.dart`;
`test/realtime/persistent_connection_auth_change_test.dart` (the event as a signal, the fetch, the empty token);
`test/realtime/emulator_token_test.dart` (the mock token and the admin credential).

Status: built. Emulator behaviour for credentials measured on the emulator (v4.11.2): `auth` needs `sub` and
`iat`, ignores `exp`, and `gauth` and bearer tokens are administrators.

## 5. Server-chosen hosts, redirects and URLs

**Decision.** Everything the server or the caller can say about a host is checked:

- A host in the server's hello (`h`) or reset (`r`) is accepted only if it is a bare lowercase DNS name
  (letters, digits, `-` and `.`, at most 253 characters, no port, user info, path, query or fragment) and it
  equals the configured host or ends in `.firebaseio.com` or `.firebasedatabase.app` on a label boundary.
  Otherwise it is ignored and a line is logged without the value. With an emulator, `h` and `r` never change
  the host. A reset counts as a failed attempt, and at most three are followed within one attempt. The cached
  host lives in memory only.
- The upgrade to a WebSocket is done by the client with `followRedirects = false`; any answer other than 101
  is a failed attempt. Compression is off (`CompressionOptions.compressionOff`). A URL never carries user
  info.
- A database URL is parsed with `Uri.parse`. The rules below are written and tested in `parseDatabaseUrl`
  (`lib/src/realtime/database_url.dart`). The `FirebaseDatabase` constructor refuses, with an `ArgumentError` before
  any connection, a database URL with a path, a custom domain without `?ns=`, a port other than 443 on a host that is
  not loopback, and an invalid project id; a failed start fails every pending and later call instead of hanging. A URL
  is refused with user info, a fragment, a query
  key other than `ns`, a non-root path, an empty host, an IP literal other than loopback, or a port other than 443 on a
  production host. The namespace is `ns`, else the first label of a `firebaseio.com` or `firebasedatabase.app` host, and
  must match `^[a-z0-9-]{1,63}$`. Every query value is percent-encoded. `refFromUrl` puts the URL without its path
  through the same parser, so it refuses user info, plain `http://`, other ports and extra query keys, and it refuses
  a host other than the database's own.
- The disk cache is keyed by the app name and the normalised database URL: every spelling of one URL shares one cache,
  two `?ns=` values on one host are two caches, and one emulator named by two hosts (`localhost` and `127.0.0.1`) has
  two.
- On the Dart VM a secure connection honours `HTTPS_PROXY` and `NO_PROXY` (and the lower-case forms) through
  `HttpClient.findProxyFromEnvironment`, with the upgrade and every frame inside the TLS of a `CONNECT` tunnel
  (`lib/src/realtime/transport/ws_channel_io.dart`). A loopback target and the emulator (plain `ws`) are always
  direct, so a proxy never reads plain-text frames. There is no API option for proxies, and the web build uses the
  browser's own settings.

**Why.** JS stores the server's host without a check (`J:realtime/Connection.ts:391-393,440-451`), writes
hosts that start with `s-` into `localStorage` and reads them back (`J:core/RepoInfo.ts:58-59,77-83`), and
builds the URL by concatenation (`J:core/RepoInfo.ts:128-129`): `s-x.firebaseio.com@evil.example` passes the
prefix test and sends the App Check token in the URL of the next connection. A reset loop reconnects at once
with no counter (`J:realtime/Connection.ts:445-451`). The hand-written URL parser lets
`https://localhost:x@evil.example/` through and writes the decoded `ns` back unencoded, so `?ns=a%26ac%3Dx`
injects a parameter (`J:core/util/libs/parser.ts: 104-191`, `J:core/RepoInfo.ts:144-146`). `dart:io`'s
`WebSocket.connect` leaves `followRedirects` at its default and negotiates compression
(`dart:_http/websocket_impl.dart:1065,1092-1099`, Dart SDK 3.11.5).

**What we gave up.** A custom domain whose server host is not on a Google suffix works only when it equals the
configured host; the host a custom domain receives in its hello has not been seen.

**Pinned by.** `test/security/hosts_test.dart` and `test/security/c_hosts_test.dart` (group "server host":
hellos and resets naming `evil.example`, `s-x.firebaseio.com@evil.example`, `s-x.firebaseio.com:444`, a path, a
fragment, a longer suffix; "the emulator ignores h and r"); `test/security/t_hosts_test.dart`;
`test/realtime/ws_channel_io_test.dart` (a 3xx answer to the upgrade is a failure);
`test/security/url_test.dart` and `test/realtime/database_url_test.dart` (accepted and refused URLs);
`test/security/c_limits_test.dart` (the reset loop); `test/realtime/ws_channel_io_test.dart` (group "through an HTTP
proxy from the environment"); `test/api/api_behaviour_test.dart` (the cache key of every spelling of one URL, and of
two namespaces on one host).

Status: built. The emulator sends the Host header as `h` and never redirects (measured on the emulator,
v4.11.2); real hosts for `firebaseio.com`, a regional database and a custom domain are not measured.

## 6. Everything from the server is bounded and validated

**Decision.** A server message is decoded into typed records; an unknown shape closes the connection and backs
off, and is never thrown into the application's zone. Specifically:

- a frame count is `^[1-9][0-9]{0,5}$` and is read only when no message is being assembled; bytes are counted
  as frames arrive, and a message past `maxMessageBytes` closes the connection before it is joined;
- JSON nested deeper than 64 levels is refused by the frame scan before decoding (`checkJsonDepth` in
  `lib/src/realtime/framing.dart`, `ConnectionTimings.maxJsonDepth`), which leaves 61 levels of data inside the
  three levels of a response envelope. That scan is the only depth check on incoming data: a rule of "32 levels plus
  the path" is not enforced anywhere, and data up to that bound reaches the decoder;
- server paths follow the rules for writes (no `. # $ [ ]`, no control characters, at most 768 UTF-8 bytes and 32
  segments, and none starting with `.`); a server `.sv` is refused; numbers must be finite; `r` and `t` must be
  integers; responses to unknown request ids are ignored. An envelope, a hello, a shutdown and a framing error close the
  connection; so does a malformed push, answer or revoke, a non-finite number, and an `ok` answer whose data is refused
  (an invalid key in the data of a `get` answer, a non-finite number or an oversized string in any answer): the
  connection logs it once and raises the reconnect delay to its cap (`test/security/p_server_input_test.dart`);
- server data is written to the disk cache only under a listen or `keepSynced`
  (`test/core/cache_server_push_test.dart`);
- the delay of a reconnect resets only after the connection was healthy and the server answered a request with
  `ok`;
- at most one forced token refresh per provider per 60 s, so a server that keeps revoking cannot spend the
  user's token quota.

**Why.** JS takes any frame of up to six characters whose `Number()` is not NaN as a count, so a count of `0`
or `-1` makes every later frame buffer forever, with no size limit
(`J:realtime/WebSocketConnection.ts:292-329`); Android ignores counts of 0 or less
(`A:connection/WebsocketConnection.java:283-293`). JS validates only what it sends
(`J:core/util/validation.ts:45-56`), parses recursively with no depth check
(`J:core/snap/nodeFromJSON.ts:40-120`), and throws a string out of the socket handler on an `error` message
(`J:core/PersistentConnection.ts:652-653`). Android writes every server update to its disk cache, listened or
not (`A:core/SyncTree.java:300-323`; `A:core/persistence/DefaultPersistenceManager.java:176-190`). JS and
Android force-refresh tokens on every revoke (`J:core/PersistentConnection.ts:985-1004`).

**What we gave up.** A server that sends something unexpected makes the client reconnect rather than carry on.
The default of `maxMessageBytes` (256 MiB, `ConnectionTimings`) is a guess to be confirmed: the emulator drops
messages above 16 MiB.

**Pinned by.** `test/security/c_limits_test.dart`, `k_limits_test.dart`, `p_limits_test.dart` and
`t_limits_test.dart` (frame counts, deep nesting, the revoke loop, a server that says hello and drops; the "hello,
then drop" delay test in `k_limits_test.dart` never marks a connection established, and no test fails when the `ok`
condition of the delay reset is deleted);
`test/security/k_server_input_test.dart` (server paths, merge keys, data keys and values, integers; it asserts the
protocol-error flag of the decoded record, so it does not show that a connection closes);
`test/realtime/server_message_test.dart` (the decoder, including a mutation sweep of field types);
`test/realtime/persistent_connection_test.dart`.

Status: built. The emulator limits (a 120 s idle timeout, 65,536 bytes per
frame, 16 MiB per message, 10 MiB per string) are measured on the emulator (v4.11.2); production limits are not
measured.

## 7. Frames are split by code point

**Decision.** The client sends a message as text frames of at most 16,384 characters, with the frame count as
its own frame first when there is more than one, as JS does (`J:realtime/WebSocketConnection.ts:44,371`), but
it never cuts inside a surrogate pair. Incoming messages are reassembled as JS does.

**Why.** JS splits by UTF-16 code unit. A WebSocket text API cannot send a lone surrogate: it sends U+FFFD,
and the emulator then stored the string corrupted (the emoji at the cut became two U+FFFD). A cut inside a
UTF-8 sequence across two text frames dropped the whole message with no answer. A cut at a code-point boundary
works. The limit of the emulator is 65,536 bytes per frame, not 16,384 units, so a 16,384 unit frame (at most
49,152 bytes) is always inside it.

**What we gave up.** A frame is occasionally one unit shorter than 16,384.

**Pinned by.** `test/realtime/framing_test.dart` (splitter and assembler, with non-BMP characters at the
boundaries); `test/integration/connection_emulator_test.dart`.

Status: built; measured on the emulator (v4.11.2) for the corruption and the limits; production not measured.

## 8. Event delivery

**Decision.** Events are delivered from one queue per database, drained in a microtask, and never inside the
call that caused them. Each `listen` on an event stream is its own registration (`Stream.multi`), with its own
initial events from the cache, including a second `listen` on the same stream object; cancelling removes it
and, when it was the last for that query, the server listen. Two streams on equal queries share one server
listen. Every event is handed to its subscriber synchronously from the top of the queue
(`MultiStreamController.addSync`), and an exception in a listener goes to that listener's zone while the queue
carries on. The rules:

1. Events of one change arrive in the upstream order: child removed, added, moved, changed, then value; within
   a type in index order.
2. Changes arrive in the order they were applied. The queue yields to the event loop after 1,000 events
   (`eventsPerDrainSlice`), never inside the events of one change, so a list never sees half a change. The yield is an
   unthrottled task: a `MessageChannel` post in a browser, which a hidden tab does not delay, and `Timer.run` on the VM.
   A burst of more than 1,000 changes in a hidden tab is therefore delivered in a bounded time (measured by another
   session in a minimised Chrome window: about 0.4 s for 20,000 local writes, against 12 s before the change). Under a
   fake clock in a browser such a burst needs a real event-loop turn to be delivered in full.
3. A local write's events are queued before its Future completes.
4. A listener's own writes go to the tail of the queue; there is no nested delivery.
5. A listener added during delivery gets the state after all applied changes; a cancel during delivery drops
   every queued event for that subscription.
6. A new listener on a location with complete cached data gets its events without a round trip; a partial
   cache raises child events but no value event.
7. A server cancel (a rules refusal) is an error followed by done; a disconnect is never a stream error.
8. Order is kept within one subscription always, and across subscriptions only while none is paused: `await
   for` pauses its subscription after every event. `Query.onChildEvents`, one stream of all four child event
   types, is the form whose order survives that.
9. `Query.once([type])` is the first event of that type, then a synchronous cancel; it may answer from the
   cache and includes pending local writes.

**Why.** JS calls listeners from inside `set`: events are queued and raised before it returns
(`J:core/Repo.ts:564-593`, `J:core/view/EventQueue.ts:62-160`), so a listener can run inside the call that
caused it. Android and iOS deliver on a callback target or queue (`A:android/AndroidEventTarget.java:20-45`;
`IH:FIRDatabase.h:171`). A plain single-subscription stream makes the most common Flutter pattern, a stream
kept in state and listened to twice, throw; a broadcast stream gives a second listener no initial value. With
ordinary `StreamController`s each subscription delivers one event per microtask and then reschedules, so two
operations' events interleave as e1, f1, e2 (`dart:async/stream_impl.dart:637-650,669-679`, Dart SDK 3.11.5);
a single queue that delivers synchronously to each subscriber removes that. Android's Kotlin extensions ended
their flow on cancel the same way (`A:Database.kt:80-82`).

**What we gave up.** Order across paused subscriptions; the rest is buffered and not dropped, so a paused
value stream holds memory. Nothing in 0.1 bounds that buffer.

**Pinned by.** `test/api/scenarios_test.dart` (the rules as scenarios, including `onChildEvents` under `await for`);
`test/core/view/event_dispatcher_test.dart` (the yield after 1,000 events) and
`test/core/view/event_generator_test.dart`; the sync-point specifications (section 2).

Status: built.

## 9. Snapshot values

**Decision.** `DataSnapshot.value` is built once per snapshot, memoised, and unmodifiable: `null`, `bool`, `int`,
`double`, `String`, `List<Object?>` and `Map<String, Object?>` at every depth, never `Map<dynamic, dynamic>`, so Dart 3
patterns work without casts. Numbers: an integral value within ±2^53 is an `int`, everything else is a `double`, and a
local optimistic value is normalised the same way before the server's echo. An `int` stays an `int`, also beyond ±2^53
on the VM and on wasm, where its ordering against other numbers is exact. Lists follow the JS rule: keys `0..n` with
more than half present read as a `List` with null holes, and `toJson()` never converts. A transaction handler receives a
fresh, mutable deep copy of the current value. Every node, child snapshots included, has a `priority`. Keys are ordered
as the server orders them (see the note below).

**Why.** JS rebuilds the value on every `val()` call (`J:api/Reference_impl.ts:461-463`;
`J:core/snap/ChildrenNode.ts:203-217`). One memoised tree costs one pass and cannot be changed by one reader
under another. The cost is that code which mutated the value it got must copy it; FlutterFire's pattern of
mutating the value inside a transaction handler is the reason the handler gets a copy. The emulator keeps
integers as 64-bit longs and fractions as doubles on the wire (`1` and `1.0` are different,
`9223372036854775807` is kept exact), and dart2js treats `5` as both `int` and `double`, so the client reads
numbers as `num` and says so in the README.

**What we gave up.** Mutating `snapshot.value` throws `UnsupportedError` at run time; the adapter returns
copies so FlutterFire code keeps working (section 22). A `Map` read at one moment can be a `List` after the
data changes.

**Key order.** Keys that look like integers sort first, numerically, as one group: the pattern is
`^-?(0*)\d{1,10}$`, so `01` and `007` count as integers for ordering, and only values in the 32-bit range are
compared as numbers (`J:core/util/util.ts:254-277,496`; `A:snapshot/ChildKey.java:71-88,115`,
`A:core/utilities/Utilities.java:152-174`). All other keys sort by UTF-16 code unit, so characters above
U+FFFF sort before U+E000 to U+FFFF. This is how the JS and Android clients compare, and it is how the
emulator orders keys, including the integer-like cases above (measured, v4.11.2; production not measured).
Only the conversion of a node to a `List` uses the strict form, without leading zeros (`^(0|[1-9]\d*)$`,
`J:core/snap/ChildrenNode.ts:194`), so `{"0":..,"01":..}` stays a map.

**Numbers.** Measured on the emulator (v4.11.2): the server keeps `1.0` as `1.0`, keeps 64-bit integers exact
(`9223372036854775807` comes back unchanged) and prints large doubles as `1.0E21`. The client reads an
integral value within ±2^53 as an `int` on every platform. On the VM, larger integers stay exact; this is
documented as not portable to dart2js clients, whose numbers lose them; the ordering of large ints is exact on
the VM and on wasm (`compareNumbers`, `lib/src/core/util/numbers.dart`). The hash treats `1` and `1.0` the
same, as JS does (`J:core/snap/LeafNode.ts:183-202`).

**Negative zero.** A `-0.0` written by the user becomes `0` before it reaches a node (`normalizeUserNumber`), so every
platform sends `0` and the local value, the server's value and the hash agree. A `-0.0` that arrives from the server is
kept as the double (`normalizeNumber`). The JS hash keeps the sign of zero (`J:core/util/util.ts:400-406`), and the web
cannot send it: `JSON.stringify(-0)` is `"0"`.

**Pinned by.** `test/api/snapshot_test.dart` (identical object on two reads, mutation throws, the list
rule); `test/core/util/key_order_test.dart` (integer-like keys including `01` and `007`, UTF-16 order);
`test/core/util/numbers_test.dart` (`-0.0`, integral doubles, ±2^53, exact comparison of large ints);
`test/core/snap/node_test.dart`; `test/integration/connection_emulator_test.dart` (numbers and key order
against the emulator).

Status: built. The wire numbers and the key order are measured on the emulator (v4.11.2); production is not
measured.

## 10. `get()`

**Decision.** `get()` answers in this order: (1) from an active listener whose view covers the query completely, with no
round trip (`J:core/Repo.ts:470`); (2) otherwise from the server, with no client timer on the age of the request while
connected (a `get` fails with `network-error` only after two connections that each ended in link silence, section 14);
(3) when not connected, wait 3 s for a connection, then answer from the cache (in memory or on disk) only when the cache
holds the complete value for that query, with its limit and range applied (a location known to be empty answers null),
else fail with `unavailable`; (4) the same from the moment a connection drops with a request out; (5) when the server
refuses, `permission-denied` and no fallback to the cache. After `goOffline()` there is no wait. A query that only
orders (no range, no limit) asks the server for the default query at its path and orders the children locally, as a
listen does, so it needs no `.indexOn` rule; a filtered or limited query is sent with its index and fails with
`index-not-defined` where the rules have none (`lib/src/core/repo_get.dart`). A successful answer is applied to the
cache and raised to other listeners before the Future completes. A `get` that fails or is answered offline does not
leave its query marked active in the cache. `get()` does not include the caller's own
unacknowledged writes unless rule 1 applied; `once()` does.

**Why.** The SDKs disagree. JS queues the request until a connection exists, with no limit
(`J:core/PersistentConnection.ts:194-223`). Android waits 3 s only when a persisted value exists and then
answers with it, also while connected and after any failure including a refusal
(`A:core/Repo.java:64,535-553`); with nothing cached the Task stays pending, although its Javadoc promises an
offline error (`A:core/Repo.java:508`; `A:connection/PersistentConnectionImpl.java:405-436`). iOS fails an
offline `get` after 3 s and falls back to the disk cache on any failure, a permission error included
(`I:Core/FPersistentConnection.m:917-933`, `I:Core/FRepo.m:544-575`). A cached answer after a refusal would
hide a rules change; a timer while connected turns a slow server into a stale answer. JS always sends the
index of an ordered `get` and the server refuses it without `.indexOn` (`J:core/Repo.ts:470`); a listen
already avoids that by asking for the default query, and `get` does the same where no filter needs the index.

**What we gave up.** Android's behaviour of answering from the cache on every failure (a deliberate
difference, `A:core/Repo.java:535-553`). The 3 s is a named constant, not configurable in 0.1; callers who
want another bound use `.timeout()`.

**Pinned by.** `test/core/repo_get_test.dart` (the rules: active view, offline with and without a cache, a drop
mid-request, a refusal with a populated cache, `goOffline` first); `test/core/get_offline_cache_test.dart` (complete
values only, and the query left inactive after an offline or refused `get`); `test/api/scenarios_test.dart` (scenarios
"get() of an ordered query asks for the default query", "of an orderByValue query", "of a limited ordered query sends
its query"); `test/realtime/persistent_connection_review_test.dart` (the `network-error` count of a `get`);
`test/integration/public_api_emulator_test.dart`.

Status: built.

## 11. Writes, validation and at-least-once delivery

**Decision.** `set(value, priority:)`, `update`, `push()` (which only makes the reference), `setPriority` and
`remove()` (a `set(null)`). A write's Future completes on the server's answer; offline it stays pending and is
not an error. Local events fire without waiting, and a rejected write rolls back with events and fails the
Future with `permission-denied`. Validation runs at the call, also in release builds, and throws
`ArgumentError` or `StateError` before anything is sent: key characters (`. # $ [ ] /` and control
characters), a key path of at most 768 UTF-8 bytes, depth at most 32, finite numbers, priority types, a string
leaf of at most 10 MiB, a non-`String` map key, and a write under `.info`. A `List` is written as a map with
index keys. **Writes are at-least-once**: a put whose answer was lost is sent again after the reconnect, and a
re-sent `ServerValue.increment` can apply twice. A transaction is the exact way to count.

**Why.** Every SDK re-sends unacknowledged puts after a reconnect and none de-duplicates, because the request
number restarts with each connection (`J:core/PersistentConnection.ts:1048-1052`;
`A:connection/PersistentConnectionImpl.java:1171-1177`; `Cd:connection/persistent_connection.cc:1044`). The
emulator confirms it: an increment was written, the socket closed before the answer was read, a new connection
sent the put again, and the value read back was 2. Android checks the key path
(`A:core/ValidationPath.java:35-36`) and iOS checks the string size and depth 1000
(`I:Constants/FConstants.m:182-183`), but neither checks both; JS checks leaf size at
`J:core/util/validation.ts:56`. C++ only logs a warning and returns an invalid query
(`Cd:query_desktop.cc:48-90`).

**What we gave up.** Nothing makes an increment exact after a lost answer; the README and a test say so. A
write under `.info` that JS accepts through `update` and `onDisconnect().cancel` is refused
(`J:api/Reference_impl.ts:798-808`, `J:api/OnDisconnect.ts:72-80`): `set`, `update`, `remove` and
`OnDisconnect.cancel()` are refused. `update({'': v})` with the empty key alone is accepted, as in the JS SDK.

**Pinned by.** `test/api/validation_test.dart` and `test/core/util/validation_test.dart` (the rules);
`test/realtime/replay_test.dart` and `test/realtime/persistent_connection_test.dart` (a put sent but not
answered is sent again on the next connection); `test/integration/chaos_emulator_test.dart`.

Status: built. The double-applied increment and the emulator's size limits (768 bytes, depth 32, 10 MiB
string) are measured on the emulator (v4.11.2).

## 12. Transactions

**Decision.** The handler is synchronous and may run several times; it receives a fresh mutable copy of the
current local value. Its first run is synchronous inside `runTransaction`, as in the JS and Android SDKs, so that
`runTransaction(h); set(5)` ends with 5 on the server; the events it causes are still queued and never delivered
inside the call, and the handler returns a `Transaction` value and cannot return a Future. An exception reaches the
Future. An abort completes with `committed: false`, the snapshot the handler saw, and no write. An
exception from the handler aborts the transaction and fails the Future with that same exception. The result of
the handler is `Transaction.success(value, priority:)` or `Transaction.abort()`, the names FlutterFire uses,
because `null` is a valid value. The transaction is sent as a put with the hash of the data it was computed
from; a `datastale` answer reruns it, up to 25 times, then `max-retries`. A transaction whose put was sent and
lost its connection before the answer is not rerun and not re-sent: any answer other than `datastale`, a lost
connection included, aborts it, so its local write is rolled back and the Future fails with `disconnected`
(`lib/src/core/repo_transactions.dart`). With `applyLocally: false` no intermediate local event is raised.
Transactions are never persisted.

**Why.** The mechanism is JS's (`J:core/Repo.ts:930-1202`, the retry cap at `J:core/Repo.ts:118`) and
Android's (`A:core/Repo.java:850-852`). The emulator treats a put with a hash as a compare-and-set: the right
hash writes and answers with the new value, a wrong one answers `datastale` and writes nothing (measured).
Android logs once that transactions are not persisted across restarts (`A:core/Repo.java:931-938`). iOS names
the retry status `maxretry` and Android `maxretries` (`I:Constants/FConstants.m:189`, `A:core/Repo.java:852`);
the client uses one code, `max-retries`.

**What we gave up.** A transaction pending when the app quits is lost, as upstream. The handler sees the value
and not the priority, which Android's `MutableData` and iOS's `FIRMutableData` expose.

**Pinned by.** `test/core/repo_transaction_test.dart` (abort, a throw, `datastale` ends after 25 tries, a
lost connection fails with `disconnected`, D40; `applyLocally: false`); `test/api/scenarios_test.dart`;
`test/integration/public_api_emulator_test.dart`.

Status: built. The compare-and-set behaviour is measured on the emulator (v4.11.2).

## 13. `onDisconnect`

**Decision.** `set`, `update`, `remove` and `cancel` register operations on the server (`o`, `om`, `oc`). The
client remembers them and, when the connection drops, applies them locally and raises the events, as JS does.
They are never written to disk: after a restart nothing is registered, and the app registers again when
`onConnected` says it is connected. Requests made while disconnected are queued and sent after the next
connect. A request that was sent and whose connection drops before the answer completes with a disconnect
status (the code `disconnected`) and is not replayed; only requests queued while offline are sent at the next
connect, and the app registers again if it needs the operation. When the signed-in user changes, the
connection sends a new `auth` on the same socket, as JS does; queued operations are kept and the server runs
the operations registered under the old identity when the socket closes. There is no `user-changed` code.

**Why.** The mechanism is `J:core/Repo.ts:671-705`, `J:core/PersistentConnection.ts:1054-1062`; Android keeps its copy
in `A:core/Repo.java:813-832`. The server forgets the registrations of a connection when it ends, so a sent request is
not replayed: its Future completes with the disconnect status and the app decides. JS keeps one socket across a token
change, so user A's operations could run when user B's session ends; the client does the same, and a new socket per user
was not built. The emulator applies registered writes within about a second of the socket closing, also after the
process was killed, and delivers a single merge push whose keys can be paths.

**What we gave up.** Presence data must be registered again on every connect. Operations registered by one
user can run when another user's session on the same socket ends.

**Pinned by.** `test/realtime/persistent_connection_review_test.dart` (a sent `onDisconnect` whose connection
drops completes once and is not replayed); `test/realtime/replay_test.dart`;
`test/contract/server_actions_reconnect_contract.dart`; `test/integration/public_api_emulator_test.dart` (an
`onDisconnect` write applied when the client goes offline).

Status: built. The server side is measured on the emulator (v4.11.2); whether the server runs an operation
with the identity of the registration after a re-`auth` is not measured.

## 14. Connection state on a desktop

**Decision.** `.info/connected` and `.info/serverTimeOffset` are typed members (`onConnected`, `isConnected`,
`serverTimeOffset`, `estimatedServerTime`) and also readable as paths; `.info/authenticated` is readable as a path only.
`goOffline()` and `goOnline()` are synchronous and valid before the first operation. `purgeOutstandingWrites()` rolls
back every pending write that the server has not acknowledged, fails their Futures with `write-canceled`, aborts
transactions and completes the `onDisconnect` operations still queued locally with `write-canceled`, as Android's does
(`A:connection/PersistentConnectionImpl.java`, `purgeOutstandingWrites`). An `onDisconnect` operation the server has
registered is not undone, and neither is a transaction the server has already accepted: it completes as committed with
the server's value. After the connection is healthy, a link with no inbound frame for 30 s gets the protocol ping, and
15 s more without a frame closes the connection and reconnects. The client resets the delay and reconnects at once on a
network change, a hint from the app's network source (`app.onNetworkConnected`); a wake from sleep gives no hint of its
own, and the dead-link probe finds a link that died in it. `keepSynced(true)` keeps a server listen open for a query so
its cache stays current.

**Lazy start.** A new `FirebaseDatabase` opens no connection. The first operation that needs the server starts it: a
read, a listener (`.info/connected` included), a write, a transaction, an `onDisconnect` call, `keepSynced(true)`, or
`goOnline()`. A database created and closed without use opens no socket. Persistence, when given, still opens at
construction. A `goOffline()` before the first operation keeps that operation offline (`lib/src/core/repo.dart`,
`_start`); JS starts its repository on first use in the same way.

**Request timeouts measure link silence.** The server never answers a request it cannot parse (it sends a
control message with no request id, or closes the socket), so requests need a bound, but not on their age. A
timer of 60 s (`ConnectionTimings.requestTimeout`) is re-armed by every inbound frame, including the pieces of
a message still being assembled, and runs while any request waits. When the link has been silent for that
long with requests outstanding, the connection is closed and the normal replay follows. Writes, `onDisconnect`
requests and listens are never failed by a timeout: they stay in the replay and complete on an answer, a
purge or a close. Only a `get` can fail with `network-error`, after two connections that each ended in such a
silence while it waited; the count belongs to that `get`. A credential request (`auth`, `appcheck`) that is
never answered closes the connection and is retried under the backoff. The 60 s is a choice, not a
measurement.

**Why.** JS, Android and iOS only send a `"0"` text frame every 45 s and never expect an answer
(`J:realtime/WebSocketConnection.ts:425-435`; `A:connection/WebsocketConnection.java:37,321-332`), so a socket
that died during sleep is noticed when a write fails or the OS closes it. JS resets its delay on browser
`online` and `visible` events only, and its monitors never fire outside a browser
(`J:core/util/OnlineMonitor.ts:29-62`). iOS reacts to reachability and to a clock change
(`I:Core/FPersistentConnection.m:606-638`). The emulator answers the protocol ping at any time after the
connection opens (once before the hello), sends no pings of its own, and closes a connection that sends
nothing for exactly 120 s; a `0` frame every 45 s kept a connection open.

**What we gave up.** The ping interval (30 s), its timeout (15 s) and the request timeout (60 s) are chosen,
not measured; production may answer pings differently. A write that the server never answers keeps its
Future pending; the app sees the connection state through `onConnected`.

**Pinned by.** `test/api/lazy_start_test.dart` (no socket before the first operation, one connection after any of them);
`test/realtime/persistent_connection_purge_test.dart` (the purge);
`test/realtime/liveness_test.dart` (the dead-link probe on a fake clock);
`test/realtime/replay_test.dart` (the silence timer: one report per silent period, re-armed by frames);
`test/realtime/persistent_connection_review_test.dart` (group "H1: link silence, not request age", including
the `get` count); `test/integration/idle_close_emulator_test.dart` (the 120 s idle close);
`test/integration/chaos_emulator_test.dart` (section 23).

Status: built. The server's answer to a ping, the 120 s idle close, the absence of server pings and the
unanswered unparsable requests are measured on the emulator (v4.11.2); the three timeouts are not measured.

## 15. Disk persistence: a separate package, in two tiers

**Decision.** `firebase_database_dart` has no native dependency. The SQLite cache is the package
`firebase_database_dart_sqlite`, passed in as `FirebaseDatabase(app, persistence:
sqlitePersistence(directory))`; persistence is off by default. Two managers exist in the core. **Tier 2**, the
one `sqlitePersistence` selects, persists the user's pending writes and the server cache with tracked queries
and pruning. **Tier 1** (`WritesOnlyPersistenceManager`) persists pending writes only, so listeners start empty
and wait for the server; `cacheServerData` (default true) on `databasePersistence` and `sqlitePersistence` selects
it, and `false` keeps the pending writes across a restart and caches no server data. The
schema is the same for both, and tier 1 leaves two tables empty. The storage is synchronous
SQLite behind Android's interface (`PersistenceStorageEngine`,
`A:core/persistence/PersistenceStorageEngine.java:30-128`), so the sync tree keeps Android's structure and its
tests. A no-op persistence manager sits under the sync tree from the start. The `.info` data uses it, as in
Android (`A:core/Repo.java:163-190`).

The layout is Android's nested rows, without the 256 KiB parts: a children node whose estimated size exceeds
16 KiB is saved child by child (`A:android/SqlPersistenceStorageEngine.java:147,881-914`), a leaf is one row,
and node values are JSON in the export form, with server-value placeholders kept
(`A:android/SqlPersistenceStorageEngine.java: 220-229`). Tables: `lease`, `server_cache`, `user_writes`,
`tracked_queries`, `tracked_keys`, with `user_version = major × 1000 + minor`. Write ids continue from the
last persisted id plus one. An acknowledgement removes the persisted write and applies the value to the cache
in one SQLite transaction. Start-up order is: take ownership, load the writes and tracked queries, build the
tree, restore the writes (without persisting them again), connect. The order matters: a write made before the
restore would reuse a restored write id.

**Pruning** follows Android and iOS, which agree: a check after more than 1,000 server updates; prune when the
size is over the limit or more than 1,000 inactive queries are tracked; remove 20 % of the inactive queries,
oldest `last_use` first, until under the limit; active queries are never pruned
(`A:core/persistence/LRUCachePolicy.java: 18-26`; `I:Persistence/FCachePolicy.m:25-27`;
`A:core/persistence/TrackedQueryManager.java:212-276`). The default size is 10 MiB, allowed from 1 MiB to 100
MiB (`A:core/Context.java:37`, `A:core/DatabaseConfig.java:165-171`; `I:Api/FIRDatabaseConfig.m:46-83`).

**Why.** Desktop apps restart, and JS keeps nothing on disk. The two tiers let restart-safe writes ship alone:
the tier-1 manager is Android's restore (about 50 lines, `A:core/Repo.java:234-281`) over the write rows
(`A:android/SqlPersistenceStorageEngine.java:220-360`), against 2,660 lines for Android's whole persistence
package. A tier-1 manager must not reuse a cache-less engine under Android's manager: the tracked-query
manager would mark a query complete and a later listen would see an empty, complete cache and a false `null`.
Not adopted: one row per tracked listen root (a whole subtree in one row). It looks simpler, but a server
merge must then patch every overlapping row, a flush of a 50 MB root rewrites 50 MB, and the atomic
acknowledgement above no longer holds. Android's engine tests (44) and tree-level tests (64) are path-level
and would be rewritten. Not adopted: iOS's one row per leaf, which needs many more rows.

**What we gave up.** Synchronous SQLite runs on the caller's isolate, which in Flutter is the UI isolate; a cold read of
a large subtree or a prune can take long enough to drop a frame. Measured on one Mac mini (macOS, AOT, medians of 5,
rows of about 100 bytes, `synchronous = FULL`, measured by the lead on 2026-11-22 with
`firebase_database_dart_sqlite/tool/bench_load.dart`): a point read takes 0.1 to 0.2 ms and one pending write 0.1 ms
whatever the cache size; loading a whole subtree takes 56.2 ms for 1 MB, 615.2 ms for 10 MB and 2,968.3 ms for 50 MB;
writing it takes 51.9, 483.8 and 2,123.7 ms; reopening the file takes 3.4, 12.7 and 55.5 ms. All of it is on the calling
isolate, so a listener on the root of a full 10 MB cache blocks it for about 0.6 s. A write-behind journal behind the
same interface is the prepared way out. Persisted writes resend an acknowledged write if the removal was lost, so
increments are at-least-once here too (section 11). Web persistence is not in 0.1.

**Pinned by.** In `firebase_database_dart_sqlite/test/`: `sqlite_storage_engine_test.dart` and
`sqlite_storage_engine_contract_test.dart` (the engine, including Android's engine tests as ported),
`node_codec_test.dart`, `sqlite_persistence_test.dart`; `android_oracles_test.dart` runs Android's tree-level
suites on the SQLite engine (the package has 247 tests). In the client, `test/oracle/persistence_test.dart`,
`pruning_test.dart`, `keep_synced_test.dart` and `random_persistence_test.dart` (ports of Android's
`PersistenceTest`, `PruningTest`, `KeepSyncedTest` and `RandomPersistenceTest`, run on the in-memory engine),
and `test/contract/persistence_*_contract_test.dart`.

Only data under a listener or `keepSynced` is written to the disk cache (section 6).

Status: built. The cost of the cache is measured on one Mac mini (above). Not measured: JSON against a binary
codec; `synchronous = FULL` against `NORMAL`; the nested layout against one row per root; the write cost on Linux
and Windows, because macOS `fsync` does not force the drive cache.

## 16. One owner per cache, and a cache that never crashes the app

**Decision.** One client owns a cache file at a time, by a lease row (owner id, epoch, expiry). Liveness is
decided by observation, not by comparing clocks: a connection that finds the row taken reads it, waits one
refresh interval plus slack (5 s plus 2.5 s), and reads it again; an unchanged row means the owner is not
refreshing and the observer takes over, a rewritten row means a live owner and the observer runs memory-only
with one logged warning. The lease lasts 15 s and the owner refreshes it every 5 s, from a timer and inside any
storage transaction that runs more than half a refresh interval after the last write of the row; a fence check
inside every write transaction (`BEGIN IMMEDIATE`) stops a former owner. `persistenceEnabled` reports the
truth. Closing releases the lease; `clearSqlitePersistence` clears under the lease and writes a tombstone row
before it deletes the files.

**A storage error never deletes pending writes and never wipes the store.** The failed transaction rolls back,
the engine stops writing, releases the lease and reads as empty for the rest of the session, and the file keeps
everything committed before the error. `SQLITE_BUSY` and `SQLITE_LOCKED` roll back that transaction and leave
the store durable; it degrades only after 3 in a row. The busy timeout is 1 s for normal work and 0 for
clean-up. The app never receives a `SqliteException`. A bad row (a write, a cache row or a lease row that does
not decode) is a cache miss: it is logged once and skipped, never thrown, and a lease row that does not read
counts as not ours.

A file the engine cannot trust is handled at the next open: a foreign file, a corrupt file or a file of a
newer major version is renamed aside together with its `-wal` file (one copy kept) and an empty cache starts;
if a live owner holds it, the client runs memory-only and leaves the file alone. The file name is a hash of
the app name and the database URL, never the URL, the namespace or the user. On POSIX the directory is 0700 and
the file 0600, created before SQLite opens it. Tokens, the server host and session ids are never written. The
database runs in WAL mode with `synchronous = FULL` and never with `locking_mode = EXCLUSIVE`.

**Why.** Android takes an exclusive SQLite lock and fails the second process
(`A:android/SqlPersistenceStorageEngine.java:828-868`); C++ opens LevelDB and calls `assert(false)` when it
cannot (`Cd:persistence/level_db_persistence_storage_engine.cc:298-311`); iOS deletes and recreates a LevelDB
it cannot open (`I:Persistence/FLevelDBStorageEngine.m:293-318`), and Android rethrows storage errors as a
`RuntimeException` (`A:core/persistence/DefaultPersistenceManager.java:200-213`). Firestore in this repository
dropped the exclusive lock because a hot restart leaves the old isolate's handle open
(`F:sqlite_client_metadata.dart:55-62`; `docs/ARCHITECTURE.md`, persistence table). File locks
are per process and a hot restart keeps the old isolate, so a lock would deadlock a developer's restart.
Neither Android's nor Firestore's SQLite sets file modes.

**What we gave up.** A stalled owner (a paused debugger, an isolate blocked for longer than the refresh
interval plus the slack) can lose the lease to a new process that then sends the same pending writes:
duplicates, harmless for `set` and double for `increment`. After a storage error the session reads as empty
and writes are no longer saved, so a write made after the error is not durable. A second instance of an app
does not get an error; it waits about 7.5 s, then loses durability and logs a warning. The
cache is in clear text; full-disk encryption is the operating system's job. On macOS `fsync` does not flush
the drive cache and `fullfsync` is not set, so the 0.1 ms per commit measured there (section 15) is not the write
cost on Linux or Windows, which is not measured.

**Pinned by.** In `firebase_database_dart_sqlite/test/`: `sqlite_lease_test.dart` (takeover by observation,
a live owner, the tombstone of a clear, a takeover from the same process); `sqlite_connection_test.dart`
(rollback, `SQLITE_BUSY` and the 1 s busy timeout, degrade, wrong SQL; group "E-D1 storage errors": after a full
disk the write committed before the error survives a reopen); `sqlite_open_test.dart` (foreign,
corrupt and newer files, one moved-aside copy kept); `sqlite_storage_engine_test.dart` (an undecodable row is
skipped; after a full disk the store is degraded and reads empty without an exception);
`sqlite_files_test.dart` (the file name); `posix_file_mode_test.dart` (modes; E-P1 passes without the `chmod` when the
runner's umask is 077, and no test sets a umask).

Status: built.

## 17. Errors

**Decision.** One exception, `FirebaseDatabaseException`, a subclass of `FirebaseException` with the plugin
`firebase_database`, a kebab-case code, a message that never contains a token or a URL query, the original
error as `cause`, and `serverStatus`, the raw status and reason from the server. Codes: `permission-denied`,
`disconnected`, `max-retries`, `overridden-by-set`, `unavailable`, `network-error`, `write-canceled`,
`index-not-defined`, `operation-failed`, `too-big`, `database-closed`, `unknown`
(`firebaseDatabaseExceptionCodes`). A rejected or expired token is not a code of its own: the server answers
`permission-denied` to an operation, and the connection retries the token itself. The server's `datastale` and
the code `user-code-exception` (a throwing transaction handler, whose own exception is rethrown) are internal
and never surfaced. Programmer errors (a bad
path, key, value or query) are `ArgumentError` or `StateError` at the call, not exceptions through the Future.
The Android spelling `write-canceled` is kept; the adapter maps it to FlutterFire's `write-cancelled`.

**Why.** JS has no error codes: the status string is the only machine-readable part, upper-cased into
`Error.code` (`J:core/Repo.ts:892-917`). Android has a catalogue of thirteen integer codes
(`A:DatabaseError.java:32-78`) and iOS maps three, with a fourth value for everything else
(`I:Utilities/FUtilities.m:252-292`). A `get` fails with a bare `Error` in JS and a plain `Exception` on
Android (`J:core/Repo.ts:532-535`, `A:connection/PersistentConnectionImpl.java:420`); here it has a code. The
emulator reports a permission error as `permission_denied` on the socket and 401 over HTTP.

**What we gave up.** Apps that switch on strings depend on the spellings; they are the part of the API that is
most expensive to change later.

**Pinned by.** `test/core/database_error_test.dart` (the status table); `test/api/public_surface_test.dart`
(the public codes); `test/api/scenarios_test.dart` (each failing call and its code); the leakage tests
`test/security/c_leakage_test.dart`, `k_leakage_test.dart` and `p_leakage_test.dart` (no token in any message,
`toString` or `cause`); `firebase_database_dart_platform/test/errors_test.dart` (the FlutterFire mapping).

Status: built.

## 18. Logging, and nothing secret in it

**Decision.** Logging is off by default and goes through a callback given to the constructor, `void
Function(DatabaseLogLevel level, String message)` with the levels debug, info, warning and error; the
repository, the connection and the persistence opener all take it (the lease, a degraded cache, `no_index`
warnings and failed persisted writes need it). Requests `auth`, `gauth`, `appcheck`, `unauth` and `unappcheck`
are logged as `<action> (contents hidden)`; URLs are logged without their query; session ids, tokens and
snapshot data never appear at info or above; data appears only at the debug level and is documented as user
data. Strings the server sends (a shutdown reason, an `e` message, an explanation) are cut at 1 KiB with
control characters escaped before they reach a log line or an exception.

**Why.** JS logs every request body, including the ID token of `auth` and the App Check token, and the
WebSocket URL with `ac=` (`J:core/PersistentConnection.ts:180-188,384,419`;
`J:realtime/WebSocketConnection.ts:158`); its REST client warns, unconditionally, URLs that contain `auth=`
(`J:core/ReadonlyRestClient.ts:194-199,222-238`), and logging can be switched on from `sessionStorage`
(`J:core/util/util.ts:120-126`). Android hides credential bodies (`A:connection/Connection.java:236-246`) but
logs whole frames on a parse error (`A:connection/WebsocketConnection.java:261,265`). FlutterFire's
`setLoggingEnabled` can be called at any time; the adapter passes a callback that reads a flag.

**What we gave up.** Three products in this repository now have three shapes of logging (Firestore a static
`setLogLevel`, Storage none, this one a callback); see the open questions.

**Pinned by.** `test/security/c_leakage_test.dart`, `k_leakage_test.dart` and `p_leakage_test.dart` (marker
tokens from fake providers; a logger at its finest level plus every exception and `toString` across a full
session contain no marker).

Status: built.

## 19. The emulator, and what it cannot show

**Decision.** The client works against the Database emulator, and the tests treat it as a separate
implementation. The default database of a project is `<projectId>-default-rtdb`; with an `emulatorHost` and no
`databaseUrl` the namespace is that name. The emulator's differences from what the JS code expects of
production are written as tests, so an emulator upgrade that changes one fails there first. The scripts
`tool/start_database_emulator.sh` and `tool/stop_database_emulator.sh` start and stop a private emulator on a
port of its own, with its own hub and logging ports, and signal only the process they started.

**Why.** Measured on the emulator (v4.11.2):

- `demo-test` and `demo-test-default-rtdb` are different databases, and the rules file given to the CLI
  applies only to `<projectId>-default-rtdb`; every other namespace is open. Namespaces never see each other's
  data, so a namespace per test isolates tests without a restart. A namespace name must be lowercase letters,
  digits and `-`.
- Token expiry is never enforced and the server never sends `ac` or `apc`: a token refresh cannot be tested
  there.
- A listen with a query but no tag makes the emulator fail the whole namespace for about 30 s, answering
  nothing to anyone in it; the client always sends a tag for a non-default query.
- Invalid requests get an `e` control message with no request id, or a silent close, not a status.
- `c` (listen cancelled) pushes carry `sin` and `ein` inside the query and come twice per revoke; revoked
  listens are not restored when the rules are loosened again. A client that derives a query id from `q`
  ignores those keys.
- Overlapping listens get duplicate pushes; onDisconnect merges arrive with path keys.
- **Pushes to a limit query** (addendum 5 of the emulator probe, measured on 2026-11-23 on the emulator with one
  tagged listen, `orderByKey().limitToLast(2)` and `orderByChild('n').limitToLast(2)` with `.indexOn`). A write below
  a child that is already in the window is pushed at its deep path (`list/c/n`). A write that brings a child into the
  window is pushed as the whole child at the child's path (`list/d`, with the fields the client never saw). A write
  that moves one child out and another in is pushed as one merge (`m`) at the query's path, carrying the entering
  and the leaving child whole. A write below a child outside the window is not pushed. No frame says that a child
  left the window; the client works that out from its limit. So the client never receives a deep write below a child
  it does not hold. Not measured: `limitToFirst`, `startAt` or `endAt` without a limit, an `update` by the writer, and
  production.
- The emulator honours `sin` and `ein` (`startAfter` and `endBefore`) when the start or end name is present,
  and implements `ch` and `rm`: one range matches and gets an empty range merge, but a two-range hash did not
  match in four tries, and the cause is not known. The client sends `ch` above 1,024 bytes of cached data
  (section 3); whether the emulator accepts our two-range hash is not measured.
- `put` with a right hash returns the new value in `d`.

**What we gave up.** Everything about production that the emulator hides: token refresh, revocation, the real
`h`, ping behaviour, size limits. There is no production kit for the Database yet; it would run against a test
project with a throwaway user.

**Pinned by.** `test/integration/connection_emulator_test.dart` (listen pushes, hashes, server values, numbers, rules
cancel, `onDisconnect`, auth), `idle_close_emulator_test.dart` (the idle close), `chaos_emulator_test.dart` and
`public_api_emulator_test.dart` (tag `emulator`; 29 pass and 2 slow ones skip themselves); no test found that
replays the limit-query frames above; `tool/start_database_emulator.sh` and
`tool/stop_database_emulator.sh`.

Status: built; measured on the emulator (v4.11.2); production not measured.

## 20. REST is not in this version

**Decision.** The client has one transport, the WebSocket. There is no REST client and no REST fallback in this version,
and `FirebaseDatabase` has no option that reaches one. A read-only client that nothing selected was written and then
removed from the package. If REST returns, the rules it was built with stay: the ID token in `auth=` and the App Check
token in the `X-Firebase-AppCheck` header (the `ac` query value on the web, because a custom header would make every
read a CORS preflight); redirects not followed and a 3xx an error; error bodies capped at 16 KiB and a success body at a
limit the caller sets; path segments encoded one at a time; the HTTP status in the exception.

**Why.** Code that no caller reaches is a second public surface in waiting: it needs its own contract, documentation and
tests, and its own security rules, and a second transport would need its own proxy rule next to the WebSocket's (section
5). JS uses REST only for crawlers and tests (`J:core/Repo.ts:218`). What the emulator was seen to do, recorded for a
later REST client: it answers a refusal with 401, treats bearer and `access_token` as administrator, requires an index
for a REST query (a WebSocket listen only warns with `no_index`), and returns objects in key order, not query order, so
a client has to sort.

**What we gave up.** A read-only path over plain HTTPS for a network where a WebSocket cannot be opened. It was never
reachable from the public API, so no app loses a working feature. There are no REST writes, streaming or ETags either.

**Pinned by.** Nothing: an absent feature has no test.

Status: not in this version. Whether a bearer ID token works on production REST
is not measured; the emulator behaviour above was measured on the emulator (v4.11.2).

## 21. The web, and what is left out

**Decision.** The main library has no `dart:io`; the one file that needs it is in a separate library, with a
conditional import for the web socket. The web build writes nothing to `localStorage` or `sessionStorage` (JS
writes `firebase:host:*` and `firebase:previous_websocket_failure`). There is no long-polling transport. On
the web the App Check token goes in the WebSocket URL, which is visible in the network panel; the ID token
never goes in a URL.

**Why.** Long polling exists for networks that break the WebSocket upgrade, which is a desktop and mobile
audience that has WebSocket and a proxy setting (`J:realtime/BrowserPollConnection.ts`, 747 lines). Not
porting it removes a transport, an iframe and a JSONP surface. The browser cannot set headers on a WebSocket
(`J:realtime/WebSocketConnection.ts:140-141`), and Android sends the token in a header
(`A:connection/WebsocketConnection.java:188-191`).

**What we gave up.** Networks that block WebSocket cannot use the client. Web disk persistence is later.

**Pinned by.** `tool/check_web_imports.dart` (run with the package directory: the main library reaches neither
`dart:io` nor `dart:ffi`; no CI step for this package was checked); `test/realtime/browser/ws_channel_web_test.dart`
(a browser test: the channel writes nothing to `localStorage` or `sessionStorage`) and
`test/realtime/browser/connection_storage_test.dart` (a whole connection session, with credentials, listens, writes, a
token change, a drop and a reconnect, leaves both storages as it found them; it compares before and after, so a
profile that already holds data does not fail it); the browser runs of the unit suite
(section 23).

Status: built; the browser runs are in section 23.

## 22. The FlutterFire adapter

**Decision.** `firebase_database_dart_platform` implements the platform interface of the official
`firebase_database` plugin on the client, so an app keeps `package:firebase_database` and only registers the
adapter: on Linux automatically, elsewhere with `FirebaseDatabaseDart.use()`. It follows the Storage adapter.
Choices:

- **Streams.** The client's streams already allow a second `listen` on one stream object, each with its own
  registration and initial events, which is what FlutterFire code relies on. The adapter passes them through
  with `.map` and a transform that converts errors (`guardStream`); there is no broadcast wrapper.
- **Settings before first use.** The adapter holds the emulator host, the persistence flag and cache size, and
  the logging flag until the client is first needed. After that, a different emulator host throws a
  `StateError` (ignoring it would send traffic to production); persistence settings are ignored, as Android
  ignores them (`FirebaseDatabasePlugin.kt:1036-1055` in FlutterFire); the logging flag takes effect at any
  time.
- **Values.** Snapshot values and the argument of a transaction handler are mutable deep copies typed
  `Map<Object?, Object?>`, which is the type FlutterFire's codec produces; a map key that is not a `String`
  is stringified on write, and a key that is invalid after that (`1.5` contains a dot) is the client's
  `ArgumentError`, passed through unchanged.
- **Query modifiers** are applied in one order whatever the call order, so `startAt(...).orderByChild(...)`
  works.
- **Errors.** The client's code `write-canceled` is mapped to FlutterFire's `write-cancelled`.
- **Three FlutterFire quirks are fixed**, each with a test: child snapshots keep their priority (native
  children get `null`); `snapshot.ref` of a child event is the child's reference (FlutterFire gives the
  query's); `startAt(null)` is a real null bound (FlutterFire drops a null cursor, and Android then queries
  the string `"null"`).
- **One client per database, and its life.** `instance` and `instanceFor` give one client per database however its URL
  is written (the app's URL, a trailing slash, another case of the host). The clients of a FlutterFire app are closed
  when its `firebase_app_dart` app is deleted, on every platform, and a re-created app gets a new client with the
  settings the `FirebaseDatabase` object had.
- **Tokens.** The adapter installs the app's token provider behind a wrapper (`TokenOnChangeProvider`), so a change
  event never carries a placeholder: each non-empty event is answered with the token of `getAccessToken`, an empty
  event means signed out, and the client fetches the token on any change event in any case (section 4).
- **No implicit environment.** The adapter reads no emulator environment variable: the emulator is used only after
  `useDatabaseEmulator`. The client's warnings and errors are printed with `debugPrint` even when logging is off; its
  debug and info lines only after `setLoggingEnabled(true)`.
- **Registration.** The adapter's `pubspec.yaml` declares `linux` and `windows` with a plugin class. On
  Windows, when the adapter is a direct dependency of the app, Flutter's tool selects it instead of the native
  plugin and leaves the native plugin out of the build. On Flutter 3.41.6, with two throwaway plugins, a
  direct dependency gave the adapter and no native entry in `generated_plugins.cmake`, and a transitive one
  gave the native plugin. A real Windows build confirms it: the generated plugin registrant calls
  `FirebaseDatabaseDart.registerWith()`.

**Why.** The platform interface hands every query call its modifiers, so the adapter holds no query state
(`firebase_database/lib/src/query.dart:9-27` in FlutterFire 13.1.0). The FlutterFire sources show the quirks: native
children are built with `'priority': null` and an off-by-one list key
(`method_channel_data_snapshot.dart:53-58,79-84,94-96`); both native and web build the event snapshot with the query's
reference (`firebase_database_web/lib/src/utils/snapshot_utils.dart:3-11`, `method_channel_query.dart:65-68`); `toMap()`
drops a null cursor value (`query_modifiers.dart:224`) and Android's builder falls to `value.toString()`
(`QueryBuilder.kt:82-139`). The resolution rule is in `flutter_tools/lib/src/flutter_plugins.dart:1676-1730` (Flutter
3.41.6). FlutterFire has a Windows plugin, which is the C++ SDK, and none for Linux. The C++ plugin does not resolve
`ServerValue.increment` and treats `startAfter` and `endBefore` as inclusive; its own integration tests skip those on
Windows (`database_reference_e2e.dart:260,291`, `query_e2e.dart:105,167`).

**What we gave up.** Code that works around the child-event reference quirk by treating `event.snapshot.ref`
as the list reference changes meaning. A mutable copy costs one deep copy per snapshot whose value is read.
A release build of a desktop app with the adapter has not been run.

**Pinned by.** In `firebase_database_dart_platform/test/`: `quirks_test.dart` (the three quirks),
`values_test.dart` (stringified keys, mutable copies), `transaction_test.dart` (an invalid stringified key is
the client's `ArgumentError`), `errors_test.dart` (the `write-cancelled` mapping), `registration_test.dart`,
`instance_test.dart` (settings before first use, one client per database), `delete_test.dart` (the app's deletion),
`token_change_test.dart` (the wrapper), `emulator_test.dart`. FlutterFire's own `firebase_database`
integration suite (77 tests, from the example at the pinned FlutterFire commit) runs through the adapter
against the emulator with `tool/test_flutterfire_database_gate.sh`: 76 pass and 1 skips itself, on the macOS
host test runner. The script patches a copy of the example (a Linux case in the options, a `databaseURL`, no
workspace resolution, the emulator port) and never changes the FlutterFire checkout.

Status: built. The suite passes against the adapter on macOS. On Windows 11 x64 (Flutter 3.47.8, debug) the Windows
example app, written against `firebase_database` alone, builds with the adapter and passes its 4 integration tests
against the emulator. On Linux x64 (a Debian 13 container) the Linux example app builds and passes its 4 integration
tests under a virtual display. Not run: a release build of a desktop app.

## 23. How the connection is tested

**Decision.** The wire layer is tested with doubles and recordings, because upstream has almost no tests of
it: JS has two unit tests of the WebSocket URL and one network test of `Connection`, and Android has one
network test of `Connection` and none for `PersistentConnectionImpl` or `WebsocketConnection`. The richest
upstream material is iOS's 31 unit tests against malformed server messages and C++'s local fake-server tests.
The client has:

- a scripted fake channel and a protocol-level fake server (`test/util/fake_ws.dart`,
  `test/util/fake_rtdb_server.dart`), with an injected clock, random source and timings, run under
  `fakeAsync`. The fake server models each behaviour measured on the emulator;
- a **chaos** setup: a TCP proxy between the client and the emulator (`test/util/chaos_proxy.dart`) and a
  WebSocket frame tap on top of it (`test/util/ws_tap.dart`) that observes whole frames and drops, delays or
  cuts on them. `test/integration/chaos_emulator_test.dart` uses it for framing on the wire, replay after a
  cut, the dead-link probe, the keep-alive and requests that are never answered. The schedules are written by
  hand; there is no seeded random schedule and no oracle client;
- a **fuzz** of the decoder in `test/realtime/server_message_test.dart`: each field of every valid server
  message is mutated to another JSON type, and the decoder must not throw and must report nothing for an
  invalid shape;
- contract tests (`test/contract/`) that run the same cases against the fake connection and the real one.

There is no recorded transcript corpus.

**Why.** The Firestore package already has the proxy pattern (`cloud_firestore_dart/test/util/chaos_proxy.dart`),
and iOS needed twelve hand-written tests for what one table-driven fuzz covers. The emulator never sends `r`,
`s`, `ac`, `apc` or `c` by itself, so those paths are exercised by injecting frames into a live session or
through the fake server.

**What we gave up.** The proxy and tap are copied into the package (packages cannot share test files), and a
browser test cannot open a server socket, so the browser channel test starts a loopback server through
`spawnHybridCode`.

**What has run, and where.**

The lead's runs are on the merged trunk plus the connection tests, unless a row says another session ran it or an
earlier commit.

| Where | Result | Whose run |
|---|---|---|
| Dart VM | 2,371 tests of the client | the other session |
| Chrome, the whole test tree | dart2js 2,328 tests, dart2wasm 2,332 tests | the other session |
| SQLite package | 247 tests on Dart 3.11.5 and on Dart 3.8.0 | lead |
| Adapter | 136 tests, 5 skipped without the emulator; 141 with it | the other session |
| FlutterFire's own `firebase_database` integration suite through the adapter | 76 pass, 1 skips itself (macOS host test runner, emulator) | lead |
| Database emulator (v4.11.2, macOS) | the tests tagged `emulator`: 29 pass, 2 skip themselves | the other session |
| Windows 11 x64 | the client's VM suite passed at an earlier commit (2,126); the Windows example app passes its 4 integration tests through the adapter (Flutter 3.47.8, debug); its disk cache test passed with an earlier version of the app | lead |
| Linux x64 (Debian 13 container) | the client's VM suite and both browser legs passed at an earlier commit (2,058; 1,125; 1,128); the Linux example app builds and passes its 4 integration tests under a virtual display | lead |
| Web gallery | a smoke script passes 66 steps on both compilers | the other session |
| Both engines | Android's persistence suites pass on the in-memory and the SQLite engine (inside the counts above) | lead |
| GitHub Actions (run 45086670535) | all 25 jobs pass: the emulator tests (29 pass, 2 skip), Chrome dart2js (2,328) and dart2wasm (2,332), the adapter with the emulator (141), FlutterFire's suite through the adapter (76 pass, 1 skips), the gallery smoke script (66 steps) | CI |

Mutation testing: 45 mutations were tried; 39 of them survived the suites as they were before the last pass, and all
45 are caught now. Independent reviews: the connection (3 high, 8 medium and 7 low findings), the SQLite engine (1
high, 5 medium and 10 low), the adapter (2 high, 4 medium and 6 low) and the API and core (1 high, 4 medium and 4 low);
all were fixed, each with a test that fails without the fix.

The connection's own unit tests first ran in a browser late, and found one web-only defect: compiled to
JavaScript an infinity passes `is int`, so `1e999` from the server passed the number checks. Every number from the
server is now asked for finiteness (`server_message_test`, `c_limits_test`, `k_server_input_test`).

Not run: a production project, a release build of a desktop app, Safari and Firefox, a real display, and CI on a
runner.

**Pinned by.** `test/realtime/`, `test/integration/`, `test/security/`, `test/contract/` and the tags in
`dart_test.yaml` (`browser`, `emulator`, `emulator-slow`).

Status: built; the run record above is the measured part.

## 24. Seams inside the client

**Decision.** The client is split into a core (the data layer, the sync tree, the repository, the persistence manager)
and a realtime half (the WebSocket connection; there is no REST client, section 20). They meet at one interface,
`ServerActions`, with a delegate for what the server pushes. The rules at that seam:

- **Tokens belong to the connection.** Each implementation takes a token source in its constructor, an adapter
  over the app's auth and App Check providers, and subscribes to token changes itself. The repository does not
  push tokens.
- **One error vocabulary.** The wire status strings are mapped once, in the realtime half, to the core's error
  codes. The realtime half declares no exception of its own for server statuses; the public
  `FirebaseDatabaseException` is defined once, in the public layer. A `get` fails with a typed exception that
  carries the status and the reason.
- **Paths** cross the seam as `/a/b`, the root as `/`, in both directions. The server pushes `a/b` and the
  empty string for the root (measured, v4.11.2); the connection normalises before it calls the delegate.
- **Start order** lives in one place: load the persisted writes, restore them, then connect. A write made
  before the restore would reuse the id of a restored write.
- **Acknowledging a write takes precomputed server values, not a clock.** Android's `ackUserWrite` takes a
  clock and resolves server values inside the acknowledgement, and its own comment calls that awkward
  (`A:core/SyncTree.java:233-236`).
- **Shutdown is asynchronous**: closing the repository awaits the connection's shutdown. It closes the
  connection first, and every outstanding `get` completes with `database_closed`; no Future that crosses the
  seam hangs across a shutdown.
- A listen's query object is computed once by the core and handed over unmodifiable, so the
  realtime half has no query type of its own. Tags start at 1 for each database, not once per process as in JS
  (`J:core/SyncTree.ts:103-105,934-938`).

**Why.** If the repository pushed tokens as well as the connection, each change would be sent twice. Two error
vocabularies would be translated twice and drift. A fake of each side, with a contract test that both pass,
lets the two halves be built and tested apart.

**What we gave up.** A change at the seam is a change for both halves; the contract test is the guard.

**Pinned by.** `test/contract/server_actions_contract.dart` and `server_actions_reconnect_contract.dart` (the same cases
run against the fake and the real connection, in `server_actions_contract_test.dart`, and
`test/realtime/persistent_connection_contract_test.dart`: request bodies, path form, a get that fails with
`ServerActionsException`, shutdown, the reconnect order).

Status: built.

## 25. Deliberate differences from the JS SDK

**Decision.** The table lists each place where the client knowingly behaves differently from the JS SDK
(`J:`), what each does, and the test that pins the client's behaviour. The reasons follow the table, keyed by
the number; the section each reason cites has the upstream lines.

| # | Topic | JS SDK | This client | Pinned by |
|---|---|---|---|---|
| 1 | `get()`, order-only | index sent, refused without it | default query, ordered here | `scenarios_test` |
| 2 | `get()` while offline | queues with no limit | waits 3 s, then cache or `unavailable` | `repo_get_test` D49, D50 |
| 3 | Request timeout | none | silence timer re-armed by frames | `replay_test` |
| 4 | Dead link | `0` frame every 45 s, no answer | ping after 30 s, close after 15 s more | `liveness_test` |
| 5 | Reconnect delay | cap 5 min, reset on browser events | cap 30 s, reset when healthy | `reconnect_backoff_test` |
| 6 | Snapshot value | `val()` builds a mutable value | one memoised unmodifiable value | `snapshot_test` |
| 7 | Event delivery | listeners can run inside `set()` | queue, microtask, never inside | `scenarios_test` D1 |
| 8 | Child events | four callbacks | four getters, `onChildEvents`, `once()` | `scenarios_test` D12 |
| 9 | Error codes | upper-case status string | kebab-case, no token codes | `database_error_test` |
| 10 | Configuration | cached instance, setters | constructor only, no cache | `public_surface_test`; no cache test |
| 11 | Plain text | `http://h:443`, emulator on `ws://` | `ArgumentError`, no token | `realtime_target_test` |
| 12 | Server hosts | stored unchecked | validated, resets capped | `hosts_test` |
| 13 | Frame split | by UTF-16 unit | by code point | `framing_test` |
| 14 | Server input | validates what it sends | bounded and validated | `k_server_input_test` |
| 15 | Compound hash | simple hash only | `ch` above 1,024 bytes | `replay_test` |
| 16 | Transaction result | return `undefined` to abort | `Transaction.success`, `abort` | `scenarios_test` D37 |
| 17 | Logging | bodies logged, tokens too | off, callback, credentials hidden | `c_leakage_test` |
| 18 | Disk persistence | none | optional SQLite, lease owner | SQLite package tests |
| 19 | Browser storage | writes `firebase:*` keys | writes nothing | `ws_channel_web_test` |
| 20 | Writes under `.info` | `update`, `cancel` accepted | `set`, `update`, `remove`, `cancel` refused | `validation_test`; `api_behaviour_test` (`cancel`) |
| 21 | Long polling | present | absent | no test found |
| 22 | Ack of pipelined `update`s | writes rebuilt on each ack | no rebuild, same state | `write_tree_test` |
| 23 | Server push to an unlistened path | no persistence; Android caches every push | cached only under a listen or `keepSynced` | `cache_server_push_test` |
| 24 | Handler writes to its own location | the nested write aborts the transaction, which is then reverted a second time (throws, a write stays pending) | aborted once with `overridden-by-set` (`write-canceled` for a purge), on the first run and on a rerun | `transaction_abort_test` |
| 25 | Ack of a write below a server leaf | upstream: re-applies the empty child, the leaf is lost | applies the leaf | `view_leaf_test` |
| 26 | Server change below a leaf in the event cache | upstream: updated child by child, the leaf is kept | the event cache is rebuilt from the server cache | `view_leaf_test` |
| 27 | Proxies | Node: `HTTPS_PROXY` or `HTTP_PROXY` read by the `ws` package (`J:realtime/WebSocketConnection.ts:166-198`); a browser uses its own settings | a secure VM connection honours `HTTPS_PROXY` and `NO_PROXY` (and lower-case forms) only; loopback and the emulator are always direct; no API option | `ws_channel_io_test` |
| 28 | REST fallback | read-only REST for crawlers and tests | none: the WebSocket is the only transport | no test found |
| 29 | A pending write removed while later writes rewrite it | an overwrite counts as invisible when a later write covers it; a merge never does, so each answered `update` of the same children rebuilds the write tree | a merge whose every child is rewritten by later visible writes also counts as invisible; neither shortcut is taken when an earlier visible write lies above the removed one | `write_tree_test` ("merge rewritten child by child by later writes was not visible", "random writes: any removal order gives a rebuild"), `write_tree_fuzz_test` |
| 30 | A removed write that was folded into an earlier write above it | the later-write shortcut is still taken: `set(a, 5)`, `set(a/b, 1)`, `set(a/b, null)`, then the second is refused, leaves `a` without its `5` (by the source; not run on the JS SDK) | the tree is rebuilt | `write_tree_test` ("an overwrite under a leaf, later deleted (JS rule)", and cases A and B beside it) |
| 31 | A write reverted while an earlier pending write lies above it (with a real server: a transaction aborted below an ancestor transaction still in flight) | only writes at or below the removed one count as overlapping it, so nothing is rebuilt, and the view returns unchanged when a write shadows the reverted path: an open listener, `get()` and a new listener below keep the reverted data until the upper write is answered (reproduced on the JS SDK 13.4.0 against the emulator with the answers reordered by a proxy; with a real server's order it lasts milliseconds) | a visible write above counts too and the tree is rebuilt; the view takes what the write tree holds, so no listener keeps the reverted data | `revert_under_pending_write_test`, `revert_under_shadow_test` |

Test file names are given without their directory: `scenarios_test`, `snapshot_test`, `public_surface_test`,
`validation_test`, `api_behaviour_test` and `revert_under_pending_write_test` are in `test/api/`; `repo_get_test`,
`database_error_test`, `write_tree_test`, `write_tree_fuzz_test` and `revert_under_shadow_test` in `test/core/`; `replay_test`, `liveness_test`, `reconnect_backoff_test`, `realtime_target_test`, `framing_test`,
`ws_channel_io_test` and `ws_channel_web_test` (in `browser/`) in `test/realtime/`; `hosts_test`, `k_server_input_test`
and `c_leakage_test` in `test/security/`.

**Why.**

1. A listen already asks for the default query and orders locally (section 10); a filtered or limited `get`
   needs the server's index and keeps the `index-not-defined` error.
2. A request that waits for ever hides an offline app (section 10).
3. A request that the server drops without an answer would otherwise hang; the rule measures the link, not the
   age of the request, so a long download is not cut and writes are never failed by it (section 14).
4. A socket that died in sleep is otherwise noticed only when a write fails (section 14).
5. A desktop client is often first opened right after a wake (section 3).
6. One pass per snapshot, and one reader cannot change what another reads (section 9).
7. A listener that runs inside `set()` can re-enter the caller; one ordered queue removes that (section 8).
8. A paused `await for` breaks the order across streams; one stream of all child events keeps it (section 8).
9. JS has no codes to branch on; a refused credential is `permission-denied` and the connection retries the
   token itself, so there are no token codes (section 17).
10. Immutable configuration makes the wrong call order impossible (section 1).
11. A real token must never go over `ws://` (section 4).
12. A server-sent host or a reset loop must not redirect tokens (section 5).
13. A lone surrogate corrupts a string on the emulator (section 7).
14. A malformed frame must not buffer for ever or throw into the app's zone (section 6).
15. A large cache is not re-downloaded in full on every connect, as on Android (section 3).
16. `null` is a valid value, so abort needs its own result (section 12).
17. JS logs credentials (section 18).
18. Desktop apps restart and keep their pending writes (sections 15 and 16).
19. A web page of the app should not gain storage keys it did not ask for (section 21).
20. A write under `.info` can only fail or do nothing useful (section 11).
21. It serves networks that break the WebSocket upgrade, which a desktop app can cover with a proxy setting
    (section 21).
22. Two merges at one location always counted as overlapping upstream, so each acknowledgement rebuilt the
    visible writes: 802 pipelined updates a second here before the change and 897 in the JS SDK, against about
    7,000 after it (one run). A merge now counts by its children's paths. The observable state is the same:
    `write_tree_test` (in `test/core/`) compares any removal order with a rebuild over 200 seeds.
23. Data nobody asked for was never pruned and could overwrite the cached data of an inactive query, which was later
    served as complete. `cache_server_push_test` is in `test/core/`.
24. An unacknowledged write that is never reverted is a data fault. `transaction_abort_test` pins the single abort.
25. A listener ended with null instead of the value the server holds. `view_leaf_test` is in `test/core/`.
26. The event cache kept a leaf for good once a write below it was replaced. `view_leaf_test` is in `test/core/`.
27. A desktop network is usually reached through the proxy the environment names, but a proxy must never read the
    plain-text frames of the emulator, and a setting in the API would be a second place to configure it (section 5).
28. Code that no caller reaches is a second surface with its own contract (section 20). JS uses REST for crawlers
    and tests only.

Status: built.

### Behaviours shared with the JS SDK that are kept

The client's local view (the write tree and the view processor) follows the JS algorithm, and seven of its known
behaviours are kept. They were found by a random differential check of the local view against a server model, and
`test/core/sync_tree_property_test.dart` lists its failing seeds by these rows. Each was then read in the code and,
where the last two columns say so, run. Rows 2 and 7 are shared with the JS SDK 13.4.0 by runs on the emulator, and so is
row 5 in its simplified form. Row 1 is better here than in JS: the JS SDK showed a wrong value that lasted, this client
does not. Rows 3, 5 (in the table's form) and 6 were seen only in the differential check; they are not reachable
through the public API in the forms run on either SDK. Row 4 is a server fact. Rows 29 to 31 above are places where
this client departs from JS. "Emulator" means the local Firebase emulator (v4.11.2); production was not run for any
row. The JS column says what a run of the JS SDK 13.4.0 showed; "Measured on" says what was run with our client.

| # | Behaviour | Minimal sequence | What is seen, and for how long | JS SDK 13.4.0 | Measured on (our client) |
|---|---|---|---|---|---|
| 1 | A child written below a leaf and then changed again could show a wrong value. The write tree treats a write below a leaf as confined to its path, but on a leaf it replaces the leaf. This client is correct in the offline form and wrong for a few ms in the refused form. | Server `r = 1`. `goOffline`, listen `r`, `set r/c {v:1}`, `set r/c null`, `goOnline`. A second form: `set r/b 1`, `set r/b null` on a leaf, the first refused by a rule | Offline form: the listener was never wrong (its `null` came in the same ms as a second client's). Refused form: `null` shown while the refusal was in flight, then `1`, wrong for about 4 ms (4, 4, 4 in three runs). The server and a second client held `null` and `1` | Wrong and lasting in both forms, 3 runs each. Offline: the writer's listener and `get()` stayed at `1` (server `null`) from about 18 to 21 ms, and still at +30 s; only a detach and re-attach gave `null`. Refused: `null` (server `1`) from 1 to 2 ms, still at +30 s, repaired only by a re-attach | Emulator, both forms, 3 runs each, public API, same harness as the JS runs. Three versions of the client (`ebd757c4`, `38e6d8a3`, `9ddd3fda`) behaved the same: correct in the offline form, wrong for 2 to 4 ms in the refused form. No commit among them changed the outcome; older ones were not run |
| 2 | A node that is emptied and refilled loses its priority in the client; the server keeps it. This holds for one update that does both, and for two separate messages. A fix for the one-update form was written and reviewed five times; every version either left a listener disagreeing with the client's own server data when nothing was pending, or was wrong where the unchanged code is right, so none is in this version. | Server `{a:1, .priority:1}`, listen. `update {a:null, b:1}`. The two-message form: `set a null`, then `set b 1` | The writer's listener and `get()`, and a second client's listener, show `{b:1}` without the priority; the server holds `{b:1, .priority:1}` (REST export, and a new connection's `get()`). Nothing repaired it in the 2 s watched | Same, in both forms: the priority was lost on the writer and the observer, kept by the server, unchanged 2 s later. For the one-update form the observer got it back after its listener was detached and attached again; the writer still lacked it 4.7 s later, after another client wrote below the node | Emulator, both forms, 3 runs each, public API |
| 3 | A priority written on a node that does not exist is shown locally, though the server refuses it (`could not set priority on non-existent node`). A pending write that creates the node later makes the priority show too, because the writes are applied together and priorities go after children. A fix that hid such a priority when complete server data shows the node missing was tried and dropped: it is wrong whenever another client creates the node before our write is answered, and the client cannot know which the server handled first. | Node `b` missing. `setPriority(b, 0)`, then `set b/x/y 2`. The race: our `setPriority(b, 0)` and another client's `set b/x 1`, arriving in either order | Seen only in the differential check; not reachable through the public API in the form run on either SDK. Public API form run (`setPriority(b, 0)`, then `set b/x/y 2`): the writer's listener showed `{x:{y:2}}` with no priority, never priority 0, in 3 of 3 runs, and the server refused the priority write | Same: the writer's listener never showed priority 0; the server refused with `invalid_parameters` | Refusal on the emulator, by our client, 3 runs. Showing the priority, and the race: differential check only |
| 4 | The emulator keeps the priority of a node emptied by one write and refilled by the next. The client's node model cannot represent an empty node with a priority, so it never agrees with this. Measured on the emulator by REST: after `DELETE r/a` the export of `r` is `{".priority":0.0}`, an empty node that still has its priority; only deleting `r` itself drops it. Whether a production server does the same is the open question for any later fix of row 2's two-message form. | Server `{d:1, .priority:1}`. `set d null`, then `set b 1`, then a read | The server holds `{b:1, .priority:1}`; the client has no priority (as in row 2). A server fact; whether a production server keeps the priority is not verified | Not run on JS (a fact about the server) | Emulator only; production not verified |
| 5 | A limit query's window is not refilled after a local removal. The client does not know the next child that would enter the window, so the window is short, or holds a child that moved out of order, until the server sends it again. A listener can receive a value while part of the window is unknown. | Table form: `listen r orderByValue limitToLast(2)`, `update r {b:null}`, `set /` (a whole-tree value), `set r/b/v 0`, the listen answered, then the last two writes reverted locally, as a transaction abort does (minimised seed 100653). Simplified form run: server `r = {a:1,b:2,c:3,d:4}` with `.indexOn: .value`, listen `orderByValue limitToLast(2)`, `goOffline`, `remove r/d`, `goOnline` | Table form: seen only in the differential check, not reachable through the public API (seed 100653: `{d}` instead of `{a, d}`; no duration measured). Simplified form: `{c:3}`, one child where 2 are due, while offline (about 510 ms, all of it offline), refilled by a server merge push 2 to 12 ms after `goOnline` (`{b:2,c:3}`). Without an index the server sends the whole node and the window is never short | Same in the simplified form: `{c:3}` while offline, refilled 6 ms after the removal was sent. Without an index the window was never short. The table form was not run | Simplified form: emulator, 3 runs, public API. Table form: differential check only |
| 6 | A listener can receive the same null value twice in a row. A revert that finds an incomplete server cache marks the view incomplete, and the next complete answer raises `null` again. | Listen `r/b/x`, `set /`, the server refuses the set, `set /r {...}`. A second form: `set /r null`, listen `r/b`, the set refused, the listen answered | Seen only in the differential check; not reachable through the public API in the forms run on either SDK. Two forms run (a refused `set /` then `set r {b:{x:null}}`; the same two writes queued offline): the events were `null`, `1`, `null`, never two identical nulls in a row, in 6 of 6 runs | Same events `null`, `1`, `null`, no repeated null, in both forms | Differential check only; the two forms above on the emulator, 3 runs each |
| 7 | A root listen added over a tagged limit query leaves the limit listener with a stale window when another client's write at the query's path is processed by the server between the client's listen frame and its unlisten frame. The tagged put sets the limit view's server cache to the filtered window, and a later push below a child outside it is dropped. The root listener is right. | Data `{a:{x:1, y:{u:2,.priority:2}, .priority:1}}`. Listen `/a` ordered by priority with `limitToFirst(2)`, then listen `/`, the limit listen answered. The client's frames after its `q /` are held by a proxy; another client sets `/a {y}`; the frames are released (seed 18113 of the property test has the same shape) | The limit listener shows `{y}` where the server holds `{x:{u:1}, y}`, at +100 ms, +2 s and +10 s; nothing in the protocol sends `x` to the limit view again, so it lasts until another write touches `x` or the listener is removed (the last part inferred). A write at `/a/x` instead leaves the listener right and only the limit view's server cache short. Without the held uplink the server handles the other client's write after the client's frames and the listener is right | Same: `{y}` at +100 ms, +2 s and +10 s, server `{x:{u:1}, y}`; the write at `/a/x` gave a right listener and a short cache in JS too | Emulator, our client and JS, one run each, uplink held by a proxy; rare without a stalled uplink. Not a general failure |

The code spots are `CompoundWrite.addWrite` and `WriteTree.removeWrite` (row 1), `ChildrenNode.updateImmediateChild`
(rows 2 and 4), `CompoundWrite` applying priorities after children (row 3), `ViewProcessor.revertUserWrite` (rows 5
and 6) and the tagged server overwrite in `view_processor_server.dart` (row 7). A priority on an empty node would need
a change in the Node model, which was not attempted.

## 26. What is not in 0.1

**Decision.** Not in the first release: long polling; typed converters (Dart 3 patterns on the typed value are
the typed read); a REST client of any kind (section 20); web disk persistence; a per-app instance cache (section
25 row 10); a typed `.info/authenticated` member (the path is readable) and a hook that goes offline when the app is
backgrounded; a proxy option in the API (on the VM a secure connection honours `HTTPS_PROXY` and `NO_PROXY`, see
the README); a configurable `get()` wait; the compat (namespaced) API;
admin-only authentication paths; the idle disconnect. No parity page for the Database exists yet; this list and
section 3 are the record of what differs.

**Why.** Each either exists for another runtime, is a different product, or changes behaviour that apps depend
on without a clear need on desktop.

**What we gave up.** Features that a user may expect from another SDK; the list above says which.

**Pinned by.** Nothing: an absent feature has no test. `test/api/public_surface_test.dart` pins the public API
that is present.

Status: built.

## Open questions for the owner

Each question lists both sides and what the client does until it is decided.

1. **A second app instance on one cache.** Another process or isolate may open the same cache file, for example a second
   copy of the app or the app plus a command-line tool. *Memory-only with a warning:* the second client watches the
   lease for about 7.5 s, then runs without disk, logs one warning, and `persistenceEnabled` is false; the app keeps
   working, but its writes are not durable and nobody is stopped. *An error:* opening fails with a typed error
   (`persistence-unavailable`) through the first operation, which makes the problem impossible to miss and matches
   Android, which fails the second process, but stops the app. **Default now:** memory-only with a warning.
2. **Re-sent increments.** A write whose answer was lost is sent again after a reconnect and a restart, and a
   `ServerValue.increment` can then apply twice; the protocol has no idempotency key. *Document it:* the
   README and a test say so, and the exact way to count is a transaction; every official SDK behaves the same.
   *Special treatment:* the client could refuse to re-send an increment whose answer was lost and fail it with
   an error the app handles, trading a possible double count for a possible lost count. **Default now:**
   document it and pin it with a test; no special treatment.
3. **The cache per app, or per signed-in user.** *Per app and database URL* (upstream): simple, and writes made at
   start-up before the session is restored (user null, then user X) still go through; the cost is that a second user on
   a shared machine can see the first user's cached data until `clearPersistence()` is called (`clearSqlitePersistence`
   in the SQLite package), which the guide says to do at sign-out. *Per user:* no cross-user reads, but start-up writes
   made before sign-in completes would fail or be hidden. *A middle option:* the server cache remembers the user it
   belongs to and is cleared when a different user signs in (a `null` at start-up is ignored, and an explicit sign-out
   clears it); pending writes are tagged with the user who made them and held, not sent and not dropped, when another
   user signs in, and reported through a stream until the app purges them. This keeps the start-up pattern working and
   costs one table, one column and a listener on the token provider. **Default now:** per app and database URL, with
   `clearPersistence()`.
4. **Snapshot values: unmodifiable, or fresh mutable copies.** *Unmodifiable and memoised:* one pass per
   snapshot, one reader cannot corrupt another, and a mutation fails loudly; the cost is that code written for
   FlutterFire or JS that edits `value` must copy it. *Fresh mutable copy on each read:* JS's `val()` and
   Firestore's `data()` behave like this, and FlutterFire-style code needs no change; the cost is a copy on
   every read. **Default now:** unmodifiable and memoised; the transaction handler and the adapter get mutable
   copies.
5. **One logging type for all products.** Firestore has a static `setLogLevel`, Storage has none, and this
   client has a constructor callback. *One shared type* (for example `package:logging` with one logger named
   after the package, or one level type in `firebase_app_dart`) keeps the three products alike; the cost is a
   dependency or a change to a published package. *A callback per product* is the smallest surface; the cost
   is a third shape. **Default now:** a constructor callback, with the credential rules of section 18
   whichever type wins.
6. **No public demo database for the web examples.** The examples that run in a browser need a database to
   talk to. *Run them against the emulator only:* nothing public is exposed and nothing can be abused, but a
   visitor cannot try them without a local emulator. *A public demo database with strict rules:* anyone can
   try the page; the cost is an account to maintain, a quota and abuse to watch for, and data from strangers.
   **Default now:** no public database; the examples and the playground run against an emulator or with no
   backend.
