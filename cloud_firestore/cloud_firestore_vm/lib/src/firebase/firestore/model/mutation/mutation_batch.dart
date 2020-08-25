// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:_firebase_database_collection_vm/_firebase_database_collection_vm.dart';
import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation_batch_result.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_vm/src/firebase/timestamp.dart';
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// A batch of mutations that will be sent as one unit to the backend. Batches can be marked as a
/// tombstone if the mutation queue does not remove them immediately. When a batch is a tombstone it
/// has no mutations.
class MutationBatch {
  const MutationBatch({
    @required this.batchId,
    @required this.localWriteTime,
    @required this.baseMutations,
    @required this.mutations,
  })
  // ignore: prefer_is_empty
  : assert(mutations.length != 0, 'Cannot create an empty mutation batch');

  /// A batch ID that was searched for and not found or a batch ID value known to be before all
  /// known batches.
  ///
  /// Batch ID values from the local store are non-negative so this value is before all batches.
  static const int unknown = -1;

  /// The unique ID of this mutation batch.
  final int batchId;

  /// Returns the local time at which the mutation batch was created / written; used to assign local
  /// times to server timestamps, etc.
  final Timestamp localWriteTime;

  /// Mutations that are used to populate the base values when this mutation is
  /// applied locally. This can be used to locally overwrite values that are
  /// persisted in the remote document cache. Base mutations are never sent to
  /// the backend.
  final List<Mutation> baseMutations;

  /// The user-provided mutations in this mutation batch. User-provided mutations are applied both
  /// locally and remotely on the backend.
  final List<Mutation> mutations;

  /// Applies all the mutations in this [MutationBatch] to the specified document to create a new
  /// remote document.
  ///
  /// [documentKey] is the key of the document to apply mutations to, [maybeDoc] is the document to
  /// apply mutations to and [batchResult] is the result of applying the [MutationBatch] to the
  /// backend.
  MaybeDocument applyToRemoteDocument(DocumentKey documentKey,
      MaybeDocument maybeDoc, MutationBatchResult batchResult) {
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
  MaybeDocument applyToLocalView(
      DocumentKey documentKey, MaybeDocument maybeDoc) {
    if (maybeDoc != null) {
      hardAssert(maybeDoc.key == documentKey,
          'applyToRemoteDocument: key $documentKey doesn\'t match maybeDoc key ${maybeDoc.key}');
    }
    // First, apply the base state. This allows us to apply non-idempotent transform against a
    // consistent set of values.
    for (int i = 0; i < baseMutations.length; i++) {
      final Mutation mutation = baseMutations[i];
      if (mutation.key == documentKey) {
        maybeDoc =
            mutation.applyToLocalView(maybeDoc, maybeDoc, localWriteTime);
      }
    }

    final MaybeDocument baseDoc = maybeDoc;

    // Second, apply all user-provided mutations.
    for (int i = 0; i < mutations.length; i++) {
      final Mutation mutation = mutations[i];
      if (mutation.key == documentKey) {
        maybeDoc = mutation.applyToLocalView(maybeDoc, baseDoc, localWriteTime);
      }
    }
    return maybeDoc;
  }

  /// Computes the local view for all provided documents given the mutations in
  /// this batch.
  ImmutableSortedMap<DocumentKey, MaybeDocument> applyToLocalDocumentSet(
      ImmutableSortedMap<DocumentKey, MaybeDocument> maybeDocumentMap) {
    // TODO(mrschmidt): This implementation is O(n^2). If we iterate through the
    //  mutations first (as done in [applyToLocalView]), we can reduce the
    //  complexity to O(n).

    ImmutableSortedMap<DocumentKey, MaybeDocument> mutatedDocuments =
        maybeDocumentMap;
    for (DocumentKey key in keys) {
      final MaybeDocument mutatedDocument =
          applyToLocalView(key, mutatedDocuments[key]);
      if (mutatedDocument != null) {
        mutatedDocuments =
            mutatedDocuments.insert(mutatedDocument.key, mutatedDocument);
      }
    }
    return mutatedDocuments;
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
          const DeepCollectionEquality()
              .equals(baseMutations, other.baseMutations) &&
          const DeepCollectionEquality().equals(mutations, other.mutations);

  @override
  int get hashCode =>
      batchId.hashCode ^
      localWriteTime.hashCode ^
      const DeepCollectionEquality().hash(baseMutations) ^
      const DeepCollectionEquality().hash(mutations);

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('batchId', batchId)
          ..add('localWriteTime', localWriteTime)
          ..add('baseMutations', baseMutations)
          ..add('mutations', mutations))
        .toString();
  }
}
