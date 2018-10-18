// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:firebase_firestore/src/firebase/timestamp.dart';

/// A queue of mutations to apply to the remote store.
abstract class MutationQueue {
  /// Starts the mutation queue, performing any initial reads that might be
  /// required to establish invariants, etc.
  ///
  /// * After starting, the mutation queue must guarantee that the
  /// [highestAcknowledgedBatchId] is less than [nextBatchId]. This prevents the
  /// local store from creating new batches that the mutation queue would
  /// consider erroneously acknowledged.
  Future<void> start();

  /// Returns true if this queue contains no mutation batches.
  Future<bool> isEmpty();

  /// Returns the next batch ID that will be assigned to a new mutation batch.
  ///
  /// * Callers generally don't care about this value except to test that the
  /// mutation queue is properly maintaining the invariant that
  /// [highestAcknowledgedBatchId] is less than [nextBatchId].
  int get nextBatchId;

  /// Acknowledges the given [batch].
  Future<void> acknowledgeBatch(MutationBatch batch, Uint8List streamToken);

  /// Returns the current stream token for this mutation queue.
  Uint8List get lastStreamToken;

  /// Sets the stream token for this mutation queue.
  Future<void> setLastStreamToken(Uint8List streamToken);

  /// Creates a new mutation batch and adds it to this mutation queue.
  Future<MutationBatch> addMutationBatch(
      Timestamp localWriteTime, List<Mutation> mutations);

  /// Loads the mutation batch with the given [batchId].
  Future<MutationBatch> lookupMutationBatch(int batchId);

  /// Returns the first unacknowledged mutation batch after the passed in
  /// [batchId] in the mutation queue or null if empty.
  ///
  /// [batchId] to search after, or [MutationBatch.unknown] for the first
  /// mutation in the queue. Returns the next [Mutation] or null if there wasn't
  /// one.
  Future<MutationBatch> getNextMutationBatchAfterBatchId(int batchId);

  /// Returns all mutation batches in the mutation queue.
  // TODO: PERF: Current consumer only needs mutated keys; if we can provide
  // that cheaply, we should replace this.
  Future<List<MutationBatch>> getAllMutationBatches();

  /// Finds all mutation batches that could <b>possibly<b> affect the given
  /// document key. Not all mutations in a batch will necessarily affect the
  /// document key, so when looping through the batch you'll need to check that
  /// the mutation itself matches the key.
  ///
  /// * Note that because of this requirement implementations are free to return
  /// mutation batches that don't contain the document key at all if it's
  /// convenient.
  ///
  /// * Batches are guaranteed to be sorted by batch ID.
  Future<List<MutationBatch>> getAllMutationBatchesAffectingDocumentKey(
      DocumentKey documentKey);

  /// Finds all mutation batches that could <b>possibly<b> affect the given set
  /// of document keys. Not all mutations in a batch will necessarily affect
  /// each key, so when looping through the batch you'll need to check that the
  /// mutation itself matches the key.
  ///
  /// * Note that because of this requirement implementations are free to return
  /// mutation batches that don't contain any of the document keys at all if
  /// it's convenient.
  ///
  /// * Batches are guaranteed to be sorted by batch ID.
  Future<List<MutationBatch>> getAllMutationBatchesAffectingDocumentKeys(
      Iterable<DocumentKey> documentKeys);

  /// Finds all mutation batches that could affect the results for the given
  /// query. Not all mutations in a batch will necessarily affect the query, so
  /// when looping through the batch you'll need to check that the mutation
  /// itself matches the query.
  ///
  /// * Note that because of this requirement implementations are free to return
  /// mutation batches that don't match the query at all if it's convenient.
  ///
  /// * Batches are guaranteed to be sorted by batch ID.
  ///
  /// * NOTE: A [PatchMutation] does not need to include all fields in the query
  /// filter criteria in order to be a match (but any fields it does contain do
  /// need to match).
  Future<List<MutationBatch>> getAllMutationBatchesAffectingQuery(Query query);

  /// Removes the given mutation batch from the queue. This is useful in two
  /// circumstances:
  ///
  /// <ul>
  /// <li>Removing applied mutations from the head of the queue
  /// <li>Removing rejected mutations from anywhere in the queue
  /// </ul>
  Future<void> removeMutationBatch(MutationBatch batch);

  /// Performs a consistency check, examining the mutation queue for any leaks,
  /// if possible.
  Future<void> performConsistencyCheck();
}
