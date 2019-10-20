// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:collection/collection.dart';
import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_database_collection/firebase_database_collection.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/document_view_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_set.dart';
import 'package:meta/meta.dart';

/// The possibly states a document can be in w.r.t syncing from local storage to the backend.
enum ViewSnapshotSyncState {
  none,
  local,
  synced,
}

class ViewSnapshot {
  const ViewSnapshot(
    this.query,
    this.documents,
    this.oldDocuments,
    this.changes,
    this.mutatedKeys, {
    @required this.isFromCache,
    @required this.didSyncStateChange,
    @required this.excludesMetadataChanges,
  });

  /// Returns a view snapshot as if all documents in the snapshot were added.
  factory ViewSnapshot.fromInitialDocuments(
    Query query,
    DocumentSet documents,
    ImmutableSortedSet<DocumentKey> mutatedKeys, {
    @required bool isFromCache,
    @required bool excludesMetadataChanges,
  }) {
    final List<DocumentViewChange> viewChanges = <DocumentViewChange>[];
    for (Document doc in documents) {
      viewChanges.add(DocumentViewChange(DocumentViewChangeType.added, doc));
    }
    return ViewSnapshot(
      query,
      documents,
      DocumentSet.emptySet(query.comparator),
      viewChanges,
      mutatedKeys,
      isFromCache: isFromCache,
      didSyncStateChange: true,
      excludesMetadataChanges: excludesMetadataChanges,
    );
  }

  final Query query;
  final DocumentSet documents;
  final DocumentSet oldDocuments;
  final List<DocumentViewChange> changes;
  final ImmutableSortedSet<DocumentKey> mutatedKeys;
  final bool isFromCache;
  final bool didSyncStateChange;
  final bool excludesMetadataChanges;

  bool get hasPendingWrites => mutatedKeys.isNotEmpty;

  ViewSnapshot copyWith({
    Query query,
    DocumentSet documents,
    DocumentSet oldDocuments,
    List<DocumentViewChange> changes,
    bool isFromCache,
    ImmutableSortedSet<DocumentKey> mutatedKeys,
    bool didSyncStateChange,
    bool excludesMetadataChanges,
  }) {
    return ViewSnapshot(
      query ?? this.query,
      documents ?? this.documents,
      oldDocuments ?? this.oldDocuments,
      changes ?? this.changes,
      mutatedKeys ?? this.mutatedKeys,
      isFromCache: isFromCache ?? this.isFromCache,
      didSyncStateChange: didSyncStateChange ?? this.didSyncStateChange,
      excludesMetadataChanges: excludesMetadataChanges ?? this.excludesMetadataChanges,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    if (other is ViewSnapshot && runtimeType == other.runtimeType) {
      return isFromCache == other.isFromCache &&
          mutatedKeys == other.mutatedKeys &&
          didSyncStateChange == other.didSyncStateChange &&
          excludesMetadataChanges == other.excludesMetadataChanges &&
          query == other.query &&
          documents == other.documents &&
          oldDocuments == other.oldDocuments &&
          const DeepCollectionEquality().equals(changes, other.changes);
    }

    return false;
  }

  @override
  int get hashCode =>
      query.hashCode * 31 +
      documents.hashCode * 31 +
      oldDocuments.hashCode * 31 +
      const DeepCollectionEquality().hash(changes) * 31 +
      mutatedKeys.hashCode +
      (isFromCache ? 0 : 1) +
      (didSyncStateChange ? 2 : 3) +
      (excludesMetadataChanges ? 4 : 5);

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('query', query)
          ..add('documents', documents)
          ..add('oldDocuments', oldDocuments)
          ..add('changes', changes)
          ..add('isFromCache', isFromCache)
          ..add('mutatedKeys', mutatedKeys)
          ..add('didSyncStateChange', didSyncStateChange)
          ..add('excludesMetadataChanges', excludesMetadataChanges))
        .toString();
  }
}
