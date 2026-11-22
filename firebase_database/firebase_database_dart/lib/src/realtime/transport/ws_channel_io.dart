/// The `dart:io` WebSocket channel (owner T). Selected by `ws_connector.dart` on the VM.
///
/// The upgrade is done by hand (threat model T4): `HttpClient.openUrl` with
/// `followRedirects = false`, a check of 101 and `Sec-WebSocket-Accept`, `detachSocket()`, then
/// `WebSocket.fromUpgradedSocket` with compression off (T5) and no `pingInterval` (liveness is the
/// protocol's ping, `rtdb_protocol.md` 3.4). The bytes of one message are counted on the detached
/// socket and the channel closes past `maxMessageBytes` (T9).
library;

import 'dart:io';

import 'package:firebase_database_dart/src/realtime/transport/ws_channel.dart';

/// Whether this platform's connector sends upgrade headers. True on the VM: the app id and the App
/// Check token travel as `X-Firebase-GMPID` and `X-Firebase-AppCheck` (`rtdb_protocol.md` 2.3,
/// Android style, section 11 last row).
const bool platformSendsHeaders = true;

/// The connector of this platform, for `ws_connector.dart`.
WsConnector createWsConnector({required int maxMessageBytes}) =>
    ioWsConnector(maxMessageBytes: maxMessageBytes);

/// A connector over `dart:io`.
///
/// [httpClient] is used for the upgrade when given (for a proxy through `HttpClient.findProxy`;
/// none is read from the environment, threat model T4); otherwise a new one is created per attempt.
/// No `badCertificateCallback` is ever set.
WsConnector ioWsConnector({
  HttpClient? httpClient,
  required int maxMessageBytes,
}) {
  throw UnimplementedError();
}

/// A [WsChannel] over a `dart:io` [WebSocket].
final class IoWsChannel implements WsChannel {
  /// Wraps [socket], which must already be open. [maxMessageBytes] bounds one inbound message.
  IoWsChannel(WebSocket socket, {required int maxMessageBytes}) {
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
