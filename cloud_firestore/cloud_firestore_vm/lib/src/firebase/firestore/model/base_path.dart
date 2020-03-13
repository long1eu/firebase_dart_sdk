// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:collection/collection.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';

/// BasePath represents a path sequence in the Firestore database. It is composed of an ordered
/// sequence of string segments.
abstract class BasePath<B extends BasePath<B>> implements Comparable<B> {
  const BasePath(this.segments);

  final List<String> segments;

  String getSegment(int index) => segments[index];

  String operator [](int index) => segments[index];

  /// Returns a new path whose segments are the current path plus the passed in path
  ///
  /// Returns a new path with this path's segment plus the new one.
  B appendSegment(String segment) {
    final List<String> newPath = List<String>.from(segments)..add(segment);
    return createPathWithSegments(newPath);
  }

  /// Returns a new path whose segments are the current path plus another's
  ///
  /// Returns a new path with this segments path plus the new one
  B appendField(B path) {
    final List<String> newPath = List<String>.from(segments)
      ..addAll(path.segments);
    return createPathWithSegments(newPath);
  }

  /// If count is null it returns a new path with the current path's first segment removed.
  /// Otherwise will return a new path with the current path's first [count] segments removed.
  B popFirst([int count = 1]) {
    final int length = this.length;
    hardAssert(length >= count,
        'Can\'t call popFirst with count > length() ($count > $length)');
    return createPathWithSegments(segments.sublist(count, length));
  }

  /// Returns a new path with the current path's last segment removed.
  B popLast() {
    return createPathWithSegments(segments.sublist(0, length - 1));
  }

  /// Returns a new path made up of the first count segments of the current path.
  B keepFirst(int count) {
    return createPathWithSegments(segments.sublist(0, count));
  }

  @override
  int compareTo(B o) {
    if (o == null) {
      return 1;
    }

    int i = 0;
    final int myLength = length;
    final int theirLength = o.length;
    while (i < myLength && i < theirLength) {
      final int localCompare = getSegment(i).compareTo(o.getSegment(i));
      if (localCompare != 0) {
        return localCompare;
      }
      i++;
    }

    return myLength.compareTo(theirLength);
  }

  bool operator >(B other) => compareTo(other) > 0;

  bool operator >=(B other) => compareTo(other) >= 0;

  bool operator <(B other) => compareTo(other) < 0;

  bool operator <=(B other) => compareTo(other) <= 0;

  /// Returns the last segment of the path
  String getLastSegment() => segments.last;

  String get last => segments.last;

  /// Returns the first segment of the path
  String getFirstSegment() => segments.first;

  String get first => segments.first;

  bool get isEmpty => segments.isEmpty;

  bool get isNotEmpty => segments.isNotEmpty;

  /// Checks to see if this path is a prefix of (or equals) another path.
  ///
  /// Returns true if current path is a prefix of the other path.
  bool isPrefixOf(B path) {
    if (length > path.length) {
      return false;
    }
    for (int i = 0; i < length; i++) {
      if (getSegment(i) != path.getSegment(i)) {
        return false;
      }
    }
    return true;
  }

  /// Returns true if the given argument is a direct child of this path.
  ///
  /// Empty path is a parent of any path that consists of a single segment.
  bool isImmediateParentOf(B potentialChild) {
    if (length + 1 != potentialChild.length) {
      return false;
    }
    for (int i = 0; i < length; i++) {
      if (getSegment(i) != potentialChild.getSegment(i)) {
        return false;
      }
    }
    return true;
  }

  String get canonicalString;

  B createPathWithSegments(List<String> segments);

  int get length {
    return segments.length;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BasePath &&
          runtimeType == other.runtimeType &&
          const DeepCollectionEquality().equals(segments, other.segments);

  @override
  int get hashCode => const ListEquality<String>().hash(segments);

  @override
  String toString() => canonicalString;
}
