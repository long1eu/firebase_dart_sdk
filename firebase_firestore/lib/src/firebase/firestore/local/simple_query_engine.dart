// File created by
// Lung Razvan <long1eu>
// on 21/09/2018

import 'dart:async';

import 'package:firebase_database_collection/firebase_database_collection.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/local_documents_view.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_engine.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/maybe_document.dart';

/// A naive implementation of QueryEngine that just loads all the documents in
/// the queried collection and then filters them in memory.
class SimpleQueryEngine implements QueryEngine {
  final LocalDocumentsView localDocumentsView;

  SimpleQueryEngine(this.localDocumentsView);

  @override
  Future<ImmutableSortedMap<DocumentKey, Document>> getDocumentsMatchingQuery(
      Query query) {
    // TODO: Once LocalDocumentsView provides a getCollectionDocuments() method,
    // we should call that here and then filter the results.
    return localDocumentsView.getDocumentsMatchingQuery(query);
  }

  @override
  void handleDocumentChange(
      MaybeDocument oldDocument, MaybeDocument newDocument) {
    // No indexes to update.
  }
}
