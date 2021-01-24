// File created by
// Lung Razvan <long1eu>
// on 17/01/2021

import 'package:_firebase_database_collection_vm/_firebase_database_collection_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';

class QueryResult {
  const QueryResult(this.documents, this.remoteKeys);

  final ImmutableSortedMap<DocumentKey, Document> documents;
  final ImmutableSortedSet<DocumentKey> remoteKeys;
}
