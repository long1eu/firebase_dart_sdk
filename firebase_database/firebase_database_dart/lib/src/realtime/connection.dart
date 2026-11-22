/// One WebSocket session with the database (owner C): open, hello, reset, shutdown, control
/// dispatch, close and the connect timeout (`rtdb_protocol.md` 3.2 to 3.5).
library;

import 'dart:async';

import 'package:firebase_database_dart/src/core/util/logger.dart';
import 'package:firebase_database_dart/src/core/view/query_params.dart';
import 'package:firebase_database_dart/src/realtime/connection_timings.dart';
import 'package:firebase_database_dart/src/realtime/framing.dart';
import 'package:firebase_database_dart/src/realtime/liveness.dart';
import 'package:firebase_database_dart/src/realtime/realtime_error.dart';
import 'package:firebase_database_dart/src/realtime/realtime_target.dart';
import 'package:firebase_database_dart/src/realtime/transport/ws_channel.dart';

/// Why a [RealtimeConnection] ended (test plan section 5, interface C to P).
enum DisconnectReason {
  /// Any ordinary end: the peer closed, the socket failed, the connection was unhealthy, a
  /// protocol error, or a local [RealtimeConnection.close].
  other,

  /// The server sent a reset (`r`) while connected; reconnect with normal backoff (3.3).
  serverReset,

  /// No hello within `ConnectionTimings.connectTimeout` (test plan B-3.4c).
  connectTimeout,

  /// A dead-link probe got no answer (test plan B-3.1i).
  deadLink,
}

/// What a [RealtimeConnection] reports to its owner. Every callback may close or replace the
/// connection (re-entrancy, test plan B-3.5b).
abstract interface class RealtimeDelegate {
  /// The hello arrived (3.2): [serverTimeMs] is its `ts`, [sessionId] its `s`. Called once.
  void onReady(int serverTimeMs, String sessionId);

  /// A data message (`{"t":"d","d":message}`) arrived; [message] is its `d` object, not yet
  /// decoded.
  void onDataMessage(Map<String, Object?> message);

  /// The connection ended for [reason]. Called at most once, never after [onKill].
  void onDisconnect(DisconnectReason reason);

  /// The server sent shutdown (`s`, 3.3) with [reason] (server text, cut and escaped before it is
  /// logged, threat model T7). No [onDisconnect] follows and the owner must never reconnect.
  void onKill(String reason);
}

enum _State { idle, connecting, connected, closed }

/// The actions whose body carries a credential, or that belong to one: logged as
/// `<action> (contents hidden)`, never with their body (threat model T7; Android
/// Connection.java:236-246). Both spellings of the App Check removal. The one list of the
/// connection half: the persistent connection logs its requests by it too (review L6).
const Set<String> credentialActions = <String>{
  RealtimeProtocol.auth,
  RealtimeProtocol.gauth,
  RealtimeProtocol.unauth,
  RealtimeProtocol.appCheck,
  'unappcheck',
  'unappeck',
};

/// One connection attempt and, after the hello, one live session (test plan section 5, C gives P).
///
/// Owns the frames (`FrameSplitter`, `FrameAssembler`), the liveness timers (`Liveness`) and the
/// connect timeout. A server host from the hello or a reset goes through
/// [RealtimeTarget.acceptServerHost] (threat model T1); at most
/// `ConnectionTimings.maxResetsPerAttempt` resets are followed in one attempt (T2). Malformed
/// control messages close the connection as an ordinary failure (iOS U-I13, U-I14).
///
/// Before the hello, a failure (connector error, socket closed, connect timeout, protocol error,
/// too many resets) also makes the target forget a server-chosen host, so the next attempt goes
/// to the configured host (Connection.ts:497-515, in memory only, T1).
final class RealtimeConnection {
  /// Creates a connection to [target] over [connector]; nothing happens before [open].
  ///
  /// [lastSessionId] becomes `ls` of the URL (2.3); [appId] and [appCheckToken] go into the
  /// headers or the URL as [target] decides. [logger] gets the `e` control errors, unknown control
  /// types and the version warning, cleaned by `safeServerText` (threat model T7); null drops them.
  RealtimeConnection(
    RealtimeTarget target,
    WsConnector connector,
    ConnectionTimings timings,
    RealtimeDelegate delegate, {
    String? lastSessionId,
    String? appId,
    String? appCheckToken,
    DatabaseLogger? logger,
  }) : _target = target,
       _connector = connector,
       _timings = timings,
       _delegate = delegate,
       _lastSessionId = lastSessionId,
       _appId = appId,
       _appCheckToken = appCheckToken,
       _logger = logger,
       _splitter = FrameSplitter(maxFrameUnits: timings.maxFrameUnits);

  static final String _pingFrame = jsStringify(<String, Object?>{
    RealtimeProtocol.typeKey: RealtimeProtocol.controlMessage,
    RealtimeProtocol.dataKey: <String, Object?>{
      RealtimeProtocol.typeKey: RealtimeProtocol.controlPing,
      RealtimeProtocol.dataKey: <String, Object?>{},
    },
  });

  final RealtimeTarget _target;
  final WsConnector _connector;
  final ConnectionTimings _timings;
  final RealtimeDelegate _delegate;
  final String? _lastSessionId;
  final String? _appId;
  final String? _appCheckToken;
  final DatabaseLogger? _logger;
  final FrameSplitter _splitter;

  _State _state = _State.idle;

  /// Bumped on every socket teardown: callbacks of an older socket or connector call compare it
  /// and do nothing (a late channel after the connect timeout is abandoned).
  int _generation = 0;
  int _resets = 0;
  WsChannel? _channel;

  /// Completed when the connection gives up on a connector call that has not returned yet.
  Completer<void>? _pendingAbort;

  /// Called for every inbound text frame, before it is assembled: each piece of a multi-frame
  /// message, the count frame, and a frame that turns out to be malformed (binary frames are
  /// ignored). The persistent connection re-arms its request timers here: a request timer
  /// measures silence of the link, not the age of a request (rulings, H1). Set it before [open];
  /// it may close the connection. The persistent connection sets it on every connection it opens.
  void Function()? onInboundFrame;
  StreamSubscription<WsEvent>? _subscription;
  FrameAssembler? _assembler;
  Liveness? _liveness;
  Timer? _connectTimer;

  /// Opens the socket and starts the connect timeout. Call once.
  ///
  /// Does nothing after [close]; throws [StateError] when called twice.
  void open() {
    switch (_state) {
      case _State.idle:
        _state = _State.connecting;
        _openSocket();
      case _State.closed:
        return;
      case _State.connecting:
      case _State.connected:
        throw StateError('RealtimeConnection.open was called twice');
    }
  }

  /// Whether the hello arrived and the connection is not closed.
  bool get isConnected => _state == _State.connected;

  /// Sends [request] as `{"t":"d","d":request}`, split into frames (3.1). Throws [StateError] when
  /// not connected.
  ///
  /// A socket that fails during the send closes the connection (`onDisconnect` runs inside this
  /// call) instead of throwing.
  void send(Map<String, Object?> request) {
    if (_state != _State.connected) {
      throw StateError('RealtimeConnection is not connected');
    }
    // jsStringify (core/view/query_params.dart:394-484) is a full JSON encoder for decoded values:
    // an integral double is written `1` as in a query identity, a lone surrogate is escaped
    // instead of reaching the server as U+FFFD, and NaN/Infinity (refused by the core's
    // validation) become `null` instead of throwing.
    final String json = jsStringify(<String, Object?>{
      RealtimeProtocol.typeKey: RealtimeProtocol.dataMessage,
      RealtimeProtocol.dataKey: request,
    });
    _logRequest(request);
    for (final String frame in _splitter.framesFor(json)) {
      if (!_sendFrame(frame)) {
        return;
      }
    }
  }

  /// Probes a connected link at once (a resume or a network change may have killed it silently):
  /// a ping now, and a close with [DisconnectReason.deadLink] if nothing arrives within
  /// `ConnectionTimings.idleProbeTimeout`. A no-op while connecting, after a close, and while a
  /// probe is outstanding, so it never starts a second reconnect. The persistent connection calls
  /// it on a connectivity hint while connected.
  void probeNow() {
    if (_state == _State.connected) {
      _liveness?.probeNow();
    }
  }

  /// Closes the connection and reports [reason] to [RealtimeDelegate.onDisconnect] once. Safe
  /// before [open], after a close, and from inside a delegate callback (3.5, test plan B-3.5a/b).
  void close([DisconnectReason reason = DisconnectReason.other]) {
    if (_state == _State.closed) {
      return;
    }
    _state = _State.closed;
    _teardownSocket(abandon: reason == DisconnectReason.connectTimeout);
    _delegate.onDisconnect(reason);
  }

  /// Shows the state only: no session id, no token (threat model T7, T8).
  @override
  String toString() => 'RealtimeConnection';

  void _openSocket() {
    final int generation = ++_generation;
    final Uri url = _target.connectionUri(
      lastSessionId: _lastSessionId,
      appId: _appId,
      appCheckToken: _appCheckToken,
    );
    final Map<String, String> headers = _target.connectionHeaders(
      appId: _appId,
      appCheckToken: _appCheckToken,
    );
    // One timer per socket: a followed reset gives the new host its own connect timeout
    // (Android WebsocketConnection.java:199-208 arms it per socket).
    _connectTimer?.cancel();
    _connectTimer = Timer(_timings.connectTimeout, _onConnectTimeout);
    _log(DatabaseLogLevel.debug, 'connecting to ${url.host}');
    final Completer<void> abort = Completer<void>();
    _pendingAbort = abort;
    void settled() {
      if (identical(_pendingAbort, abort)) {
        _pendingAbort = null;
      }
    }

    unawaited(
      Future<WsChannel>.sync(
        () => _connector(url, headers: headers, abort: abort.future),
      ).then<void>(
        (WsChannel channel) {
          settled();
          _onChannel(generation, channel);
        },
        onError: (Object error) {
          settled();
          _onConnectError(generation, error);
        },
      ),
    );
  }

  void _onChannel(int generation, WsChannel channel) {
    if (generation != _generation || _state != _State.connecting) {
      // The attempt timed out or was closed while the connector ran (iOS U-I17, U-I18).
      channel.abandon();
      return;
    }
    _channel = channel;
    _assembler = FrameAssembler(
      maxMessageBytes: _timings.maxMessageBytes,
      maxDepth: _timings.maxJsonDepth,
    );
    final Liveness liveness = Liveness(
      timings: _timings,
      sendKeepAlive: () => _sendFrame(RealtimeProtocol.keepAliveFrame),
      sendPing: () => _sendFrame(_pingFrame),
      close: _fail,
    );
    _liveness = liveness;
    _subscription = channel.events.listen(
      (WsEvent event) => _onEvent(generation, event),
      onError: (Object error) =>
          _onChannelEnd(generation, 'socket error (${error.runtimeType})'),
      onDone: () => _onChannelEnd(generation, 'socket ended'),
    );
    liveness.start();
  }

  void _onConnectError(int generation, Object error) {
    if (generation != _generation || _state == _State.closed) {
      return;
    }
    // The error may hold the URL with its query (T8): name its kind or type only.
    final String kind = error is WsConnectException
        ? error.kind.name
        : '${error.runtimeType}';
    _log(DatabaseLogLevel.info, 'connect failed ($kind)');
    _fail(DisconnectReason.other);
  }

  void _onConnectTimeout() {
    _connectTimer = null;
    if (_state != _State.connecting) {
      return;
    }
    _log(DatabaseLogLevel.info, 'no hello within ${_timings.connectTimeout}');
    _fail(DisconnectReason.connectTimeout);
  }

  void _onEvent(int generation, WsEvent event) {
    if (generation != _generation || _state == _State.closed) {
      return;
    }
    switch (event) {
      case WsText(:final String data):
        _onText(data);
      case WsBinary():
        // Ignored, also when empty (iOS FWebSocketConnectionTest.m:119, test plan B-3.1f).
        _log(DatabaseLogLevel.debug, 'binary frame ignored');
      case WsClosed(:final int? code):
        _onChannelEnd(generation, 'socket closed ($code)');
      case WsError(:final Object error):
        _onChannelEnd(generation, 'socket error (${error.runtimeType})');
    }
  }

  void _onChannelEnd(int generation, String why) {
    if (generation != _generation || _state == _State.closed) {
      return;
    }
    _log(DatabaseLogLevel.info, why);
    _fail(DisconnectReason.other);
  }

  void _onText(String frame) {
    _liveness?.onFrameReceived(frame.length);
    onInboundFrame?.call();
    if (_state == _State.closed) {
      return;
    }
    final FrameAssembler? assembler = _assembler;
    if (_state == _State.closed || assembler == null) {
      return;
    }
    final Map<String, Object?>? message;
    try {
      message = assembler.add(frame);
    } on FramingException catch (error) {
      _protocolError(error.message);
      return;
    }
    if (message != null) {
      _onMessage(message);
    }
  }

  void _onMessage(Map<String, Object?> message) {
    final Object? type = message[RealtimeProtocol.typeKey];
    final Object? data = message[RealtimeProtocol.dataKey];
    if (type == RealtimeProtocol.dataMessage && data is Map<String, Object?>) {
      _onData(data);
    } else if (type == RealtimeProtocol.controlMessage &&
        data is Map<String, Object?>) {
      _onControl(data);
    } else {
      // JS throws from requireKey (util.ts:292-303); Android closes (Connection.java:140-145).
      _protocolError('message without a valid envelope');
    }
  }

  void _onData(Map<String, Object?> message) {
    if (_state != _State.connected) {
      // The owner has no session yet; the server sends no data before its hello (probe).
      _protocolError('data message before the hello');
      return;
    }
    _liveness?.onResponse();
    _delegate.onDataMessage(message);
  }

  void _onControl(Map<String, Object?> control) {
    final Object? type = control[RealtimeProtocol.typeKey];
    if (type is! String) {
      _protocolError('control message without a type');
      return;
    }
    final Object? payload = control[RealtimeProtocol.dataKey];
    switch (type) {
      case RealtimeProtocol.controlHello:
        _onHello(payload);
      case RealtimeProtocol.controlShutdown:
        _onShutdown(payload);
      case RealtimeProtocol.controlReset:
        _onReset(payload);
      case RealtimeProtocol.controlError:
        // No state change (Connection.ts:368-369); the request it refers to times out (probe).
        _log(DatabaseLogLevel.warning, 'server error: ${_describe(payload)}');
      case RealtimeProtocol.controlPong:
        _liveness?.onResponse(isPong: true);
      case RealtimeProtocol.controlSwitchAck:
      case RealtimeProtocol.controlEndTransmission:
        // Long-poll upgrade only (3.3).
        break;
      default:
        _log(
          DatabaseLogLevel.warning,
          'unknown control message ${safeServerText(type)}',
        );
    }
  }

  void _onHello(Object? payload) {
    if (_state != _State.connecting) {
      // Connection.ts:394: only a connecting connection takes a hello.
      _log(DatabaseLogLevel.debug, 'second hello ignored');
      return;
    }
    if (payload is! Map<String, Object?>) {
      _protocolError('hello is not an object');
      return;
    }
    final Object? ts = payload['ts'];
    final Object? sessionId = payload['s'];
    final Object? host = payload['h'];
    if (ts is! int || sessionId is! String || host is! String) {
      _protocolError('hello with a missing or invalid ts, s or h');
      return;
    }
    final Object? version = payload['v'];
    if (version != RealtimeProtocol.protocolVersion) {
      // Connection.ts:398-400 warns and goes on.
      _log(
        DatabaseLogLevel.warning,
        'protocol version mismatch: ${_describe(version)}',
      );
    }
    // The emulator names its own Host header; the user's host is kept (Connection.ts:348-351).
    if (!_target.repoInfo.isUsingEmulator && !_target.acceptServerHost(host)) {
      _log(DatabaseLogLevel.warning, 'ignored server host (invalid)');
    }
    _connectTimer?.cancel();
    _connectTimer = null;
    _state = _State.connected;
    _liveness?.onHello();
    _delegate.onReady(ts, sessionId);
  }

  void _onShutdown(Object? payload) {
    if (payload is! String) {
      _protocolError('shutdown without a reason');
      return;
    }
    final String reason = safeServerText(payload);
    _log(DatabaseLogLevel.warning, 'server shutdown: $reason');
    // Closed before the callback, so a close() from inside onKill reports nothing
    // (Connection.ts:517-530 clears onDisconnect_).
    _state = _State.closed;
    _teardownSocket(abandon: false);
    _delegate.onKill(reason);
  }

  void _onReset(Object? payload) {
    final bool emulator = _target.repoInfo.isUsingEmulator;
    if (payload is! String || emulator || !_target.acceptServerHost(payload)) {
      // B-3.3c: an invalid host restores the configured one; the emulator never changes host
      // (T1). Either way the attempt fails into the normal backoff.
      _log(
        DatabaseLogLevel.warning,
        emulator
            ? 'server reset (the emulator keeps its host)'
            : 'ignored server host (invalid)',
      );
      _target.forgetServerHost();
      close();
      return;
    }
    if (_state == _State.connected) {
      // Connection.ts:444-446: a reset after the hello is an ordinary disconnect.
      close(DisconnectReason.serverReset);
      return;
    }
    if (_resets >= _timings.maxResetsPerAttempt) {
      // T2: JS reconnects at once without a limit (Connection.ts:447-451).
      _log(DatabaseLogLevel.warning, 'too many server resets in one attempt');
      _fail(DisconnectReason.other);
      return;
    }
    _resets++;
    _log(DatabaseLogLevel.info, 'server reset before the hello, reconnecting');
    _teardownSocket(abandon: false);
    _openSocket();
  }

  void _protocolError(String what) {
    _log(DatabaseLogLevel.warning, 'protocol error: $what');
    _fail(DisconnectReason.other);
  }

  /// Ends the connection for [reason]; before the hello the server host is forgotten too.
  void _fail(DisconnectReason reason) {
    if (_state == _State.connecting) {
      _target.forgetServerHost();
    }
    close(reason);
  }

  /// Sends one raw frame. False when the socket is gone (the connection is then closed).
  bool _sendFrame(String frame) {
    final WsChannel? channel = _channel;
    if (channel == null || _state == _State.closed) {
      return false;
    }
    try {
      channel.sendText(frame);
    } on Object catch (error) {
      _log(DatabaseLogLevel.info, 'send failed (${error.runtimeType})');
      _fail(DisconnectReason.other);
      return false;
    }
    _liveness?.onFrameSent(frame.length);
    return true;
  }

  void _teardownSocket({required bool abandon}) {
    _generation++;
    // A connector call still running is told to give up, so no socket stays open (review M2).
    final Completer<void>? pendingAbort = _pendingAbort;
    _pendingAbort = null;
    if (pendingAbort != null && !pendingAbort.isCompleted) {
      pendingAbort.complete();
    }
    _connectTimer?.cancel();
    _connectTimer = null;
    _liveness?.stop();
    _liveness = null;
    _assembler?.reset();
    _assembler = null;
    final StreamSubscription<WsEvent>? subscription = _subscription;
    _subscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    final WsChannel? channel = _channel;
    _channel = null;
    if (channel == null) {
      return;
    }
    if (abandon) {
      channel.abandon();
      return;
    }
    unawaited(
      channel.close().then<void>(
        (_) {},
        onError: (Object error) =>
            _log(DatabaseLogLevel.debug, 'close failed (${error.runtimeType})'),
      ),
    );
  }

  void _logRequest(Map<String, Object?> request) {
    final Object? action = request[RealtimeProtocol.actionKey];
    if (action is! String) {
      _log(DatabaseLogLevel.debug, 'send request');
    } else if (credentialActions.contains(action)) {
      _log(DatabaseLogLevel.debug, '$action (contents hidden)');
    } else {
      _log(DatabaseLogLevel.debug, 'send $action');
    }
  }

  void _log(DatabaseLogLevel level, String message) {
    _logger?.call(level, message);
  }

  static String _describe(Object? value) =>
      value is String ? safeServerText(value) : '(${value.runtimeType})';
}
