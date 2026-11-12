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
class KeepAliveTransportConnector implements ClientTransportConnector {
  KeepAliveTransportConnector({
    required this.host,
    required this.port,
    required this.credentials,
    required this.pingInterval,
    required this.pingTimeout,
    this.connectTimeout,
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

  Socket? _socket;

  @override
  Future<ClientTransportConnection> connect() async {
    Socket socket = await Socket.connect(host, port, timeout: connectTimeout);
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
    return KeepAliveTransportConnection(
      ClientTransportConnection.viaSocket(socket),
      pingInterval: pingInterval,
      pingTimeout: pingTimeout,
    );
  }

  @override
  Future<void> get done => _socket!.done;

  @override
  void shutdown() => _socket?.destroy();

  @override
  String get authority =>
      credentials.authority ?? (port == 443 ? host : '$host:$port');
}

/// Decorates a [ClientTransportConnection] with the keepalive logic of
/// [KeepAliveTransportConnector].
class KeepAliveTransportConnection implements ClientTransportConnection {
  KeepAliveTransportConnection(
    this._inner, {
    required this.pingInterval,
    required this.pingTimeout,
  }) {
    _inner.onActiveStateChanged = _onActiveStateChanged;
    _frames = _inner.onFrameReceived.listen((_) => _onFrameReceived());
  }

  final ClientTransportConnection _inner;
  final Duration pingInterval;
  final Duration pingTimeout;

  late final StreamSubscription<void> _frames;
  ActiveStateHandler? _activeStateHandler;
  bool _active = false;
  final Stopwatch _sinceLastFrame = Stopwatch()..start();
  Timer? _pingTimer;
  Timer? _timeoutTimer;

  void _onActiveStateChanged(bool isActive) {
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
        _inner.terminate().catchError((Object _) {});
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
  }) => _inner.makeRequest(headers, endStream: endStream);

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
    _cancelTimers();
    return _inner.finish();
  }

  @override
  Future<void> terminate([int? errorCode]) {
    _cancelTimers();
    _frames.cancel();
    return _inner.terminate(errorCode);
  }
}
