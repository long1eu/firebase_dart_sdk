## 0.0.1

Work in progress, not published. A client of the Firebase Realtime Database in Dart for the VM and the web, tested
against the Database emulator.

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
- Logging through a callback, off by default; credentials are never logged.
- Optional disk persistence through `firebase_database_dart_sqlite`; only data under a listener or `keepSynced` is
  written to the cache; an offline `get()` answers from the cache only when it holds the complete value for the query;
  `cacheServerData: false` keeps only the pending writes. `package:firebase_database_dart/storage_engine.dart` is the
  library for custom persistence engines.
  It names only types it exports: an engine stores a query as its path and `QuerySpec.toWireObject()` and rebuilds
  it with `QuerySpec.fromPathAndWireObject`; `Index`, `KeyIndex` and `NamedNode` are exported there; the
  `QuerySpec(path, params)` and `ImmutableTree(value, children)` constructors, `QuerySpec.params`,
  `QuerySpec.toListenSpec` and `ImmutableTree.children` are `@internal`.
- `package:firebase_database_dart/testing.dart`: a fake server for tests of your own code.
- The event dispatcher yields to the event loop after 1,000 events with an unthrottled task in the browser, so a burst
  of events in a hidden tab is delivered in bounded time.
- Writes are delivered at least once: a re-sent `ServerValue.increment` can apply twice.
- Not included: long polling, typed converters, a REST client or fallback, web disk persistence, an instance cache,
  the compat API, a proxy option in the API.
