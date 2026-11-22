// Owner U. A test-only TCP proxy between the client and the emulator that misbehaves on demand;
// a copy of cloud_firestore_dart's test/util/chaos_proxy.dart (test plan 2.5) with one addition:
// a [ChaosFilter] (installed by ws_tap.dart) that sees every chunk first and decides what is
// forwarded, so faults can be placed on WebSocket frame boundaries.
//
// Runs only in the main session's integration runs (dart:io, real sockets).

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

  /// Keeps the bytes without forwarding or closing; forwards them in order on [forward].
  stall,

  /// Like [stall], only from the client to the backend.
  stallUp,

  /// Like [stall], only from the backend to the client: the backend still applies the requests.
  stallDown,

  /// Drops the bytes without closing; leaving this mode cuts the connections that lost bytes.
  blackHole,
}

/// One proxied connection, as a [ChaosFilter] sees it.
abstract interface class ChaosLink {
  /// The number of the connection (the one [ChaosProxy.tap] receives).
  int get id;

  /// Whether the connection was cut or ended.
  bool get isClosed;

  /// Hands [data] on in [direction], through the proxy's [ChaosProxy.mode] and
  /// [ChaosProxy.delay]. Does nothing once [isClosed].
  void send(ChaosDirection direction, Uint8List data);

  /// Cuts this connection (counted in [ChaosProxy.cuts]).
  void cut();
}

/// Sees every chunk a [ChaosProxy] receives, after [ChaosProxy.tap] and [ChaosProxy.cutWhen],
/// and decides what is forwarded by calling [ChaosLink.send] (nothing is forwarded otherwise).
/// The end of a direction (the sender closed) bypasses the filter.
abstract interface class ChaosFilter {
  /// Receives [data] that arrived on [link] in [direction].
  void onChunk(ChaosLink link, ChaosDirection direction, Uint8List data);

  /// [link] was cut or ended.
  void onClosed(ChaosLink link);
}

/// A TCP proxy to a target host and port on a free loopback port, controlled from a test:
///
///  * [cut] drops the open connections; with [refuseConnections] new ones are dropped as soon
///    as they are accepted;
///  * [mode] stalls or black-holes the traffic without closing the connections;
///  * [delay] adds latency in both directions;
///  * [cutWhen] / [cutAfter] cut a connection mid-stream, at a moment chosen from the bytes that
///    go through;
///  * [filter] decides chunk by chunk what is forwarded (the WebSocket tap).
final class ChaosProxy {
  ChaosProxy._(this._server, this._targetHost, this._targetPort);

  /// Starts a proxy to [targetHost]:[targetPort].
  static Future<ChaosProxy> start(String targetHost, int targetPort) async {
    final ServerSocket server = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final ChaosProxy proxy = ChaosProxy._(server, targetHost, targetPort);
    server.listen(proxy._accept);
    return proxy;
  }

  ServerSocket _server;
  final String _targetHost;
  final int _targetPort;
  final Set<_Connection> _connections = <_Connection>{};
  bool _closed = false;
  bool _unplugged = false;
  int _connectionCount = 0;

  /// The loopback address the proxy listens on.
  late final String host = _server.address.address;

  /// The port; the same across [unplug] and [plug].
  late final int port = _server.port;

  /// Stops listening and drops the open connections: connecting fails (refused), as it does when
  /// the network is gone. [refuseConnections] is different: there the connection is established
  /// and then closed.
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

  /// Called with every chunk received (`delivered` false) and handed on (`delivered` true), with
  /// the number of the connection. For the failure output of a test: it changes nothing.
  void Function(
    int connection,
    ChaosDirection direction,
    Uint8List data, {
    required bool delivered,
  })?
  tap;

  /// Called with every chunk before it is forwarded; true cuts the connection instead. It stays
  /// installed until it is cleared.
  bool Function(ChaosDirection direction, Uint8List data)? cutWhen;

  /// Decides what is forwarded (see [ChaosFilter]); null forwards every chunk as it comes.
  ChaosFilter? filter;

  int _acceptedConnections = 0;
  int _cuts = 0;
  int _bytesUp = 0;
  int _bytesDown = 0;
  int _answerBytesLostByCuts = 0;

  /// The number of connections accepted so far.
  int get acceptedConnections => _acceptedConnections;

  /// The number of connections cut by the proxy so far.
  int get cuts => _cuts;

  /// The bytes received from the clients so far.
  int get bytesUp => _bytesUp;

  /// The bytes received from the backend so far.
  int get bytesDown => _bytesDown;

  /// Backend bytes that a cut dropped before they reached the client (lost answers). Zero means
  /// that no cut so far lost an answer. Bytes a [filter] held back when the cut came count too;
  /// a filter that drops or rewrites frames makes this count meaningless.
  int get answerBytesLostByCuts => _answerBytesLostByCuts;

  /// Whether nothing waits in a delay queue: every request that was forwarded reached the
  /// backend, and every answer that was received was handed to the client. Stalled bytes do not
  /// count.
  bool get delayQueuesEmpty => _connections.every(
    (_Connection connection) =>
        connection._queued[ChaosDirection.up] == 0 &&
        connection._queued[ChaosDirection.down] == 0,
  );

  ChaosMode _mode = ChaosMode.forward;

  /// The current mode.
  ChaosMode get mode => _mode;

  /// Changes the mode (see [ChaosMode]).
  set mode(ChaosMode value) {
    final ChaosMode previous = _mode;
    _mode = value;
    if (previous == ChaosMode.blackHole && value != ChaosMode.blackHole) {
      // A connection that lost bytes has a hole in its byte stream that no real network
      // produces (TCP resends what was lost), so it is cut now.
      for (final _Connection connection in _connections.toList()) {
        if (connection.lostBytes) {
          connection.destroy();
        }
      }
    }
    if (value != ChaosMode.forward) {
      return;
    }
    for (final _Connection connection in _connections.toList()) {
      connection.flush();
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

  /// Cuts and refuses new connections until [restore].
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

  /// Cuts once [bytes] more bytes went in [direction] (the chunk that crosses the limit is not
  /// forwarded); completes when the cut happened.
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

  /// Cuts at the next chunk in [direction] of at least [minBytes] bytes, without forwarding it;
  /// completes when the cut happened.
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

  /// Completes once the delay queues are empty and the backend was quiet for [quiet], or after
  /// [timeout]: the backend received every request that was forwarded, and has answered it.
  Future<void> backendQuiet({
    Duration quiet = const Duration(milliseconds: 400),
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final Stopwatch total = Stopwatch()..start();
    final Stopwatch silence = Stopwatch()..start();
    int seen = _bytesDown;
    while ((silence.elapsed < quiet || !delayQueuesEmpty) &&
        total.elapsed < timeout) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      if (_bytesDown != seen || !delayQueuesEmpty) {
        seen = _bytesDown;
        silence.reset();
      }
    }
  }

  /// Stops the proxy.
  Future<void> close() async {
    _closed = true;
    cut();
    if (!_unplugged) {
      await _server.close();
    }
  }

  Future<void> _accept(Socket client) async {
    _acceptedConnections++;
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

final class _Connection implements ChaosLink {
  _Connection(this._proxy, this._client, this._upstream)
    : id = _proxy._connectionCount++;

  @override
  final int id;
  final ChaosProxy _proxy;
  final Socket _client;
  final Socket _upstream;

  /// What was received while the proxy stalled, in order. A null chunk is the end of that
  /// direction.
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

  /// The bytes received from the backend, and those handed to the client socket.
  int _downReceived = 0;
  int _downDelivered = 0;

  /// Whether bytes of this connection were dropped by a black hole.
  bool lostBytes = false;

  @override
  bool get isClosed => _destroyed;

  Socket _target(ChaosDirection direction) =>
      direction == ChaosDirection.up ? _upstream : _client;

  void start() {
    // Writing to a socket the peer closed fails asynchronously: that is a closed connection, not
    // a test failure.
    unawaited(_client.done.catchError((Object _) {}));
    unawaited(_upstream.done.catchError((Object _) {}));
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

  /// Handles a chunk received in [direction]; a null chunk is the end of that direction.
  void _onData(ChaosDirection direction, Uint8List? data) {
    if (_destroyed) {
      return;
    }
    if (data == null) {
      _route(direction, null);
      return;
    }
    if (direction == ChaosDirection.up) {
      _proxy._bytesUp += data.length;
    } else {
      _proxy._bytesDown += data.length;
      _downReceived += data.length;
    }
    _proxy.tap?.call(id, direction, data, delivered: false);
    final bool Function(ChaosDirection, Uint8List)? cutWhen = _proxy.cutWhen;
    if (cutWhen != null && cutWhen(direction, data)) {
      destroy();
      return;
    }
    final ChaosFilter? filter = _proxy.filter;
    if (filter == null) {
      _route(direction, data);
    } else {
      filter.onChunk(this, direction, data);
    }
  }

  @override
  void send(ChaosDirection direction, Uint8List data) {
    if (_destroyed) {
      return;
    }
    _route(direction, data);
  }

  @override
  void cut() => destroy();

  /// Applies the proxy's mode to a chunk (or the end of the direction).
  void _route(ChaosDirection direction, Uint8List? data) {
    final ChaosMode mode = _proxy.mode;
    final bool stalls =
        mode == ChaosMode.stall ||
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

  /// Forwards a chunk (or the end of the direction) after the delay of the proxy, behind what is
  /// already queued in that direction: the order is kept.
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
      // The sender closed: close the other side for writing once everything is flushed, and drop
      // the connection when both directions ended.
      _ended.add(direction);
      if (_ended.length == 2) {
        unawaited(
          _target(direction)
              .flush()
              .catchError((Object _) {})
              .whenComplete(() => destroy(countAsCut: false)),
        );
      } else {
        unawaited(_target(direction).close().catchError((Object _) {}));
      }
      return;
    }
    if (direction == ChaosDirection.down) {
      _downDelivered += data.length;
    }
    _proxy.tap?.call(id, direction, data, delivered: true);
    try {
      _target(direction).add(data);
    } on Object {
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
      _proxy._cuts++;
      _proxy._answerBytesLostByCuts += _downReceived - _downDelivered;
    }
    _proxy._connections.remove(this);
    _client.destroy();
    _upstream.destroy();
    _proxy.filter?.onClosed(this);
  }
}
