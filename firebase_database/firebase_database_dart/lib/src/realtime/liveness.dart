/// The timers that keep a connection alive and give up on a bad one (owner C): keep-alive, health
/// check, extra ping and dead-link probe (`rtdb_protocol.md` 3.1, 3.4; test plan B-3.1h, B-3.1i,
/// B-3.4a, B-3.4b).
library;

import 'package:firebase_database_dart/src/realtime/connection.dart';
import 'package:firebase_database_dart/src/realtime/connection_timings.dart';

/// The liveness state of one connection, driven by `RealtimeConnection`.
///
/// Uses plain `Timer`s so `fakeAsync` drives it (test plan 2.4). After [stop] no timer is left and
/// no callback runs (iOS U-I19).
final class Liveness {
  /// Creates the state with [timings]. [sendKeepAlive] sends the frame `0`; [sendPing] sends the
  /// control ping `p`; [close] ends the connection for the given reason (`other` when unhealthy,
  /// `deadLink` when a probe gets no answer).
  Liveness({
    required ConnectionTimings timings,
    required void Function() sendKeepAlive,
    required void Function() sendPing,
    required void Function(DisconnectReason reason) close,
  }) {
    throw UnimplementedError();
  }

  /// The socket opened: arms the keep-alive and the health timer (3.4: the 30 s timer starts with
  /// the connection).
  void start() {
    throw UnimplementedError();
  }

  /// The hello arrived: arms the extra ping (`ConnectionTimings.extraPingDelay`, 3.4) and the
  /// dead-link probe.
  void onHello() {
    throw UnimplementedError();
  }

  /// A frame of [units] UTF-16 code units was sent: re-arms the keep-alive, counts bytes sent.
  void onFrameSent(int units) {
    throw UnimplementedError();
  }

  /// A frame of [units] UTF-16 code units arrived: re-arms the keep-alive and the dead-link probe,
  /// counts bytes received.
  void onFrameReceived(int units) {
    throw UnimplementedError();
  }

  /// A data message or a pong arrived: counts toward health; while not healthy after a pong, pings
  /// again (3.4).
  void onResponse() {
    throw UnimplementedError();
  }

  /// Whether the connection has met the health rule of 3.4.
  bool get isHealthy => throw UnimplementedError();

  /// Cancels every timer; nothing can be re-armed afterwards.
  void stop() {
    throw UnimplementedError();
  }
}
