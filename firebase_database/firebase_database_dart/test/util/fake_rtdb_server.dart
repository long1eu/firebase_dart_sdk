// Owner T. A protocol-level fake server over FakeWsConnector, still without sockets (test plan
// 2.3): it speaks `rtdb_protocol.md` 4 and 5 at message level, with the shapes measured on the
// emulator (`rtdb_emulator_probe.md`).

import 'dart:async';

import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/realtime/framing.dart';

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
/// Default answers, as measured (`rtdb_emulator_probe.md`, "Listen details", "Server values",
/// "Control messages and errors", "Frame and message limits"):
/// - `q` records a listen (one per request; a reused tag replaces the listen with that tag) and
///   answers `{}`, after a `d` push of the stored value unless the request's `h` equals the
///   server's hash of it (no push then). `n` ends one matching listen and answers `""`.
/// - `p` and `m` store with server values (`{".sv":...}`) resolved, push the resolved value once
///   per open listen that overlaps the path (each with its own tag), then answer `""`. A `p` with
///   `h` is a compare-and-set: on a mismatch it answers `datastale` and writes nothing, on a match
///   it answers the new value. A `m` ignores `h`.
/// - `g` answers the stored value (null when absent); `auth`/`gauth` answer
///   `{"auth":null,"expires":null}`; `unauth` and `unappcheck` answer `"unauthenticated"`;
///   everything else answers `""`. A request without `r` is answered with `r` 0.
/// - A frame that is not a JSON object, an unknown control type or action, a key with `.`, `#`,
///   `$`, `[`, `]` or `/` (`.priority`, `.value`, `.sv` excepted) or an unknown server value gets
///   the control error `e` and no answer. A path with `.` or `$` in a segment (a last `.priority`
///   excepted: `setPriority` writes there) is answered `invalid_parameters`.
///   A `q` or `p` without `p` closes the socket with 1006. A query listen without a tag is
///   answered `internal_error`, then a reset `r` and a 1006 close.
/// - A client frame over 65536 UTF-8 bytes closes with 1002; a message over 16 MiB with 1006.
/// - With the constructor's `idleClose`, a connection without a client frame for that long is
///   closed with 1006 (the emulator: [measuredIdleClose]).
///
/// The constructor's flags turn the hash checks, the server values and the request validation
/// off for tests that need the simple form.
final class FakeRtdbServer {
  /// Creates the server. Every accepted connection gets a hello after [helloDelay] with session id
  /// [session] (the n-th connection, n >= 2, gets `<session>-<n>`) and host [host]; [clock] gives
  /// the hello `ts` and the server timestamp in ms ([FakeWsConnector.helloEpochMs] plus [elapsed]
  /// when absent). [elapsed] gives the virtual time of the recorded frames and attempts.
  ///
  /// [checkHashes] compares listen and put hashes with the stored data (measured); off, a listen
  /// pushes whenever there is data and a hashed put is a plain put. [resolveServerValues] resolves
  /// `.sv` in writes (measured); off, they are stored and pushed as sent. [validateRequests]
  /// applies the measured answers to malformed requests and the frame limits; off, every request
  /// is answered. [idleClose] closes a connection silent from the client side for that long; null
  /// (the default, so that no timer is left pending) never does.
  FakeRtdbServer({
    Duration helloDelay = Duration.zero,
    String session = 'sess-1',
    String host = 'h.example',
    int Function()? clock,
    Duration Function()? elapsed,
    bool checkHashes = true,
    bool resolveServerValues = true,
    bool validateRequests = true,
    Duration? idleClose,
  }) : _helloDelay = helloDelay,
       _session = session,
       _host = host,
       _clock = clock,
       _elapsed = elapsed,
       _checkHashes = checkHashes,
       _resolveServerValues = resolveServerValues,
       _validateRequests = validateRequests,
       _idleClose = idleClose {
    _connector = FakeWsConnector(elapsed: elapsed, onAccept: _onAccept);
  }

  /// The idle close of the emulator: 120 s without a frame from the client (measured).
  static const Duration measuredIdleClose = Duration(seconds: 120);

  /// The largest client frame the emulator accepts: 65536 bytes (measured; 65537 closes 1002).
  static const int maxFrameBytes = 65536;

  /// The largest client message the fake accepts, in characters (measured: 16777080 passed,
  /// 17.8 MB dropped the socket with 1006).
  static const int maxMessageChars = 16 * 1024 * 1024;

  /// The answer of a hashed put on a mismatch (measured).
  static const String staleReason = 'Transaction ETag does not match';

  /// The control error the emulator sends for a frame it cannot use (measured).
  static const String incomingError =
      'ClientId[1]:ErrorId[1]: Error on incoming message';

  final Duration _helloDelay;
  final String _session;
  final String _host;
  final int Function()? _clock;
  final Duration Function()? _elapsed;
  final bool _checkHashes;
  final bool _resolveServerValues;
  final bool _validateRequests;
  final Duration? _idleClose;
  late final FakeWsConnector _connector;
  final List<_Link> _links = <_Link>[];
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

  int _now() {
    final Duration elapsed = _elapsed?.call() ?? Duration.zero;
    return _clock?.call() ??
        FakeWsConnector.helloEpochMs + elapsed.inMilliseconds;
  }

  void _onAccept(FakeWsChannel channel, Uri url) {
    _connections++;
    final _Link link = _Link(_connections, channel);
    _current = link;
    _links.add(link);
    channel
      ..onClientFrame = ((String frame) => _onFrame(link, frame))
      ..onClosed = () {
        link.idleTimer?.cancel();
        _links.remove(link);
      };
    final String session = link.number == 1
        ? _session
        : '$_session-${link.number}';
    void hello() {
      if (!channel.isClosed) {
        channel.serverHello(ts: _now(), h: _host, s: session);
      }
    }

    if (_helloDelay == Duration.zero) {
      hello();
    } else {
      Timer(_helloDelay, hello);
    }
    _armIdle(link);
  }

  void _armIdle(_Link link) {
    final Duration? idle = _idleClose;
    if (idle == null) {
      return;
    }
    link.idleTimer?.cancel();
    link.idleTimer = Timer(idle, () => _drop(link, 1006));
  }

  /// Closes [link] from the server side with [code], as the emulator does: no frame, no reason.
  void _drop(_Link link, int code) {
    link.pieces.clear();
    link.expected = 0;
    if (!link.channel.isClosed) {
      link.channel.serverClose(code);
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
    _armIdle(link);
    if (_validateRequests && utf8Length(frame) > maxFrameBytes) {
      _drop(link, 1002);
      return;
    }
    if (link.expected == 0) {
      if (frame == '0') {
        return;
      }
      final int? count = frame.length <= 6 ? int.tryParse(frame) : null;
      if (count != null && count > 0) {
        link.expected = count;
        link.pieceChars = 0;
        return;
      }
      _onText(link, frame);
      return;
    }
    link.pieces.add(frame);
    link.pieceChars += frame.length;
    if (_validateRequests && link.pieceChars > maxMessageChars) {
      _drop(link, 1006);
      return;
    }
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
      _controlError(link);
      return;
    }
    _onMessage(link, message);
  }

  void _controlError(_Link link) {
    link.channel.serverControl('e', incomingError);
  }

  void _onMessage(_Link link, Map<String, Object?> message) {
    final Object? type = message['t'];
    final Object? inner = message['d'];
    if (inner is! Map<String, Object?>) {
      _controlError(link);
      return;
    }
    if (type == 'c') {
      if (inner['t'] == 'p' && inner['d'] is Map) {
        link.channel.serverControl('o');
      } else {
        _controlError(link);
      }
      return;
    }
    final Object? action = inner['a'];
    final Object? body = inner['b'];
    final Object? r = inner['r'];
    if (type != 'd' || action is! String || body is! Map<String, Object?>) {
      _controlError(link);
      return;
    }
    _log.add(ServerSeen(link.number, r is int ? r : null, action, body));
    final int answerR = r is int ? r : 0;
    if (_validateRequests && _refused(link, answerR, action, body)) {
      return;
    }
    _answer(link, answerR, action, body);
  }

  static const Set<String> _knownActions = <String>{
    'q', 'n', 'g', 'p', 'm', 'o', 'om', 'oc', 's', //
    'auth', 'gauth', 'unauth', 'appcheck', 'unappcheck',
    // The production spelling (JS); the emulator refuses it (measured), the fake models
    // production here so that the production code path gets an answer.
    'unappeck',
  };

  static const Set<String> _pathActions = <String>{
    'q', 'n', 'g', 'p', 'm', 'o', 'om', 'oc', //
  };

  static const Set<String> _writeActions = <String>{'p', 'm', 'o', 'om'};

  /// Handles a malformed request the way the emulator does; true when it was handled.
  bool _refused(_Link link, int r, String action, Map<String, Object?> body) {
    if (!_knownActions.contains(action)) {
      _controlError(link);
      return true;
    }
    final Object? path = body['p'];
    if (_pathActions.contains(action)) {
      if (path is! String) {
        if (action == 'q' || action == 'p') {
          // Measured: the socket closes (1006) with no message.
          _drop(link, 1006);
        } else {
          _controlError(link);
        }
        return true;
      }
      if (_segments(path).any(
        (String segment) =>
            segment != '.priority' &&
            (segment.contains('.') || segment.contains(r'$')),
      )) {
        _respond(link, r, <String, Object?>{
          's': 'invalid_parameters',
          'd': 'Invalid token in path',
        });
        return true;
      }
    }
    final Object? query = body['q'];
    if (action == 'q' &&
        query is Map &&
        query.isNotEmpty &&
        body['t'] == null) {
      // Measured: the namespace goes down for 30 s; here the answer, the reset and the close.
      _respond(link, r, <String, Object?>{
        's': 'internal_error',
        'd': 'An internal error occurred',
      });
      link.channel.serverControl('r', _host);
      _drop(link, 1006);
      return true;
    }
    if (_writeActions.contains(action)) {
      final bool merge = action == 'm' || action == 'om';
      if (!_validData(body['d'], pathKeys: merge) ||
          (_resolveServerValues && _hasUnknownServerValue(body['d']))) {
        _controlError(link);
        return true;
      }
    }
    return false;
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
    final (String status, Object? data) = handler != null
        ? ('ok', handler(body))
        : _defaultAnswer(link, action, body);
    _respond(link, r, <String, Object?>{'s': status, 'd': data});
  }

  (String, Object?) _defaultAnswer(
    _Link link,
    String action,
    Map<String, Object?> body,
  ) {
    final String path = body['p'] is String
        ? _normalPath(body['p']! as String)
        : '';
    final Object? tag = body['t'];
    switch (action) {
      case 'q':
        _listen(link, path, tag is int ? tag : null, body['h']);
        return ('ok', <String, Object?>{});
      case 'n':
        final int index = link.listens.indexWhere(
          (_Listen l) => l.path == path && l.tag == tag,
        );
        if (index >= 0) {
          link.listens.removeAt(index);
        }
        return ('ok', '');
      case 'g':
        return ('ok', _read(path));
      case 'p':
        return _put(path, body);
      case 'm':
        _merge(path, body['d']);
        return ('ok', '');
      case 'auth' || 'gauth':
        return ('ok', <String, Object?>{'auth': null, 'expires': null});
      case 'unauth' || 'unappcheck' || 'unappeck':
        return ('ok', 'unauthenticated');
      default:
        return ('ok', '');
    }
  }

  void _listen(_Link link, String path, int? tag, Object? hash) {
    if (tag != null) {
      // Measured: reusing a tag replaces the listen that had it.
      link.listens.removeWhere((_Listen l) => l.tag == tag);
    }
    link.listens.add(_Listen(path, tag));
    final Object? value = _read(path);
    final bool clientIsCurrent = _checkHashes && hash is String
        ? hash == _hash(value)
        : value == null;
    if (!clientIsCurrent) {
      link.channel.serverPush('d', <String, Object?>{
        'p': path,
        'd': value,
        't': ?tag,
      });
    }
  }

  (String, Object?) _put(String path, Map<String, Object?> body) {
    final Object? hash = body['h'];
    if (_checkHashes && hash is String && hash != _hash(_read(path))) {
      return ('datastale', staleReason);
    }
    final Object? value = _resolve(path, body['d']);
    _write(path, value);
    _echoPut(path, value);
    // Measured: a hashed put that matched answers the new value.
    return ('ok', _checkHashes && hash is String ? value : '');
  }

  void _merge(String path, Object? changes) {
    if (changes is! Map<String, Object?>) {
      return;
    }
    final Map<String, Object?> resolved = <String, Object?>{
      for (final MapEntry<String, Object?> change in changes.entries)
        change.key: _resolve(_child(path, change.key), change.value),
    };
    resolved.forEach((String key, Object? value) {
      _write(_child(path, key), value);
    });
    for (final _Link link in _openLinks()) {
      for (final _Listen listen in link.listens) {
        if (_covers(listen.path, path)) {
          link.channel.serverPush('m', <String, Object?>{
            'p': path,
            'd': resolved,
            't': ?listen.tag,
          });
        } else if (_covers(path, listen.path)) {
          link.channel.serverPush('d', <String, Object?>{
            'p': listen.path,
            'd': _read(listen.path),
            't': ?listen.tag,
          });
        }
      }
    }
  }

  /// Pushes a put at [path] once per listen that overlaps it, with the listen's tag (measured).
  void _echoPut(String path, Object? value) {
    for (final _Link link in _openLinks()) {
      for (final _Listen listen in link.listens) {
        if (_covers(listen.path, path)) {
          link.channel.serverPush('d', <String, Object?>{
            'p': path,
            'd': value,
            't': ?listen.tag,
          });
        } else if (_covers(path, listen.path)) {
          link.channel.serverPush('d', <String, Object?>{
            'p': listen.path,
            'd': _read(listen.path),
            't': ?listen.tag,
          });
        }
      }
    }
  }

  List<_Link> _openLinks() => <_Link>[
    for (final _Link link in _links)
      if (!link.channel.isClosed) link,
  ];

  /// Whether [ancestor] is [path] or one of its ancestors (`""` is the root).
  static bool _covers(String ancestor, String path) =>
      ancestor.isEmpty || path == ancestor || path.startsWith('$ancestor/');

  /// The server's hash of [value]: the JS node hash, which the emulator uses (measured).
  static String _hash(Object? value) => nodeFromJson(value).hash();

  /// [value] with its server values resolved against the stored data under [path] (measured:
  /// `timestamp` is the server time in ms, `increment` adds to a stored number, 0 otherwise).
  Object? _resolve(String path, Object? value) {
    if (!_resolveServerValues || value is! Map<String, Object?>) {
      return value;
    }
    if (value.containsKey('.sv')) {
      final Object? sv = value['.sv'];
      if (sv == 'timestamp') {
        return _now();
      }
      final Object? increment = sv is Map ? sv['increment'] : null;
      final Object? stored = _read(path);
      return (stored is num ? stored : 0) + (increment is num ? increment : 0);
    }
    return <String, Object?>{
      for (final MapEntry<String, Object?> entry in value.entries)
        entry.key: _resolve(_child(path, entry.key), entry.value),
    };
  }

  static bool _hasUnknownServerValue(Object? value) {
    if (value is Map<String, Object?>) {
      if (value.containsKey('.sv')) {
        final Object? sv = value['.sv'];
        final bool known =
            sv == 'timestamp' ||
            (sv is Map && sv.length == 1 && sv['increment'] is num);
        return !known;
      }
      return value.values.any(_hasUnknownServerValue);
    }
    return false;
  }

  static final RegExp _badKeyChars = RegExp(r'[.#$\[\]/\x00-\x1F\x7F]');

  static const Set<String> _pseudoKeys = <String>{'.priority', '.value', '.sv'};

  /// Whether every key of [data] is a legal key (measured: a key with `.` gets the control
  /// error); with [pathKeys] the top-level keys are paths (a merge).
  static bool _validData(Object? data, {required bool pathKeys}) {
    if (data is! Map<String, Object?>) {
      return true;
    }
    for (final MapEntry<String, Object?> entry in data.entries) {
      final List<String> segments = pathKeys
          ? _segments(entry.key)
          : <String>[entry.key];
      if (segments.isEmpty && pathKeys) {
        return false;
      }
      for (final String key in segments) {
        if (key.isEmpty ||
            (!_pseudoKeys.contains(key) && _badKeyChars.hasMatch(key))) {
          return false;
        }
      }
      if (entry.key != '.sv' && !_validData(entry.value, pathKeys: false)) {
        return false;
      }
    }
    return true;
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

  static String _normalPath(String path) => _segments(path).join('/');

  static String _child(String path, String key) {
    final String relative = _normalPath(key);
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

/// One listen of a connection: its path (no leading slash) and its tag.
final class _Listen {
  _Listen(this.path, this.tag);

  final String path;
  final int? tag;
}

/// One accepted connection: its number, its channel, its frame buffer, its listens and its idle
/// timer.
final class _Link {
  _Link(this.number, this.channel);

  final int number;
  final FakeWsChannel channel;
  final List<String> pieces = <String>[];
  final List<_Listen> listens = <_Listen>[];
  int expected = 0;
  int pieceChars = 0;
  Timer? idleTimer;
}
