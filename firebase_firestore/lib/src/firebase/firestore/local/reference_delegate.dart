// File created by
// Lung Razvan <long1eu>
// on 19/09/2018

import 'dart:async';

import 'package:firebase_firestore/src/firebase/firestore/local/query_data.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/reference_set.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/database_impl.dart';

/// A [ReferenceDelegate] instance handles all of the hooks into the
/// document-reference lifecycle. This includes being added to a target, being
/// removed from a target, being subject to mutation, and being mutated by the
/// user.
///
/// * Different implementations may do different things with each of these
/// events. Not every implementation needs to do something with every lifecycle
/// hook.
///
/// * Implementations that care about sequence numbers are responsible for
/// generating them and making them available.
abstract class ReferenceDelegate {
  /// Registers a [ReferenceSet] of documents that should be considered
  /// 'referenced' and not eligible for removal during garbage collection.
  set additionalReferences(ReferenceSet additionalReferences);

  /// Notify the delegate that the given document was added to a target.
  Future<void> addReference(DatabaseExecutor tx, DocumentKey key);

  /// Notify the delegate that the given document was removed from a target.
  Future<void> removeReference(DatabaseExecutor tx, DocumentKey key);

  /// Notify the delegate that a document is no longer being mutated by the
  /// user.
  Future<void> removeMutationReference(DatabaseExecutor tx, DocumentKey key);

  /// Notify the delegate that a target was removed. The delegate may, but is
  /// not obligated to, actually delete the target and associated data.
  Future<void> removeTarget(DatabaseExecutor tx, QueryData queryData);

  /// Notify the delegate that a limbo document was updated.
  Future<void> updateLimboDocument(DatabaseExecutor tx, DocumentKey key);

  /// Returns the sequence number of the current transaction. Only valid during
  /// a transaction.
  int get currentSequenceNumber;

  /// Lifecycle hook to notify the delegate that a transaction has started.
  void onTransactionStarted();

  /// Lifecycle hook to notify the delegate that a transaction has committed.
  void onTransactionCommitted();
}
