// Owner T. A protocol-level fake server over FakeWsConnector, still without sockets (test plan
// 2.3): it speaks `rtdb_protocol.md` 4 and 5 at message level.

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
final class FakeRtdbServer {
  /// Creates the server. Every accepted connection gets a hello after [helloDelay] with session id
  /// [session] and host [host]; [clock] gives the hello `ts` in ms.
  FakeRtdbServer({
    Duration helloDelay = Duration.zero,
    String session = 'sess-1',
    String host = 'h.example',
    int Function()? clock,
  }) {
    throw UnimplementedError();
  }

  /// The connector under the server, for scripting attempts.
  FakeWsConnector get connector => throw UnimplementedError();

  /// The closure to inject as the [WsConnector].
  WsConnector get connect => throw UnimplementedError();

  /// A tiny in-memory tree, for the tests that need an echo (a put answered by a `d` push).
  Map<String, Object?> get data => throw UnimplementedError();

  /// Answers every request of [action] with [handler]'s result as `d` and status `ok`.
  void respondTo(
    String action,
    Object? Function(Map<String, Object?> body) handler,
  ) {
    throw UnimplementedError();
  }

  /// Answers the next request of [action] with [status] and [reason].
  void failNext(String action, String status, [String? reason]) {
    throw UnimplementedError();
  }

  /// Keeps responses back (sent, not acked) until [releaseResponses].
  void holdResponses() {
    throw UnimplementedError();
  }

  /// Sends the held responses in order.
  void releaseResponses() {
    throw UnimplementedError();
  }

  /// Pushes `d` with [json] at [path], tagged with [tag] when given.
  void pushData(String path, Object? json, {int? tag}) {
    throw UnimplementedError();
  }

  /// Pushes `m` with [changes] at [path], tagged with [tag] when given.
  void pushMerge(String path, Map<String, Object?> changes, {int? tag}) {
    throw UnimplementedError();
  }

  /// Pushes `rm` at [path] with [ranges] (`{"s":..,"e":..,"m":..}` entries as measured, their
  /// `s`/`e` paths sent without the leading slash), tagged with [tag] when given.
  void pushRangeMerge(
    String path,
    List<Map<String, Object?>> ranges, {
    int? tag,
  }) {
    throw UnimplementedError();
  }

  /// Pushes `c` for [path] with the query objects [queries] when given.
  void pushListenCancel(String path, [List<Map<String, Object?>>? queries]) {
    throw UnimplementedError();
  }

  /// Pushes `ac` with [status] and [explanation].
  void pushAuthRevoked(String status, String explanation) {
    throw UnimplementedError();
  }

  /// Pushes `apc` with [status] and [explanation].
  void pushAppCheckRevoked(String status, String explanation) {
    throw UnimplementedError();
  }

  /// Sends the control shutdown `s` with [reason].
  void pushShutdown(String reason) {
    throw UnimplementedError();
  }

  /// Sends the control reset `r` with [host].
  void pushReset(String host) {
    throw UnimplementedError();
  }

  /// Every request received, with its connection number.
  List<ServerSeen> get log => throw UnimplementedError();

  /// How many connections were accepted.
  int get connections => throw UnimplementedError();
}
