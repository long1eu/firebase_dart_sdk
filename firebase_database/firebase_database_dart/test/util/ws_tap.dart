// Owner U. WebSocket-aware observation and faults on top of ChaosProxy (test plan 2.5): parses the
// HTTP upgrade and the RFC 6455 frames, reassembles the RTDB envelopes, and acts on whole frames.

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

  /// The text of a text frame, else null.
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

/// Frame-accurate observation and faults on a [ChaosProxy] (plugs into its `tap` and `cutWhen`).
final class WsFrameTap {
  /// Installs the tap on [proxy].
  WsFrameTap(ChaosProxy proxy) {
    throw UnimplementedError();
  }

  /// Every frame, both directions.
  Stream<TapFrame> get frames => throw UnimplementedError();

  /// Every re-assembled envelope, both directions.
  Stream<TapMessage> get messages => throw UnimplementedError();

  /// The headers of the last upgrade request.
  Map<String, String> get upgradeHeaders => throw UnimplementedError();

  /// The URI of the last upgrade request.
  Uri get upgradeUri => throw UnimplementedError();

  /// Drops the first frame matching [test], then cuts ("cut before the ack").
  void cutBeforeFrame(bool Function(TapMessage m) test) {
    throw UnimplementedError();
  }

  /// Forwards the first frame matching [test], then cuts.
  void cutAfterFrame(bool Function(TapMessage m) test) {
    throw UnimplementedError();
  }

  /// Black-holes the frames matching [test] and keeps the connection (lost ack without a cut).
  void dropFrames(bool Function(TapMessage m) test) {
    throw UnimplementedError();
  }

  /// Delays by [d] the frames matching [where] (all when null).
  void delayFrames(Duration d, {bool Function(TapMessage m)? where}) {
    throw UnimplementedError();
  }

  /// Sends [envelope] to the client as if the server had sent it.
  void injectToClient(Map<String, Object?> envelope) {
    throw UnimplementedError();
  }

  /// Sends a real close frame with [code] and [reason] to the client.
  void closeToClient(int code, [String? reason]) {
    throw UnimplementedError();
  }

  /// Rewrites every server message through [f]; null drops it. Null [f] removes the rewrite.
  void rewriteServerMessages(
    Map<String, Object?>? Function(Map<String, Object?> m)? f,
  ) {
    throw UnimplementedError();
  }

  /// Completes with the next client message matching [test], or fails after [timeout].
  Future<TapMessage> nextClient(
    bool Function(TapMessage m) test, {
    required Duration timeout,
  }) {
    throw UnimplementedError();
  }
}
