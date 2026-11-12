// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:firebase_app_dart/internal.dart';

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
