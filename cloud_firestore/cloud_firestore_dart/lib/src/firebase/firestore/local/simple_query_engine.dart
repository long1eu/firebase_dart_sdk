// File created by
// Lung Razvan <long1eu>
// on 21/09/2018

import 'dart:async';

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_documents_view.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_engine.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';

/// A naive implementation of QueryEngine that just loads all the documents in
/// the queried collection and then filters them in memory.
class SimpleQueryEngine implements QueryEngine {
  SimpleQueryEngine(this.localDocumentsView);

  final LocalDocumentsView localDocumentsView;

  @override
  Future<ImmutableSortedMap<DocumentKey, Document>> getDocumentsMatchingQuery(
      Query query) {
    // TODO(long1eu): Once LocalDocumentsView provides a
    //  getCollectionDocuments() method, we should call that here and then
    //  filter the results.
    return localDocumentsView.getDocumentsMatchingQuery(query);
  }

  @override
  void handleDocumentChange(
      MaybeDocument oldDocument, MaybeDocument newDocument) {
    // No indexes to update.
  }
}
