// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';

/// BasePath represents a path sequence in the Firestore database. It is
/// composed of an ordered sequence of string segments.
abstract class BasePath<B extends BasePath<B>> implements Comparable<B> {
  final List<String> _segments;

  const BasePath(this._segments);

  String getSegment(int index) => _segments[index];

  String operator [](int index) => _segments[index];

  /// Returns a new path whose segments are the current path plus the passed in
  /// path
  ///
  /// Returns a new path with this path's segment plus the new one.
  B appendSegment(String segment) {
    final List<String> newPath = List<String>.from(_segments)..add(segment);
    return createPathWithSegments(newPath);
  }

  /// Returns a new path whose segments are the current path plus another's
  ///
  /// Returns a new path with this segments path plus the new one
  B appendPath(B path) {
    final List<String> newPath = List<String>.from(_segments)
      ..addAll(path._segments);
    return createPathWithSegments(newPath);
  }

  /// If count is null it returns a new path with the current path's first
  /// segment removed. Otherwise will return a new path with the current path's
  /// first [count] segments removed.
  B popFirst([int count = 1]) {
    int length = this.length;
    Assert.hardAssert(length >= count,
        "Can't call popFirst with count > length() ($count > $length)");
    return createPathWithSegments(_segments.sublist(count, length));
  }

  /// Returns a new path with the current path's last segment removed.
  B popLast() {
    return createPathWithSegments(_segments.sublist(0, length - 1));
  }

  /// Returns a new path made up of the first count segments of the current
  /// path.
  B keepFirst(int count) {
    return createPathWithSegments(_segments.sublist(0, count));
  }

  @override
  int compareTo(B o) {
    int i = 0;
    int myLength = length;
    int theirLength = o.length;
    while (i < myLength && i < theirLength) {
      int localCompare = getSegment(i).compareTo(o.getSegment(i));
      if (localCompare != 0) {
        return localCompare;
      }
      i++;
    }

    return myLength.compareTo(theirLength);
  }

  /// Returns the last segment of the path
  String getLastSegment() => _segments.last;

  String get last => _segments.last;

  /// Returns the first segment of the path
  String getFirstSegment() => _segments.first;

  String get first => _segments.first;

  bool get isEmpty => _segments.isEmpty;

  bool get isNotEmpty => _segments.isNotEmpty;

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
  /// * Empty path is a parent of any path that consists of a single segment.
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

  int get length => _segments.length;

  @override
  String toString() => canonicalString;

  @override
  int get hashCode {
    int prime = 37;
    int result = 1;
    result = prime * result + runtimeType.hashCode;
    result = prime * result + _segments.hashCode;
    return result;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BasePath &&
          runtimeType == other.runtimeType &&
          (compareTo(other as B) == 0);
}
