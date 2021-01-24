// File created by
// Lung Razvan <long1eu>
// on 19/09/2018

import 'dart:async';

import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistence/target_data.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/reference_set.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';

/// A [ReferenceDelegate] instance handles all of the hooks into the
/// document-reference lifecycle. This includes being added to a target, being
/// removed from a target, being subject to mutation, and being mutated by the
/// user.
///
/// Different implementations may do different things with each of these events.
/// Not every implementation needs to do something with every lifecycle hook.
///
/// Implementations that care about sequence numbers are responsible for
/// generating them and making them available.
abstract class ReferenceDelegate {
  /// Registers a [ReferenceSet] of documents that should be considered
  /// 'referenced' and not eligible for removal during garbage collection.
  set inMemoryPins(ReferenceSet inMemoryPins);

  /// Notify the delegate that the given document was added to a target.
  Future<void> addReference(DocumentKey key);

  /// Notify the delegate that the given document was removed from a target.
  Future<void> removeReference(DocumentKey key);

  /// Notify the delegate that a document is no longer being mutated by the
  /// user.
  Future<void> removeMutationReference(DocumentKey key);

  /// Notify the delegate that a target was removed. The delegate may, but is
  /// not obligated to, actually delete the target and associated data.
  Future<void> removeTarget(TargetData queryData);

  /// Notify the delegate that a limbo document was updated.
  Future<void> updateLimboDocument(DocumentKey key);

  /// Returns the sequence number of the current transaction. Only valid during
  /// a transaction.
  int get currentSequenceNumber;

  /// Lifecycle hook to notify the delegate that a transaction has started.
  void onTransactionStarted();

  /// Lifecycle hook to notify the delegate that a transaction has committed.
  Future<void> onTransactionCommitted();
}
