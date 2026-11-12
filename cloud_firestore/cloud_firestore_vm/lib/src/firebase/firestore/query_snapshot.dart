// File created by
// Lung Razvan <long1eu>
// on 25/09/2018

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/view_snapshot.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/document_change.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/document_snapshot.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/metadata_change.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document.dart'
    as core;
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/query_document_snapshot.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/snapshot_metadata.dart';
import 'package:meta/meta.dart';

/// A [QuerySnapshot] contains the results of a query. It can contain zero or more [DocumentSnapshot] objects.
///
/// **Subclassing Note**: Firestore classes are not meant to be subclassed except for use in test mocks. Subclassing is
/// not supported in production code and new SDK releases may break code that does so.
class QuerySnapshot<T extends dynamic>
    extends Iterable<QueryDocumentSnapshot<T>> {
  @internal
  QuerySnapshot(this.query, this.snapshot, this._firestore)
      : metadata =
            SnapshotMetadata(snapshot.hasPendingWrites, snapshot.isFromCache);

  final Query<T> query;

  /// Returns the metadata for this document snapshot.
  final SnapshotMetadata metadata;

  final ViewSnapshot snapshot;
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
  /// [metadataChanges] Indicates whether metadata-only changes (i.e. only [Query.metadata] changed) should be included.
  ///
  /// Returns the list of document changes since the last snapshot.
  List<DocumentChange<T>> getDocumentChanges(MetadataChanges metadataChanges) {
    if (metadataChanges == MetadataChanges.include &&
        snapshot.excludesMetadataChanges) {
      throw ArgumentError(
          'To include metadata changes with your document changes, you must also pass '
          'MetadataChanges.include to getSnapshots().');
    }

    List<DocumentChange<T>>? cachedChanges = _cachedChanges;
    if (cachedChanges == null ||
        _cachedChangesMetadataState != metadataChanges) {
      cachedChanges = DocumentChange.changesFromSnapshot<T>(
              _firestore, metadataChanges, snapshot, query.converter)
          .toList(growable: false);
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
      for (core.Document doc in snapshot.documents) _convertDocument(doc)
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
    }()
        .iterator;
  }

  QueryDocumentSnapshot<T> _convertDocument(Document document) {
    return QueryDocumentSnapshot<T>.fromDocument(
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
