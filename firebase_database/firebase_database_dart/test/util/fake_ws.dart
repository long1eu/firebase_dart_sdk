// Owner T. The scripted WebSocket channel and connector of the unit tests (test plan 2.2), driven
// by `fakeAsync`.

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
  FakeWsChannel({Duration Function()? elapsed}) {
    throw UnimplementedError();
  }

  /// The raw frames sent by the code under test, in order.
  List<SentFrame> get sentFrames => throw UnimplementedError();

  /// The sent frames re-assembled (count header handled) and JSON-decoded.
  List<Map<String, Object?>> get sentMessages => throw UnimplementedError();

  /// The `d` envelopes `{r, a, b}` of the sent data messages, filtered by [action] when given.
  List<Map<String, Object?>> sentRequests([String? action]) {
    throw UnimplementedError();
  }

  /// The last sent request of [action], or null.
  Map<String, Object?>? lastRequest(String action) {
    throw UnimplementedError();
  }

  /// Whether the channel is closed (by either side).
  bool get isClosed => throw UnimplementedError();

  /// The code of a local [close], or null.
  int? get localCloseCode => throw UnimplementedError();

  /// Whether the code under test called [abandon].
  bool get abandoned => throw UnimplementedError();

  /// Delivers one raw text [frame] (framing tests).
  void serverText(String frame) {
    throw UnimplementedError();
  }

  /// Delivers [envelope] as JSON, split like the real server into a count frame and pieces of at
  /// most [frameSize] code units when given.
  void serverMessage(Map<String, Object?> envelope, {int? frameSize}) {
    throw UnimplementedError();
  }

  /// Delivers the hello `{"t":"c","d":{"t":"h","d":{"ts":ts,"v":v,"h":h,"s":s}}}`.
  void serverHello({
    required int ts,
    String v = '5',
    required String h,
    String s = 'sess-1',
  }) {
    throw UnimplementedError();
  }

  /// Delivers the response `{"t":"d","d":{"r":r,"b":{"s":status,"d":data}}}`.
  void serverResponse(int r, {String status = 'ok', Object? data}) {
    throw UnimplementedError();
  }

  /// Delivers the push `{"t":"d","d":{"a":action,"b":body}}`.
  void serverPush(String action, Map<String, Object?> body) {
    throw UnimplementedError();
  }

  /// Delivers the control message `{"t":"c","d":{"t":type,"d":payload}}`.
  void serverControl(String type, [Object? payload]) {
    throw UnimplementedError();
  }

  /// Delivers a binary frame of [bytes].
  void serverBinary(List<int> bytes) {
    throw UnimplementedError();
  }

  /// Closes cleanly from the server side with [code] and [reason].
  void serverClose([int? code, String? reason]) {
    throw UnimplementedError();
  }

  /// Raises [error] as a [WsError], then closes.
  void serverError(Object error) {
    throw UnimplementedError();
  }

  /// Half-open link: nothing is delivered either way and no event is raised. With
  /// [dropOutbound] the frames sent meanwhile are lost, otherwise they are delivered on [resume].
  void goSilent({bool dropOutbound = true}) {
    throw UnimplementedError();
  }

  /// Ends the silence; queued inbound frames are delivered in order.
  void resume() {
    throw UnimplementedError();
  }

  @override
  Stream<WsEvent> get events => throw UnimplementedError();

  @override
  void sendText(String frame) {
    throw UnimplementedError();
  }

  @override
  Future<void> close([int code = 1000, String? reason]) {
    throw UnimplementedError();
  }

  @override
  void abandon() {
    throw UnimplementedError();
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

  /// Never completes (the connect-timeout test).
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

  /// An attempt that never completes.
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
  const ConnectAttempt(this.url, this.headers, this.at, this.channel);

  /// The URL passed (may hold `ac` on the web form).
  final Uri url;

  /// The upgrade headers passed (may hold the App Check token).
  final Map<String, String> headers;

  /// The virtual time of the call.
  final Duration at;

  /// The channel of a successful attempt, else null.
  final FakeWsChannel? channel;

  /// Shows the host and the time only: the query and the headers may hold tokens.
  @override
  String toString() => 'ConnectAttempt(${url.host} at $at)';
}

/// A [WsConnector] that follows a script of [AttemptBehavior]s (test plan 2.2).
final class FakeWsConnector {
  /// Creates the connector. With [autoHello] every accepted channel sends a hello right away.
  /// [elapsed] gives the virtual time.
  FakeWsConnector({bool autoHello = false, Duration Function()? elapsed}) {
    throw UnimplementedError();
  }

  /// The closure to inject as the [WsConnector].
  WsConnector get connect => throw UnimplementedError();

  /// Every call so far, in order.
  List<ConnectAttempt> get attempts => throw UnimplementedError();

  /// Sets the behaviour of the next attempts, one per attempt; once used up, attempts accept.
  void script(List<AttemptBehavior> perAttempt) {
    throw UnimplementedError();
  }

  /// The channel of the last successful attempt.
  FakeWsChannel get last => throw UnimplementedError();

  /// Completes with the channel of the next successful attempt.
  Future<FakeWsChannel> get nextChannel => throw UnimplementedError();
}
