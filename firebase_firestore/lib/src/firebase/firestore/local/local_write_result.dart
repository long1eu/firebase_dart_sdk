// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_database_collection/firebase_database_collection.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/maybe_document.dart';

/// The result of a write to the local store.
class LocalWriteResult {
  final int batchId;

  final ImmutableSortedMap<DocumentKey, MaybeDocument> changes;

  const LocalWriteResult(this.batchId, this.changes);

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('batchId', batchId)
          ..add('changes', changes))
        .toString();
  }
}
