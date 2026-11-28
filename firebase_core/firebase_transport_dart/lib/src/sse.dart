/// One result of [SseDecoder].
sealed class SseItem {
  /// Subclasses only.
  const SseItem();
}

/// One dispatched event: the joined `data` lines, without the final line feed.
final class SseEvent extends SseItem {
  /// An event with [data].
  const SseEvent(this.data);

  /// The joined `data` lines.
  final String data;
}

/// From [SseDecoder.add]: invalid UTF-8. From [SseDecoder.close]: the body ended inside a line or
/// inside an event.
final class SseMalformed extends SseItem {
  /// The body is malformed.
  const SseMalformed();
}

/// From [SseDecoder.add]: the bytes of the current line plus the event's accumulated data passed
/// `maxEventBytes`.
final class SseEventTooLarge extends SseItem {
  /// The event is too large.
  const SseEventTooLarge();
}

/// From [SseDecoder.add]: the bytes given to [SseDecoder.add] so far passed `maxStreamBytes`.
final class SseStreamTooLarge extends SseItem {
  /// The stream is too large.
  const SseStreamTooLarge();
}

const int _lineFeed = 0x0a;
const int _carriageReturn = 0x0d;
const int _colon = 0x3a;
const int _byteOrderMark = 0xfeff;

/// Decodes a server-sent events body, chunk by chunk, with caps.
///
/// Bytes are strict UTF-8 (a sequence may be split across chunks; a leading byte-order mark is
/// ignored). A line ends at CR LF, LF or a lone CR, also when the CR and the LF are in two chunks.
/// A line starting with `:` is a comment. Otherwise the field name is the text before the first `:`
/// (the whole line if there is none) and the value the rest, with one leading space removed; a
/// `data` field appends its value and a line feed to the event's data, and every other field is
/// ignored. An empty line dispatches the event when its data is not empty, without the final line
/// feed. [SseMalformed], [SseEventTooLarge] and [SseStreamTooLarge] end the decoding: each is
/// returned once, after the events completed before it, and every later [add] and [close] returns
/// an empty list.
final class SseDecoder {
  /// Throws [ArgumentError] unless both caps are greater than 0.
  SseDecoder({required int maxEventBytes, required int maxStreamBytes})
    : _maxEventBytes = maxEventBytes,
      _maxStreamBytes = maxStreamBytes {
    if (maxEventBytes <= 0) {
      throw ArgumentError.value(
        maxEventBytes,
        'maxEventBytes',
        'must be greater than 0',
      );
    }
    if (maxStreamBytes <= 0) {
      throw ArgumentError.value(
        maxStreamBytes,
        'maxStreamBytes',
        'must be greater than 0',
      );
    }
  }

  final int _maxEventBytes;
  final int _maxStreamBytes;
  final _Utf8Reader _utf8 = _Utf8Reader();
  final StringBuffer _line = StringBuffer();
  final StringBuffer _data = StringBuffer();
  int _lineBytes = 0;
  int _dataBytes = 0;
  int _streamBytes = 0;
  bool _started = false;
  bool _afterCarriageReturn = false;
  bool _finished = false;

  /// Takes the next bytes of the body and returns the items they complete, in order.
  List<SseItem> add(List<int> chunk) {
    final List<SseItem> items = <SseItem>[];
    for (final int byte in chunk) {
      if (_finished) {
        break;
      }
      _streamBytes++;
      if (_streamBytes > _maxStreamBytes) {
        _end(items, const SseStreamTooLarge());
        break;
      }
      _addByte(byte, items);
    }
    return items;
  }

  /// Tells the decoder that the body ended.
  ///
  /// Returns one [SseMalformed] when a line or an event is unfinished, otherwise an empty list.
  List<SseItem> close() {
    if (_finished) {
      return <SseItem>[];
    }
    _finished = true;
    if (_utf8.inSequence || _lineBytes > 0 || _dataBytes > 0) {
      return <SseItem>[const SseMalformed()];
    }
    return <SseItem>[];
  }

  void _addByte(int byte, List<SseItem> items) {
    final int codePoint = _utf8.feed(byte);
    if (codePoint == _Utf8Reader.invalid) {
      _end(items, const SseMalformed());
    } else if (codePoint != _Utf8Reader.pending) {
      _addCodePoint(codePoint, items);
    }
  }

  void _addCodePoint(int codePoint, List<SseItem> items) {
    if (!_started) {
      _started = true;
      if (codePoint == _byteOrderMark) {
        return;
      }
    }
    final bool afterCarriageReturn = _afterCarriageReturn;
    _afterCarriageReturn = false;
    if (codePoint == _lineFeed) {
      if (!afterCarriageReturn) {
        _endLine(items);
      }
      return;
    }
    if (codePoint == _carriageReturn) {
      _endLine(items);
      _afterCarriageReturn = true;
      return;
    }
    _line.writeCharCode(codePoint);
    _lineBytes += _utf8Length(codePoint);
    if (_lineBytes + _dataBytes > _maxEventBytes) {
      _end(items, const SseEventTooLarge());
    }
  }

  void _endLine(List<SseItem> items) {
    final String line = _line.toString();
    _line.clear();
    _lineBytes = 0;
    if (line.isEmpty) {
      _dispatch(items);
      return;
    }
    if (line.codeUnitAt(0) == _colon) {
      return;
    }
    final int colon = line.indexOf(':');
    final String field = colon < 0 ? line : line.substring(0, colon);
    if (field != 'data') {
      return;
    }
    String value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) {
      value = value.substring(1);
    }
    _data
      ..write(value)
      ..writeCharCode(_lineFeed);
    _dataBytes += _utf8LengthOf(value) + 1;
  }

  void _dispatch(List<SseItem> items) {
    if (_dataBytes == 0) {
      return;
    }
    final String data = _data.toString();
    _data.clear();
    _dataBytes = 0;
    items.add(SseEvent(data.substring(0, data.length - 1)));
  }

  void _end(List<SseItem> items, SseItem item) {
    _finished = true;
    items.add(item);
  }
}

int _utf8Length(int codePoint) {
  if (codePoint < 0x80) {
    return 1;
  }
  if (codePoint < 0x800) {
    return 2;
  }
  return codePoint < 0x10000 ? 3 : 4;
}

int _utf8LengthOf(String text) {
  int length = 0;
  for (final int rune in text.runes) {
    length += _utf8Length(rune);
  }
  return length;
}

/// A strict, incremental UTF-8 decoder of one code point at a time.
///
/// Refuses overlong forms, surrogates, code points above U+10FFFF, stray continuation bytes, a lead
/// byte inside a sequence and values that are not bytes.
final class _Utf8Reader {
  /// [feed] needs more bytes.
  static const int pending = -1;

  /// [feed] saw invalid UTF-8.
  static const int invalid = -2;

  int _needed = 0;
  int _codePoint = 0;
  int _lower = 0x80;
  int _upper = 0xbf;

  /// True when a sequence is started and not finished.
  bool get inSequence => _needed > 0;

  /// Takes one byte; returns a code point, [pending] or [invalid].
  int feed(int byte) {
    if (byte < 0 || byte > 0xff) {
      return invalid;
    }
    if (_needed == 0) {
      return _lead(byte);
    }
    if (byte < _lower || byte > _upper) {
      return invalid;
    }
    _lower = 0x80;
    _upper = 0xbf;
    _codePoint = (_codePoint << 6) | (byte & 0x3f);
    _needed--;
    return _needed == 0 ? _codePoint : pending;
  }

  int _lead(int byte) {
    if (byte < 0x80) {
      return byte;
    }
    if (byte >= 0xc2 && byte <= 0xdf) {
      return _begin(1, byte & 0x1f, 0x80, 0xbf);
    }
    if (byte >= 0xe0 && byte <= 0xef) {
      return _leadOfThree(byte);
    }
    if (byte >= 0xf0 && byte <= 0xf4) {
      return _leadOfFour(byte);
    }
    return invalid;
  }

  /// E0 needs A0 to BF next (no overlong form); ED needs 80 to 9F (no surrogate).
  int _leadOfThree(int byte) {
    final int lower = byte == 0xe0 ? 0xa0 : 0x80;
    final int upper = byte == 0xed ? 0x9f : 0xbf;
    return _begin(2, byte & 0x0f, lower, upper);
  }

  /// F0 needs 90 to BF next (no overlong form); F4 needs 80 to 8F (at most U+10FFFF).
  int _leadOfFour(int byte) {
    final int lower = byte == 0xf0 ? 0x90 : 0x80;
    final int upper = byte == 0xf4 ? 0x8f : 0xbf;
    return _begin(3, byte & 0x07, lower, upper);
  }

  int _begin(int needed, int bits, int lower, int upper) {
    _needed = needed;
    _codePoint = bits;
    _lower = lower;
    _upper = upper;
    return pending;
  }
}
