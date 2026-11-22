// Owner T. A protocol-level fake server over FakeWsConnector, still without sockets (test plan
// 2.3): it speaks `rtdb_protocol.md` 4 and 5 at message level, with the shapes measured on the
// emulator (`rtdb_emulator_probe.md`).

import 'dart:async';

import 'package:firebase_database_dart/src/realtime/transport/ws_channel.dart';

import 'fake_ws.dart';

/// A request the fake server received.
final class ServerSeen {
  /// Creates the record of request [r] with [action] and [body] on connection number
  /// [connection].
  const ServerSeen(this.connection, this.r, this.action, this.body);

  /// The number of the connection it arrived on, from 1.
  final int connection;

  /// The request number, or null for a request without one.
  final int? r;

  /// The action (`q`, `p`, `auth`, ...).
  final String action;

  /// The body.
  final Map<String, Object?> body;

  /// Shows the action and the numbers: the body may hold a token.
  @override
  String toString() => 'ServerSeen(#$connection r$r $action)';
}

/// A scripted Realtime Database server for the unit tests of `PersistentConnection`.
///
/// Push paths are given as `/a/b` and sent like the real server does: without the leading slash
/// (`a/b`, root `""`; emulator probe, measured). A ping is answered with a pong
/// `{"t":"c","d":{"t":"o","d":null}}` at any time.
///
/// Default answers, as measured: `q` pushes the stored value at its path (when there is one) and
/// answers `{}`; `g` answers the stored value (null when absent); `p` and `m` store, push `d` / `m`
/// to the listens of the same connection at or above the path, then answer `""`; `n` answers `""`
/// and ends the listen; `auth`/`gauth` answer `{"auth":null,"expires":null}`; `unauth` and
/// `unappcheck` answer `"unauthenticated"`; everything else answers `""`. A request without `r`
/// is answered with `r` 0. A frame that is not a JSON object, an unknown control type or a
/// request without an action gets the control error `e` and no answer (measured).
final class FakeRtdbServer {
  /// Creates the server. Every accepted connection gets a hello after [helloDelay] with session id
  /// [session] (the n-th connection, n >= 2, gets `<session>-<n>`) and host [host]; [clock] gives
  /// the hello `ts` in ms ([FakeWsConnector.helloEpochMs] plus [elapsed] when absent). [elapsed]
  /// gives the virtual time of the recorded frames and attempts.
  FakeRtdbServer({
    Duration helloDelay = Duration.zero,
    String session = 'sess-1',
    String host = 'h.example',
    int Function()? clock,
    Duration Function()? elapsed,
  }) : _helloDelay = helloDelay,
       _session = session,
       _host = host,
       _clock = clock,
       _elapsed = elapsed {
    _connector = FakeWsConnector(elapsed: elapsed, onAccept: _onAccept);
  }

  /// The control error the emulator sends for a frame it cannot use (measured).
  static const String incomingError =
      'ClientId[1]:ErrorId[1]: Error on incoming message';

  final Duration _helloDelay;
  final String _session;
  final String _host;
  final int Function()? _clock;
  final Duration Function()? _elapsed;
  late final FakeWsConnector _connector;
  final Map<String, Object?> _data = <String, Object?>{};
  final Map<String, Object? Function(Map<String, Object?> body)> _handlers =
      <String, Object? Function(Map<String, Object?> body)>{};
  final Map<String, List<(String, String?)>> _failures =
      <String, List<(String, String?)>>{};
  final List<ServerSeen> _log = <ServerSeen>[];
  final List<(_Link, int, Map<String, Object?>)> _held =
      <(_Link, int, Map<String, Object?>)>[];
  bool _holding = false;
  int _connections = 0;
  _Link? _current;

  /// The connector under the server, for scripting attempts.
  FakeWsConnector get connector => _connector;

  /// The closure to inject as the [WsConnector].
  WsConnector get connect => _connector.connect;

  /// A tiny in-memory tree, for the tests that need an echo (a put answered by a `d` push).
  /// Children are nested maps; the root is this map.
  Map<String, Object?> get data => _data;

  /// Answers every request of [action] with [handler]'s result as `d` and status `ok`.
  void respondTo(
    String action,
    Object? Function(Map<String, Object?> body) handler,
  ) {
    _handlers[action] = handler;
  }

  /// Answers the next request of [action] with [status] and [reason].
  void failNext(String action, String status, [String? reason]) {
    _failures.putIfAbsent(action, () => <(String, String?)>[]).add((
      status,
      reason,
    ));
  }

  /// Keeps responses back (sent, not acked) until [releaseResponses]. Pushes are not held.
  void holdResponses() {
    _holding = true;
  }

  /// Sends the held responses in order. A response whose connection has closed meanwhile is
  /// dropped: that request stays unacknowledged, as on a real server.
  void releaseResponses() {
    _holding = false;
    final List<(_Link, int, Map<String, Object?>)> held =
        List<(_Link, int, Map<String, Object?>)>.of(_held);
    _held.clear();
    for (final (_Link link, int r, Map<String, Object?> body) in held) {
      if (!link.channel.isClosed) {
        _sendResponse(link.channel, r, body);
      }
    }
  }

  /// Pushes `d` with [json] at [path], tagged with [tag] when given.
  void pushData(String path, Object? json, {int? tag}) {
    _push('d', <String, Object?>{'p': wirePath(path), 'd': json, 't': ?tag});
  }

  /// Pushes `m` with [changes] at [path], tagged with [tag] when given.
  void pushMerge(String path, Map<String, Object?> changes, {int? tag}) {
    _push('m', <String, Object?>{'p': wirePath(path), 'd': changes, 't': ?tag});
  }

  /// Pushes `rm` at [path] with [ranges] (`{"s":..,"e":..,"m":..}` entries as measured, their
  /// `s`/`e` paths sent without the leading slash), tagged with [tag] when given.
  void pushRangeMerge(
    String path,
    List<Map<String, Object?>> ranges, {
    int? tag,
  }) {
    final List<Map<String, Object?>> wireRanges = <Map<String, Object?>>[
      for (final Map<String, Object?> range in ranges)
        <String, Object?>{
          for (final MapEntry<String, Object?> entry in range.entries)
            entry.key:
                (entry.key == 's' || entry.key == 'e') && entry.value is String
                ? wirePath(entry.value! as String)
                : entry.value,
        },
    ];
    _push('rm', <String, Object?>{
      'p': wirePath(path),
      'd': wireRanges,
      't': ?tag,
    });
  }

  /// Pushes `c` for [path] with the query objects [queries] when given. Without them the body
  /// carries `"q":null`, as the emulator sends it (measured).
  void pushListenCancel(String path, [List<Map<String, Object?>>? queries]) {
    _push('c', <String, Object?>{'p': wirePath(path), 'q': queries});
  }

  /// Pushes `ac` with [status] and [explanation].
  void pushAuthRevoked(String status, String explanation) {
    _push('ac', <String, Object?>{'s': status, 'd': explanation});
  }

  /// Pushes `apc` with [status] and [explanation].
  void pushAppCheckRevoked(String status, String explanation) {
    _push('apc', <String, Object?>{'s': status, 'd': explanation});
  }

  /// Sends the control shutdown `s` with [reason].
  void pushShutdown(String reason) {
    _currentChannel().serverControl('s', reason);
  }

  /// Sends the control reset `r` with [host].
  void pushReset(String host) {
    _currentChannel().serverControl('r', host);
  }

  /// Every request received, with its connection number.
  List<ServerSeen> get log => List<ServerSeen>.unmodifiable(_log);

  /// The requests of [action] received, in order.
  List<ServerSeen> seen(String action) => <ServerSeen>[
    for (final ServerSeen s in _log)
      if (s.action == action) s,
  ];

  /// How many connections were accepted.
  int get connections => _connections;

  /// The path [path] as the server sends it: no leading slash, the root as `""`.
  static String wirePath(String path) =>
      path.startsWith('/') ? path.substring(1) : path;

  void _onAccept(FakeWsChannel channel, Uri url) {
    _connections++;
    final _Link link = _Link(_connections, channel);
    _current = link;
    channel.onClientFrame = (String frame) => _onFrame(link, frame);
    final String session = link.number == 1
        ? _session
        : '$_session-${link.number}';
    void hello() {
      if (channel.isClosed) {
        return;
      }
      final Duration elapsed = _elapsed?.call() ?? Duration.zero;
      final int ts =
          _clock?.call() ??
          FakeWsConnector.helloEpochMs + elapsed.inMilliseconds;
      channel.serverHello(ts: ts, h: _host, s: session);
    }

    if (_helloDelay == Duration.zero) {
      hello();
    } else {
      Timer(_helloDelay, hello);
    }
  }

  FakeWsChannel _currentChannel() {
    final _Link? link = _current;
    if (link == null || link.channel.isClosed) {
      throw StateError('no open connection to push on');
    }
    return link.channel;
  }

  void _push(String action, Map<String, Object?> body) {
    _currentChannel().serverPush(action, body);
  }

  void _onFrame(_Link link, String frame) {
    if (link.expected == 0) {
      if (frame == '0') {
        return;
      }
      final int? count = frame.length <= 6 ? int.tryParse(frame) : null;
      if (count != null && count > 0) {
        link.expected = count;
        return;
      }
      _onText(link, frame);
      return;
    }
    link.pieces.add(frame);
    if (link.pieces.length < link.expected) {
      return;
    }
    final String text = link.pieces.join();
    link.pieces.clear();
    link.expected = 0;
    _onText(link, text);
  }

  void _onText(_Link link, String text) {
    final Map<String, Object?>? message = ClientFrameJoiner.decodeObject(text);
    if (message == null) {
      link.channel.serverControl('e', incomingError);
      return;
    }
    _onMessage(link, message);
  }

  void _onMessage(_Link link, Map<String, Object?> message) {
    final Object? type = message['t'];
    final Object? inner = message['d'];
    if (inner is! Map<String, Object?>) {
      link.channel.serverControl('e', incomingError);
      return;
    }
    if (type == 'c') {
      if (inner['t'] == 'p' && inner['d'] is Map) {
        link.channel.serverControl('o');
      } else {
        link.channel.serverControl('e', incomingError);
      }
      return;
    }
    final Object? action = inner['a'];
    final Object? body = inner['b'];
    final Object? r = inner['r'];
    if (type != 'd' || action is! String || body is! Map<String, Object?>) {
      link.channel.serverControl('e', incomingError);
      return;
    }
    _log.add(ServerSeen(link.number, r is int ? r : null, action, body));
    _answer(link, r is int ? r : 0, action, body);
  }

  void _answer(_Link link, int r, String action, Map<String, Object?> body) {
    final List<(String, String?)>? failures = _failures[action];
    if (failures != null && failures.isNotEmpty) {
      final (String status, String? reason) = failures.removeAt(0);
      _respond(link, r, <String, Object?>{'s': status, 'd': reason});
      return;
    }
    final Object? Function(Map<String, Object?> body)? handler =
        _handlers[action];
    final Object? data = handler != null
        ? handler(body)
        : _defaultAnswer(link, action, body);
    _respond(link, r, <String, Object?>{'s': 'ok', 'd': data});
  }

  Object? _defaultAnswer(_Link link, String action, Map<String, Object?> body) {
    final String path = body['p'] is String
        ? wirePath(body['p']! as String)
        : '';
    switch (action) {
      case 'q':
        link.listens.add(path);
        final Object? value = _read(path);
        if (value != null) {
          link.channel.serverPush('d', <String, Object?>{
            'p': path,
            'd': value,
            't': ?body['t'],
          });
        }
        return <String, Object?>{};
      case 'n':
        link.listens.remove(path);
        return '';
      case 'g':
        return _read(path);
      case 'p':
        _write(path, body['d']);
        _echo(link, 'd', path, body['d']);
        return '';
      case 'm':
        final Object? changes = body['d'];
        if (changes is Map<String, Object?>) {
          for (final MapEntry<String, Object?> change in changes.entries) {
            _write(_child(path, change.key), change.value);
          }
        }
        _echo(link, 'm', path, changes);
        return '';
      case 'auth' || 'gauth':
        return <String, Object?>{'auth': null, 'expires': null};
      case 'unauth' || 'unappcheck':
        return 'unauthenticated';
      default:
        return '';
    }
  }

  void _respond(_Link link, int r, Map<String, Object?> body) {
    if (_holding) {
      _held.add((link, r, body));
      return;
    }
    _sendResponse(link.channel, r, body);
  }

  void _sendResponse(FakeWsChannel channel, int r, Map<String, Object?> body) {
    channel.serverMessage(<String, Object?>{
      't': 'd',
      'd': <String, Object?>{'r': r, 'b': body},
    });
  }

  void _echo(_Link link, String action, String path, Object? value) {
    for (final String listen in link.listens) {
      if (listen.isEmpty || path == listen || path.startsWith('$listen/')) {
        link.channel.serverPush(action, <String, Object?>{
          'p': path,
          'd': value,
        });
        return;
      }
    }
  }

  static String _child(String path, String key) {
    final String relative = wirePath(key);
    return path.isEmpty ? relative : '$path/$relative';
  }

  static List<String> _segments(String path) => <String>[
    for (final String s in path.split('/'))
      if (s.isNotEmpty) s,
  ];

  Object? _read(String path) {
    Object? node = _data;
    for (final String segment in _segments(path)) {
      if (node is! Map<String, Object?>) {
        return null;
      }
      node = node[segment];
    }
    if (node is Map && node.isEmpty) {
      return null;
    }
    return node;
  }

  void _write(String path, Object? value) {
    final List<String> segments = _segments(path);
    if (segments.isEmpty) {
      _data.clear();
      if (value is Map<String, Object?>) {
        _data.addAll(value);
      }
      return;
    }
    Map<String, Object?> node = _data;
    for (final String segment in segments.take(segments.length - 1)) {
      final Object? child = node[segment];
      if (child is Map<String, Object?>) {
        node = child;
      } else {
        final Map<String, Object?> created = <String, Object?>{};
        node[segment] = created;
        node = created;
      }
    }
    if (value == null) {
      node.remove(segments.last);
    } else {
      node[segments.last] = value;
    }
  }
}

/// One accepted connection: its number, its channel, its frame buffer and its listens.
final class _Link {
  _Link(this.number, this.channel);

  final int number;
  final FakeWsChannel channel;
  final List<String> pieces = <String>[];
  final Set<String> listens = <String>{};
  int expected = 0;
}
