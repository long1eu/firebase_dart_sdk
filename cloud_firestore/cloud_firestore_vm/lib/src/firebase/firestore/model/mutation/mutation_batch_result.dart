// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'dart:typed_data';

import 'package:firebase_core/firebase_core_vm.dart';
import 'package:_firebase_database_collection_vm/_firebase_database_collection_vm.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_collections.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/snapshot_version.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';

class MutationBatchResult {
  const MutationBatchResult(
    this.batch,
    this.commitVersion,
    this.mutationResults,
    this.streamToken,
    this.docVersions,
  );

  /// Creates a new [MutationBatchResult] for the given [batch] and [results].
  /// There must be one result for each mutation in the batch. This factory caches a
  /// document=>version mapping (as [docVersions]).
  factory MutationBatchResult.create(MutationBatch batch, SnapshotVersion commitVersion,
      List<MutationResult> mutationResults, Uint8List streamToken) {
    hardAssert(
        batch.mutations.length == mutationResults.length,
        'Mutations sent ${batch.mutations.length} must equal results received '
        '${mutationResults.length}');

    ImmutableSortedMap<DocumentKey, SnapshotVersion> docVersions =
        DocumentCollections.emptyVersionMap();

    final List<Mutation> mutations = batch.mutations;
    for (int i = 0; i < mutations.length; i++) {
      docVersions = docVersions.insert(mutations[i].key, mutationResults[i].version);
    }
    return MutationBatchResult(
      batch,
      commitVersion,
      mutationResults,
      streamToken,
      docVersions,
    );
  }

  final MutationBatch batch;
  final SnapshotVersion commitVersion;
  final List<MutationResult> mutationResults;
  final Uint8List streamToken;
  final ImmutableSortedMap<DocumentKey, SnapshotVersion> docVersions;

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('batch', batch)
          ..add('commitVersion', commitVersion)
          ..add('mutationResults', mutationResults)
          ..add('streamToken', streamToken)
          ..add('docVersions', docVersions))
        .toString();
  }
}
