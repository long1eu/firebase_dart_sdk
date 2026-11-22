# Owners of the connection half

One builder per file, no shared file (`rtdb_connection_test_plan.md` section 5). "Needs" lists
the declarations of other owners' files that a file compiles against; every one of them exists in the
skeleton with its final signature. Spec sections: `rtdb_protocol.md` numbers, `T<n>` = threat model.

Owners: **T** transport and framing, **C** connection, **P** persistent connection, **K** tokens,
backoff and message decoding, **R** REST client (and the `ListenSpec` interface), **U** URL,
RepoInfo, emulator and test rig.

## lib/src/realtime

| File | Owner | Needs from other files | Implements |
|---|---|---|---|
| `transport/ws_channel.dart` | T | nothing | test plan 2.1; 2.3 (headers advisory); T4, T8 |
| `transport/ws_channel_io.dart` | T | `ws_channel.dart` | 2.3 (headers); 3.4 (no `pingInterval`); T4, T5, T9 |
| `transport/ws_channel_web.dart` | T | `ws_channel.dart` | 2.3 (`p`/`ac` in URL); T25, T27 |
| `transport/ws_connector.dart` | T | `ws_channel*.dart` | conditional import (test plan 2.1) |
| `framing.dart` | T | nothing (`maxFrameUnits` etc. are passed in) | 3.1; T9, T10 |
| `connection.dart` | C | T: `WsConnector`, `WsChannel`, `WsEvent`, `FrameSplitter`, `FrameAssembler`, `FramingException`; U: `ConnectionTarget`; C: `ConnectionTimings`, `Liveness` | 3.2, 3.3, 3.5; T1, T2, T7, T11 |
| `liveness.dart` | C | C: `ConnectionTimings`, `DisconnectReason` | 3.1 (keep-alive), 3.4; dead-link rule |
| `connection_timings.dart` | C | nothing | 1.1, 1.2, 1.3, 1.4 (server limits); T2, T9, T10, T14 |
| `persistent_connection.dart` | P | C: `RealtimeConnection`, `RealtimeDelegate`, `DisconnectReason`, `ConnectionTimings`, `RealtimeProtocol`; K: `AuthSession`, `RealtimeTokenSource`, `ReconnectBackoff`, `decodeServerMessage` and its records, `statusToError`; U: `ConnectionTarget`; R: `ListenSpec`; P: `RequestTable` | 4, 5, 8.1, 8.2, 8.4 to 8.8; T13, T15, T18 |
| `request_table.dart` | P | nothing | 4 (envelope, `r` counter) |
| `auth_session.dart` | K | `firebase_app_dart` (`AuthTokenProvider`, `AppCheckTokenProvider`) | 4.6, 4.7, 4.8, 8.1, 8.3; T7, T14 |
| `reconnect_backoff.dart` | K | nothing | 8.2; T13 |
| `server_message.dart` | K | nothing | 4 (responses), 5 (pushes); T11 (shapes, paths) |
| `realtime_error.dart` | K | `firebase_app_dart` (`FirebaseException`) | 9; T7, T8 |
| `rest_client.dart` | R | U: `RepoInfo.restUri`, `RepoInfo.mayReceiveTokens`; K: `RealtimeTokenSource`, `FirebaseDatabaseException`, `statusToError`; R: `ListenSpec`; `package:http` | 6.4, 9, 10; T7, T8, T23 |
| `listen_spec.dart` | R (interface only; the query half implements it) | nothing | 6.1 to 6.4 |
| `database_url.dart` | U | K: `FirebaseDatabaseException` (its constructor is real code) | 1.1, 2.1, 2.4 (env value); T3, T6 |
| `repo_info.dart` | U | U: `DatabaseUrl` | 2.2, 2.3, 2.4, 10 (REST URL); T1, T3, T6 |
| `emulator_token.dart` | U | nothing | 2.4; T3 |

## test/util

| File | Owner | Needs | Implements |
|---|---|---|---|
| `fake_ws.dart` | T | T: `ws_channel.dart` | test plan 2.2 |
| `fake_rtdb_server.dart` | T | T: `fake_ws.dart`, `ws_channel.dart` | test plan 2.3 |
| `fakes.dart` | K | K: `RequestSender`; `firebase_app_dart` | test plan 2.4, 2.4a |
| `chaos_proxy.dart` | U | `dart:io` (copy of the Firestore proxy) | test plan 2.5 |
| `ws_tap.dart` | U | U: `chaos_proxy.dart` | test plan 2.5 |

## Rules for every file

- No `dart:io`, `dart:html`, `dart:js_interop` or `package:web` outside `*_io.dart` / `*_web.dart`
  (`dart tool/check_web_imports.dart firebase_database/firebase_database_dart <lib files>` passes).
- `final` classes, `sealed` where a set of records is closed, no global mutable state, injected
  `now`/`random` and plain `Timer`s (no rxdart, no `DateTime.now()`, `Random()` or `Future.delayed`).
- Every type that can hold a token, a session id or a URL with a query hides it in `toString`.
- `package:firebase_database_dart/...` imports in `lib`; the test helpers import each other by
  relative path (a `package:` URI cannot reach `test/`).
