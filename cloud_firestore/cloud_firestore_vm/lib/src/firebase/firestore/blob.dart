// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore_vm/src/firebase/firestore/util/util.dart';
import 'package:collection/collection.dart';

class Blob implements Comparable<Blob> {
  Blob(Uint8List bytes) : bytes = Uint8List.fromList(bytes);

  /// Creates a blob from a base64-encoded string.
  ///
  /// Throws a [FormatException] if [base64String] is not valid base64.
  factory Blob.fromBase64String(String base64String) {
    return Blob(base64Decode(base64String));
  }

  /// Builds a blob from a JSON map created by [toJson].
  ///
  /// Throws an [ArgumentError] if [json] does not have that shape, or carries a
  /// non-zero `subtype` (BSON binary data, which this SDK does not support),
  /// and a [FormatException] if `bytes` is not valid base64.
  factory Blob.fromJson(Map<String, Object?> json) {
    final Object? data = json['bytes'];
    final Object? subtype = json['subtype'];
    if (json['type'] != jsonType ||
        data is! String ||
        (subtype != null && subtype != 0)) {
      throw ArgumentError.value(
          json, 'json', 'Not a JSON representation of a Blob');
    }
    return Blob.fromBase64String(data);
  }

  /// The value of the `type` field written by [toJson].
  static const String jsonType = 'firestore/bytes/1.0';

  final Uint8List bytes;

  /// The bytes of this blob, base64-encoded.
  String toBase64() => base64Encode(bytes);

  /// A JSON-serializable representation of this blob, in the same shape as the
  /// JS SDK's `Bytes.toJSON()`. Read it back with [Blob.fromJson].
  Map<String, Object> toJson() {
    return <String, Object>{'type': jsonType, 'bytes': toBase64()};
  }

  @override
  int compareTo(Blob other) {
    final int size = min(bytes.length, other.bytes.length);

    for (int i = 0; i < size; i++) {
      // Make sure the bytes are unsigned
      final int thisByte = bytes[i] & 0xff;
      final int otherByte = other.bytes[i] & 0xff;
      if (thisByte < otherByte) {
        return -1;
      } else if (thisByte > otherByte) {
        return 1;
      }
      // Byte values are equal, continue with comparison
    }

    return bytes.length.compareTo(other.bytes.length);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Blob &&
          runtimeType == other.runtimeType &&
          const ListEquality<int>().equals(bytes, other.bytes);

  @override
  int get hashCode => const ListEquality<int>().hash(bytes);

  @override
  String toString() => 'Blob { bytes= ${toDebugString(bytes)} }';
}
