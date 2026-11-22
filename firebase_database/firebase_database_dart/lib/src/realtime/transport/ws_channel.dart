/// The WebSocket abstraction of the connection half (owner T).
///
/// The events, the channel and the connector of `rtdb_connection_test_plan.md` section 2.1. A
/// channel moves whole text frames: it never splits, joins or frames anything (that is
/// `framing.dart`), and it has no timeout (the connection owns the 30 s connect guard,
/// `rtdb_protocol.md` 1.2).
library;

import 'dart:typed_data';

/// One event of an open [WsChannel], in the order the peer produced them.
sealed class WsEvent {
  /// Constructor for the subclasses.
  const WsEvent();
}

/// A text frame from the server.
final class WsText extends WsEvent {
  /// Creates the event of the frame [data].
  const WsText(this.data);

  /// The text of the frame, as received.
  final String data;

  /// Shows the length only: a frame holds user data (threat model T7).
  @override
  String toString() => 'WsText(${data.length} chars)';
}

/// A binary frame from the server. The connection ignores it (iOS `FWebSocketConnectionTest.m:119`,
/// test plan U-I15).
final class WsBinary extends WsEvent {
  /// Creates the event of the frame [data].
  const WsBinary(this.data);

  /// The bytes of the frame.
  final Uint8List data;

  @override
  String toString() => 'WsBinary(${data.length} bytes)';
}

/// The channel closed, by the peer or locally. Always the last event of [WsChannel.events].
final class WsClosed extends WsEvent {
  /// Creates the event with the close [code] and [reason] when known.
  const WsClosed(this.code, this.reason);

  /// The close code, or null when unknown (a browser gives 1006 or nothing).
  final int? code;

  /// The close reason sent by the peer, if any. Server text: cut before it is logged (T7).
  final String? reason;

  @override
  String toString() => 'WsClosed($code)';
}

/// A transport error. A [WsClosed] may or may not follow; the stream ends either way.
final class WsError extends WsEvent {
  /// Creates the event of [error] raised at [stackTrace].
  const WsError(this.error, this.stackTrace);

  /// The error of the platform socket. May hold a URL with its query: never put it in a message.
  final Object error;

  /// Where [error] was raised.
  final StackTrace stackTrace;

  /// Shows the type of [error] only (threat model T8).
  @override
  String toString() => 'WsError(${error.runtimeType})';
}

/// One open WebSocket, as the connection sees it (test plan 2.1).
abstract interface class WsChannel {
  /// The events of this channel, in order. Single-subscription; ends after a [WsClosed] or a
  /// [WsError].
  Stream<WsEvent> get events;

  /// Sends [frame] as one text frame. Throws [StateError] when the channel is closed. Never splits
  /// and never adds a frame count (`rtdb_protocol.md` 3.1 is done by `FrameSplitter`).
  void sendText(String frame);

  /// Closes the channel with [code] and [reason]. Idempotent; completes when the close handshake
  /// ended or after a short bound.
  Future<void> close([int code = 1000, String? reason]);

  /// Drops the channel without waiting for anything: the connect-timeout case (iOS
  /// `FWebSocketConnectionTest.m:141`, C++ `web_socket_client_impl_test.cc:788`).
  void abandon();
}

/// Opens a WebSocket to [url] with the upgrade [headers].
///
/// Completes when the upgrade succeeded, fails with a [WsConnectException] otherwise. Has no
/// timeout. Only `ws` and `wss` are accepted: another scheme fails with
/// [WsConnectFailure.badScheme] before any socket is opened (C++ U-C20). [headers] are advisory:
/// the browser cannot send them (`rtdb_protocol.md` 2.3).
typedef WsConnector =
    Future<WsChannel> Function(Uri url, {Map<String, String> headers});

/// Why a [WsConnector] could not open a channel.
enum WsConnectFailure {
  /// The peer refused the TCP connection.
  refused,

  /// The host name did not resolve.
  dns,

  /// The TLS handshake failed.
  tls,

  /// The server answered the upgrade with something other than 101, including a 3xx (redirects
  /// are never followed, threat model T4).
  upgradeRejected,

  /// The URL scheme is not `ws` or `wss`.
  badScheme,

  /// Anything else (the browser reports no detail).
  other,
}

/// Thrown (as a failed future) by a [WsConnector].
///
/// Neither [message] nor [toString] holds the URL or a header: the URL can carry the App Check
/// token on the web (threat model T7, T8, T25).
final class WsConnectException implements Exception {
  /// Creates the exception of [kind] with a [message] for people.
  const WsConnectException(
    this.kind,
    this.message, {
    this.httpStatus,
    this.cause,
  });

  /// What went wrong.
  final WsConnectFailure kind;

  /// A description without URL, query or header values.
  final String message;

  /// The HTTP status of a rejected upgrade, when there was one.
  final int? httpStatus;

  /// The platform error, kept for debugging. Never part of [toString]: it may hold the URL.
  final Object? cause;

  @override
  String toString() {
    final String status = httpStatus == null ? '' : ' (HTTP $httpStatus)';
    return 'WsConnectException(${kind.name}): $message$status';
  }
}
