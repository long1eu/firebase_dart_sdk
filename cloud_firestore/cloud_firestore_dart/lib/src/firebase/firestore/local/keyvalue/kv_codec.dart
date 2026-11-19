// The byte layout of the key-value cache (see [CacheStore]): an order-preserving encoding of the parts of a key, so
// that the byte order of the encoded keys is the order of their parts.

import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';

/// Writes the parts of a key (or of the header of a value) so that the byte order of the result is the order of the
/// parts, compared one after the other:
///
/// * a string: its UTF-8 bytes, each 0x00 written as `00 FF`, then the terminator `00 01`. A string before any longer
///   string it is a prefix of, and the encodings are prefix free. Bytes ([KvKeyWriter.bytesPart]) the same way.
/// * an integer: 8 bytes, big endian, of the value plus 2^53 (values between -2^53 and 2^53, so that the web, whose
///   integers are doubles, writes the same bytes).
/// * a resource path: its segments as strings, then `00 00`, which sorts before any segment: a path before the paths
///   it is a prefix of, and the segments of a collection's documents directly after the collection's path.
/// * a document key: the path of its collection, then its id as a string. All documents of a collection share a
///   prefix that the documents of its subcollections do not have.
class KvKeyWriter {
  final List<int> _bytes = <int>[];

  static const int _two32 = 0x100000000;
  static const int _intOffset = 0x20000000000000; // 2^53

  /// Writes a string.
  KvKeyWriter string(String value) => bytesPart(utf8.encode(value));

  /// Writes bytes as a part of the key, escaped as a string is: ordered as the bytes are, a prefix first.
  KvKeyWriter bytesPart(List<int> value) {
    for (final int byte in value) {
      if (byte == 0) {
        _bytes
          ..add(0)
          ..add(0xff);
      } else {
        _bytes.add(byte);
      }
    }
    _bytes
      ..add(0)
      ..add(1);
    return this;
  }

  /// Writes an integer between -2^53 and 2^53.
  KvKeyWriter integer(int value) {
    if (value < -_intOffset || value > _intOffset) {
      throw ArgumentError.value(value, 'value', 'Out of the range of a key');
    }
    // The two words of value + 2^53, without computing that sum: on the web it needs 54 bits, more than a double
    // holds exactly. Division rather than shifts: the web shifts 32-bit integers.
    final int quotient = (value / _two32).floor();
    _word(quotient + _intOffset ~/ _two32);
    _word(value - quotient * _two32);
    return this;
  }

  void _word(int value) {
    _bytes
      ..add(value ~/ 0x1000000 % 256)
      ..add(value ~/ 0x10000 % 256)
      ..add(value ~/ 0x100 % 256)
      ..add(value % 256);
  }

  /// Writes a resource path.
  KvKeyWriter path(ResourcePath path) {
    for (final String segment in path.segments) {
      string(segment);
    }
    _bytes
      ..add(0)
      ..add(0);
    return this;
  }

  /// Writes a document key: the path of its collection, then its id.
  KvKeyWriter documentKey(DocumentKey key) {
    final ResourcePath path = key.path;
    return this.path(path.popLast()).string(path.getLastSegment());
  }

  /// Writes bytes as they are, for the last part of a value.
  KvKeyWriter raw(List<int> bytes) {
    _bytes.addAll(bytes);
    return this;
  }

  /// The bytes written.
  Uint8List get bytes => Uint8List.fromList(_bytes);
}

/// Reads what a [KvKeyWriter] wrote, in the same order.
class KvKeyReader {
  KvKeyReader(this._bytes, [this._offset = 0]);

  final Uint8List _bytes;
  int _offset;

  static const int _two32 = 0x100000000;
  static const int _intOffset = 0x20000000000000;

  /// Reads a string.
  String string() => utf8.decode(bytesPart());

  /// Reads what [KvKeyWriter.bytesPart] wrote.
  Uint8List bytesPart() {
    final List<int> bytes = <int>[];
    while (true) {
      final int byte = _next();
      if (byte != 0) {
        bytes.add(byte);
        continue;
      }
      final int escaped = _next();
      if (escaped == 1) {
        return Uint8List.fromList(bytes);
      } else if (escaped == 0xff) {
        bytes.add(0);
      } else {
        throw const FormatException('Not a string of the key-value cache');
      }
    }
  }

  /// Reads an integer.
  int integer() {
    int high = 0;
    int low = 0;
    for (int i = 0; i < 4; i++) {
      high = high * 256 + _next();
    }
    for (int i = 0; i < 4; i++) {
      low = low * 256 + _next();
    }
    // Without forming high * 2^32 + low, which may need 54 bits (see KvKeyWriter.integer).
    return (high - _intOffset ~/ _two32) * _two32 + low;
  }

  /// Reads a resource path.
  ResourcePath path() {
    final List<String> segments = <String>[];
    while (!_atPathEnd()) {
      segments.add(string());
    }
    _offset += 2;
    return ResourcePath.fromSegments(segments);
  }

  /// Reads a document key.
  DocumentKey documentKey() {
    final ResourcePath collection = path();
    return DocumentKey.fromPath(collection.appendSegment(string()));
  }

  /// The bytes that are left.
  Uint8List rest() => Uint8List.sublistView(_bytes, _offset);

  bool _atPathEnd() =>
      _offset + 1 < _bytes.length &&
      _bytes[_offset] == 0 &&
      _bytes[_offset + 1] == 0;

  int _next() {
    if (_offset >= _bytes.length) {
      throw const FormatException('Truncated key of the key-value cache');
    }
    return _bytes[_offset++];
  }
}

/// The smallest key that is larger than every key starting with [prefix]: the end of a scan over that prefix.
Uint8List prefixEnd(Uint8List prefix) {
  final Uint8List end = Uint8List.fromList(prefix);
  for (int i = end.length - 1; i >= 0; i--) {
    if (end[i] != 0xff) {
      end[i]++;
      return Uint8List.sublistView(end, 0, i + 1);
    }
  }
  // Only 0xff bytes (never one of our prefixes, which start with a string): past every key that has them.
  return Uint8List.fromList(<int>[...prefix, 0xff, 0xff, 0xff, 0xff]);
}

/// The smallest key that is larger than [key]: where a scan continues after it.
Uint8List keySuccessor(Uint8List key) => Uint8List.fromList(<int>[...key, 0]);
