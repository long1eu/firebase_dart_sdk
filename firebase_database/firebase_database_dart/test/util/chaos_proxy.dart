// Owner U. A test-only TCP proxy between the client and the emulator that misbehaves on demand;
// the API of cloud_firestore_dart's test/util/chaos_proxy.dart, to be copied in (test plan 2.5).

import 'dart:typed_data';

/// The direction of the bytes going through a [ChaosProxy].
enum ChaosDirection {
  /// From the client to the backend.
  up,

  /// From the backend to the client.
  down,
}

/// How a [ChaosProxy] treats the bytes it receives.
enum ChaosMode {
  /// Forwards the bytes (after [ChaosProxy.delay]).
  forward,

  /// Keeps the bytes without forwarding or closing; forwards them in order on [forward].
  stall,

  /// Like [stall], only from the client to the backend.
  stallUp,

  /// Like [stall], only from the backend to the client: the backend still applies the requests.
  stallDown,

  /// Drops the bytes without closing; leaving this mode cuts the connections that lost bytes.
  blackHole,
}

/// A TCP proxy to a target host and port on a free loopback port.
final class ChaosProxy {
  ChaosProxy._();

  /// Starts a proxy to [targetHost]:[targetPort].
  static Future<ChaosProxy> start(String targetHost, int targetPort) {
    throw UnimplementedError();
  }

  /// The loopback address the proxy listens on.
  String get host => throw UnimplementedError();

  /// The port; the same across [unplug] and [plug].
  int get port => throw UnimplementedError();

  /// Stops listening and drops the open connections: connecting fails (refused).
  Future<void> unplug() {
    throw UnimplementedError();
  }

  /// Listens again on the same port after [unplug].
  Future<void> plug() {
    throw UnimplementedError();
  }

  /// The latency added to every chunk, in both directions.
  Duration delay = Duration.zero;

  /// While true, new connections are closed as soon as they are accepted.
  bool refuseConnections = false;

  /// Called with every chunk received (`delivered` false) and handed on (`delivered` true).
  void Function(
    int connection,
    ChaosDirection direction,
    Uint8List data, {
    required bool delivered,
  })?
  tap;

  /// Called with every chunk before it is forwarded; true cuts the connection instead.
  bool Function(ChaosDirection direction, Uint8List data)? cutWhen;

  /// The number of connections accepted so far.
  int get acceptedConnections => throw UnimplementedError();

  /// The number of connections cut by the proxy so far.
  int get cuts => throw UnimplementedError();

  /// The bytes received from the clients so far.
  int get bytesUp => throw UnimplementedError();

  /// The bytes received from the backend so far.
  int get bytesDown => throw UnimplementedError();

  /// Backend bytes that a cut dropped before they reached the client (lost answers).
  int get answerBytesLostByCuts => throw UnimplementedError();

  /// Whether nothing waits in a delay queue.
  bool get delayQueuesEmpty => throw UnimplementedError();

  /// The current mode.
  ChaosMode get mode => throw UnimplementedError();

  /// Changes the mode (see [ChaosMode]).
  set mode(ChaosMode value) {
    throw UnimplementedError();
  }

  /// The number of connections currently open.
  int get openConnections => throw UnimplementedError();

  /// Drops every open connection.
  void cut() {
    throw UnimplementedError();
  }

  /// Cuts and refuses new connections until [restore].
  void disconnect() {
    throw UnimplementedError();
  }

  /// Accepts connections again after [disconnect].
  void restore() {
    throw UnimplementedError();
  }

  /// Cuts once [bytes] more bytes went in [direction]; completes when the cut happened.
  Future<void> cutAfter(ChaosDirection direction, int bytes) {
    throw UnimplementedError();
  }

  /// Cuts at the next chunk in [direction] of at least [minBytes] bytes.
  Future<void> cutOnNext(ChaosDirection direction, {int minBytes = 1}) {
    throw UnimplementedError();
  }

  /// Completes once the delay queues are empty and the backend was quiet for [quiet], or after
  /// [timeout].
  Future<void> backendQuiet({
    Duration quiet = const Duration(milliseconds: 400),
    Duration timeout = const Duration(seconds: 5),
  }) {
    throw UnimplementedError();
  }

  /// Stops the proxy.
  Future<void> close() {
    throw UnimplementedError();
  }
}
