// A local TCP proxy that makes a loopback connection behave like a slower network: each direction delays
// every chunk by half the round-trip time and, optionally, caps the bandwidth of that direction (shared by all
// connections through the proxy, like one link). It reads from a socket only while fewer than a megabyte of
// its data wait to be released, so a fast sender cannot make the proxy (in the process of the benchmark) hold
// the whole upload in memory.
//
// The TCP handshake of a new connection is not delayed; a request and its response are.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// One direction of the link: the time at which it is free again.
class _Link {
  _Link(this.clock);

  final Stopwatch clock;
  int freeAtMicros = 0;
}

/// Copies `source` to `sink`, delayed.
class _Pipe {
  _Pipe(
    this._source,
    this._sink,
    this._link,
    this._oneWay,
    this._bytesPerSecond,
    this._onFailure,
  ) {
    _subscription = _source.listen(
      _onData,
      onDone: _onDone,
      onError: (Object _) => _onFailure(),
    );
  }

  static const int _highWater = 1024 * 1024;
  static const int _lowWater = 256 * 1024;

  final Socket _source;
  final Socket _sink;
  final _Link _link;
  final Duration _oneWay;
  final double _bytesPerSecond;
  final void Function() _onFailure;
  late final StreamSubscription<Uint8List> _subscription;
  int _waiting = 0;

  void _onData(Uint8List data) {
    final int now = _link.clock.elapsedMicroseconds;
    final int start = math.max(now, _link.freeAtMicros);
    final int serialize = _bytesPerSecond <= 0
        ? 0
        : (data.length * 1e6 / _bytesPerSecond).round();
    _link.freeAtMicros = start + serialize;
    final int release = _link.freeAtMicros + _oneWay.inMicroseconds;
    _waiting += data.length;
    if (_waiting > _highWater) {
      _subscription.pause();
    }
    Timer(Duration(microseconds: math.max(0, release - now)), () {
      try {
        _sink.add(data);
      } on Object {
        _onFailure();
        return;
      }
      _waiting -= data.length;
      if (_subscription.isPaused && _waiting <= _lowWater) {
        _subscription.resume();
      }
    });
  }

  void _onDone() {
    final int now = _link.clock.elapsedMicroseconds;
    final int release = _link.freeAtMicros + _oneWay.inMicroseconds;
    Timer(Duration(microseconds: math.max(0, release - now)), () {
      unawaited(_sink.close().catchError((Object _) {}));
    });
  }

  void cancel() => unawaited(_subscription.cancel());
}

/// A proxy to `targetHost:targetPort` on a port of its own, on 127.0.0.1.
class DelayProxy {
  DelayProxy._(
    this._server,
    this._targetHost,
    this._targetPort,
    this._oneWay,
    this._bytesPerSecond,
  ) {
    _server.listen(_accept);
  }

  /// Starts a proxy that adds `rtt` to every round trip and caps each direction at `bandwidthMbit` megabits per
  /// second (0 for no cap).
  static Future<DelayProxy> start({
    required String targetHost,
    required int targetPort,
    required Duration rtt,
    double bandwidthMbit = 0,
  }) async {
    final ServerSocket server = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    return DelayProxy._(
      server,
      targetHost,
      targetPort,
      rtt ~/ 2,
      bandwidthMbit * 1e6 / 8,
    );
  }

  final ServerSocket _server;
  final String _targetHost;
  final int _targetPort;
  final Duration _oneWay;
  final double _bytesPerSecond;
  final Stopwatch _clock = Stopwatch()..start();
  late final _Link _up = _Link(_clock);
  late final _Link _down = _Link(_clock);
  final Set<Socket> _sockets = <Socket>{};

  /// `127.0.0.1:<port>`, for `FirebaseStorage(emulatorHost: ...)`.
  String get address => '127.0.0.1:${_server.port}';

  Future<void> _accept(Socket client) async {
    final Socket upstream;
    try {
      upstream = await Socket.connect(_targetHost, _targetPort);
    } on SocketException {
      client.destroy();
      return;
    }
    client.setOption(SocketOption.tcpNoDelay, true);
    upstream.setOption(SocketOption.tcpNoDelay, true);
    _sockets
      ..add(client)
      ..add(upstream);
    late final _Pipe forward;
    late final _Pipe backward;
    void fail() {
      forward.cancel();
      backward.cancel();
      client.destroy();
      upstream.destroy();
      _sockets
        ..remove(client)
        ..remove(upstream);
    }

    forward = _Pipe(client, upstream, _up, _oneWay, _bytesPerSecond, fail);
    backward = _Pipe(upstream, client, _down, _oneWay, _bytesPerSecond, fail);
  }

  /// Stops listening and drops every connection.
  Future<void> close() async {
    await _server.close();
    for (final Socket socket in _sockets.toList()) {
      socket.destroy();
    }
    _sockets.clear();
  }
}
