/// The timers that keep a connection alive and give up on a bad one (owner C): keep-alive, health
/// check, extra ping and dead-link probe (`rtdb_protocol.md` 3.1, 3.4; test plan B-3.1h, B-3.1i,
/// B-3.4a, B-3.4b).
library;

import 'dart:async';

import 'package:firebase_database_dart/src/realtime/connection.dart';
import 'package:firebase_database_dart/src/realtime/connection_timings.dart';

/// The liveness state of one connection, driven by `RealtimeConnection`.
///
/// Uses plain `Timer`s so `fakeAsync` drives it (test plan 2.4). After [stop] no timer is left and
/// no callback runs (iOS U-I19).
///
/// Four timers:
/// - keep-alive: [ConnectionTimings.keepAlive] after the last frame in either direction, the frame
///   `0` is sent (WebSocketConnection.ts:425-435); the server closes a connection that sent nothing
///   for 120 s (`rtdb_emulator_probe.md`, measured).
/// - health: [ConnectionTimings.healthyTimeout] after [start], a connection that is not healthy is
///   closed unless it received or sent enough bytes (Connection.ts:151-184).
/// - extra ping: [ConnectionTimings.extraPingDelay] after the hello, a ping if not yet healthy, and
///   one more after every pong while not healthy (Connection.ts:370-373, 454-482).
/// - dead-link probe: after the hello, [ConnectionTimings.idleProbeAfter] without an inbound frame
///   sends a ping; [ConnectionTimings.idleProbeTimeout] more without one closes the connection with
///   [DisconnectReason.deadLink]. The server answers a ping at any time (probe addendum 2 item 9,
///   measured). Upstream has no such rule (`rtdb_protocol.md` 3.1); it is the lead's decision.
final class Liveness {
  /// Creates the state with [timings]. [sendKeepAlive] sends the frame `0`; [sendPing] sends the
  /// control ping `p`; [close] ends the connection for the given reason (`other` when unhealthy,
  /// `deadLink` when a probe gets no answer).
  Liveness({
    required ConnectionTimings timings,
    required void Function() sendKeepAlive,
    required void Function() sendPing,
    required void Function(DisconnectReason reason) close,
  }) : _timings = timings,
       _sendKeepAlive = sendKeepAlive,
       _sendPing = sendPing,
       _close = close,
       _responsesNeeded = timings.responsesRequiredToBeHealthy;

  final ConnectionTimings _timings;
  final void Function() _sendKeepAlive;
  final void Function() _sendPing;
  final void Function(DisconnectReason reason) _close;

  int _responsesNeeded;
  int _bytesSent = 0;
  int _bytesReceived = 0;
  bool _started = false;
  bool _helloSeen = false;
  bool _healthy = false;
  bool _stopped = false;
  bool _probing = false;

  Timer? _keepAliveTimer;
  Timer? _healthTimer;
  Timer? _extraPingTimer;
  Timer? _idleTimer;

  /// The socket opened: arms the keep-alive and the health timer (3.4: the 30 s timer starts with
  /// the connection).
  void start() {
    if (_stopped || _started) {
      return;
    }
    _started = true;
    _armKeepAlive();
    _healthTimer = Timer(_timings.healthyTimeout, _onHealthTimeout);
  }

  /// The hello arrived: arms the extra ping (`ConnectionTimings.extraPingDelay`, 3.4) and the
  /// dead-link probe.
  void onHello() {
    if (_stopped || _helloSeen) {
      return;
    }
    _helloSeen = true;
    // Connection.ts:466-474: a transport that needs no responses is healthy at once.
    if (_responsesNeeded <= 0) {
      _markHealthy();
    } else {
      _extraPingTimer = Timer(_timings.extraPingDelay, () {
        _extraPingTimer = null;
        _pingIfUnhealthy();
      });
    }
    _armIdleProbe();
  }

  /// A frame of [units] UTF-16 code units was sent: re-arms the keep-alive, counts bytes sent.
  void onFrameSent(int units) {
    if (_stopped) {
      return;
    }
    _bytesSent += units;
    _armKeepAlive();
  }

  /// A frame of [units] UTF-16 code units arrived: re-arms the keep-alive and the dead-link probe,
  /// counts bytes received.
  void onFrameReceived(int units) {
    if (_stopped) {
      return;
    }
    _bytesReceived += units;
    _armKeepAlive();
    if (_helloSeen) {
      _armIdleProbe();
    }
  }

  /// A data message or, with [isPong], a pong arrived: counts toward health; while not healthy
  /// after a pong, pings again (3.4, Connection.ts:370-373: only a pong triggers the next ping).
  void onResponse({bool isPong = false}) {
    if (_stopped) {
      return;
    }
    if (!_healthy) {
      _responsesNeeded--;
      if (_responsesNeeded <= 0) {
        _markHealthy();
      }
    }
    if (isPong) {
      _pingIfUnhealthy();
    }
  }

  /// Whether the connection has met the health rule of 3.4.
  bool get isHealthy => _healthy;

  /// Cancels every timer; nothing can be re-armed afterwards.
  void stop() {
    _stopped = true;
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    _healthTimer?.cancel();
    _healthTimer = null;
    _extraPingTimer?.cancel();
    _extraPingTimer = null;
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  void _markHealthy() {
    _healthy = true;
    _healthTimer?.cancel();
    _healthTimer = null;
  }

  void _pingIfUnhealthy() {
    if (!_stopped && _helloSeen && !_healthy) {
      _sendPing();
    }
  }

  void _armKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer(_timings.keepAlive, _onKeepAlive);
  }

  void _onKeepAlive() {
    _keepAliveTimer = null;
    _sendKeepAlive();
    // The send normally re-arms through onFrameSent; re-arm here when it could not send.
    if (!_stopped && _keepAliveTimer == null) {
      _armKeepAlive();
    }
  }

  void _armIdleProbe() {
    _idleTimer?.cancel();
    _probing = false;
    _idleTimer = Timer(_timings.idleProbeAfter, _onIdle);
  }

  void _onIdle() {
    _idleTimer = null;
    if (_probing) {
      _close(DisconnectReason.deadLink);
      return;
    }
    _probing = true;
    _sendPing();
    if (!_stopped && _idleTimer == null) {
      _idleTimer = Timer(_timings.idleProbeTimeout, _onIdle);
    }
  }

  void _onHealthTimeout() {
    _healthTimer = null;
    if (_healthy) {
      return;
    }
    // Connection.ts:153-184: many bytes received count as healthy; many bytes sent leave the
    // connection alone (no proof they arrived) and it is never checked again.
    if (_bytesReceived > _timings.bytesReceivedHealthyOverride) {
      _healthy = true;
    } else if (_bytesSent > _timings.bytesSentHealthyOverride) {
      return;
    } else {
      _close(DisconnectReason.other);
    }
  }
}
