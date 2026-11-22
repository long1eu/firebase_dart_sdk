/// Splitting outgoing messages into frames and joining incoming frames (owner T).
///
/// `rtdb_protocol.md` 3.1; limits of threat model T9 and T10.
library;

/// Splits the JSON text of one message into WebSocket text frames (`rtdb_protocol.md` 3.1).
final class FrameSplitter {
  /// Creates a splitter with frames of at most [maxFrameUnits] UTF-16 code units
  /// (`ConnectionTimings.maxFrameUnits`, 16384).
  const FrameSplitter({required this.maxFrameUnits});

  /// The largest frame, in UTF-16 code units.
  final int maxFrameUnits;

  /// The frames of [json]: [json] itself when it fits in one frame; otherwise the decimal count of
  /// pieces, then the pieces. Pieces are cut on code-point boundaries, never inside a surrogate
  /// pair: the server decodes each frame as UTF-8 on its own, so a split inside a UTF-8 sequence
  /// makes it drop the whole message silently, and a lone surrogate is stored as U+FFFD
  /// (`rtdb_emulator_probe.md` addendum 2 item 5, measured; JS splits by code unit, a defect). A
  /// piece may therefore be one unit shorter than [maxFrameUnits].
  List<String> framesFor(String json) {
    throw UnimplementedError();
  }
}

/// Joins incoming frames into messages (`rtdb_protocol.md` 3.1, threat model T9, T10).
///
/// A frame is a count only when nothing is buffered and it matches `^[1-9][0-9]{0,5}$`. A frame
/// `0` while nothing is buffered is ignored (Android `WebsocketConnection.java:285-289`, test plan
/// B-3.1e). Any other frame starts and ends a one-frame message.
final class FrameAssembler {
  /// Creates an assembler that refuses a message longer than [maxMessageBytes] (counted while the
  /// pieces arrive, before they are joined) or nested deeper than [maxDepth] (scanned without
  /// recursion before decoding).
  FrameAssembler({required int maxMessageBytes, required int maxDepth}) {
    throw UnimplementedError();
  }

  /// Adds [frame]. Returns the decoded message when [frame] completed one, null while more pieces
  /// are expected or when [frame] was ignored. Throws [FramingException] when the message is not a
  /// JSON object, is too large or too deep; the assembler is then [reset].
  Map<String, Object?>? add(String frame) {
    throw UnimplementedError();
  }

  /// Whether pieces of a multi-frame message are buffered.
  bool get isBuffering => throw UnimplementedError();

  /// Drops any buffered piece (the channel closed).
  void reset() {
    throw UnimplementedError();
  }
}

/// A frame sequence that is not a valid message. The connection closes as a protocol error and
/// reconnects with backoff (threat model T11); it never reaches the app zone.
final class FramingException implements Exception {
  /// Creates the exception with a [message] that never contains frame text (T7).
  const FramingException(this.message);

  /// What was wrong, without the content.
  final String message;

  @override
  String toString() => 'FramingException: $message';
}
