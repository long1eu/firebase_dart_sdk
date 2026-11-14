// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart';
import 'package:collection/collection.dart';

/// An immutable sequence of bytes, the value of a `bytes` field in a document.
///
/// Two blobs are equal when their bytes and their [subtype] are equal, and blobs are ordered by
/// subtype and then byte by byte.
class Blob implements Comparable<Blob> {
  /// Creates a blob holding a copy of [bytes].
  Blob(Uint8List bytes) : _bytes = Uint8List.fromList(bytes), subtype = 0;

  /// Creates BSON binary data, a blob with a [subtype].
  ///
  /// A [subtype] of 0 creates the same value as the default constructor. Only
  /// databases of the Enterprise edition store blobs with another subtype.
  ///
  /// Throws an [ArgumentError] if [subtype] is not in the range `[0, 255]`.
  Blob.bsonBinary(this.subtype, Uint8List bytes)
    : _bytes = Uint8List.fromList(bytes) {
    if (subtype < 0 || subtype > 255) {
      throw ArgumentError.value(
        subtype,
        'subtype',
        'The subtype for Blob must be a value in the inclusive [0, 255] range.',
      );
    }
  }

  /// Creates a blob from a base64-encoded string.
  ///
  /// Throws a [FormatException] if [base64String] is not valid base64.
  factory Blob.fromBase64String(String base64String) {
    return Blob(base64Decode(base64String));
  }

  /// Builds a blob from a JSON map created by [toJson].
  ///
  /// Throws an [ArgumentError] if [json] does not have that shape, or carries a
  /// `subtype` that is not an integer in the range `[0, 255]`, and a
  /// [FormatException] if `bytes` is not valid base64.
  factory Blob.fromJson(Map<String, Object?> json) {
    final Object? data = json['bytes'];
    final Object? subtype = json['subtype'];
    if (json['type'] != jsonType ||
        data is! String ||
        (subtype != null && subtype is! int)) {
      throw ArgumentError.value(
        json,
        'json',
        'Not a JSON representation of a Blob',
      );
    }
    return Blob.bsonBinary(subtype as int? ?? 0, base64Decode(data));
  }

  /// The value of the `type` field written by [toJson].
  static const String jsonType = 'firestore/bytes/1.0';

  /// The bytes of this blob.
  final Uint8List _bytes;

  /// A copy of the bytes of this blob (a blob is immutable, as upstream).
  Uint8List get bytes => Uint8List.fromList(_bytes);

  /// The subtype of BSON binary data, 0 for a regular blob.
  final int subtype;

  /// The bytes of this blob, base64-encoded.
  String toBase64() => base64Encode(_bytes);

  /// A JSON-serializable representation of this blob, in the same shape as the
  /// JS SDK's `Bytes.toJSON()`. Read it back with [Blob.fromJson].
  Map<String, Object> toJson() {
    return <String, Object>{
      'type': jsonType,
      'bytes': toBase64(),
      // The backend rejects a subtype of 0, so it is left out like the JS SDK
      // does.
      if (subtype != 0) 'subtype': subtype,
    };
  }

  @override
  int compareTo(Blob other) {
    // Blobs sort by subtype first, a regular blob has the subtype 0.
    if (subtype != other.subtype) {
      return subtype.compareTo(other.subtype);
    }

    final int size = min(_bytes.length, other._bytes.length);

    for (int i = 0; i < size; i++) {
      // Make sure the bytes are unsigned
      final int thisByte = _bytes[i] & 0xff;
      final int otherByte = other._bytes[i] & 0xff;
      if (thisByte < otherByte) {
        return -1;
      } else if (thisByte > otherByte) {
        return 1;
      }
      // Byte values are equal, continue with comparison
    }

    return _bytes.length.compareTo(other._bytes.length);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Blob &&
          runtimeType == other.runtimeType &&
          subtype == other.subtype &&
          const ListEquality<int>().equals(_bytes, other._bytes);

  @override
  int get hashCode => subtype == 0
      ? const ListEquality<int>().hash(_bytes)
      : Object.hash(subtype, const ListEquality<int>().hash(_bytes));

  @override
  String toString() => subtype == 0
      ? 'Blob { bytes= ${toDebugString(_bytes)} }'
      : 'Blob { bytes= ${toDebugString(_bytes)}, subtype= $subtype }';
}
