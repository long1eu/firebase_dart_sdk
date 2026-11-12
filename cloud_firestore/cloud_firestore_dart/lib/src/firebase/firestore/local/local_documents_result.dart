import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';

/// Represents a local view (overlay) of a set of documents, and the highest
/// mutation batch id that was applied to them. Port of `LocalDocumentsResult`
/// of the Android SDK.
class LocalDocumentsResult {
  const LocalDocumentsResult(this.batchId, this.documents, this.readTimes);

  /// The largest batch id of the overlays that were read, or
  /// `FieldIndex.initialLargestBatchId` when none was.
  final int batchId;

  /// The local views. A key maps to null when the document neither is cached
  /// nor results from a local mutation (for example a deleted document).
  final Map<DocumentKey, MaybeDocument?> documents;

  /// The read time of the cached version of each document:
  /// [SnapshotVersion.none] for a document that only exists as a local
  /// mutation.
  ///
  /// PORTING NOTE: upstream reads it from the document
  /// (`MutableDocument.getReadTime`).
  final Map<DocumentKey, SnapshotVersion> readTimes;
}
