// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/document_view_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_set.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:collection/collection.dart';
import 'package:firebase_app_dart/internal.dart';

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
    required this.isFromCache,
    required this.didSyncStateChange,
    required this.excludesMetadataChanges,
    required this.hasCachedResults,
    this.readTime = SnapshotVersion.none,
  });

  /// Returns a view snapshot as if all documents in the snapshot were added.
  factory ViewSnapshot.fromInitialDocuments(
    Query query,
    DocumentSet documents,
    ImmutableSortedSet<DocumentKey> mutatedKeys, {
    required bool isFromCache,
    required bool excludesMetadataChanges,
    required bool hasCachedResults,
    SnapshotVersion readTime = SnapshotVersion.none,
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
      hasCachedResults: hasCachedResults,
      readTime: readTime,
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

  /// Whether the snapshot was computed from a target that has been synced with the backend before (it has a resume
  /// token), so that even an empty result is a meaningful cached result.
  final bool hasCachedResults;

  /// The backend snapshot version at which the documents of this snapshot are known to be consistent with the
  /// server, or [SnapshotVersion.none] when unknown (for example when the snapshot is from cache).
  ///
  /// It is a lower bound: the view may still be consistent at later versions. It is used as the read time of the
  /// bundle written by `QuerySnapshot.toJson()`, so that resuming the listen does not miss changes. It is not part of
  /// [operator ==] or [hashCode].
  final SnapshotVersion readTime;

  bool get hasPendingWrites => mutatedKeys.isNotEmpty;

  ViewSnapshot copyWith({
    Query? query,
    DocumentSet? documents,
    DocumentSet? oldDocuments,
    List<DocumentViewChange>? changes,
    bool? isFromCache,
    ImmutableSortedSet<DocumentKey>? mutatedKeys,
    bool? didSyncStateChange,
    bool? excludesMetadataChanges,
    bool? hasCachedResults,
    SnapshotVersion? readTime,
  }) {
    return ViewSnapshot(
      query ?? this.query,
      documents ?? this.documents,
      oldDocuments ?? this.oldDocuments,
      changes ?? this.changes,
      mutatedKeys ?? this.mutatedKeys,
      isFromCache: isFromCache ?? this.isFromCache,
      didSyncStateChange: didSyncStateChange ?? this.didSyncStateChange,
      excludesMetadataChanges:
          excludesMetadataChanges ?? this.excludesMetadataChanges,
      hasCachedResults: hasCachedResults ?? this.hasCachedResults,
      readTime: readTime ?? this.readTime,
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
          hasCachedResults == other.hasCachedResults &&
          query == other.query &&
          documents == other.documents &&
          oldDocuments == other.oldDocuments &&
          const DeepCollectionEquality().equals(changes, other.changes);
    }

    return false;
  }

  @override
  int get hashCode =>
      query.hashCode ^
      documents.hashCode ^
      oldDocuments.hashCode ^
      const DeepCollectionEquality().hash(changes) ^
      mutatedKeys.hashCode ^
      (isFromCache ? 0 : 1) ^
      (didSyncStateChange ? 2 : 3) ^
      (excludesMetadataChanges ? 4 : 5) ^
      (hasCachedResults ? 6 : 7);

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
          ..add('excludesMetadataChanges', excludesMetadataChanges)
          ..add('hasCachedResults', hasCachedResults)
          ..add('readTime', readTime))
        .toString();
  }
}
