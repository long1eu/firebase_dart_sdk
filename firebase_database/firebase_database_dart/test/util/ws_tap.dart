// Owner U. WebSocket-aware observation and faults on top of ChaosProxy (test plan 2.5): parses the
// HTTP upgrade and the RFC 6455 frames, reassembles the RTDB envelopes, and acts on whole frames.
//
// Installed as the proxy's ChaosFilter, the tap holds the bytes of a direction until a whole
// frame arrived, and the frames of an RTDB message (count frame plus pieces) until the whole
// message arrived, then forwards them together: a rule never leaves half a message on the wire.
// Control frames (close, ping, pong) and the keep-alive `0` are forwarded at once. A connection
// whose first request is not a WebSocket upgrade (REST through the same port) is passed through
// untouched.
//
// Runs only in the main session's integration runs (dart:io sockets through the proxy).

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'chaos_proxy.dart';

/// One WebSocket frame seen by the tap.
final class TapFrame {
  /// Creates the record of a frame.
  const TapFrame(this.direction, this.opcode, this.text, this.receivedAt);

  /// [ChaosDirection.up] for client frames (masked on the wire), [ChaosDirection.down] for server
  /// frames.
  final ChaosDirection direction;

  /// The RFC 6455 opcode.
  final int opcode;

  /// The text of a text frame, else null. For a fragmented message (FIN 0 plus continuations)
  /// the frame that ends it carries the text of the whole message.
  final String? text;

  /// When the proxy received it.
  final DateTime receivedAt;

  /// Shows no text: a frame may hold a token.
  @override
  String toString() => 'TapFrame(${direction.name}, op $opcode)';
}

/// One RTDB envelope, re-assembled from a count frame and pieces.
final class TapMessage {
  /// Creates the record of [envelope] in [direction].
  const TapMessage(this.direction, this.envelope);

  /// Who sent it.
  final ChaosDirection direction;

  /// The decoded `{"t":..,"d":..}`.
  final Map<String, Object?> envelope;

  /// Shows the type only: the envelope may hold a token.
  @override
  String toString() => 'TapMessage(${direction.name}, ${envelope['t']})';
}

/// Frame-accurate observation and faults on a [ChaosProxy] (plugs into its `filter`).
///
/// The streams are broadcast streams: listen (or call [nextClient]) before the traffic that is
/// awaited. Rules and rewrites match the message as its sender sent it; [injectToClient] and
/// [closeToClient] go to the newest connection whose upgrade was answered with 101, and are not
/// reported on [frames] or [messages].
final class WsFrameTap implements ChaosFilter {
  /// Installs the tap on [proxy].
  WsFrameTap(ChaosProxy proxy) {
    proxy.filter = this;
  }

  final StreamController<TapFrame> _frames =
      StreamController<TapFrame>.broadcast();
  final StreamController<TapMessage> _messages =
      StreamController<TapMessage>.broadcast();
  final Map<ChaosLink, _Link> _links = <ChaosLink, _Link>{};
  _Link? _newest;

  Map<String, String> _upgradeHeaders = const <String, String>{};
  Uri? _upgradeUri;

  final List<_OneShot> _oneShots = <_OneShot>[];
  final List<bool Function(TapMessage m)> _drops =
      <bool Function(TapMessage m)>[];
  Duration _delay = Duration.zero;
  bool Function(TapMessage m)? _delayWhere;
  Map<String, Object?>? Function(Map<String, Object?> m)? _rewrite;

  /// Every frame, both directions.
  Stream<TapFrame> get frames => _frames.stream;

  /// Every re-assembled envelope, both directions.
  Stream<TapMessage> get messages => _messages.stream;

  /// The headers of the last upgrade request, names lowercased (repeated names joined with
  /// `, `); empty before the first upgrade.
  Map<String, String> get upgradeHeaders => _upgradeHeaders;

  /// The URI of the last upgrade request (`ws://<Host header><request target>`). Throws a
  /// [StateError] before the first upgrade.
  Uri get upgradeUri =>
      _upgradeUri ?? (throw StateError('No WebSocket upgrade seen yet'));

  /// Drops the first frame matching [test], then cuts ("cut before the ack").
  void cutBeforeFrame(bool Function(TapMessage m) test) {
    _oneShots.add(_OneShot(test, forwardFirst: false));
  }

  /// Forwards the first frame matching [test], then cuts.
  void cutAfterFrame(bool Function(TapMessage m) test) {
    _oneShots.add(_OneShot(test, forwardFirst: true));
  }

  /// Black-holes the frames matching [test] and keeps the connection (lost ack without a cut).
  void dropFrames(bool Function(TapMessage m) test) {
    _drops.add(test);
  }

  /// Delays by [d] the frames matching [where] (all when null). The order of a direction is
  /// kept: what follows a delayed message waits for it. [Duration.zero] removes the delay.
  void delayFrames(Duration d, {bool Function(TapMessage m)? where}) {
    _delay = d;
    _delayWhere = where;
  }

  /// Sends [envelope] to the client as if the server had sent it.
  void injectToClient(Map<String, Object?> envelope) {
    final _Link link = _liveLink();
    final List<Uint8List> raw = _serverTextFrames(jsonEncode(envelope));
    link.down.enqueue(Duration.zero, () {
      for (final Uint8List frame in raw) {
        link.link.send(ChaosDirection.down, frame);
      }
    });
  }

  /// Sends a real close frame with [code] and [reason] to the client; later server frames of
  /// that connection are dropped (RFC 6455 5.5.1: nothing follows a close).
  void closeToClient(int code, [String? reason]) {
    final _Link link = _liveLink();
    final List<int> reasonBytes = utf8.encode(reason ?? '');
    if (reasonBytes.length > 123) {
      throw ArgumentError.value(reason, 'reason', 'longer than 123 bytes');
    }
    final Uint8List frame = _frame(0x8, <int>[
      (code >> 8) & 0xff,
      code & 0xff,
      ...reasonBytes,
    ]);
    link.down.enqueue(Duration.zero, () {
      link.link.send(ChaosDirection.down, frame);
      link.down.closedToPeer = true;
    });
  }

  /// Rewrites every server message through [f]; null drops it. Null [f] removes the rewrite.
  // ignore: use_setters_to_change_properties, the test plan 2.5 API reads as an action.
  void rewriteServerMessages(
    Map<String, Object?>? Function(Map<String, Object?> m)? f,
  ) {
    _rewrite = f;
  }

  /// Completes with the next client message matching [test], or fails after [timeout].
  Future<TapMessage> nextClient(
    bool Function(TapMessage m) test, {
    required Duration timeout,
  }) {
    final Completer<TapMessage> done = Completer<TapMessage>();
    late final StreamSubscription<TapMessage> subscription;
    final Timer timer = Timer(timeout, () {
      unawaited(subscription.cancel());
      done.completeError(
        TimeoutException('No client message matched', timeout),
      );
    });
    subscription = messages.listen((TapMessage m) {
      if (m.direction == ChaosDirection.up && test(m)) {
        timer.cancel();
        unawaited(subscription.cancel());
        done.complete(m);
      }
    });
    return done.future;
  }

  @override
  void onChunk(ChaosLink link, ChaosDirection direction, Uint8List data) {
    final _Link state = _links.putIfAbsent(link, () => _Link(link));
    final _Side side = state.side(direction);
    side.append(data);
    if (side.passThrough) {
      side.flushRaw(link);
      return;
    }
    if (!side.handshakeDone && !_handshake(state, side)) {
      return;
    }
    if (side.passThrough) {
      side.flushRaw(link);
      return;
    }
    _readFrames(state, side);
  }

  @override
  void onClosed(ChaosLink link) {
    final _Link? state = _links.remove(link);
    if (state != null && identical(state, _newest)) {
      _newest = null;
    }
  }

  _Link _liveLink() {
    final _Link? link = _newest;
    if (link == null || link.link.isClosed) {
      throw StateError('No live WebSocket connection through the proxy');
    }
    return link;
  }

  /// Reads the HTTP head of [side]; false while it is incomplete.
  bool _handshake(_Link state, _Side side) {
    final int end = side.indexOfHeadEnd();
    if (end < 0) {
      return false;
    }
    final Uint8List head = side.take(end);
    final List<String> lines = latin1.decode(head).split('\r\n');
    side.handshakeDone = true;
    side.enqueue(Duration.zero, () => state.link.send(side.direction, head));
    if (side.direction == ChaosDirection.up) {
      final Map<String, String> headers = _headers(lines);
      final bool upgrade =
          (headers['upgrade'] ?? '').toLowerCase() == 'websocket';
      if (!upgrade) {
        state.up.passThrough = true;
        state.down.passThrough = true;
        return true;
      }
      _upgradeHeaders = headers;
      _upgradeUri = _requestUri(lines.first, headers['host']);
    } else if (lines.first.split(' ').elementAtOrNull(1) == '101') {
      _newest = state;
    } else {
      state.down.passThrough = true;
    }
    return true;
  }

  void _readFrames(_Link state, _Side side) {
    while (true) {
      final _Frame? frame = side.nextFrame();
      if (frame == null) {
        return;
      }
      _onFrame(state, side, frame);
    }
  }

  void _onFrame(_Link state, _Side side, _Frame frame) {
    final DateTime now = DateTime.now();
    if (frame.opcode >= 0x8) {
      _frames.add(TapFrame(side.direction, frame.opcode, null, now));
      _send(state, side, <Uint8List>[frame.raw], Duration.zero);
      return;
    }
    final _Frame? message = side.assemble(frame);
    if (message == null) {
      _frames.add(TapFrame(side.direction, frame.opcode, null, now));
      return;
    }
    if (message.opcode != 0x1) {
      _frames.add(TapFrame(side.direction, message.opcode, null, now));
      _send(state, side, side.takeFragments(), Duration.zero);
      return;
    }
    final String text = utf8.decode(message.payload, allowMalformed: true);
    _frames.add(TapFrame(side.direction, 0x1, text, now));
    _onText(state, side, text, side.takeFragments());
  }

  /// Re-assembles the RTDB message of [side] from [text] (rtdb_protocol.md 3.1).
  void _onText(_Link state, _Side side, String text, List<Uint8List> raw) {
    if (side.expectedPieces == null && RegExp(r'^[0-9]{1,6}$').hasMatch(text)) {
      final int count = int.parse(text);
      if (count == 0) {
        _send(state, side, raw, Duration.zero);
      } else {
        side.expectedPieces = count;
        side.held.addAll(raw);
      }
      return;
    }
    side.held.addAll(raw);
    side.pieces.add(text);
    if (side.expectedPieces != null &&
        side.pieces.length < side.expectedPieces!) {
      return;
    }
    final String json = side.pieces.join();
    final List<Uint8List> frames = List<Uint8List>.of(side.held);
    side.resetMessage();
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      _send(state, side, frames, Duration.zero);
      return;
    }
    if (decoded is! Map<String, Object?>) {
      _send(state, side, frames, Duration.zero);
      return;
    }
    _onMessage(state, side, TapMessage(side.direction, decoded), frames);
  }

  void _onMessage(
    _Link state,
    _Side side,
    TapMessage message,
    List<Uint8List> frames,
  ) {
    _messages.add(message);
    List<Uint8List> out = frames;
    final Map<String, Object?>? Function(Map<String, Object?>)? rewrite =
        _rewrite;
    if (rewrite != null && side.direction == ChaosDirection.down) {
      final String before = jsonEncode(message.envelope);
      final Map<String, Object?>? rewritten = rewrite(
        jsonDecode(before) as Map<String, Object?>,
      );
      if (rewritten == null) {
        return;
      }
      final String after = jsonEncode(rewritten);
      if (after != before) {
        out = _serverTextFrames(after);
      }
    }
    for (final _OneShot rule in List<_OneShot>.of(_oneShots)) {
      if (rule.test(message)) {
        _oneShots.remove(rule);
        if (rule.forwardFirst) {
          _send(state, side, out, Duration.zero);
        }
        side.enqueue(Duration.zero, state.link.cut);
        return;
      }
    }
    for (final bool Function(TapMessage) drop in _drops) {
      if (drop(message)) {
        return;
      }
    }
    final bool Function(TapMessage m)? where = _delayWhere;
    final bool delayed = where == null || where(message);
    _send(state, side, out, delayed ? _delay : Duration.zero);
  }

  void _send(_Link state, _Side side, List<Uint8List> frames, Duration d) {
    side.enqueue(d, () {
      if (side.direction == ChaosDirection.down && side.closedToPeer) {
        return;
      }
      for (final Uint8List frame in frames) {
        state.link.send(side.direction, frame);
      }
    });
  }

  static Map<String, String> _headers(List<String> lines) {
    final Map<String, String> headers = <String, String>{};
    for (final String line in lines.skip(1)) {
      final int colon = line.indexOf(':');
      if (colon <= 0) {
        continue;
      }
      final String name = line.substring(0, colon).trim().toLowerCase();
      final String value = line.substring(colon + 1).trim();
      final String? previous = headers[name];
      headers[name] = previous == null ? value : '$previous, $value';
    }
    return headers;
  }

  static Uri? _requestUri(String requestLine, String? host) {
    final List<String> parts = requestLine.split(' ');
    if (parts.length < 2) {
      return null;
    }
    return Uri.tryParse('ws://${host ?? 'localhost'}${parts[1]}');
  }
}

/// Server frames (unmasked, FIN set) for [text]: one text frame, or a count frame and pieces of
/// at most 16384 UTF-16 units cut between code points (rtdb_protocol.md 3.1; probe addendum 2,
/// question 5).
List<Uint8List> _serverTextFrames(String text) {
  const int maxUnits = 16384;
  if (text.length <= maxUnits) {
    return <Uint8List>[_frame(0x1, utf8.encode(text))];
  }
  final List<String> pieces = <String>[];
  int start = 0;
  while (start < text.length) {
    int end = start + maxUnits;
    if (end >= text.length) {
      end = text.length;
    } else if (_isLeadSurrogate(text.codeUnitAt(end - 1))) {
      end--;
    }
    pieces.add(text.substring(start, end));
    start = end;
  }
  return <Uint8List>[
    _frame(0x1, utf8.encode('${pieces.length}')),
    for (final String piece in pieces) _frame(0x1, utf8.encode(piece)),
  ];
}

bool _isLeadSurrogate(int unit) => unit >= 0xd800 && unit <= 0xdbff;

/// One unmasked frame with FIN set.
Uint8List _frame(int opcode, List<int> payload) {
  final BytesBuilder out = BytesBuilder(copy: false);
  final int length = payload.length;
  out.addByte(0x80 | opcode);
  if (length < 126) {
    out.addByte(length);
  } else if (length <= 0xffff) {
    out
      ..addByte(126)
      ..addByte(length >> 8)
      ..addByte(length & 0xff);
  } else {
    out.addByte(127);
    for (int shift = 56; shift >= 0; shift -= 8) {
      out.addByte((length >> shift) & 0xff);
    }
  }
  out.add(payload);
  return out.takeBytes();
}

final class _OneShot {
  _OneShot(this.test, {required this.forwardFirst});

  final bool Function(TapMessage m) test;
  final bool forwardFirst;
}

/// A parsed frame: its header bits, unmasked payload and the bytes as they came.
final class _Frame {
  _Frame(this.fin, this.opcode, this.payload, this.raw);

  final bool fin;
  final int opcode;
  final Uint8List payload;
  final Uint8List raw;
}

final class _Link {
  _Link(this.link);

  final ChaosLink link;
  final _Side up = _Side(ChaosDirection.up);
  final _Side down = _Side(ChaosDirection.down);

  _Side side(ChaosDirection direction) =>
      direction == ChaosDirection.up ? up : down;
}

/// The parsing state and the ordered output queue of one direction of one connection.
final class _Side {
  _Side(this.direction);

  final ChaosDirection direction;
  Uint8List _buffer = Uint8List(0);
  bool handshakeDone = false;
  bool passThrough = false;
  bool closedToPeer = false;

  /// The data frames of the WebSocket message in progress (FIN 0 plus continuations).
  final List<_Frame> _fragments = <_Frame>[];

  /// The RTDB message in progress: the announced count, the texts and the raw frames.
  int? expectedPieces;
  final List<String> pieces = <String>[];
  final List<Uint8List> held = <Uint8List>[];

  Future<void> _tail = Future<void>.value();
  int _queued = 0;

  void append(Uint8List data) {
    if (_buffer.isEmpty) {
      _buffer = data;
      return;
    }
    _buffer =
        (BytesBuilder(copy: false)
              ..add(_buffer)
              ..add(data))
            .takeBytes();
  }

  /// Hands every buffered byte on as it is.
  void flushRaw(ChaosLink link) {
    if (_buffer.isEmpty) {
      return;
    }
    final Uint8List bytes = _buffer;
    _buffer = Uint8List(0);
    enqueue(Duration.zero, () => link.send(direction, bytes));
  }

  /// The index just past the `\r\n\r\n` that ends an HTTP head, or -1.
  int indexOfHeadEnd() {
    for (int i = 3; i < _buffer.length; i++) {
      if (_buffer[i] == 0x0a &&
          _buffer[i - 1] == 0x0d &&
          _buffer[i - 2] == 0x0a &&
          _buffer[i - 3] == 0x0d) {
        return i + 1;
      }
    }
    return -1;
  }

  /// Removes and returns the first [count] buffered bytes.
  Uint8List take(int count) {
    final Uint8List head = Uint8List.fromList(_buffer.sublist(0, count));
    _buffer = Uint8List.fromList(_buffer.sublist(count));
    return head;
  }

  /// The next whole frame of the buffer, or null while it is incomplete (RFC 6455 5.2).
  _Frame? nextFrame() {
    final Uint8List b = _buffer;
    if (b.length < 2) {
      return null;
    }
    int length = b[1] & 0x7f;
    int position = 2;
    if (length == 126) {
      if (b.length < 4) {
        return null;
      }
      length = (b[2] << 8) | b[3];
      position = 4;
    } else if (length == 127) {
      if (b.length < 10) {
        return null;
      }
      length = 0;
      for (int i = 2; i < 10; i++) {
        length = (length << 8) | b[i];
      }
      position = 10;
    }
    final bool masked = (b[1] & 0x80) != 0;
    final int maskAt = position;
    if (masked) {
      position += 4;
    }
    if (b.length < position + length) {
      return null;
    }
    final Uint8List payload = Uint8List.fromList(
      b.sublist(position, position + length),
    );
    if (masked) {
      for (int i = 0; i < payload.length; i++) {
        payload[i] ^= b[maskAt + (i % 4)];
      }
    }
    final Uint8List raw = take(position + length);
    return _Frame((raw[0] & 0x80) != 0, raw[0] & 0x0f, payload, raw);
  }

  /// Adds a data frame to the message in progress; returns the whole message (opcode of its
  /// first frame, joined payload) when [frame] ends it, else null.
  _Frame? assemble(_Frame frame) {
    _fragments.add(frame);
    if (!frame.fin) {
      return null;
    }
    final BytesBuilder payload = BytesBuilder(copy: false);
    for (final _Frame part in _fragments) {
      payload.add(part.payload);
    }
    return _Frame(
      true,
      _fragments.first.opcode,
      payload.takeBytes(),
      frame.raw,
    );
  }

  /// The raw frames of the message [assemble] returned, and a fresh start.
  List<Uint8List> takeFragments() {
    final List<Uint8List> raw = <Uint8List>[
      for (final _Frame part in _fragments) part.raw,
    ];
    _fragments.clear();
    return raw;
  }

  void resetMessage() {
    expectedPieces = null;
    pieces.clear();
    held.clear();
  }

  /// Runs [action] after [delay], behind everything already queued in this direction.
  void enqueue(Duration delay, void Function() action) {
    if (delay == Duration.zero && _queued == 0) {
      action();
      return;
    }
    _queued++;
    _tail = _tail.then((_) async {
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
      _queued--;
      action();
    });
  }
}
