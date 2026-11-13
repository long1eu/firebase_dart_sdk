// A test-only TCP proxy that sits between a client and the emulator and misbehaves on demand.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// The direction of the bytes going through a [ChaosProxy].
enum ChaosDirection {
  /// From the client to the backend.
  up,

  /// From the backend to the client.
  down,
}

/// How a [ChaosProxy] treats the bytes it receives.
enum ChaosMode {
  /// Forwards the bytes (after [ChaosProxy.delay]).
  forward,

  /// Keeps the bytes without forwarding them and without closing anything: a connection that went silent. The bytes
  /// are forwarded, in order, when the mode goes back to [forward].
  stall,

  /// Like [stall], but only for the bytes going from the client to the backend: the answers of the backend to what
  /// it already received still arrive. Cutting after a moment in this mode loses requests but no answer.
  stallUp,

  /// Like [stall], but only for the bytes going from the backend to the client: the backend still receives (and
  /// applies) the requests. Cutting after a moment in this mode loses the answers.
  stallDown,

  /// Drops the bytes without closing anything. The connections that lost bytes are unusable, so going back to
  /// [forward] cuts them.
  blackHole,
}

/// A TCP proxy to `targetHost:targetPort`, controlled from a test:
///
///  * [cut] drops the open connections; with [refuseConnections] new ones are dropped as soon as they are accepted;
///  * [mode] stalls or black-holes the traffic without closing the connections;
///  * [delay] adds latency in both directions;
///  * [cutWhen] / [cutAfter] cut a connection mid-stream, at a moment chosen from the bytes that go through.
class ChaosProxy {
  ChaosProxy._(this._server, this._targetHost, this._targetPort);

  /// Starts a proxy on a free loopback port.
  static Future<ChaosProxy> start(String targetHost, int targetPort) async {
    final ServerSocket server =
        await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final ChaosProxy proxy = ChaosProxy._(server, targetHost, targetPort);
    server.listen(proxy._accept);
    return proxy;
  }

  ServerSocket _server;
  final String _targetHost;
  final int _targetPort;
  final Set<_Connection> _connections = <_Connection>{};
  bool _closed = false;

  late final String host = _server.address.address;

  /// The port stays the same across [unplug] and [plug].
  late final int port = _server.port;

  bool _unplugged = false;

  /// Stops listening and drops the open connections: connecting to the proxy fails (connection refused), as it does
  /// when the network is gone. [refuseConnections] is different: there the connection is established and then closed.
  Future<void> unplug() async {
    if (_unplugged || _closed) {
      return;
    }
    // Read the address before the socket goes away.
    host;
    port;
    _unplugged = true;
    cut();
    await _server.close();
  }

  /// Listens again on the same port after [unplug].
  Future<void> plug() async {
    if (!_unplugged || _closed) {
      return;
    }
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    _unplugged = false;
    _server.listen(_accept);
  }

  /// The latency added to every chunk, in both directions.
  Duration delay = Duration.zero;

  /// While true, new connections are closed as soon as they are accepted.
  bool refuseConnections = false;

  /// Called with every chunk before it is forwarded. Returning true cuts the connection instead of forwarding the
  /// chunk. It stays installed until it is cleared.
  bool Function(ChaosDirection direction, Uint8List data)? cutWhen;

  /// The number of connections accepted so far.
  int acceptedConnections = 0;

  /// The number of connections cut by the proxy so far.
  int cuts = 0;

  /// The bytes received from the clients and from the backend so far.
  int bytesUp = 0;
  int bytesDown = 0;

  ChaosMode _mode = ChaosMode.forward;

  ChaosMode get mode => _mode;

  set mode(ChaosMode value) {
    final ChaosMode previous = _mode;
    _mode = value;
    if (value != ChaosMode.forward) {
      return;
    }
    for (final _Connection connection in _connections.toList()) {
      if (previous == ChaosMode.blackHole && connection.lostBytes) {
        connection.destroy();
      } else {
        connection.flush();
      }
    }
  }

  /// The number of connections currently open.
  int get openConnections => _connections.length;

  /// Drops every open connection. New connections are still accepted (see [refuseConnections]).
  void cut() {
    for (final _Connection connection in _connections.toList()) {
      connection.destroy();
    }
  }

  /// Drops the connections and refuses new ones until [restore].
  void disconnect() {
    refuseConnections = true;
    cut();
  }

  /// Back to a working network: connections are accepted and the traffic is forwarded.
  void restore() {
    refuseConnections = false;
    cutWhen = null;
    mode = ChaosMode.forward;
  }

  /// Cuts the connection once [bytes] more bytes went in [direction] (the chunk that crosses the limit is not
  /// forwarded). Completes when the cut happened.
  Future<void> cutAfter(ChaosDirection direction, int bytes) {
    final Completer<void> done = Completer<void>();
    int seen = 0;
    cutWhen = (ChaosDirection d, Uint8List data) {
      if (d != direction) {
        return false;
      }
      seen += data.length;
      if (seen <= bytes) {
        return false;
      }
      cutWhen = null;
      done.complete();
      return true;
    };
    return done.future;
  }

  /// Cuts the connection at the next chunk in [direction] of at least [minBytes] bytes, without forwarding it.
  /// Completes when the cut happened.
  Future<void> cutOnNext(ChaosDirection direction, {int minBytes = 1}) {
    final Completer<void> done = Completer<void>();
    cutWhen = (ChaosDirection d, Uint8List data) {
      if (d != direction || data.length < minBytes) {
        return false;
      }
      cutWhen = null;
      done.complete();
      return true;
    };
    return done.future;
  }

  /// Completes once nothing came from the backend for [quiet] (or after [timeout]): the backend has answered what it
  /// received.
  Future<void> backendQuiet(
      {Duration quiet = const Duration(milliseconds: 400),
      Duration timeout = const Duration(seconds: 5)}) async {
    final Stopwatch total = Stopwatch()..start();
    final Stopwatch silence = Stopwatch()..start();
    int seen = bytesDown;
    while (silence.elapsed < quiet && total.elapsed < timeout) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      if (bytesDown != seen) {
        seen = bytesDown;
        silence.reset();
      }
    }
  }

  Future<void> close() async {
    _closed = true;
    cut();
    if (!_unplugged) {
      await _server.close();
    }
  }

  Future<void> _accept(Socket client) async {
    acceptedConnections++;
    if (refuseConnections || _closed) {
      client.destroy();
      return;
    }
    final Socket upstream;
    try {
      upstream = await Socket.connect(_targetHost, _targetPort);
    } on SocketException {
      client.destroy();
      return;
    }
    client.setOption(SocketOption.tcpNoDelay, true);
    upstream.setOption(SocketOption.tcpNoDelay, true);
    final _Connection connection = _Connection(this, client, upstream);
    _connections.add(connection);
    connection.start();
  }
}

class _Connection {
  _Connection(this._proxy, this._client, this._upstream);

  final ChaosProxy _proxy;
  final Socket _client;
  final Socket _upstream;

  /// What was received while the proxy stalled, in order. A null chunk is the end of that direction.
  final List<(ChaosDirection, Uint8List?)> _stalled =
      <(ChaosDirection, Uint8List?)>[];
  final Map<ChaosDirection, Future<void>> _tails =
      <ChaosDirection, Future<void>>{
    ChaosDirection.up: Future<void>.value(),
    ChaosDirection.down: Future<void>.value(),
  };
  final Map<ChaosDirection, int> _queued = <ChaosDirection, int>{
    ChaosDirection.up: 0,
    ChaosDirection.down: 0,
  };
  final Set<ChaosDirection> _ended = <ChaosDirection>{};
  bool _destroyed = false;

  /// Whether bytes of this connection were dropped by a black hole.
  bool lostBytes = false;

  Socket _target(ChaosDirection direction) =>
      direction == ChaosDirection.up ? _upstream : _client;

  void start() {
    // Writing to a socket the peer closed fails asynchronously: that is a closed connection, not a test failure.
    _client.done.catchError((Object _) {});
    _upstream.done.catchError((Object _) {});
    _pipe(_client, ChaosDirection.up);
    _pipe(_upstream, ChaosDirection.down);
  }

  void _pipe(Socket from, ChaosDirection direction) {
    from.listen(
      (Uint8List data) => _onData(direction, data),
      onError: (Object _) => destroy(countAsCut: false),
      onDone: () => _onData(direction, null),
    );
  }

  /// Handles a chunk received in [direction]; a null chunk is the end of that direction (the sender closed).
  void _onData(ChaosDirection direction, Uint8List? data) {
    if (_destroyed) {
      return;
    }
    if (data != null) {
      if (direction == ChaosDirection.up) {
        _proxy.bytesUp += data.length;
      } else {
        _proxy.bytesDown += data.length;
      }
      final bool Function(ChaosDirection, Uint8List)? cutWhen = _proxy.cutWhen;
      if (cutWhen != null && cutWhen(direction, data)) {
        destroy();
        return;
      }
    }
    final ChaosMode mode = _proxy.mode;
    final bool stalls = mode == ChaosMode.stall ||
        (mode == ChaosMode.stallUp && direction == ChaosDirection.up) ||
        (mode == ChaosMode.stallDown && direction == ChaosDirection.down);
    if (mode == ChaosMode.blackHole) {
      // Not even the end of the connection gets through.
      lostBytes = true;
    } else if (stalls) {
      _stalled.add((direction, data));
    } else {
      _forward(direction, data);
    }
  }

  /// Forwards a chunk (or the end of the direction) after the delay of the proxy, behind what is already queued in
  /// that direction: the order is kept, and nothing that was received is lost when the sender closes.
  void _forward(ChaosDirection direction, Uint8List? data) {
    final Duration delay = _proxy.delay;
    if (delay == Duration.zero && _queued[direction] == 0) {
      _deliver(direction, data);
      return;
    }
    _queued[direction] = _queued[direction]! + 1;
    _tails[direction] = _tails[direction]!.then((_) async {
      await Future<void>.delayed(delay);
      _queued[direction] = _queued[direction]! - 1;
      _deliver(direction, data);
    });
  }

  void _deliver(ChaosDirection direction, Uint8List? data) {
    if (_destroyed) {
      return;
    }
    if (data == null) {
      // The sender closed: close the other side for writing once everything is flushed, and drop the connection
      // when both directions ended.
      _ended.add(direction);
      if (_ended.length == 2) {
        _target(direction)
            .flush()
            .catchError((Object _) {})
            .whenComplete(() => destroy(countAsCut: false));
      } else {
        _target(direction).close().catchError((Object _) {});
      }
      return;
    }
    try {
      _target(direction).add(data);
    } catch (_) {
      destroy(countAsCut: false);
    }
  }

  /// Forwards what was kept while the proxy stalled.
  void flush() {
    final List<(ChaosDirection, Uint8List?)> stalled =
        List<(ChaosDirection, Uint8List?)>.of(_stalled);
    _stalled.clear();
    for (final (ChaosDirection direction, Uint8List? data) in stalled) {
      _forward(direction, data);
    }
  }

  void destroy({bool countAsCut = true}) {
    if (_destroyed) {
      return;
    }
    _destroyed = true;
    if (countAsCut) {
      _proxy.cuts++;
    }
    _proxy._connections.remove(this);
    _client.destroy();
    _upstream.destroy();
  }
}
