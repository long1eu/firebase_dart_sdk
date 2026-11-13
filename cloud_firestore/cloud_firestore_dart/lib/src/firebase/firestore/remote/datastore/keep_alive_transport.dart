// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:async';
import 'dart:io';

import 'package:grpc/grpc.dart';
import 'package:http2/transport.dart';
import 'package:meta/meta.dart';

import 'flow_control_window.dart';

/// A [ClientTransportConnector] that detects dead connections.
///
/// The Android SDK relies on gRPC's keepalive to tear down a connection that
/// the OS never reported as closed ("half-dead"), so that the Listen and Write
/// streams fail with UNAVAILABLE and get re-established. `package:grpc` has
/// [ClientKeepAliveOptions], but when a ping times out it only calls
/// `ClientTransportConnection.finish()`, which waits for the calls that are in
/// flight, and those are exactly the long-lived streams that are hung. This
/// connector pings the same way (only while there are active calls) and
/// terminates the connection forcefully when no frame arrives in time.
///
/// It also keeps `package:grpc` from reconnecting in a tight loop. When a
/// connection is established and then lost before a call could use it (the
/// peer closes it at once, or sends GOAWAY: a load balancer without a backend,
/// a captive portal, a TLS-terminating middlebox), gRPC keeps the calls that
/// are waiting and connects again immediately, about 40 times per second,
/// without ever failing a call, so the backoff of the streams never applies.
/// This connector fails the connection attempt that follows such a connection
/// instead of connecting: gRPC then fails the waiting calls with UNAVAILABLE,
/// and the streams retry with their exponential backoff, like they do when
/// the connection is refused.
class KeepAliveTransportConnector implements ClientTransportConnector {
  KeepAliveTransportConnector({
    required this.host,
    required this.port,
    required this.credentials,
    required this.pingInterval,
    required this.pingTimeout,
    this.connectTimeout,
    this.uselessConnectionWindow = const Duration(seconds: 10),
    this.flowControlWindow = http2DefaultWindowSize,
  });

  final String host;
  final int port;
  final ChannelCredentials credentials;

  /// How often to ping while there are active calls.
  final Duration pingInterval;

  /// How long to wait for any frame after a ping before the connection is
  /// terminated.
  final Duration pingTimeout;

  /// The timeout of a single connection attempt.
  final Duration? connectTimeout;

  /// A new connection is asked for this soon after the previous one was
  /// established, and no call was ever started on the previous one: that
  /// connection was lost before it was of any use.
  final Duration uselessConnectionWindow;

  /// The HTTP/2 receive window of the connection and of each stream, in bytes; see [FlowControlWindow].
  final int flowControlWindow;

  Socket? _socket;
  KeepAliveTransportConnection? _connection;
  final Stopwatch _sinceConnected = Stopwatch();

  /// The number of connections that were opened, and the number of attempts
  /// that were failed without connecting because the previous connection was
  /// useless.
  @visibleForTesting
  int connectionsOpened = 0;
  @visibleForTesting
  int attemptsFailedFast = 0;

  @override
  Future<ClientTransportConnection> connect() async {
    final KeepAliveTransportConnection? previous = _connection;
    _connection = null;
    if (previous != null &&
        !previous.wasUsed &&
        !previous.closedByClient &&
        _sinceConnected.elapsed < uselessConnectionWindow) {
      // gRPC does not close a connection that it abandons after a GOAWAY.
      _socket?.destroy();
      attemptsFailedFast++;
      throw SocketException(
        'The previous connection to $host:$port was lost before a call could '
        'use it; not reconnecting right away',
      );
    }

    Socket socket = await Socket.connect(host, port, timeout: connectTimeout);
    connectionsOpened++;
    // Don't wait for io buffers to fill up before sending requests.
    socket.setOption(SocketOption.tcpNoDelay, true);
    final SecurityContext? context = credentials.securityContext;
    if (context != null) {
      socket = await SecureSocket.secure(
        socket,
        host: credentials.authority ?? host,
        context: context,
        onBadCertificate: (X509Certificate certificate) {
          final BadCertificateHandler? handler = credentials.onBadCertificate;
          return handler != null && handler(certificate, authority);
        },
      );
    }
    _socket = socket;
    final ClientTransportConnection transport = await _openTransport(socket);
    _sinceConnected
      ..reset()
      ..start();
    return _connection = KeepAliveTransportConnection(
      transport,
      pingInterval: pingInterval,
      pingTimeout: pingTimeout,
      destroySocket: socket.destroy,
    );
  }

  /// Starts HTTP/2 on [socket] with the [flowControlWindow]. Another window than the default of HTTP/2 is only
  /// returned once the server acknowledged it (see [FlowControlWindow]).
  Future<ClientTransportConnection> _openTransport(Socket socket) async {
    if (flowControlWindow == http2DefaultWindowSize) {
      return ClientTransportConnection.viaSocket(socket);
    }
    final ClientSettings settings = ClientSettings(
      streamWindowSize: flowControlWindow,
    );
    final FlowControlWindow window = FlowControlWindow(flowControlWindow);
    final ClientTransportConnection transport =
        ClientTransportConnection.viaStreams(
          window.bindIncoming(socket),
          window.bindOutgoing(socket),
          settings: settings,
        );
    try {
      await window.settingsAcknowledged.timeout(
        connectTimeout ?? const Duration(seconds: 20),
      );
    } catch (e) {
      unawaited(transport.terminate().catchError((Object _) {}));
      socket.destroy();
      throw SocketException(
        'The HTTP/2 settings were not acknowledged by $host:$port ($e)',
      );
    }
    return transport;
  }

  @override
  Future<void> get done => _socket!.done;

  @override
  void shutdown() {
    _connection?.closedByClient = true;
    _socket?.destroy();
  }

  @override
  String get authority =>
      credentials.authority ?? (port == 443 ? host : '$host:$port');
}

/// How long [KeepAliveTransportConnection.terminate] waits for the HTTP/2
/// connection to close before it destroys the socket.
///
/// The Android SDK gives the channel one second to shut down gracefully and
/// then shuts it down forcefully (`GrpcCallProvider.shutdown`:
/// `awaitTermination(1, SECONDS)`, then `shutdownNow()`).
const Duration gracefulTerminateTimeout = Duration(seconds: 1);

/// Decorates a [ClientTransportConnection] with the keepalive logic of
/// [KeepAliveTransportConnector].
class KeepAliveTransportConnection implements ClientTransportConnection {
  KeepAliveTransportConnection(
    this._inner, {
    required this.pingInterval,
    required this.pingTimeout,
    required void Function() destroySocket,
  }) : _destroySocket = destroySocket {
    _inner.onActiveStateChanged = _onActiveStateChanged;
    _frames = _inner.onFrameReceived.listen((_) => _onFrameReceived());
  }

  final ClientTransportConnection _inner;
  final Duration pingInterval;
  final Duration pingTimeout;
  final void Function() _destroySocket;

  late final StreamSubscription<void> _frames;
  ActiveStateHandler? _activeStateHandler;
  bool _active = false;
  final Stopwatch _sinceLastFrame = Stopwatch()..start();
  Timer? _pingTimer;
  Timer? _timeoutTimer;

  /// Whether a call was ever started on this connection. gRPC does not start
  /// one on a connection that is already closed (or that got a GOAWAY) when
  /// it is ready to.
  bool wasUsed = false;

  /// Whether the client closed the connection itself.
  bool closedByClient = false;

  /// Whether the client terminated the connection.
  bool _terminated = false;

  void _onActiveStateChanged(bool isActive) {
    if (_terminated) {
      // The calls of a terminated connection end after gRPC shut it down.
      // Reporting that would make gRPC start its idle timer (five minutes)
      // on the shut down channel, which keeps the isolate alive.
      return;
    }
    _active = isActive;
    if (isActive) {
      // Like gRPC, don't reset the time since the last frame so that a
      // connection that was idle for long gets checked quickly.
      _schedulePing();
    } else {
      _cancelTimers();
    }
    _activeStateHandler?.call(isActive);
  }

  void _onFrameReceived() {
    _sinceLastFrame
      ..reset()
      ..start();
    // Any frame proves that the connection is alive.
    if (_timeoutTimer != null) {
      _timeoutTimer!.cancel();
      _timeoutTimer = null;
      if (_active) {
        _schedulePing();
      }
    }
  }

  void _schedulePing() {
    if (_timeoutTimer != null) {
      return;
    }
    _pingTimer?.cancel();
    final Duration remaining = pingInterval - _sinceLastFrame.elapsed;
    _pingTimer = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      _pingTimer = null;
      if (!_active || !_inner.isOpen) {
        return;
      }
      if (_sinceLastFrame.elapsed < pingInterval) {
        // Data arrived in the meantime, check again later.
        _schedulePing();
        return;
      }
      // The ping fails when the connection is terminated, nobody waits for it.
      _inner.ping().catchError((Object _) {});
      _timeoutTimer = Timer(pingTimeout, () {
        _timeoutTimer = null;
        _cancelTimers();
        // The pending calls fail with the connection error.
        _terminateInner(null).catchError((Object _) {});
      });
    });
  }

  void _cancelTimers() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
  }

  @override
  set onActiveStateChanged(ActiveStateHandler callback) =>
      _activeStateHandler = callback;

  @override
  bool get isOpen => _inner.isOpen;

  @override
  ClientTransportStream makeRequest(
    List<Header> headers, {
    bool endStream = false,
  }) {
    wasUsed = true;
    return _inner.makeRequest(headers, endStream: endStream);
  }

  @override
  Future<void> ping() => _inner.ping();

  @override
  Future<void> get onInitialPeerSettingsReceived =>
      _inner.onInitialPeerSettingsReceived;

  @override
  Stream<int> get onPingReceived => _inner.onPingReceived;

  @override
  Stream<void> get onFrameReceived => _inner.onFrameReceived;

  @override
  Future<void> finish() {
    closedByClient = true;
    _cancelTimers();
    return _inner.finish();
  }

  @override
  Future<void> terminate([int? errorCode]) {
    closedByClient = true;
    _terminated = true;
    _cancelTimers();
    _frames.cancel();
    return _terminateInner(errorCode);
  }

  /// Terminates the HTTP/2 connection, and destroys the socket when that does
  /// not complete in [gracefulTerminateTimeout].
  ///
  /// `package:http2` closes its side and then waits for the socket to be done.
  /// When the peer dropped the connection while a request was on its way out,
  /// and the client did not read that yet, that never happens: the read side
  /// is cancelled first, so the socket never learns that the peer is gone, and
  /// it stays open.
  Future<void> _terminateInner(int? errorCode) {
    // The future of package:http2 is not a Future<void> at runtime.
    final Future<void> terminated = _inner.terminate(errorCode).then((_) {});
    return terminated.timeout(
      gracefulTerminateTimeout,
      onTimeout: _destroySocket,
    );
  }
}
