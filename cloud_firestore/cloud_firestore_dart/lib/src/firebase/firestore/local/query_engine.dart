// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

import 'dart:async';

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_documents_view.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';

/// Represents a query engine capable of performing queries over the local document cache. You must call
/// [setLocalDocumentsView] before using it.
abstract class QueryEngine {
  /// Sets the document view to query against.
  void setLocalDocumentsView(LocalDocumentsView localDocuments);

  /// Returns all local documents matching the specified query.
  ///
  /// [lastLimboFreeSnapshotVersion] is the snapshot version at which the target was last free of limbo documents
  /// ([SnapshotVersion.none] if it never was or the previous results must not be used) and [remoteKeys] are the keys
  /// of the documents that matched the target at that version.
  Future<ImmutableSortedMap<DocumentKey, Document>> getDocumentsMatchingQuery(
    Query query,
    SnapshotVersion lastLimboFreeSnapshotVersion,
    ImmutableSortedSet<DocumentKey> remoteKeys,
  );

  /// Whether the engine creates a field index for a query when it finds that the index would have made the query
  /// cheaper (see `PersistentCacheIndexManager`). Off by default.
  abstract bool indexAutoCreationEnabled;

  /// Notifies the query engine of a document change in case it would like to
  /// update indexes and the like.
  // TODO(long1eu): We can change this to just accept the changed fields
  //  (w/ old and new values) if it's convenient for the caller to compute.
  void handleDocumentChange(
    MaybeDocument oldDocument,
    MaybeDocument newDocument,
  );
}
