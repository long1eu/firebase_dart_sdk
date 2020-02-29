// File created by
// Lung Razvan <long1eu>
// on 25/09/2018

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/view_snapshot.dart';
import 'package:firebase_firestore/src/firebase/firestore/document_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/document_snapshot.dart';
import 'package:firebase_firestore/src/firebase/firestore/firebase_firestore.dart';
import 'package:firebase_firestore/src/firebase/firestore/metadata_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart' as core;
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/query.dart' as core;
import 'package:firebase_firestore/src/firebase/firestore/query_document_snapshot.dart';
import 'package:firebase_firestore/src/firebase/firestore/snapshot_metadata.dart';

/// A [QuerySnapshot] contains the results of a query. It can contain zero or more [DocumentSnapshot] objects.
///
/// **Subclassing Note**: Firestore classes are not meant to be subclassed except for use in test mocks. Subclassing is
/// not supported in production code and new SDK releases may break code that does so.
class QuerySnapshot extends Iterable<QueryDocumentSnapshot> {
  QuerySnapshot(this.query, this.snapshot, this._firestore)
      : assert(query != null),
        assert(snapshot != null),
        assert(_firestore != null),
        metadata = SnapshotMetadata(snapshot.hasPendingWrites, snapshot.isFromCache);

  final Query query;

  /// Returns the metadata for this document snapshot.
  final SnapshotMetadata metadata;

  final ViewSnapshot snapshot;
  final FirebaseFirestore _firestore;

  List<DocumentChange> _cachedChanges;
  MetadataChanges _cachedChangesMetadataState;

  /// Returns the list of documents that changed since the last snapshot. If it's the first snapshot all documents will
  /// be in the list as added changes.
  ///
  /// Documents with changes only to their metadata will not be included.
  ///
  /// Returns the list of document changes since the last snapshot.
  List<DocumentChange> get documentChanges => getDocumentChanges(MetadataChanges.exclude);

  /// Returns the list of documents that changed since the last snapshot. If it's the first snapshot all documents will
  /// be in the list as added changes.
  ///
  /// [metadataChanges] Indicates whether metadata-only changes (i.e. only [Query.metadata] changed) should be included.
  ///
  /// Returns the list of document changes since the last snapshot.
  List<DocumentChange> getDocumentChanges(MetadataChanges metadataChanges) {
    if (metadataChanges == MetadataChanges.include && snapshot.excludesMetadataChanges) {
      throw ArgumentError('To include metadata changes with your document changes, you must also pass '
          'MetadataChanges.include to getSnapshots().');
    }

    if (_cachedChanges == null || _cachedChangesMetadataState != metadataChanges) {
      _cachedChanges =
          DocumentChange.changesFromSnapshot(_firestore, metadataChanges, snapshot).toList(growable: false);
      _cachedChangesMetadataState = metadataChanges;
    }
    return _cachedChanges;
  }

  /// Returns the documents in this [QuerySnapshot] as a List in order of the query.
  ///
  /// Returns the list of documents.
  List<DocumentSnapshot> get documents {
    final List<DocumentSnapshot> res = List<DocumentSnapshot>(snapshot.documents.length);
    int i = 0;
    for (core.Document doc in snapshot.documents) {
      res[i] = _convertDocument(doc);
      i++;
    }
    return res;
  }

  /// Returns true if there are no documents in the QuerySnapshot.
  @override
  bool get isEmpty => snapshot.documents.isEmpty;

  /// Returns the number of documents in the QuerySnapshot.
  @override
  int get length => snapshot.documents.length;

  @override
  Iterator<QueryDocumentSnapshot> get iterator {
    return () sync* {
      final Iterator<core.Document> it = snapshot.documents.iterator;
      while (it.moveNext()) {
        yield _convertDocument(it.current);
      }
    }()
        .iterator;
  }

  QueryDocumentSnapshot _convertDocument(Document document) {
    return QueryDocumentSnapshot.fromDocument(
      _firestore,
      document,
      fromCache: snapshot.isFromCache,
      hasPendingWrites: snapshot.mutatedKeys.contains(document.key),
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
