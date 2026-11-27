## 0.1.1

- One update is applied in two passes, independent of key order, as production does: every value entry first, then
  every priority entry, parents before children. A node whose last child goes keeps its priority as an emptied node,
  so `update` with `{'.priority': 2, 'x/v': null, 'x/.priority': null}` on `{x: {v: 1, .priority: 1}}` leaves
  `{'.priority': 2}` in either key order.
- Fixes a defect of 0.1.0: when the server patched only part of a cached node and the patched part contained none of
  that node's children, the client dropped the node's priority even though the server still held it, so listeners saw
  the priority as null until the data was loaded again.
- Also in 0.1.0, not fixed: a query window that holds an emptied node is sent again at each listen in 0.1.0, because
  that client holds no emptied node and the server counts it in the window's hash. This version holds emptied nodes,
  but a limit or range view can still hold one with a stale priority, and a limit view whose window holds emptied
  children only drops them; such a window is sent again too.
- Also in 0.1.0, not fixed: with the SQLite engine, an acknowledged update that removes a child, adds another and sets
  the node's priority (`update(x, {a: null, b: 5, '.priority': 7})` on `x = {a: 1}`) while a listen on the added child
  is waiting for its data stores the node without the priority, until the node is loaded from the server again.

## 0.1.0

- First version. A client of the Firebase Realtime Database in Dart, for the Dart VM and the web. It speaks the
  WebSocket protocol of the Firebase JS SDK, with Dart names (`DatabaseReference`, `onValue`, `runTransaction`) and
  Dart streams. It is not affiliated with or supported by Google or Firebase.
- It covers reads and writes, listeners, queries, transactions, `onDisconnect`, server values and the connection
  state. An optional disk cache is in `firebase_database_dart_sqlite`.
- Where it ran. Dart VM: macOS (2,645 tests of the client, 60 of them skipped; 29 tests against the Database emulator
  v4.11.2), Linux x64 in a Debian 13 container and Windows 11 x64 (both at an earlier commit). Web: Chrome on macOS, the
  whole test tree, 2,584 tests with dart2js and 2,588 with dart2wasm. Not run: a release build of a desktop app, Safari,
  Firefox and a real display.
- Verified against production. The verification kit has 41 checks. On 2026-11-27 all 41 ran as one run against a
  dedicated database instance of one Firebase project, on the final client of this version, and all 41 passed; the
  same day the kit ran on the emulator and all 41 passed there too. Earlier runs passed as well (2026-11-25 and 26,
  checks 1 to 39; checks 40 and 41 each alone). The 2026-11-27 run had no `--expect-emptied-node-fix`, so checks 22
  and 38 (c), (e) and (f) record that the client drops the priority of an emptied node, as the JS SDK does
  (`tool/verify_production_database/README.md`, "Known results"). "Run" here means one run, not repeated runs. Some
  checks are informational and record what the client does. The kit signs up a throwaway user, writes about 1.1 MB
  below a path of its own and removes it. It covers the connection and its TLS, the server's host, every value type,
  server values, listeners, queries, transactions, `onDisconnect`, offline writes, rules with and without a user, a
  token refresh on a live connection, a sign-out, timings, a 1 MB value, pipelined writes, and raw frames for the
  server's answers about priorities and limit queries.
- Never run against production: token expiry after an hour, a rules change during a connection, a 10 MiB string leaf
  and a 16 MB write, App Check with a real provider, the legacy `firebaseio.com` host and a custom domain, the re-send
  of an `increment` whose answer was lost, and the limit-view race of section 25. Section 23 of
  `docs/database_decisions.md` has the list.
- Known limits:
  - Writes are delivered at least once. A re-sent `ServerValue.increment` can apply twice; use a transaction to count.
  - A hung TLS handshake cannot be closed on the Dart VM. The client gives up after its 30 s connect timeout and
    tries again.
  - A dead socket after a wake is noticed after about 46 s, and after about 75 s at worst, plus the connect (computed
    from the timing constants, not measured).
  - A `ServerValue.increment` whose sum leaves the range of a double is a local infinity until the server's value
    replaces it.
  - One process or isolate owns a cache file; a second one runs memory-only with one logged warning.
  - Transactions and `onDisconnect` registrations are not persisted.
  - Priorities and pending writes. As in the JS SDK, a node that is emptied and refilled loses its priority locally
    while the server keeps it, and a transaction on a node that holds only a priority fails with `max-retries`
    (reported upstream as firebase/firebase-js-sdk #10688; README, "Known limits", and section 25 of
    `docs/database_decisions.md`, table "Behaviours shared with the JS SDK that are kept", rows 2 and 8).
  - A write below a leaf that the server refuses shows a wrong value until the refusal arrives, 2 to 4 ms on the
    emulator; the JS SDK keeps the wrong value until a listener is attached again (firebase/firebase-js-sdk #10687; the
    offline form, #10686, is right in this client). Section 25 of `docs/database_decisions.md`, same table, row 1.
  - Not in this version: long polling, web disk persistence, a REST client, an instance cache, typed converters, the
    compat API and a proxy option in the API. On the Dart VM a secure connection honours `HTTPS_PROXY` and `NO_PROXY`.
- Differences from the JS SDK are in the README, "How it differs from the JS SDK", and in section 25 of
  `docs/database_decisions.md` (38 rows, each with the test that pins it).
- `FirebaseDatabase(app, databaseUrl:, emulatorHost:, mockUserToken:, persistence:, logger:)`: one instance is one
  connection; configuration is constructor-only and there is no instance cache. A new instance opens no connection:
  the first operation that needs the server (a read, a listener, a write, a transaction, an `onDisconnect` call,
  `keepSynced(true)`) or `goOnline()` does. Persistence still opens at construction.
- The constructor refuses, before any connection, a database URL with a path, a custom domain without `?ns=`, a port
  other than 443 off loopback, an invalid project id and plain `http://` outside the emulator; a start that fails fails
  every pending and later call. `refFromUrl` refuses user info, plain http, other ports and extra query keys. The
  disk cache key is the normalised database URL.
- Reads and writes: `get`, `once`, `set`, `update`, `push`, `setPriority`, `remove`, `refFromUrl`; `DataSnapshot.value`
  is plain, unmodifiable Dart data. A `get()` with a range or a limit on `orderByChild` or `orderByValue` needs
  `.indexOn` in the rules; an order-only one does not.
- `DataSnapshot.toJson()` (the export form) reads numbers as `value` and `priority` do: a value or priority the
  server stores as `1.0` exports as the `int` 1 on every compiler, as JS `exportVal()` gives `1`.
- Listening: `onValue`, `onChildAdded`, `onChildChanged`, `onChildMoved`, `onChildRemoved` and `onChildEvents`, one
  ordered stream of the four child events.
- Queries: `orderByChild`, `orderByKey`, `orderByValue`, `orderByPriority`, `startAt`, `startAfter`, `endAt`,
  `endBefore`, `equalTo`, `limitToFirst`, `limitToLast`, `keepSynced`.
- `runTransaction` with `Transaction.success` and `Transaction.abort`: the first run of the handler happens inside the
  call, its events are queued, and a sent transaction that loses its connection fails with `disconnected`;
  `onDisconnect` with `set`, `update`, `remove` and `cancel`; `ServerValue.timestamp` and `ServerValue.increment`.
- Connection state: `onConnected`, `isConnected`, `serverTimeOffset`, `estimatedServerTime`, `goOffline`, `goOnline`,
  `purgeOutstandingWrites` (cancels writes not yet acknowledged and `onDisconnect` operations still queued locally); a
  dead-link probe, and reconnect with a 30 s cap. A server message the client cannot accept closes the connection and
  reconnects with the delay at its cap; JSON deeper than 64 levels is refused before decoding.
- A secure connection on the Dart VM honours `HTTPS_PROXY` and `NO_PROXY` (and the lower-case forms); loopback and the
  emulator are always direct; there is no API option.
- ID and App Check tokens from the app's providers, sent only over TLS or to the emulator; a change event of the
  auth provider is a signal and the client fetches the token (an empty token means signed out); `mockUserTokenFor` for
  the emulator.
- `FirebaseDatabaseException` with the codes `permission-denied`, `disconnected`, `max-retries`, `overridden-by-set`,
  `unavailable`, `network-error`, `write-canceled`, `index-not-defined`, `operation-failed`, `too-big`,
  `database-closed`, `data-stale` and `unknown`. For a server status the client does not know, `unknown` carries the
  server's reason as its message and `status: reason` as `serverStatus`, as for the other codes; a `get()` fails the
  same way as a write. A `get()` whose answer the client cannot read fails with `unknown`, a fixed message, the
  original error as `cause` and no `serverStatus`.
- Closing the database or deleting its app ends every stream with done and no error; pending Futures fail with
  `database-closed`. A server refusal ends a stream with an error; losing the connection never does.
- Logging through a callback, off by default; credentials are never logged.
- Optional disk persistence through `firebase_database_dart_sqlite`; only data under a listener or `keepSynced` is
  written to the cache; an offline `get()` answers from the cache only when it holds the complete value for the query;
  `cacheServerData: false` keeps only the pending writes. `package:firebase_database_dart/storage_engine.dart` is the
  library for custom persistence engines.
  It names only types it exports: an engine stores a query as its path and `QuerySpec.toWireObject()` and rebuilds
  it with `QuerySpec.fromPathAndWireObject`; `Index`, `KeyIndex` and `NamedNode` are exported there; the
  `QuerySpec(path, params)` and `ImmutableTree(value, children)` constructors, `QuerySpec.params`,
  `QuerySpec.toListenSpec` and `ImmutableTree.children` are `@internal`.
- `package:firebase_database_dart/testing.dart`: a fake server for tests of your own code. Breaking for tests that
  acked the newest write first: `FakeDatabaseServer`'s `ackLastWrite`, `failLastWrite` and `ackLastOnDisconnect` now
  throw a `StateError` when the newest request is not the oldest unanswered one, because a test must answer writes and
  `onDisconnect` requests in the order they left (after a reconnect, puts and merges before `onDisconnect` requests
  made offline, as the client sends them). Pass `outOfOrder: true` to keep the old behaviour; the new `ackNextWrite`,
  `failNextWrite` and `ackNextOnDisconnect` answer the oldest.
- The event dispatcher yields to the event loop after 1,000 events with an unthrottled task in the browser, so a burst
  of events in a hidden tab is delivered in bounded time.
- A limit query under a listener at or above its path keeps the right window when one update by another client
  moves a child out of it: the child that enters holds the update's earlier changes, and the window ends as the
  server's. The JS SDK showed a stale or removed child there until every listener at the path was removed.
- `update` and `OnDisconnect.update` throw an `ArgumentError` at the call for an object, at any depth, with a non-null
  priority and no value once nulls and empty objects are dropped (`{'n': {'.priority': 5}}`,
  `{'n': {'.value': null, '.priority': 5}}`, `{'n': {'.priority': 5, 'a': {}}}`): the server answers such a merge
  with an error that names no request, so its Future would never complete. `update({'.priority': p})`, a
  `'n/.priority'` key, `{'.value': v, '.priority': p}` and empty objects (removals) are accepted as before; `set` and
  transactions are unchanged and leave such an object out.
