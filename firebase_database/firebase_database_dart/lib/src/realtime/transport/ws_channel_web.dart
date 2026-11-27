/// The browser WebSocket channel over `package:web` (owner T). Selected by `ws_connector.dart`
/// on the web; must compile with dart2js and dart2wasm.
///
/// `binaryType = 'arraybuffer'`; the headers argument of the connector is ignored, so the caller
/// puts `p` and `ac` in the URL (`rtdb_protocol.md` 2.3, threat model T25). `onerror` carries no
/// detail ([WsError] with a fixed message); `onclose` gives the code. Nothing is written to
/// `localStorage` or `sessionStorage` (threat model T27; JS writes both).
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:firebase_database_dart/src/realtime/transport/ws_channel.dart';
import 'package:web/web.dart' as web;

/// Whether this platform's connector sends upgrade headers. False in a browser: the WebSocket API
/// cannot set them (`rtdb_protocol.md` 2.3).
const bool platformSendsHeaders = false;

/// The connector of this platform, for `ws_connector.dart`. [maxMessageBytes] is not enforced:
/// the browser's limits apply (threat model T9, accepted).
WsConnector createWsConnector({required int maxMessageBytes}) =>
    webWsConnector();

/// A connector over the browser's `WebSocket`.
WsConnector webWsConnector() => _connect;

Future<WsChannel> _connect(
  Uri url, {
  Map<String, String> headers = const <String, String>{},
  Future<void>? abort,
}) {
  if (url.scheme != 'ws' && url.scheme != 'wss') {
    return Future<WsChannel>.error(
      const WsConnectException(
        WsConnectFailure.badScheme,
        'only ws and wss URLs are accepted',
      ),
    );
  }
  final web.WebSocket socket;
  try {
    socket = web.WebSocket(url.toString());
  } on Object catch (e) {
    // A SyntaxError for a URL the browser refuses (a blocked port, a fragment).
    return Future<WsChannel>.error(
      WsConnectException(
        WsConnectFailure.other,
        'the browser refused to open the WebSocket',
        cause: e,
      ),
    );
  }
  socket.binaryType = 'arraybuffer';
  final Completer<WsChannel> completer = Completer<WsChannel>();
  void fail([
    String message = 'the WebSocket did not open (the browser gives no detail)',
  ]) {
    socket
      ..onopen = null
      ..onerror = null
      ..onclose = null;
    if (!completer.isCompleted) {
      completer.completeError(
        WsConnectException(WsConnectFailure.other, message),
      );
    }
  }

  if (abort != null) {
    void stop() {
      if (!completer.isCompleted) {
        try {
          socket.close();
        } on Object {
          // Already closing: nothing more to drop.
        }
        fail('the connect attempt was aborted');
      }
    }

    unawaited(abort.then((_) => stop(), onError: (Object _) => stop()));
  }
  socket
    ..onopen = ((web.Event _) {
      socket
        ..onopen = null
        ..onerror = null
        ..onclose = null;
      if (!completer.isCompleted) {
        completer.complete(WebWsChannel(socket));
      }
    }).toJS
    ..onerror = ((web.Event _) => fail()).toJS
    ..onclose = ((web.CloseEvent _) => fail()).toJS;
  return completer.future;
}

/// How long [WebWsChannel.close] waits for `onclose`.
const Duration _closeBound = Duration(seconds: 5);

/// A [WsChannel] over a browser [web.WebSocket].
final class WebWsChannel implements WsChannel {
  /// Wraps [socket], which must already be open.
  WebWsChannel(web.WebSocket socket) : _socket = socket {
    socket
      ..binaryType = 'arraybuffer'
      ..onmessage = _onMessage.toJS
      ..onerror = _onError.toJS
      ..onclose = _onClose.toJS;
  }

  final web.WebSocket _socket;
  final StreamController<WsEvent> _events = StreamController<WsEvent>();
  final Completer<void> _closedByBrowser = Completer<void>();
  bool _closed = false;
  bool _ended = false;
  Future<void>? _closing;

  @override
  Stream<WsEvent> get events => _events.stream;

  @override
  void sendText(String frame) {
    if (_closed) {
      throw StateError('sendText on a closed WebSocket channel');
    }
    _socket.send(frame.toJS);
  }

  @override
  Future<void> close([int code = 1000, String? reason]) {
    return _closing ??= _close(code, reason);
  }

  Future<void> _close(int code, String? reason) async {
    _closed = true;
    // A browser accepts only 1000 and 3000 to 4999, and a reason of at most 123 bytes.
    final int browserCode = code == 1000 || (code >= 3000 && code <= 4999)
        ? code
        : 1000;
    final String? browserReason = reason != null && reason.length <= 40
        ? reason
        : null;
    try {
      if (browserReason == null) {
        _socket.close(browserCode);
      } else {
        _socket.close(browserCode, browserReason);
      }
    } on Object {
      // Already closing; onclose follows.
    }
    await _closedByBrowser.future.timeout(_closeBound, onTimeout: () {});
  }

  @override
  void abandon() {
    if (_ended) {
      return;
    }
    _closed = true;
    _socket
      ..onmessage = null
      ..onerror = null
      ..onclose = null;
    try {
      _socket.close();
    } on Object {
      // Nothing to do: the socket is dropped either way.
    }
    _end(const WsClosed(null, null));
  }

  void _onMessage(web.MessageEvent event) {
    if (_ended) {
      return;
    }
    final JSAny? data = event.data;
    if (data.isA<JSString>()) {
      _events.add(WsText((data! as JSString).toDart));
    } else if (data.isA<JSArrayBuffer>()) {
      _events.add(WsBinary((data! as JSArrayBuffer).toDart.asUint8List()));
    }
  }

  void _onError(web.Event _) {
    if (!_ended) {
      _events.add(
        WsError(
          StateError('WebSocket error (the browser gives no detail)'),
          StackTrace.current,
        ),
      );
    }
  }

  void _onClose(web.CloseEvent event) {
    _closed = true;
    if (!_closedByBrowser.isCompleted) {
      _closedByBrowser.complete();
    }
    _end(WsClosed(event.code, event.reason.isEmpty ? null : event.reason));
  }

  void _end(WsClosed event) {
    if (_ended) {
      return;
    }
    _ended = true;
    _events.add(event);
    unawaited(_events.close());
  }
}
