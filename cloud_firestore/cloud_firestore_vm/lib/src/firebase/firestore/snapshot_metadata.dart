// File created by
// Lung Razvan <long1eu>
// on 25/09/2018

import 'package:firebase_core/firebase_core_vm.dart';
import 'package:firebase_firestore/src/firebase/firestore/metadata_change.dart';

/// Metadata about a snapshot, describing the state of the snapshot.
///
/// **Subclassing Note**: Firestore classes are not meant to be subclassed except for use in test
/// mocks. Subclassing is not supported in production code and new SDK releases may break code that
/// does so.
class SnapshotMetadata {
  const SnapshotMetadata(this.hasPendingWrites, this.isFromCache);

  /// Returns true if the snapshot contains the result of local writes (e.g. set() or update()
  /// calls) that have not yet been committed to the backend. If your listener has opted into
  /// metadata updates (via [MetadataChanges.include]) you will receive another snapshot with
  /// [hasPendingWrites] equal to false once the writes have been committed to the backend.
  final bool hasPendingWrites;

  /// Returns true if the snapshot was created from cached data rather than guaranteed up-to-date
  /// server data. If your listener has opted into metadata updates (via [MetadataChanges.include])
  /// you will receive another snapshot with [isFomCache] equal to false once the client has
  /// received up-to-date data from the backend.
  final bool isFromCache;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SnapshotMetadata &&
          runtimeType == other.runtimeType &&
          hasPendingWrites == other.hasPendingWrites &&
          isFromCache == other.isFromCache;

  @override
  int get hashCode => (hasPendingWrites ? 1 : 0) + (isFromCache ? 2 : 3);

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('hasPendingWrites', hasPendingWrites)
          ..add('isFromCache', isFromCache))
        .toString();
  }
}
