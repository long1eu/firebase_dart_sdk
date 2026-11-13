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
import 'package:firebase_app_dart/internal.dart';

/// A [QuerySnapshot] contains the results of a query. It can contain zero or more [DocumentSnapshot] objects.
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
  /// the [converter] of the original query to get typed data back. Throws a [FirestoreError] if [json] is not a valid
  /// query snapshot JSON object, for example one of a different project or database.
  ///
  /// This is the JS SDK `querySnapshotFromJSON()`.
  factory QuerySnapshot.fromJson(
    Firestore firestore,
    Map<String, Object?> json, {
    FirestoreDataConverter<T>? converter,
  }) {
    return snapshot_json.querySnapshotFromJson<T>(firestore, json, converter);
  }

  /// The query whose results this snapshot holds.
  final Query<T> query;

  /// Returns the metadata for this document snapshot.
  final SnapshotMetadata metadata;

  final ViewSnapshot _snapshot;
  final Firestore _firestore;

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

  /// Same as [documentChanges]; this is the name used by the current official
  /// Firestore API.
  List<DocumentChange<T>> get docChanges =>
      getDocumentChanges(MetadataChanges.exclude);

  /// Returns the list of documents that changed since the last snapshot. If it's the first snapshot all documents will
  /// be in the list as added changes.
  ///
  /// [metadataChanges] Indicates whether metadata-only changes (i.e. only [QuerySnapshot.metadata] changed) should be included.
  ///
  /// Returns the list of document changes since the last snapshot.
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
  /// query. Same as [documents] but typed as [QueryDocumentSnapshot]; this is
  /// the name used by the current official Firestore API.
  List<QueryDocumentSnapshot<T>> get docs => toList(growable: false);

  /// Returns true if there are no documents in the QuerySnapshot.
  @override
  bool get isEmpty => snapshot.documents.isEmpty;

  /// Returns the number of documents in the QuerySnapshot.
  @override
  int get length => snapshot.documents.length;

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
  /// `bundleName`. Throws a [FirestoreError] (failed-precondition) if the snapshot has pending writes: await
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
  String toString() {
    return (ToStringHelper(QuerySnapshot)
          ..add('query', query)
          ..add('metadata', metadata)
          ..add('snapshot', snapshot)
          ..add('cachedChanges', _cachedChanges)
          ..add('cachedChangesMetadataState', _cachedChangesMetadataState))
        .toString();
  }
}

/// Members of [QuerySnapshot] for the SDK itself. Not exported by the public libraries.
extension QuerySnapshotInternal<T> on QuerySnapshot<T> {
  /// The view snapshot this public snapshot wraps.
  ViewSnapshot get snapshot => _snapshot;

  /// The snapshot of [query] for the view [snapshot].
  static QuerySnapshot<T> create<T extends dynamic>(
    Query<T> query,
    ViewSnapshot snapshot,
    Firestore firestore,
  ) => QuerySnapshot<T>._(query, snapshot, firestore);
}
