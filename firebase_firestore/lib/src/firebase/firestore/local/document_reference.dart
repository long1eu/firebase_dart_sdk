// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

import 'package:firebase_firestore/src/firebase/firestore/document_reference.dart'
    as public;
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';

/// An immutable value used to keep track of an association between some
/// referencing target or batch and a document key that the target or batch
/// references.
///
/// * A reference can be from either listen targets (identified by their
/// target id) or mutation batches (identified by their batch id).
/// See [GarbageCollector] for more details.
///
/// * Not to be confused with [public.DocumentReference] in the public API.
class DocumentReference {
  /// Returns the document key that's the target of this reference.
  final DocumentKey key;
  final int _targetOrBatchId;

  /// Initializes the document reference with the given key and ID.
  DocumentReference(this.key, this._targetOrBatchId);

  /// Returns the [targetId] of a referring target or the [batchId] of a
  /// referring mutation batch. (Which this is depends upon which [ReferenceSet]
  /// this reference is a part of.)
  int get id => _targetOrBatchId;

  /// Sorts document references by key then ID.
  static int byKey(DocumentReference a, DocumentReference b) {
    final int keyComp = a.key.compareTo(b.key);
    return keyComp != 0
        ? keyComp
        : a._targetOrBatchId.compareTo(b._targetOrBatchId);
  }

  static int byTarget(DocumentReference a, DocumentReference b) {
    final int targetComp = a._targetOrBatchId.compareTo(b._targetOrBatchId);
    return targetComp != 0 ? targetComp : a.key.compareTo(b.key);
  }
}
