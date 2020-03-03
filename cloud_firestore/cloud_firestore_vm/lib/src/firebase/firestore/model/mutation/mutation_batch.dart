// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:collection/collection.dart';
import 'package:firebase_core/firebase_core_vm.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/maybe_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation_batch_result.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';
import 'package:firebase_firestore/src/firebase/timestamp.dart';

/// A batch of mutations that will be sent as one unit to the backend. Batches can be marked as a
/// tombstone if the mutation queue does not remove them immediately. When a batch is a tombstone it
/// has no mutations.
class MutationBatch {
  const MutationBatch(this.batchId, this.localWriteTime, this.mutations)
      // ignore: prefer_is_empty
      : assert(mutations.length != 0, 'Cannot create an empty mutation batch');

  /// A batch ID that was searched for and not found or a batch ID value known to be before all
  /// known batches.
  ///
  /// Batch ID values from the local store are non-negative so this value is before all batches.
  static const int unknown = -1;

  final int batchId;

  /// Returns the local time at which the mutation batch was created / written; used to assign local
  /// times to server timestamps, etc.
  final Timestamp localWriteTime;
  final List<Mutation> mutations;

  /// Applies all the mutations in this [MutationBatch] to the specified document to create a new
  /// remote document.
  ///
  /// [documentKey] is the key of the document to apply mutations to, [maybeDoc] is the document to
  /// apply mutations to and [batchResult] is the result of applying the [MutationBatch] to the
  /// backend.
  MaybeDocument applyToRemoteDocument(
      DocumentKey documentKey, MaybeDocument maybeDoc, MutationBatchResult batchResult) {
    if (maybeDoc != null) {
      hardAssert(maybeDoc.key == documentKey,
          'applyToRemoteDocument: key $documentKey doesn\'t match maybeDoc key ${maybeDoc.key}');
    }

    final int size = mutations.length;
    final List<MutationResult> mutationResults = batchResult.mutationResults;
    hardAssert(mutationResults.length == size,
        'Mismatch between mutations length ($size) and results length (${mutationResults.length})');

    for (int i = 0; i < size; i++) {
      final Mutation mutation = mutations[i];
      if (mutation.key == documentKey) {
        final MutationResult mutationResult = mutationResults[i];
        maybeDoc = mutation.applyToRemoteDocument(maybeDoc, mutationResult);
      }
    }
    return maybeDoc;
  }

  /// Computes the local view of a document given all the mutations in this batch.
  MaybeDocument applyToLocalView(DocumentKey documentKey, MaybeDocument maybeDoc) {
    if (maybeDoc != null) {
      hardAssert(maybeDoc.key == documentKey,
          'applyToRemoteDocument: key $documentKey doesn\'t match maybeDoc key ${maybeDoc.key}');
    }

    final MaybeDocument baseDoc = maybeDoc;

    for (int i = 0; i < mutations.length; i++) {
      final Mutation mutation = mutations[i];
      if (mutation.key == documentKey) {
        maybeDoc = mutation.applyToLocalView(maybeDoc, baseDoc, localWriteTime);
      }
    }
    return maybeDoc;
  }

  /// Returns the set of unique keys referenced by all mutations in the batch.
  Set<DocumentKey> get keys {
    final Set<DocumentKey> set = <DocumentKey>{};
    for (Mutation mutation in mutations) {
      set.add(mutation.key);
    }
    return set;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MutationBatch &&
          runtimeType == other.runtimeType &&
          batchId == other.batchId &&
          localWriteTime == other.localWriteTime &&
          const DeepCollectionEquality().equals(mutations, other.mutations);

  @override
  int get hashCode =>
      batchId.hashCode ^ localWriteTime.hashCode ^ const DeepCollectionEquality().hash(mutations);

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('batchId', batchId)
          ..add('localWriteTime', localWriteTime)
          ..add('mutations', mutations))
        .toString();
  }
}
