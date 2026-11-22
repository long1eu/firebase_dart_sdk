/// One WebSocket session with the database (owner C): open, hello, reset, shutdown, control
/// dispatch, close and the connect timeout (`rtdb_protocol.md` 3.2 to 3.5).
library;

import 'package:firebase_database_dart/src/core/util/logger.dart';
import 'package:firebase_database_dart/src/realtime/connection_timings.dart';
import 'package:firebase_database_dart/src/realtime/realtime_target.dart';
import 'package:firebase_database_dart/src/realtime/transport/ws_channel.dart';

/// Why a [RealtimeConnection] ended (test plan section 5, interface C to P).
enum DisconnectReason {
  /// Any ordinary end: the peer closed, the socket failed, the connection was unhealthy, a
  /// protocol error, or a local [RealtimeConnection.close].
  other,

  /// The server sent a reset (`r`) while connected; reconnect with normal backoff (3.3).
  serverReset,

  /// No hello within `ConnectionTimings.connectTimeout` (test plan B-3.4c).
  connectTimeout,

  /// A dead-link probe got no answer (test plan B-3.1i).
  deadLink,
}

/// What a [RealtimeConnection] reports to its owner. Every callback may close or replace the
/// connection (re-entrancy, test plan B-3.5b).
abstract interface class RealtimeDelegate {
  /// The hello arrived (3.2): [serverTimeMs] is its `ts`, [sessionId] its `s`. Called once.
  void onReady(int serverTimeMs, String sessionId);

  /// A data message (`{"t":"d","d":message}`) arrived; [message] is its `d` object, not yet
  /// decoded.
  void onDataMessage(Map<String, Object?> message);

  /// The connection ended for [reason]. Called at most once, never after [onKill].
  void onDisconnect(DisconnectReason reason);

  /// The server sent shutdown (`s`, 3.3) with [reason] (server text, cut and escaped before it is
  /// logged, threat model T7). No [onDisconnect] follows and the owner must never reconnect.
  void onKill(String reason);
}

/// One connection attempt and, after the hello, one live session (test plan section 5, C gives P).
///
/// Owns the frames (`FrameSplitter`, `FrameAssembler`), the liveness timers (`Liveness`) and the
/// connect timeout. A server host from the hello or a reset goes through
/// [RealtimeTarget.acceptServerHost] (threat model T1); at most
/// `ConnectionTimings.maxResetsPerAttempt` resets are followed in one attempt (T2). Malformed
/// control messages close the connection as an ordinary failure (iOS U-I13, U-I14).
final class RealtimeConnection {
  /// Creates a connection to [target] over [connector]; nothing happens before [open].
  ///
  /// [lastSessionId] becomes `ls` of the URL (2.3); [appId] and [appCheckToken] go into the
  /// headers or the URL as [target] decides. [now] and [random] replace the clock and the random
  /// source (test plan 2.4). [logger] gets the `e` control errors, unknown control types and the
  /// version warning, cleaned by `safeServerText` (threat model T7); null drops them.
  RealtimeConnection(
    RealtimeTarget target,
    WsConnector connector,
    ConnectionTimings timings,
    RealtimeDelegate delegate, {
    String? lastSessionId,
    String? appId,
    String? appCheckToken,
    DatabaseLogger? logger,
    required DateTime Function() now,
    required double Function() random,
  }) {
    throw UnimplementedError();
  }

  /// Opens the socket and starts the connect timeout. Call once.
  void open() {
    throw UnimplementedError();
  }

  /// Whether the hello arrived and the connection is not closed.
  bool get isConnected => throw UnimplementedError();

  /// Sends [request] as `{"t":"d","d":request}`, split into frames (3.1). Throws [StateError] when
  /// not connected.
  void send(Map<String, Object?> request) {
    throw UnimplementedError();
  }

  /// Closes the connection and reports [reason] to [RealtimeDelegate.onDisconnect] once. Safe
  /// before [open], after a close, and from inside a delegate callback (3.5, test plan B-3.5a/b).
  void close([DisconnectReason reason = DisconnectReason.other]) {
    throw UnimplementedError();
  }

  /// Shows the state only: no session id, no token (threat model T7, T8).
  @override
  String toString() => 'RealtimeConnection';
}
