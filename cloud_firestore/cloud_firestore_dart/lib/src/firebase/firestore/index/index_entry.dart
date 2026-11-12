import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:collection/collection.dart';

/// Compares two byte arrays as unsigned bytes; a prefix sorts first. The order
/// SQLite uses for BLOBs (`memcmp`), and `Util.compareByteArrays` upstream.
int compareByteArrays(List<int> left, List<int> right) {
  final int size = left.length < right.length ? left.length : right.length;
  for (int i = 0; i < size; i++) {
    final int cmp = (left[i] & 0xff).compareTo(right[i] & 0xff);
    if (cmp != 0) {
      return cmp;
    }
  }
  return left.length.compareTo(right.length);
}

/// Represents an index entry saved by the SDK in its local storage. Port of
/// `IndexEntry` of the Android SDK.
class IndexEntry implements Comparable<IndexEntry> {
  const IndexEntry(
    this.indexId,
    this.documentKey,
    this.arrayValue,
    this.directionalValue,
  );

  final int indexId;
  final DocumentKey documentKey;

  /// The encoded value of the array element this entry is for; empty for
  /// indexes without an array segment.
  final Uint8List arrayValue;

  /// The encoded values of the directional segments.
  final Uint8List directionalValue;

  @override
  int compareTo(IndexEntry other) {
    int cmp = indexId.compareTo(other.indexId);
    if (cmp != 0) {
      return cmp;
    }
    cmp = documentKey.compareTo(other.documentKey);
    if (cmp != 0) {
      return cmp;
    }
    cmp = compareByteArrays(arrayValue, other.arrayValue);
    if (cmp != 0) {
      return cmp;
    }
    return compareByteArrays(directionalValue, other.directionalValue);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IndexEntry &&
          indexId == other.indexId &&
          documentKey == other.documentKey &&
          const ListEquality<int>().equals(arrayValue, other.arrayValue) &&
          const ListEquality<int>().equals(
            directionalValue,
            other.directionalValue,
          );

  @override
  int get hashCode => Object.hash(
    indexId,
    documentKey,
    const ListEquality<int>().hash(arrayValue),
    const ListEquality<int>().hash(directionalValue),
  );

  @override
  String toString() =>
      'IndexEntry{indexId=$indexId, documentKey=$documentKey, '
      'arrayValue=$arrayValue, directionalValue=$directionalValue}';
}
