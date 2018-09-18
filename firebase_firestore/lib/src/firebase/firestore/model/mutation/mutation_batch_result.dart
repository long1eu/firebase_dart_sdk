// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'dart:collection';

import 'package:firebase_firestore/src/firebase/firestore/model/document_collections.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/snapshot_version.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';

class MutationBatchResult {
  final MutationBatch batch;
  final SnapshotVersion commitVersion;
  final List<MutationResult> mutationResults;
  final List<int> streamToken;
  final SplayTreeMap<DocumentKey, SnapshotVersion> docVersions;

  const MutationBatchResult(
    this.batch,
    this.commitVersion,
    this.mutationResults,
    this.streamToken,
    this.docVersions,
  );

  /// Creates a new [MutationBatchResult] for the given [batch] and [results].
  /// There must be one result for each mutation in the batch. This factory
  /// caches a document=>version mapping (as [docVersions]).
  factory MutationBatchResult.create(
      MutationBatch batch,
      SnapshotVersion commitVersion,
      List<MutationResult> mutationResults,
      List<int> streamToken) {
    Assert.hardAssert(batch.mutations.length == mutationResults.length,
        'Mutations sent ${batch.mutations.length} must equal results received ${mutationResults.length}');

    final SplayTreeMap<DocumentKey, SnapshotVersion> docVersions =
        DocumentCollections.emptyVersionMap();

    List<Mutation> mutations = batch.mutations;
    for (int i = 0; i < mutations.length; i++) {
      docVersions[mutations[i].key] = mutationResults[i].version;
    }
    return MutationBatchResult(
        batch, commitVersion, mutationResults, streamToken, docVersions);
  }
}
