// Owner T. The scripted WebSocket channel and connector of the unit tests (test plan 2.2), driven
// by `fakeAsync` or by real time: every delivery goes through an asynchronous StreamController, so
// the code under test is never re-entered from inside its own `sendText`, and a test sees the
// events after `flushMicrotasks()` (or one `await pumpEventQueue()`).

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_database_dart/src/realtime/transport/ws_channel.dart';

/// A frame the code under test sent, with the virtual time it was sent at.
final class SentFrame {
  /// Creates the record of [text] sent at [at].
  const SentFrame(this.text, this.at);

  /// The raw text frame.
  final String text;

  /// The virtual time since the fake was created.
  final Duration at;

  /// Shows the length only: a frame may carry a token.
  @override
  String toString() => 'SentFrame(${text.length} chars at $at)';
}

/// A [WsChannel] whose server side is scripted by the test (test plan 2.2).
final class FakeWsChannel implements WsChannel {
  /// Creates an open channel. [elapsed] gives the virtual time for [SentFrame.at] (the elapsed
  /// time of `fakeAsync`); zero when absent.
  FakeWsChannel({Duration Function()? elapsed}) : _elapsed = elapsed ?? _zero;

  static Duration _zero() => Duration.zero;

  final Duration Function() _elapsed;
  final StreamController<WsEvent> _events = StreamController<WsEvent>();
  final List<SentFrame> _sent = <SentFrame>[];
  final List<WsEvent> _heldInbound = <WsEvent>[];
  final List<String> _heldOutbound = <String>[];
  bool _closed = false;
  bool _streamEnded = false;
  bool _silent = false;
  bool _dropOutbound = true;
  int? _localCloseCode;
  bool _abandoned = false;

  /// The server side's view of the client frames: called with every frame the code under test
  /// sends, unless the link is silent (then the frame is held or dropped, see [goSilent]).
  /// `FakeRtdbServer` sets it.
  void Function(String frame)? onClientFrame;

  /// Called once when the channel closes, from either side (`FakeRtdbServer` cancels its idle
  /// timer with it).
  void Function()? onClosed;

  /// The raw frames sent by the code under test, in order (also those lost to a silent link).
  List<SentFrame> get sentFrames => List<SentFrame>.unmodifiable(_sent);

  /// The sent frames re-assembled (count header handled) and JSON-decoded. A keep-alive `0` and a
  /// frame that is not a JSON object are skipped.
  List<Map<String, Object?>> get sentMessages {
    final List<Map<String, Object?>> messages = <Map<String, Object?>>[];
    final ClientFrameJoiner joiner = ClientFrameJoiner();
    for (final SentFrame frame in _sent) {
      final Map<String, Object?>? message = joiner.add(frame.text);
      if (message != null) {
        messages.add(message);
      }
    }
    return messages;
  }

  /// The `d` envelopes `{r, a, b}` of the sent data messages, filtered by [action] when given.
  List<Map<String, Object?>> sentRequests([String? action]) {
    final List<Map<String, Object?>> requests = <Map<String, Object?>>[];
    for (final Map<String, Object?> message in sentMessages) {
      final Object? inner = message['d'];
      if (message['t'] != 'd' || inner is! Map<String, Object?>) {
        continue;
      }
      if (action == null || inner['a'] == action) {
        requests.add(inner);
      }
    }
    return requests;
  }

  /// The last sent request of [action], or null.
  Map<String, Object?>? lastRequest(String action) {
    final List<Map<String, Object?>> requests = sentRequests(action);
    return requests.isEmpty ? null : requests.last;
  }

  /// Whether the channel is closed (by either side).
  bool get isClosed => _closed;

  /// The code of a local [close], or null.
  int? get localCloseCode => _localCloseCode;

  /// Whether the code under test called [abandon].
  bool get abandoned => _abandoned;

  /// Whether the link is silent ([goSilent] without [resume]).
  bool get isSilent => _silent;

  /// Delivers one raw text [frame] (framing tests).
  void serverText(String frame) => _deliver(WsText(frame));

  /// Delivers [envelope] as JSON, split like the real server into a count frame and pieces of at
  /// most [frameSize] code units when given. The split is by code unit, as the server's own frames
  /// were measured (`rtdb_emulator_probe.md`, frame limits); the pieces join back unchanged.
  void serverMessage(Map<String, Object?> envelope, {int? frameSize}) {
    final String json = jsonEncode(envelope);
    if (frameSize == null || json.length <= frameSize) {
      serverText(json);
      return;
    }
    final List<String> pieces = <String>[];
    for (int start = 0; start < json.length; start += frameSize) {
      final int end = start + frameSize < json.length
          ? start + frameSize
          : json.length;
      pieces.add(json.substring(start, end));
    }
    serverText('${pieces.length}');
    pieces.forEach(serverText);
  }

  /// Delivers the hello `{"t":"c","d":{"t":"h","d":{"ts":ts,"v":v,"h":h,"s":s}}}`.
  void serverHello({
    required int ts,
    String v = '5',
    required String h,
    String s = 'sess-1',
  }) {
    serverControl('h', <String, Object?>{'ts': ts, 'v': v, 'h': h, 's': s});
  }

  /// Delivers the response `{"t":"d","d":{"r":r,"b":{"s":status,"d":data}}}`.
  void serverResponse(int r, {String status = 'ok', Object? data}) {
    serverMessage(<String, Object?>{
      't': 'd',
      'd': <String, Object?>{
        'r': r,
        'b': <String, Object?>{'s': status, 'd': data},
      },
    });
  }

  /// Delivers the push `{"t":"d","d":{"a":action,"b":body}}`.
  void serverPush(String action, Map<String, Object?> body) {
    serverMessage(<String, Object?>{
      't': 'd',
      'd': <String, Object?>{'a': action, 'b': body},
    });
  }

  /// Delivers the control message `{"t":"c","d":{"t":type,"d":payload}}`.
  void serverControl(String type, [Object? payload]) {
    serverMessage(<String, Object?>{
      't': 'c',
      'd': <String, Object?>{'t': type, 'd': payload},
    });
  }

  /// Delivers a binary frame of [bytes].
  void serverBinary(List<int> bytes) =>
      _deliver(WsBinary(Uint8List.fromList(bytes)));

  /// Closes cleanly from the server side with [code] and [reason]. While silent, the close is held
  /// like any other inbound event.
  void serverClose([int? code, String? reason]) =>
      _deliver(WsClosed(code, reason));

  /// Raises [error] as a [WsError], then closes with 1006 (as the io channel reports an error
  /// followed by the end of the socket).
  void serverError(Object error) {
    _deliver(WsError(error, StackTrace.current));
    _deliver(const WsClosed(1006, null));
  }

  /// Half-open link: nothing is delivered either way and no event is raised. With
  /// [dropOutbound] the frames sent meanwhile are lost, otherwise they are delivered on [resume].
  void goSilent({bool dropOutbound = true}) {
    _silent = true;
    _dropOutbound = dropOutbound;
  }

  /// Ends the silence; queued inbound frames are delivered in order.
  void resume() {
    if (!_silent) {
      return;
    }
    _silent = false;
    final List<String> outbound = List<String>.of(_heldOutbound);
    _heldOutbound.clear();
    for (final String frame in outbound) {
      onClientFrame?.call(frame);
    }
    final List<WsEvent> inbound = List<WsEvent>.of(_heldInbound);
    _heldInbound.clear();
    inbound.forEach(_deliver);
  }

  @override
  Stream<WsEvent> get events => _events.stream;

  @override
  void sendText(String frame) {
    if (_closed) {
      throw StateError('sendText on a closed channel');
    }
    _sent.add(SentFrame(frame, _elapsed()));
    if (!_silent) {
      onClientFrame?.call(frame);
    } else if (!_dropOutbound) {
      _heldOutbound.add(frame);
    }
  }

  @override
  Future<void> close([int code = 1000, String? reason]) async {
    if (_closed) {
      return;
    }
    _closed = true;
    _localCloseCode = code;
    _end(WsClosed(code, reason));
  }

  @override
  void abandon() {
    if (_abandoned) {
      return;
    }
    _abandoned = true;
    _closed = true;
    _end(const WsClosed(null, null));
  }

  void _deliver(WsEvent event) {
    if (_streamEnded) {
      return;
    }
    if (_silent) {
      _heldInbound.add(event);
      return;
    }
    switch (event) {
      case WsClosed():
        _closed = true;
        _end(event);
      case WsText() || WsBinary() || WsError():
        _events.add(event);
    }
  }

  void _end(WsClosed event) {
    if (_streamEnded) {
      return;
    }
    _streamEnded = true;
    _heldInbound.clear();
    onClosed?.call();
    _events.add(event);
    unawaited(_events.close());
  }
}

/// Joins the frames a client sends (count frame, pieces) into decoded messages, independently of
/// the production `FrameAssembler` so that the fakes check it rather than repeat it. A keep-alive
/// `0` and a frame that is not a JSON object yield null.
final class ClientFrameJoiner {
  final List<String> _pieces = <String>[];
  int _expected = 0;

  /// Adds [frame]; returns the message it completed, or null.
  Map<String, Object?>? add(String frame) {
    if (_expected == 0) {
      final int? count = frame.length <= 6 ? int.tryParse(frame) : null;
      if (count != null) {
        _expected = count;
        return null;
      }
      return decodeObject(frame);
    }
    _pieces.add(frame);
    if (_pieces.length < _expected) {
      return null;
    }
    final String text = _pieces.join();
    _pieces.clear();
    _expected = 0;
    return decodeObject(text);
  }

  /// [text] decoded when it is a JSON object, else null.
  static Map<String, Object?>? decodeObject(String text) {
    try {
      final Object? decoded = jsonDecode(text);
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}

/// What the [FakeWsConnector] does with one attempt.
enum AttemptKind {
  /// Completes with an open channel.
  accept,

  /// Fails with [WsConnectFailure.refused].
  refuse,

  /// Fails with [WsConnectFailure.dns].
  dnsFailure,

  /// Never completes (the connect-timeout test), unless the caller aborts it: it then fails with
  /// [WsConnectFailure.other].
  hang,

  /// Completes with a channel that is silent from the start (the dead-link test).
  acceptThenSilent,

  /// Completes with a channel that the server closes at once with [AttemptBehavior.closeCode].
  acceptThenClose,
}

/// The scripted behaviour of one connect attempt.
final class AttemptBehavior {
  /// An attempt that succeeds.
  const AttemptBehavior.accept() : kind = AttemptKind.accept, closeCode = null;

  /// An attempt refused by the peer.
  const AttemptBehavior.refuse() : kind = AttemptKind.refuse, closeCode = null;

  /// An attempt whose host does not resolve.
  const AttemptBehavior.dnsFailure()
    : kind = AttemptKind.dnsFailure,
      closeCode = null;

  /// An attempt that never completes unless aborted.
  const AttemptBehavior.hang() : kind = AttemptKind.hang, closeCode = null;

  /// An attempt that succeeds and then never delivers a frame.
  const AttemptBehavior.acceptThenSilent()
    : kind = AttemptKind.acceptThenSilent,
      closeCode = null;

  /// An attempt that succeeds and is closed by the server with [closeCode].
  const AttemptBehavior.acceptThenClose(int this.closeCode)
    : kind = AttemptKind.acceptThenClose;

  /// What happens.
  final AttemptKind kind;

  /// The close code of [AttemptKind.acceptThenClose].
  final int? closeCode;
}

/// One call of the connector, as recorded.
final class ConnectAttempt {
  /// Creates the record of a call with [url] and [headers] at [at].
  const ConnectAttempt(
    this.url,
    this.headers,
    this.at,
    this.channel, {
    this.abort,
  });

  /// The URL passed (may hold `ac` on the web form).
  final Uri url;

  /// The upgrade headers passed (may hold the App Check token).
  final Map<String, String> headers;

  /// The virtual time of the call.
  final Duration at;

  /// The channel of a successful attempt, else null.
  final FakeWsChannel? channel;

  /// The abort signal the caller passed, if any.
  final Future<void>? abort;

  /// Shows the host and the time only: the query and the headers may hold tokens.
  @override
  String toString() => 'ConnectAttempt(${url.host} at $at)';
}

/// A [WsConnector] that follows a script of [AttemptBehavior]s (test plan 2.2).
///
/// Like the real connectors, a URL whose scheme is not `ws` or `wss` fails with
/// [WsConnectFailure.badScheme] before anything else; the attempt is still recorded (with no
/// channel) and uses no scripted behaviour.
final class FakeWsConnector {
  /// Creates the connector. With [autoHello] every accepted channel sends a hello right away
  /// (`ts` = [helloEpochMs] plus the virtual time, `h` = the URL's host, `s` = `sess-<n>` for the
  /// n-th accepted channel). [elapsed] gives the virtual time. [onAccept] sees every accepted
  /// channel but one closed at once ([AttemptKind.acceptThenClose]) before the code under test
  /// does; a silent one is already silent (`FakeRtdbServer` uses it).
  FakeWsConnector({
    bool autoHello = false,
    Duration Function()? elapsed,
    void Function(FakeWsChannel channel, Uri url)? onAccept,
  }) : _autoHello = autoHello,
       _elapsed = elapsed ?? FakeWsChannel._zero,
       _onAccept = onAccept;

  /// The base of the `ts` of the automatic hello: 2023-11-14T22:13:20Z in ms.
  static const int helloEpochMs = 1700000000000;

  final bool _autoHello;
  final Duration Function() _elapsed;
  final void Function(FakeWsChannel channel, Uri url)? _onAccept;
  final List<ConnectAttempt> _attempts = <ConnectAttempt>[];
  final List<AttemptBehavior> _script = <AttemptBehavior>[];
  final List<Completer<FakeWsChannel>> _waiters = <Completer<FakeWsChannel>>[];
  FakeWsChannel? _last;
  int _accepted = 0;

  /// The closure to inject as the [WsConnector].
  WsConnector get connect => _connect;

  /// Every call so far, in order.
  List<ConnectAttempt> get attempts =>
      List<ConnectAttempt>.unmodifiable(_attempts);

  /// Sets the behaviour of the next attempts, one per attempt; once used up, attempts accept.
  void script(List<AttemptBehavior> perAttempt) {
    _script
      ..clear()
      ..addAll(perAttempt);
  }

  /// The channel of the last successful attempt.
  FakeWsChannel get last {
    final FakeWsChannel? channel = _last;
    if (channel == null) {
      throw StateError('no attempt was accepted yet');
    }
    return channel;
  }

  /// Completes with the channel of the next successful attempt.
  Future<FakeWsChannel> get nextChannel {
    final Completer<FakeWsChannel> waiter = Completer<FakeWsChannel>();
    _waiters.add(waiter);
    return waiter.future;
  }

  Future<WsChannel> _connect(
    Uri url, {
    Map<String, String> headers = const <String, String>{},
    Future<void>? abort,
  }) {
    final Duration at = _elapsed();
    final Map<String, String> headersCopy = Map<String, String>.unmodifiable(
      headers,
    );
    if (url.scheme != 'ws' && url.scheme != 'wss') {
      _attempts.add(ConnectAttempt(url, headersCopy, at, null, abort: abort));
      return Future<WsChannel>.error(
        const WsConnectException(
          WsConnectFailure.badScheme,
          'only ws and wss URLs are accepted',
        ),
      );
    }
    final AttemptBehavior behavior = _script.isEmpty
        ? const AttemptBehavior.accept()
        : _script.removeAt(0);
    switch (behavior.kind) {
      case AttemptKind.refuse:
        _attempts.add(ConnectAttempt(url, headersCopy, at, null, abort: abort));
        return Future<WsChannel>.error(
          const WsConnectException(
            WsConnectFailure.refused,
            'connection refused',
          ),
        );
      case AttemptKind.dnsFailure:
        _attempts.add(ConnectAttempt(url, headersCopy, at, null, abort: abort));
        return Future<WsChannel>.error(
          const WsConnectException(WsConnectFailure.dns, 'host lookup failed'),
        );
      case AttemptKind.hang:
        _attempts.add(ConnectAttempt(url, headersCopy, at, null, abort: abort));
        final Completer<WsChannel> pending = Completer<WsChannel>();
        if (abort != null) {
          void stop() {
            if (!pending.isCompleted) {
              pending.completeError(
                const WsConnectException(
                  WsConnectFailure.other,
                  'the connect attempt was aborted',
                ),
              );
            }
          }

          unawaited(abort.then((_) => stop(), onError: (Object _) => stop()));
        }
        return pending.future;
      case AttemptKind.accept ||
          AttemptKind.acceptThenSilent ||
          AttemptKind.acceptThenClose:
        return _accept(url, headersCopy, at, behavior, abort);
    }
  }

  Future<WsChannel> _accept(
    Uri url,
    Map<String, String> headers,
    Duration at,
    AttemptBehavior behavior,
    Future<void>? abort,
  ) {
    final FakeWsChannel channel = FakeWsChannel(elapsed: _elapsed);
    _accepted++;
    _attempts.add(ConnectAttempt(url, headers, at, channel, abort: abort));
    _last = channel;
    if (behavior.kind == AttemptKind.acceptThenClose) {
      channel.serverClose(behavior.closeCode);
    } else {
      // A silent channel holds the hello (and anything else) until `resume`.
      if (behavior.kind == AttemptKind.acceptThenSilent) {
        channel.goSilent();
      }
      _onAccept?.call(channel, url);
      if (_autoHello) {
        channel.serverHello(
          ts: helloEpochMs + _elapsed().inMilliseconds,
          h: url.host,
          s: 'sess-$_accepted',
        );
      }
    }
    final List<Completer<FakeWsChannel>> waiters =
        List<Completer<FakeWsChannel>>.of(_waiters);
    _waiters.clear();
    for (final Completer<FakeWsChannel> waiter in waiters) {
      waiter.complete(channel);
    }
    return Future<WsChannel>.value(channel);
  }
}
