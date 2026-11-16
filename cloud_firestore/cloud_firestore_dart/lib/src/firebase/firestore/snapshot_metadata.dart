// File created by
// Lung Razvan <long1eu>
// on 25/09/2018

/// Metadata about a snapshot, describing the state of the snapshot.
///
/// Every `DocumentSnapshot` and `QuerySnapshot` has one. By default a listener is not told when only
/// the metadata changes; listen with `snapshots(includeMetadataChanges: true)` to get those snapshots too, for
/// example to show whether a local write has reached the backend.
///
/// ```dart
/// firestore.doc('cities/SF').snapshots(includeMetadataChanges: true).listen((
///   DocumentSnapshot<Map<String, Object?>> snapshot,
/// ) {
///   final SnapshotMetadata metadata = snapshot.metadata;
///   print('pending writes: ${metadata.hasPendingWrites}');
///   print('from cache: ${metadata.isFromCache}');
/// });
/// ```
///
/// **Subclassing Note**: Firestore classes are not meant to be subclassed except for use in test
/// mocks. Subclassing is not supported in production code and new SDK releases may break code that
/// does so.
class SnapshotMetadata {
  /// Creates the metadata of a snapshot. The SDK creates them; you only need this constructor in
  /// tests.
  const SnapshotMetadata(this.hasPendingWrites, this.isFromCache);

  /// Returns true if the snapshot contains the result of local writes (e.g. set() or update()
  /// calls) that have not yet been committed to the backend. If your listener has opted into
  /// metadata updates (`includeMetadataChanges: true`) you will receive another snapshot with
  /// [hasPendingWrites] equal to false once the writes have been committed to the backend.
  final bool hasPendingWrites;

  /// Returns true if the snapshot was created from cached data rather than guaranteed up-to-date
  /// server data. If your listener has opted into metadata updates (`includeMetadataChanges: true`)
  /// you will receive another snapshot with [isFromCache] equal to false once the client has
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
  String toString() =>
      'SnapshotMetadata{hasPendingWrites=$hasPendingWrites, isFromCache=$isFromCache}';
}
