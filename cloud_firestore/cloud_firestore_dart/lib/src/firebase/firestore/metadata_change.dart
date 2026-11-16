// File created by
// Lung Razvan <long1eu>
// on 18/09/2018

import 'package:cloud_firestore_dart/src/firebase/firestore/document_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query_snapshot.dart';

/// Indicates whether metadata-only changes (i.e. only [DocumentSnapshot.metadata] or
/// [QuerySnapshot.metadata] changed) should trigger snapshot events.
///
/// Pass it to `getSnapshots` or in a `SnapshotListenOptions`. This is the `includeMetadataChanges`
/// option of `onSnapshot` in the JS SDK.
///
/// ```dart
/// firestore
///     .collection('cities')
///     .snapshots(includeMetadataChanges: true)
///     .listen((QuerySnapshot<Map<String, Object?>> snapshot) {
///       print('from cache: ${snapshot.metadata.isFromCache}');
///     });
/// ```
enum MetadataChanges {
  /// Snapshot events are not triggered by metadata-only changes.
  exclude,

  /// Snapshot events are also triggered when only the metadata changed.
  include,
}
