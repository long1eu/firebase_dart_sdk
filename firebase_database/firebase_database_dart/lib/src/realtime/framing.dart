/// Splitting outgoing messages into frames and joining incoming frames (owner T).
///
/// `rtdb_protocol.md` 3.1; limits of threat model T9 and T10.
library;

import 'dart:convert';

/// Splits the JSON text of one message into WebSocket text frames (`rtdb_protocol.md` 3.1).
final class FrameSplitter {
  /// Creates a splitter with frames of at most [maxFrameUnits] UTF-16 code units
  /// (`ConnectionTimings.maxFrameUnits`, 16384). At least 2, so that a surrogate pair always fits.
  const FrameSplitter({required this.maxFrameUnits})
    : assert(maxFrameUnits >= 2, 'a frame must hold a surrogate pair');

  /// The largest frame, in UTF-16 code units.
  final int maxFrameUnits;

  /// The largest piece count a frame count can carry: 6 digits (`rtdb_protocol.md` 1.2).
  static const int _maxPieces = 999999;

  /// The frames of [json]: [json] itself when it fits in one frame; otherwise the decimal count of
  /// pieces, then the pieces. Pieces are cut on code-point boundaries, never inside a surrogate
  /// pair: the server decodes each frame as UTF-8 on its own, so a split inside a UTF-8 sequence
  /// makes it drop the whole message silently, and a lone surrogate is stored as U+FFFD
  /// (`rtdb_emulator_probe.md` addendum 2 item 5, measured; JS splits by code unit, a defect). A
  /// piece may therefore be one unit shorter than [maxFrameUnits].
  ///
  /// Throws [ArgumentError] when [json] needs more than 999999 pieces (the count has at most 6
  /// digits; far above the server's 16 MiB message limit).
  List<String> framesFor(String json) {
    if (json.length <= maxFrameUnits) {
      return <String>[json];
    }
    final List<String> pieces = <String>[];
    int start = 0;
    while (start < json.length) {
      int end = start + maxFrameUnits;
      if (end >= json.length) {
        end = json.length;
      } else if (_isLead(json.codeUnitAt(end - 1)) &&
          _isTrail(json.codeUnitAt(end))) {
        end -= 1;
      }
      pieces.add(json.substring(start, end));
      start = end;
    }
    if (pieces.length > _maxPieces) {
      throw ArgumentError(
        'a message of ${json.length} code units needs more than $_maxPieces frames',
      );
    }
    return <String>['${pieces.length}', ...pieces];
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
  FrameAssembler({required int maxMessageBytes, required int maxDepth})
    : _maxMessageBytes = maxMessageBytes,
      _maxDepth = maxDepth;

  /// A frame count: 1 to 6 digits, no leading zero (threat model T9; JS accepts anything that
  /// `Number()` parses, `WebSocketConnection.ts:316-329`, which lets `0`, `-1` or `1e3` start a
  /// buffer that never completes).
  static final RegExp _countPattern = RegExp(r'^[1-9][0-9]{0,5}$');

  final int _maxMessageBytes;
  final int _maxDepth;
  final List<String> _pieces = <String>[];
  int _expected = 0;
  int _bytes = 0;

  /// Adds [frame]. Returns the decoded message when [frame] completed one, null while more pieces
  /// are expected or when [frame] was ignored. Throws [FramingException] when the message is not a
  /// JSON object, is too large or too deep; the assembler is then [reset].
  Map<String, Object?>? add(String frame) {
    if (!isBuffering) {
      if (frame == '0') {
        return null;
      }
      if (_countPattern.hasMatch(frame)) {
        _expected = int.parse(frame);
        return null;
      }
      _countBytes(frame);
      _bytes = 0;
      return _decode(frame);
    }
    _countBytes(frame);
    _pieces.add(frame);
    if (_pieces.length < _expected) {
      return null;
    }
    final String text = _pieces.join();
    reset();
    return _decode(text);
  }

  /// Whether pieces of a multi-frame message are buffered.
  bool get isBuffering => _expected > 0;

  /// Drops any buffered piece (the channel closed).
  void reset() {
    _pieces.clear();
    _expected = 0;
    _bytes = 0;
  }

  void _countBytes(String frame) {
    _bytes += utf8Length(frame);
    if (_bytes > _maxMessageBytes) {
      reset();
      throw FramingException('message larger than $_maxMessageBytes bytes');
    }
  }

  Map<String, Object?> _decode(String text) {
    checkJsonDepth(text, _maxDepth);
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw const FramingException('message is not valid JSON');
    }
    if (decoded is! Map<String, Object?>) {
      throw const FramingException('message is not a JSON object');
    }
    return decoded;
  }
}

/// Throws [FramingException] when the arrays and objects of the JSON text [text] nest deeper than
/// [maxDepth] (threat model T10). One pass over the code units, no recursion; brackets inside
/// strings do not count. Malformed JSON is left to the decoder.
void checkJsonDepth(String text, int maxDepth) {
  int depth = 0;
  bool inString = false;
  bool escaped = false;
  for (int i = 0; i < text.length; i++) {
    final int unit = text.codeUnitAt(i);
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (unit == _backslash) {
        escaped = true;
      } else if (unit == _quote) {
        inString = false;
      }
    } else if (unit == _quote) {
      inString = true;
    } else if (unit == _openBrace || unit == _openBracket) {
      depth++;
      if (depth > maxDepth) {
        throw FramingException('message nested deeper than $maxDepth');
      }
    } else if (unit == _closeBrace || unit == _closeBracket) {
      depth--;
    }
  }
}

/// The length of [text] in UTF-8 bytes, without encoding it. A lone surrogate counts 3 bytes (it
/// is encoded as U+FFFD).
int utf8Length(String text) {
  int bytes = 0;
  final int length = text.length;
  for (int i = 0; i < length; i++) {
    final int unit = text.codeUnitAt(i);
    if (unit < 0x80) {
      bytes += 1;
    } else if (unit < 0x800) {
      bytes += 2;
    } else if (_isLead(unit) &&
        i + 1 < length &&
        _isTrail(text.codeUnitAt(i + 1))) {
      bytes += 4;
      i++;
    } else {
      bytes += 3;
    }
  }
  return bytes;
}

bool _isLead(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

bool _isTrail(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

const int _quote = 0x22;
const int _backslash = 0x5C;
const int _openBrace = 0x7B;
const int _closeBrace = 0x7D;
const int _openBracket = 0x5B;
const int _closeBracket = 0x5D;

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
