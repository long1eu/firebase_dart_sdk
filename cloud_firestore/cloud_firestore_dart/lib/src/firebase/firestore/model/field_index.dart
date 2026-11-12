import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:collection/collection.dart';

/// The type of an index segment: for which kind of query it can be used.
///
/// The order of the values is part of [IndexSegment.compareTo].
enum SegmentKind {
  /// Ordered index. Can be used for <, <=, ==, >=, >, !=, IN and NOT IN
  /// queries.
  ascending,

  /// Ordered index. Can be used for <, <=, ==, >=, >, !=, IN and NOT IN
  /// queries.
  descending,

  /// Contains index. Can be used for ArrayContains and ArrayContainsAny.
  contains,
}

/// An index component consisting of field path and index type. Port of
/// `FieldIndex.Segment`.
class IndexSegment implements Comparable<IndexSegment> {
  const IndexSegment(this.fieldPath, this.kind);

  /// The field path of the component.
  final FieldPath fieldPath;

  /// The indexes sorting order.
  final SegmentKind kind;

  @override
  int compareTo(IndexSegment other) {
    final int cmp = fieldPath.compareTo(other.fieldPath);
    if (cmp != 0) {
      return cmp;
    }
    return kind.index.compareTo(other.kind.index);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IndexSegment &&
          fieldPath == other.fieldPath &&
          kind == other.kind;

  @override
  int get hashCode => Object.hash(fieldPath, kind);

  @override
  String toString() => 'IndexSegment{fieldPath=$fieldPath, kind=${kind.name}}';
}

/// Stores the latest read time and document that were processed for an index.
/// Port of `FieldIndex.IndexOffset`.
class IndexOffset implements Comparable<IndexOffset> {
  /// Creates an offset that matches all documents with a read time higher than
  /// [readTime] or with a key higher than [documentKey] for equal read times.
  /// The [largestBatchId] is used as a final tie breaker.
  const IndexOffset(this.readTime, this.documentKey, this.largestBatchId);

  /// Creates an offset that matches all documents with a read time higher than
  /// [readTime].
  factory IndexOffset.createSuccessor(
    SnapshotVersion readTime,
    int largestBatchId,
  ) {
    // We want to create an offset that matches all documents with a read time
    // greater than the provided read time. To do so, we technically need to
    // create an offset for `(readTime, MAX_DOCUMENT_KEY)`. While we could use
    // Unicode codepoints to generate MAX_DOCUMENT_KEY, it is much easier to use
    // `(readTime + 1, DocumentKey.empty())` since `> DocumentKey.empty()`
    // matches all valid document IDs.
    final int successorSeconds = readTime.timestamp.seconds;
    final int successorNanos = readTime.timestamp.nanoseconds + 1;
    final SnapshotVersion successor = SnapshotVersion(
      successorNanos == 1000000000
          ? Timestamp(successorSeconds + 1, 0)
          : Timestamp(successorSeconds, successorNanos),
    );
    return IndexOffset(successor, DocumentKey.empty(), largestBatchId);
  }

  /// The offset of an index that has not processed any document.
  static final IndexOffset none = IndexOffset(
    SnapshotVersion.none,
    DocumentKey.empty(),
    FieldIndex.initialLargestBatchId,
  );

  /// The latest read time version that has been indexed by Firestore for this
  /// field index.
  final SnapshotVersion readTime;

  /// The key of the last document that was indexed for this query.
  /// [DocumentKey.empty] if no document has been indexed.
  final DocumentKey documentKey;

  /// The largest mutation batch id that's been processed by Firestore.
  final int largestBatchId;

  @override
  int compareTo(IndexOffset other) {
    int cmp = readTime.compareTo(other.readTime);
    if (cmp != 0) {
      return cmp;
    }
    cmp = documentKey.compareTo(other.documentKey);
    if (cmp != 0) {
      return cmp;
    }
    return largestBatchId.compareTo(other.largestBatchId);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IndexOffset &&
          readTime == other.readTime &&
          documentKey == other.documentKey &&
          largestBatchId == other.largestBatchId;

  @override
  int get hashCode => Object.hash(readTime, documentKey, largestBatchId);

  @override
  String toString() =>
      'IndexOffset{readTime=$readTime, '
      'documentKey=$documentKey, largestBatchId=$largestBatchId}';
}

/// Stores the "high water mark" that indicates how updated the index is for
/// the current user. Port of `FieldIndex.IndexState`.
class IndexState {
  const IndexState(this.sequenceNumber, this.offset);

  /// A number that indicates when the index was last updated (relative to
  /// other indexes).
  final int sequenceNumber;

  /// The latest indexed read time and document.
  final IndexOffset offset;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IndexState &&
          sequenceNumber == other.sequenceNumber &&
          offset == other.offset;

  @override
  int get hashCode => Object.hash(sequenceNumber, offset);

  @override
  String toString() =>
      'IndexState{sequenceNumber=$sequenceNumber, offset=$offset}';
}

/// An index definition for field indices in Firestore. Port of `FieldIndex` of
/// the Android SDK.
///
/// Every index is associated with a collection. The definition contains a list
/// of fields and their index kind (which can be [SegmentKind.ascending],
/// [SegmentKind.descending] or [SegmentKind.contains] for ArrayContains /
/// ArrayContainsAny queries).
///
/// Unlike the backend, the SDK does not differentiate between collection or
/// collection group-scoped indices. Every index can be used for both single
/// collection and collection group queries.
class FieldIndex {
  FieldIndex(
    this.indexId,
    this.collectionGroup,
    List<IndexSegment> segments,
    this.indexState,
  ) : segments = List<IndexSegment>.unmodifiable(segments);

  /// An ID for an index that has not yet been added to persistence.
  static const int unknownId = -1;

  /// The initial mutation batch id for each index. Gets updated during index
  /// backfill.
  static const int initialLargestBatchId = -1;

  /// The initial sequence number for each index. Gets updated during index
  /// backfill.
  static const int initialSequenceNumber = 0;

  /// The state of an index that has not yet been backfilled.
  static final IndexState initialState = IndexState(
    initialSequenceNumber,
    IndexOffset.none,
  );

  /// Compares indexes by collection group and segments. Ignores update time
  /// and index ID.
  static int semanticCompare(FieldIndex left, FieldIndex right) {
    int cmp = left.collectionGroup.compareTo(right.collectionGroup);
    if (cmp != 0) {
      return cmp;
    }

    final Iterator<IndexSegment> leftIt = left.segments.iterator;
    final Iterator<IndexSegment> rightIt = right.segments.iterator;
    while (true) {
      final bool leftHasNext = leftIt.moveNext();
      final bool rightHasNext = rightIt.moveNext();
      if (!leftHasNext || !rightHasNext) {
        return leftHasNext == rightHasNext ? 0 : (leftHasNext ? 1 : -1);
      }
      cmp = leftIt.current.compareTo(rightIt.current);
      if (cmp != 0) {
        return cmp;
      }
    }
  }

  /// The index ID. [unknownId] if the index ID is not available (for example,
  /// the index has not yet been persisted).
  final int indexId;

  /// The collection ID this index applies to.
  final String collectionGroup;

  /// All field segments for this index.
  final List<IndexSegment> segments;

  /// How up-to-date the index is for the current user.
  final IndexState indexState;

  /// All directional (ascending/descending) segments for this index.
  List<IndexSegment> get directionalSegments => segments
      .where((IndexSegment segment) => segment.kind != SegmentKind.contains)
      .toList();

  /// The ArrayContains/ArrayContainsAny segment for this index, if any.
  ///
  /// Firestore queries can only have a single ArrayContains/ArrayContainsAny
  /// statement.
  IndexSegment? get arraySegment => segments.firstWhereOrNull(
    (IndexSegment segment) => segment.kind == SegmentKind.contains,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FieldIndex &&
          indexId == other.indexId &&
          collectionGroup == other.collectionGroup &&
          const ListEquality<IndexSegment>().equals(segments, other.segments) &&
          indexState == other.indexState;

  @override
  int get hashCode => Object.hash(
    indexId,
    collectionGroup,
    const ListEquality<IndexSegment>().hash(segments),
    indexState,
  );

  @override
  String toString() =>
      'FieldIndex{indexId=$indexId, '
      'collectionGroup=$collectionGroup, segments=$segments, '
      'indexState=$indexState}';
}
