// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

import 'package:_firebase_database_collection_vm/_firebase_database_collection_vm.dart';
import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/maybe_document.dart';

/// The result of a write to the local store.
class LocalWriteResult {
  const LocalWriteResult(this.batchId, this.changes);

  final int batchId;

  final ImmutableSortedMap<DocumentKey, MaybeDocument> changes;

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('batchId', batchId)
          ..add('changes', changes))
        .toString();
  }
}
