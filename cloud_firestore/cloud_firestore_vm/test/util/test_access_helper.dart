// File created by
// Lung Razvan <long1eu>
// on 25/09/2018

import 'package:cloud_firestore_vm/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';

class TestAccessHelper {
  /// Makes the DocumentReference constructor accessible.
  static DocumentReference createDocumentReference(DocumentKey documentKey) {
    // We can use null here because the tests only use this as a wrapper for
    // documentKeys.
    return DocumentReference(documentKey, null);
  }

  /// Makes the getKey() method accessible. */
  static DocumentKey referenceKey(DocumentReference documentReference) {
    return documentReference.key;
  }
}
