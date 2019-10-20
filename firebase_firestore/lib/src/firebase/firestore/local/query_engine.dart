// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

import 'dart:async';

import 'package:firebase_database_collection/firebase_database_collection.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/maybe_document.dart';

/// Represents a query engine capable of performing queries over the local document cache.
abstract class QueryEngine {
  /// Returns all local documents matching the specified query.
  Future<ImmutableSortedMap<DocumentKey, Document>> getDocumentsMatchingQuery(Query query);

  /// Notifies the query engine of a document change in case it would like to update indexes and the
  /// like.
  // TODO: We can change this to just accept the changed fields (w/ old and new values) if it's
  //  convenient for the caller to compute.
  void handleDocumentChange(MaybeDocument oldDocument, MaybeDocument newDocument);
}
