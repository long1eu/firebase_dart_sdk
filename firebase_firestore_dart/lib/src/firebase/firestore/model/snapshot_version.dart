// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_firestore/src/firebase/timestamp.dart';

/// A version of a document in Firestore. This corresponds to the version timestamp, such as
/// update_time or read_time.
class SnapshotVersion implements Comparable<SnapshotVersion> {
  /// Creates a new version representing the given timestamp.
  const SnapshotVersion(this.timestamp);

  final Timestamp timestamp;

  /// A version that is smaller than all other versions.
  static final SnapshotVersion none = SnapshotVersion(Timestamp(0, 0));

  @override
  int compareTo(SnapshotVersion other) => timestamp.compareTo(other.timestamp);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SnapshotVersion && runtimeType == other.runtimeType && timestamp == other.timestamp;

  @override
  int get hashCode => timestamp.hashCode;

  @override
  String toString() => 'SnapshotVersion{timestamp: $timestamp}';
}
