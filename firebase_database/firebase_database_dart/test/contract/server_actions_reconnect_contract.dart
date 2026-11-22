// Owner P. The reconnect part of the ServerActions contract (lib/src/core/connection/
// server_actions.dart): what an implementation that keeps a connection across drops must do, on
// top of runServerActionsContract (server_actions_contract.dart). A function file, no main: P's
// runner (over FakeRtdbServer) imports it and calls runServerActionsReconnectContract. The
// read-only REST client does not run it (it has no connection to lose).

import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:test/test.dart';

import 'server_actions_contract.dart';

/// Plays the server across connections: the core's [ServerActionsHarness] plus reconnects and
/// the pushes that only a live server sends.
abstract interface class ServerActionsReconnectHarness
    implements ServerActionsHarness {
  /// The number of the connection (from 1) on which `received[index]` arrived.
  int connectionOf(int index);

  /// Accepts the next connection attempt after a [drop] and sends its hello; completes once the
  /// client's replay has arrived.
  Future<void> reconnect();

  /// Pushes `c` (listen revoked) for [path] in the server's form (`users/ada`), with the query
  /// objects [queries] when given.
  Future<void> revokeListen(String path, [List<Map<String, Object?>>? queries]);

  /// Pushes `ac` (auth revoked) with [status] and [explanation].
  Future<void> revokeAuth(String status, String explanation);
}

/// The reconnect contract: one `test` per case, each failing with [UnimplementedError] until P
/// writes it (so the runner lists what is still missing instead of failing to load).
///
/// Cases:
/// * replay order after a reconnect: `auth`, `appcheck`, listens (with a freshly computed hash),
///   unacknowledged puts and merges in order, onDisconnect requests not yet sent, outstanding
///   gets; only then `ServerActionsDelegate.onConnect`;
/// * acknowledged puts and acknowledged onDisconnect requests are not replayed; a sent transaction
///   put (with a hash) completes with [statusDisconnect] instead of being replayed, before
///   `ServerActionsDelegate.onDisconnect`;
/// * a failed listen, and a listen revoked by a `c` push, complete with their status, leave the
///   listen table and are not replayed;
/// * onDisconnect requests made while offline are queued and sent at the next connection;
/// * a `get` outstanding at a drop is re-sent once and completes once; a failed `get` fails with
///   [ServerActionsException] carrying the status and reason;
/// * a request that times out twice on live connections completes with `network_error` and is
///   not replayed again (`ConnectionTimings.maxRequestTimeouts`);
/// * an auth revoke closes the connection and the next connection authenticates again.
void runServerActionsReconnectContract(
  ServerActionsReconnectHarness Function() createHarness,
) {
  const List<String> cases = <String>[
    'replay order after a reconnect, then onConnect',
    'acknowledged work is not replayed; a sent transaction put completes with disconnect',
    'a failed or revoked listen leaves the table and is not replayed',
    'onDisconnect requests made while offline are sent at the next connection',
    'an outstanding get is re-sent once; a failed get throws ServerActionsException',
    'a request that times out twice fails with network_error',
    'an auth revoke closes the connection and the next one authenticates again',
  ];
  for (final String name in cases) {
    test(name, () => throw UnimplementedError());
  }
}
