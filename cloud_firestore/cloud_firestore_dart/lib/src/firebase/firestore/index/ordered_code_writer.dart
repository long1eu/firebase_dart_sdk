import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';

/// Writes values in the "ordered code" format of the backend: the byte-wise
/// (unsigned) order of two encodings is the order of the encoded values.
/// Port of `OrderedCodeWriter` of the Android SDK.
///
/// Every value can be written ascending or descending; a descending encoding
/// is the bitwise complement of the ascending one.
///
/// PORTING NOTE: 64-bit integers go through [Int64] and doubles through
/// [ByteData], so that the encoding is the same on the web, where `int` has
/// 53 bits.
class OrderedCodeWriter {
  /// Creates a new writer with a default initial buffer size.
  OrderedCodeWriter() : _buffer = Uint8List(_defaultBufferSize);

  // Note: This code is copied from the backend. Code that is not used by
  // Firestore was removed.

  static const int escape1 = 0x00;
  static const int nullByte = 0xff; // Combined with escape1
  static const int separator = 0x01; // Combined with escape1

  static const int escape2 = 0xff;
  static const int infinity = 0xff; // Combined with escape2
  static const int ffByte = 0x00; // Combined with escape2

  /// The default size of the buffer. This is arbitrary, but likely larger than
  /// most index values so that less copies of the underlying buffer will be
  /// made. For large values, a single copy will made to double the buffer
  /// length.
  static const int _defaultBufferSize = 1024;

  /// This array maps encoding length to header bits in the first two bytes for
  /// SignedNumAscending encoding.
  static const List<List<int>> _lengthToHeaderBits = <List<int>>[
    <int>[0, 0],
    <int>[0x80, 0],
    <int>[0xc0, 0],
    <int>[0xe0, 0],
    <int>[0xf0, 0],
    <int>[0xf8, 0],
    <int>[0xfc, 0],
    <int>[0xfe, 0],
    <int>[0xff, 0],
    <int>[0xff, 0x80],
    <int>[0xff, 0xc0],
  ];

  Uint8List _buffer;
  int _position = 0;

  void writeBytesAscending(List<int> value) {
    for (int i = 0; i < value.length; ++i) {
      _writeByteAscending(value[i] & 0xff);
    }
    _writeSeparatorAscending();
  }

  void writeBytesDescending(List<int> value) {
    for (int i = 0; i < value.length; ++i) {
      _writeByteDescending(value[i] & 0xff);
    }
    _writeSeparatorDescending();
  }

  /// Writes utf8 bytes into this byte sequence, ascending.
  void writeUtf8Ascending(String sequence) {
    _writeUtf8(sequence, _writeByteAscending);
    _writeSeparatorAscending();
  }

  /// Writes utf8 bytes into this byte sequence, descending.
  void writeUtf8Descending(String sequence) {
    _writeUtf8(sequence, _writeByteDescending);
    _writeSeparatorDescending();
  }

  /// Encodes the UTF-16 [sequence] as UTF-8, one byte at a time. Like the
  /// Android writer (and unlike `utf8.encode`) an unpaired surrogate is
  /// combined with the code unit that follows it instead of being replaced.
  void _writeUtf8(String sequence, void Function(int byte) writeByte) {
    final int utf16Length = sequence.length;
    for (int i = 0; i < utf16Length; i++) {
      final int c = sequence.codeUnitAt(i);
      if (c < 0x80) {
        writeByte(c);
      } else if (c < 0x800) {
        writeByte(0xc0 | (c >> 6));
        writeByte(0x80 | (0x3f & c));
      } else if (c < 0xd800 || 0xdfff < c) {
        writeByte(0xe0 | (c >> 12));
        writeByte(0x80 | (0x3f & (c >> 6)));
        writeByte(0x80 | (0x3f & c));
      } else {
        final int codePoint = _codePointAt(sequence, i);
        ++i; // Skip the low surrogate.
        writeByte(0xf0 | ((codePoint >> 18) & 0x07));
        writeByte(0x80 | (0x3f & (codePoint >> 12)));
        writeByte(0x80 | (0x3f & (codePoint >> 6)));
        writeByte(0x80 | (0x3f & codePoint));
      }
    }
  }

  /// `Character.codePointAt`: the code point of a valid surrogate pair at
  /// [index], otherwise the code unit itself.
  static int _codePointAt(String sequence, int index) {
    final int high = sequence.codeUnitAt(index);
    if (high >= 0xd800 && high <= 0xdbff && index + 1 < sequence.length) {
      final int low = sequence.codeUnitAt(index + 1);
      if (low >= 0xdc00 && low <= 0xdfff) {
        return 0x10000 + ((high - 0xd800) << 10) + (low - 0xdc00);
      }
    }
    return high;
  }

  /// Writes an unsigned long in the ordered code format, ascending.
  void writeUnsignedLongAscending(Int64 value) {
    // Values are encoded with a single byte length prefix, followed by the
    // actual value in big-endian format with leading 0 bytes dropped.
    final int len = _unsignedNumLength(value);
    _ensureAvailable(1 + len);
    _buffer[_position++] = len; // Write the length
    Int64 x = value;
    for (int i = _position + len - 1; i >= _position; --i) {
      _buffer[i] = (x & 0xff).toInt();
      x = x.shiftRightUnsigned(8);
    }
    _position += len;
  }

  /// Writes an unsigned long in the ordered code format, descending.
  void writeUnsignedLongDescending(Int64 value) {
    // Values are encoded with a complemented single byte length prefix,
    // followed by the complement of the actual value in big-endian format with
    // leading 0xff bytes dropped.
    final int len = _unsignedNumLength(value);
    _ensureAvailable(1 + len);
    _buffer[_position++] = ~len & 0xff; // Write the length
    Int64 x = value;
    for (int i = _position + len - 1; i >= _position; --i) {
      _buffer[i] = ~(x & 0xff).toInt() & 0xff;
      x = x.shiftRightUnsigned(8);
    }
    _position += len;
  }

  /// Writes a signed long in the ordered code format, ascending.
  void writeSignedLongAscending(Int64 value) {
    final Int64 val = value.isNegative ? ~value : value;
    if (val < 64) {
      // Fast path for encoding length == 1
      _ensureAvailable(1);
      _buffer[_position++] =
          (_lengthToHeaderBits[1][0] ^ (value & 0xff).toInt()) & 0xff;
      return;
    }
    final int len = _signedNumLength(val);
    _ensureAvailable(len);
    // We should handle all encoding length == 1 above.
    if (len < 2) {
      throw AssertionError('Invalid length ($len) returned by signedNumLength');
    }
    final int signByte = value.isNegative ? 0xff : 0;
    int startIndex = _position;
    // Sign extend longs that are encoded as 9 or 10 bytes.
    if (len == 10) {
      startIndex += 2;
      _buffer[_position] = signByte;
      _buffer[_position + 1] = signByte;
    } else if (len == 9) {
      startIndex += 1;
      _buffer[_position] = signByte;
    }
    // Encode the long big-endian
    Int64 x = value;
    for (int i = len - 1 + _position; i >= startIndex; --i) {
      _buffer[i] = (x & 0xff).toInt();
      x >>= 8;
    }
    // Encode the length in header bits.
    _buffer[_position] ^= _lengthToHeaderBits[len][0];
    _buffer[_position + 1] ^= _lengthToHeaderBits[len][1];
    _position += len;
  }

  /// Writes a signed long in the ordered code format, descending.
  void writeSignedLongDescending(Int64 value) {
    writeSignedLongAscending(~value);
  }

  void writeDoubleAscending(double val) {
    // This particular encoding has the following properties:
    // The order matches the IEEE 754 floating-point comparison results with the
    // following exceptions:
    //   -0.0 < 0.0
    //   all non-NaN < NaN
    //   NaN = NaN
    writeUnsignedLongAscending(_orderedDoubleBits(val));
  }

  void writeDoubleDescending(double val) {
    // See note in [writeDoubleAscending]
    writeUnsignedLongDescending(_orderedDoubleBits(val));
  }

  /// `Double.doubleToLongBits` (every NaN is the canonical NaN), with the sign
  /// bit flipped for positive numbers and all bits flipped for negative ones.
  static Int64 _orderedDoubleBits(double val) {
    final ByteData data = ByteData(8)
      ..setFloat64(0, val.isNaN ? double.nan : val);
    final Int64 bits = Int64.fromBytesBigEndian(data.buffer.asUint8List());
    return val.isNaN
        // The canonical NaN of Java, 0x7ff8000000000000, with the sign flipped.
        ? Int64.fromInts(0xfff80000, 0)
        : bits ^ (bits.isNegative ? Int64(-1) : Int64.MIN_VALUE);
  }

  /// Writes the "infinity" byte sequence that sorts after all other byte
  /// sequences written in ascending order.
  void writeInfinityAscending() {
    _writeEscapedByteAscending(escape2);
    _writeEscapedByteAscending(infinity);
  }

  /// Writes the "infinity" byte sequence that sorts before all other byte
  /// sequences written in descending order.
  void writeInfinityDescending() {
    _writeEscapedByteDescending(escape2);
    _writeEscapedByteDescending(infinity);
  }

  /// Resets the buffer such that it is the same as when it was newly
  /// constructed.
  void reset() {
    _position = 0;
  }

  /// Makes a copy of the encoded bytes in this buffer.
  Uint8List encodedBytes() =>
      Uint8List.fromList(Uint8List.sublistView(_buffer, 0, _position));

  /// Writes a single byte ascending to the buffer, doing proper escaping.
  void _writeByteAscending(int b) {
    if (b == escape1) {
      _writeEscapedByteAscending(escape1);
      _writeEscapedByteAscending(nullByte);
    } else if (b == escape2) {
      _writeEscapedByteAscending(escape2);
      _writeEscapedByteAscending(ffByte);
    } else {
      _writeEscapedByteAscending(b);
    }
  }

  /// Writes a single byte descending to the buffer, doing proper escaping.
  void _writeByteDescending(int b) {
    if (b == escape1) {
      _writeEscapedByteDescending(escape1);
      _writeEscapedByteDescending(nullByte);
    } else if (b == escape2) {
      _writeEscapedByteDescending(escape2);
      _writeEscapedByteDescending(ffByte);
    } else {
      _writeEscapedByteDescending(b);
    }
  }

  void _writeSeparatorAscending() {
    _writeEscapedByteAscending(escape1);
    _writeEscapedByteAscending(separator);
  }

  void _writeSeparatorDescending() {
    _writeEscapedByteDescending(escape1);
    _writeEscapedByteDescending(separator);
  }

  void _writeEscapedByteAscending(int b) {
    _ensureAvailable(1);
    _buffer[_position++] = b & 0xff;
  }

  void _writeEscapedByteDescending(int b) {
    _ensureAvailable(1);
    _buffer[_position++] = ~b & 0xff;
  }

  void _ensureAvailable(int bytes) {
    final int minCapacity = bytes + _position;
    if (minCapacity <= _buffer.length) {
      return;
    }
    // Try doubling.
    int newLength = _buffer.length * 2;
    // Still not big enough? Just allocate the right size.
    if (newLength < minCapacity) {
      newLength = minCapacity;
    }
    // Create the new buffer.
    _buffer = Uint8List(newLength)..setRange(0, _position, _buffer);
  }

  /// The number of bytes of the signed encoding of the non-negative [n]: 7
  /// bits per byte, one of them for the sign.
  static int _signedNumLength(Int64 n) {
    final int numBits = 64 - n.numberOfLeadingZeros() + 1;
    return (numBits + 6) ~/ 7;
  }

  /// The number of bytes of the unsigned representation of [value].
  static int _unsignedNumLength(Int64 value) {
    final int numBits = 64 - value.numberOfLeadingZeros();
    return (numBits + 7) ~/ 8;
  }

  /// Appends [encodedBytes] as they are.
  void seed(List<int> encodedBytes) {
    _ensureAvailable(encodedBytes.length);
    for (final int b in encodedBytes) {
      _buffer[_position++] = b & 0xff;
    }
  }
}
