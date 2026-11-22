/// The browser WebSocket channel over `package:web` (owner T). Selected by `ws_connector.dart`
/// on the web; must compile with dart2js and dart2wasm.
///
/// `binaryType = 'arraybuffer'`; the headers argument of the connector is ignored, so the caller
/// puts `p` and `ac` in the URL (`rtdb_protocol.md` 2.3, threat model T25). `onerror` carries no
/// detail ([WsError] with a fixed message); `onclose` gives the code.
library;

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
WsConnector webWsConnector() {
  throw UnimplementedError();
}

/// A [WsChannel] over a browser [web.WebSocket].
final class WebWsChannel implements WsChannel {
  /// Wraps [socket], which must already be open.
  WebWsChannel(web.WebSocket socket) {
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
