// File created by
// Lung Razvan <long1eu>
// on 25/09/2018

import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_data_converter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/snapshot_json.dart'
    as snapshot_json;
import 'package:cloud_firestore_dart/src/firebase/firestore/core/view_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/metadata_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart'
    as core;
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/snapshot_metadata.dart';

/// A [QuerySnapshot] contains the results of a query. It can contain zero or more [DocumentSnapshot] objects.
///
/// It is an `Iterable` of [QueryDocumentSnapshot]s in the order of the query, so you can loop over it directly;
/// [docs] gives them as a list and [docChanges] lists what changed since the previous snapshot of the same listener.
/// [metadata] tells whether the results came from the local cache and whether they include local writes that the
/// backend has not acknowledged yet.
///
/// ```dart
/// final QuerySnapshot<Map<String, Object?>> snapshot = await firestore
///     .collection('cities')
///     .where('state', isEqualTo: 'CA')
///     .get();
/// print('${snapshot.length} cities, from cache: ${snapshot.metadata.isFromCache}');
/// for (final QueryDocumentSnapshot<Map<String, Object?>> city in snapshot) {
///   print('${city.id}: ${city.data}');
/// }
/// ```
///
/// **Subclassing Note**: Firestore classes are not meant to be subclassed except for use in test mocks. Subclassing is
/// not supported in production code and new SDK releases may break code that does so.
class QuerySnapshot<T extends dynamic>
    extends Iterable<QueryDocumentSnapshot<T>> {
  /// Implementation detail of the SDK; not part of the supported API.
  QuerySnapshot._(this.query, this._snapshot, this._firestore)
    : metadata = SnapshotMetadata(
        _snapshot.hasPendingWrites,
        _snapshot.isFromCache,
      );

  /// Builds a [QuerySnapshot] from the JSON object written by [toJson], for the [firestore] instance.
  ///
  /// The snapshot is not from cache and has no pending writes; its [query] is the one of the original snapshot. Pass
  /// the [converter] of the original query to get typed data back. Throws a [FirestoreException] if [json] is not a valid
  /// query snapshot JSON object, for example one of a different project or database.
  ///
  /// This is the JS SDK `querySnapshotFromJSON()`.
  factory QuerySnapshot.fromJson(
    FirebaseFirestore firestore,
    Map<String, Object?> json, {
    FirestoreDataConverter<T>? converter,
  }) {
    return snapshot_json.querySnapshotFromJson<T>(firestore, json, converter);
  }

  /// The query whose results this snapshot holds.
  final Query<T> query;

  /// The metadata of this query snapshot: whether the results came from the cache
  /// ([SnapshotMetadata.isFromCache]) and whether one of the documents has local writes that the backend has not
  /// acknowledged yet ([SnapshotMetadata.hasPendingWrites]).
  final SnapshotMetadata metadata;

  final ViewSnapshot _snapshot;
  final FirebaseFirestore _firestore;

  List<DocumentChange<T>>? _cachedChanges;
  MetadataChanges? _cachedChangesMetadataState;

  /// Returns the list of documents that changed since the last snapshot. If it's the first snapshot all documents will
  /// be in the list as added changes.
  ///
  /// Documents with changes only to their metadata will not be included.
  ///
  /// Returns the list of document changes since the last snapshot.
  @Deprecated('Use docChanges instead.')
  List<DocumentChange<T>> get documentChanges => docChanges;

  /// The documents that changed since the previous snapshot of the same listener, in the order the changes apply. In
  /// the first snapshot every document is a [DocumentChangeType.added] change. Changes to the metadata of a document
  /// only are not included; use [getDocumentChanges] for those.
  ///
  /// Same as [docChanges]; this is the name used by the current official
  /// Firestore API.
  ///
  /// ```dart
  /// firestore.collection('cities').snapshots.listen((
  ///   QuerySnapshot<Map<String, Object?>> snapshot,
  /// ) {
  ///   for (final DocumentChange<Map<String, Object?>> change
  ///       in snapshot.docChanges) {
  ///     switch (change.type) {
  ///       case DocumentChangeType.added:
  ///         print('new city: ${change.document.data}');
  ///       case DocumentChangeType.modified:
  ///         print('modified city: ${change.document.data}');
  ///       case DocumentChangeType.removed:
  ///         print('removed city: ${change.document.id}');
  ///     }
  ///   }
  /// });
  /// ```
  List<DocumentChange<T>> get docChanges =>
      getDocumentChanges(MetadataChanges.exclude);

  /// Returns the list of documents that changed since the last snapshot. If it's the first snapshot all documents will
  /// be in the list as added changes.
  ///
  /// [metadataChanges] Indicates whether metadata-only changes (i.e. only [QuerySnapshot.metadata] changed) should be included.
  /// A metadata-only change of a document is reported as [DocumentChangeType.modified].
  ///
  /// Returns the list of document changes since the last snapshot. Throws an [ArgumentError] when
  /// [metadataChanges] is [MetadataChanges.include] but the listener that produced this snapshot was not started
  /// with [MetadataChanges.include] (for example a snapshot from `Query.snapshots`).
  List<DocumentChange<T>> getDocumentChanges(MetadataChanges metadataChanges) {
    if (metadataChanges == MetadataChanges.include &&
        snapshot.excludesMetadataChanges) {
      throw ArgumentError(
        'To include metadata changes with your document changes, you must also pass '
        'MetadataChanges.include to getSnapshots().',
      );
    }

    List<DocumentChange<T>>? cachedChanges = _cachedChanges;
    if (cachedChanges == null ||
        _cachedChangesMetadataState != metadataChanges) {
      cachedChanges = DocumentChangeInternal.changesFromSnapshot<T>(
        _firestore,
        metadataChanges,
        snapshot,
        query.converter,
      ).toList(growable: false);
      _cachedChanges = cachedChanges;
      _cachedChangesMetadataState = metadataChanges;
    }
    return cachedChanges;
  }

  /// Returns the documents in this [QuerySnapshot] as a List in order of the query.
  ///
  /// Returns the list of documents.
  @Deprecated('Use docs instead.')
  List<DocumentSnapshot<T>> get documents {
    return <DocumentSnapshot<T>>[
      for (core.Document doc in snapshot.documents) _convertDocument(doc),
    ];
  }

  /// Returns the documents in this [QuerySnapshot] as a List in order of the
  /// query. Same as [docs] but typed as [QueryDocumentSnapshot]; this is
  /// the name used by the current official Firestore API.
  ///
  /// The list cannot be modified, and each access builds a new list.
  ///
  /// ```dart
  /// final List<String> names = snapshot.docs
  ///     .map((QueryDocumentSnapshot<Map<String, Object?>> doc) => doc.id)
  ///     .toList();
  /// ```
  List<QueryDocumentSnapshot<T>> get docs => toList(growable: false);

  /// Returns true if there are no documents in the QuerySnapshot.
  @override
  bool get isEmpty => snapshot.documents.isEmpty;

  /// Returns the number of documents in the QuerySnapshot. This is the JS SDK `size`.
  @override
  int get length => snapshot.documents.length;

  /// Iterates over the documents of this snapshot in the order of the query.
  @override
  Iterator<QueryDocumentSnapshot<T>> get iterator {
    return () sync* {
      final Iterator<core.Document> it = snapshot.documents.iterator;
      while (it.moveNext()) {
        yield _convertDocument(it.current);
      }
    }().iterator;
  }

  /// The value of the `type` field written by [toJson].
  static const String jsonType = 'firestore/querySnapshot/1.0';

  /// Returns a JSON-serializable representation of this snapshot, which [QuerySnapshot.fromJson] reads back and
  /// `Firestore.querySnapshotsFromJson` listens from.
  ///
  /// The `bundle` field holds the query and its documents as a Firestore bundle, with the query under the name in
  /// `bundleName`. Throws a [FirestoreException] (failed-precondition) if the snapshot has pending writes: await
  /// `waitForPendingWrites()` first.
  ///
  /// This is the JS SDK `QuerySnapshot.toJSON()`; the JSON is interchangeable with the one of the JS SDK (Node).
  Map<String, Object?> toJson() =>
      snapshot_json.querySnapshotToJson(_firestore, snapshot);

  QueryDocumentSnapshot<T> _convertDocument(Document document) {
    return QueryDocumentSnapshotInternal.fromDocument<T>(
      _firestore,
      document,
      fromCache: snapshot.isFromCache,
      hasPendingWrites: snapshot.mutatedKeys.contains(document.key),
      converter: query.converter,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuerySnapshot &&
          runtimeType == other.runtimeType &&
          query == other.query &&
          metadata == other.metadata &&
          snapshot == other.snapshot &&
          _firestore == other._firestore;

  @override
  int get hashCode {
    return query.hashCode ^ //
        metadata.hashCode ^
        snapshot.hashCode ^
        _firestore.hashCode;
  }

  @override
  String toString() =>
      'QuerySnapshot(query: $query, metadata: $metadata, size: $length)';
}

/// Members of [QuerySnapshot] for the SDK itself. Not exported by the public libraries.
extension QuerySnapshotInternal<T> on QuerySnapshot<T> {
  /// The view snapshot this public snapshot wraps.
  ViewSnapshot get snapshot => _snapshot;

  /// The snapshot of [query] for the view [snapshot].
  static QuerySnapshot<T> create<T extends dynamic>(
    Query<T> query,
    ViewSnapshot snapshot,
    FirebaseFirestore firestore,
  ) => QuerySnapshot<T>._(query, snapshot, firestore);
}
