// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'dart:math';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/util.dart';

@publicApi
class Blob implements Comparable<Blob> {
  final Uint8List bytes;

  Blob(Uint8List bytes) : bytes = Uint8List.fromList(bytes.toList());

  Blob.fromList(List<int> bytes) : bytes = Uint8List.fromList(bytes.toList());

  @override
  @publicApi
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
          const DeepCollectionEquality().equals(bytes, other.bytes);

  @override
  int get hashCode => const DeepCollectionEquality().hash(bytes);

  @override
  String toString() => 'Blob { bytes= ${Util.toDebugString(bytes)} }';
}
