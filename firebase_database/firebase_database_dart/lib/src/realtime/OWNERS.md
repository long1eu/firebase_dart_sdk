# Owners of the connection half

One builder per file, no shared file (`rtdb_connection_test_plan.md` section 5). "Needs" lists
the declarations of other files that a file compiles against; every one exists with its final
signature. Spec sections: `rtdb_protocol.md` numbers; `T<n>` = threat model; `A.<n>` =
`rtdb_seam_changes.md`; "probe" = `rtdb_emulator_probe.md` (measured).

Owners: **T** transport and framing, **C** connection, **P** persistent connection, **K** tokens,
backoff, message decoding and status strings, **U** URL, `RealtimeTarget`, emulator and test rig.

The seam with the core is `lib/src/core/connection/` (`ServerActions`, `ServerActionsDelegate`,
`ListenSpec`, `ListenHashProvider`, `WireRangeMerge`), with `core/repo_info.dart` (`RepoInfo`) and
`core/database_error.dart` (`DatabaseErrorCode`, `DatabaseError`). Those files belong to the core;
the connection half imports and implements them, and declares no `ListenSpec`, `QuerySpec`,
`RepoInfo` or exception of its own. Paths cross the seam as `/a/b` (root `/`) both ways.

The decided seam changes (A.1 to A.10) are in the core since 7cbaba84: tokens belong to the
connection, `Future<void> shutdown()`, `ServerActionsException` for a failed `get`,
`DatabaseLogger` (`core/util/logger.dart`, nullable:
the core's `ServerActionsFactory` passes `DatabaseLogger?`). `RealtimeTarget` is the class A.5
calls `ConnectionTarget`.

## lib/src/realtime

| File | Owner | Needs from other files | Implements |
|---|---|---|---|
| `transport/ws_channel.dart` | T | nothing | test plan 2.1; 2.3 (headers advisory); T4, T8 |
| `transport/ws_channel_io.dart` | T | `ws_channel.dart` | 2.3 (headers); 3.4 (no `pingInterval`); T4, T5, T9 |
| `transport/ws_channel_web.dart` | T | `ws_channel.dart` | 2.3 (`p`/`ac` in URL); T25, T27 |
| `transport/ws_connector.dart` | T | `ws_channel*.dart` | conditional import (test plan 2.1) |
| `framing.dart` | T | nothing (limits passed in) | 3.1, code-point splitting (probe: 65536-byte frames, UTF-8 split drops the message); T9, T10 |
| `connection.dart` | C | T: `WsConnector`, `WsChannel`, `WsEvent`, `FrameSplitter`, `FrameAssembler`, `FramingException`; U: `RealtimeTarget`; C: `ConnectionTimings`, `RealtimeProtocol`, `Liveness`; K: `safeServerText`; core: `DatabaseLogger` | 3.2, 3.3, 3.5; T1, T2, T7, T11 |
| `liveness.dart` | C | C: `ConnectionTimings`, `DisconnectReason` | 3.1 (keep-alive under the 120 s idle close), 3.4, dead-link probe (pong at any time) |
| `connection_timings.dart` | C | nothing | 1.1 to 1.4; `unappCheck` by emulator (probe); T2, T9, T10, T14 |
| `persistent_connection.dart` | P | core: implements `ServerActions`, calls `ServerActionsDelegate`, reads `ListenSpec`, `ListenHashProvider`; C: `RealtimeConnection`, `RealtimeDelegate`, `DisconnectReason`, `ConnectionTimings`, `RealtimeProtocol`; K: `AuthSession`, `RealtimeTokenSource`, `ReconnectBackoff`, `decodeServerMessage` and its records, `wirePathFromServer`, `countsAsInvalidToken`; U: `RealtimeTarget`; P: `RequestTable`; core: `ServerActionsException`, `DatabaseLogger` | 4, 5, 8.1, 8.2, 8.4 to 8.8; A.1 to A.3, A.6; T13, T15, T18 |
| `request_table.dart` | P | nothing | 4 (envelope, `r` counter, per-request timeout armed only on a live socket; P counts: 2 timeouts -> `network_error`) |
| `auth_session.dart` | K | `firebase_app_dart` (`AuthTokenProvider`, `AppCheckTokenProvider`); C: `RealtimeProtocol` | 4.6, 4.7, 4.8, 8.1, 8.3; A.1; T7, T14 |
| `reconnect_backoff.dart` | K | nothing | 8.2; T13 |
| `server_message.dart` | K | core: `WireRangeMerge` | 4 (responses), 5 (pushes, `rm` as measured), `wirePathFromServer` (A.3); T11 |
| `realtime_error.dart` | K | core: `DatabaseErrorCode` | 9 (status strings to `DatabaseErrorCode`); A.9; T7 (`safeServerText`) |
| `database_url.dart` | U | core: `RepoInfo` | 1.1, 2.1, 2.4 (env value); T3, T6; bad URL = `FormatException`/`ArgumentError` |
| `realtime_target.dart` | U | core: `RepoInfo` | 2.2, 2.3, 2.4; A.5; T1, T3, T6 |
| `emulator_token.dart` | U | nothing | 2.4; T3 |

## test

| File | Owner | Needs | Implements |
|---|---|---|---|
| `test/util/fake_ws.dart` | T | T: `ws_channel.dart` | test plan 2.2 |
| `test/util/fake_rtdb_server.dart` | T | T: `fake_ws.dart`, `ws_channel.dart` | test plan 2.3; push paths without the leading slash (probe) |
| `test/util/fakes.dart` | K | K: `RequestSender`; `firebase_app_dart` | test plan 2.4, 2.4a |
| `test/util/chaos_proxy.dart` | U | `dart:io` (copy of the Firestore proxy) | test plan 2.5 |
| `test/util/ws_tap.dart` | U | U: `chaos_proxy.dart` | test plan 2.5 |
| `test/contract/server_actions_reconnect_contract.dart` | P | core: `ServerActionsHarness` (`server_actions_contract.dart`), `ServerActions` | reconnect contract: replay order, revoked/failed listens, offline onDisconnect queue, typed `get` error, two timeouts -> `network_error`, re-auth after revoke |
| `test/realtime/persistent_connection_contract_test.dart` | P | core: `runServerActionsContract`; P: `runServerActionsReconnectContract`; T: `FakeRtdbServer` | the seam contract against `PersistentConnection` |
| `test/realtime/skeleton_compile_test.dart` | lead | every lib file but `ws_channel_web.dart` | references every public symbol; a builder who adds or renames a public symbol updates it |

The recording `ServerActionsDelegate` for the tests of P is the core's
`lib/src/testing/recording_server_actions_delegate.dart` (A.8). P runs the core's
`runServerActionsContract` with a harness over `FakeRtdbServer`.

## Rules for every file

- No `dart:io`, `dart:html`, `dart:js_interop` or `package:web` outside `*_io.dart` / `*_web.dart`
  (`dart tool/check_web_imports.dart firebase_database/firebase_database_dart <lib files>` passes).
- `final` classes, `sealed` where a set of records is closed, no global mutable state, injected
  `now`/`random` and plain `Timer`s (no rxdart, no `DateTime.now()`, `Random()` or `Future.delayed`).
- Every type that can hold a token, a session id or a URL with a query hides it in `toString`; log
  lines go through the injected `DatabaseLogger` and never carry a token (T7).
- `package:firebase_database_dart/...` imports in `lib`; the test helpers import each other by
  relative path (a `package:` URI cannot reach `test/`).
