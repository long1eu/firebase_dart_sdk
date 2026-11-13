// File created by
// Lung Razvan <long1eu>
// on 25/09/2018

import 'package:cloud_firestore_dart/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';

// ignore: non_constant_identifier_names
Firestore _NullFirestore() =>
    FirestoreInternal.detached(DatabaseId.forProject('project'));

class TestAccessHelper {
  /// Makes the DocumentReference constructor accessible.
  static DocumentReference createDocumentReference(DocumentKey documentKey) {
    // We use a stub Firestore here because the tests only use this as a wrapper for
    // documentKeys.
    return DocumentReferenceInternal.create(documentKey, _NullFirestore());
  }

  /// Makes the getKey() method accessible. */
  static DocumentKey referenceKey(DocumentReference documentReference) {
    return documentReference.key;
  }
}
