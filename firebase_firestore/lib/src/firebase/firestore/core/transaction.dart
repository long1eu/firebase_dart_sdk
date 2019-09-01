// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

import 'dart:async';

import 'package:firebase_firestore/src/firebase/firestore/core/user_data.dart';
import 'package:firebase_firestore/src/firebase/firestore/firebase_firestore_error.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/maybe_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/delete_mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/no_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/snapshot_version.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/datastore.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';

/// Internal transaction object responsible for accumulating the mutations to
/// perform and the base versions for any documents read.
class Transaction {
  Transaction(this.datastore);

  final Datastore datastore;
  final Map<DocumentKey, SnapshotVersion> readVersions =
      <DocumentKey, SnapshotVersion>{};
  final List<Mutation> mutations = <Mutation>[];
  bool committed = false;

  void _recordVersion(MaybeDocument doc) {
    SnapshotVersion docVersion;
    if (doc is Document) {
      docVersion = doc.version;
    } else if (doc is NoDocument) {
      // For nonexistent docs, we must use precondition with version 0 when we
      // overwrite them.
      docVersion = SnapshotVersion.none;
    } else {
      throw Assert.fail(
          'Unexpected document type in transaction: ${doc.runtimeType}');
    }

    if (readVersions.containsKey(doc.key)) {
      final SnapshotVersion existingVersion = readVersions[doc.key];
      if (existingVersion != doc.version) {
        // This transaction will fail no matter what.
        throw FirebaseFirestoreError(
            'Document version changed between two reads.',
            FirebaseFirestoreErrorCode.failedPrecondition);
      }
    } else {
      readVersions[doc.key] = docVersion;
    }
  }

  /// Takes a set of keys and asynchronously attempts to fetch all the documents
  /// from the backend, ignoring any local changes.
  Future<List<MaybeDocument>> lookup(List<DocumentKey> keys) async {
    if (committed) {
      return Future<List<MaybeDocument>>.error(FirebaseFirestoreError(
          'Transaction has already completed.',
          FirebaseFirestoreErrorCode.failedPrecondition));
    }
    if (mutations.isNotEmpty) {
      return Future<List<MaybeDocument>>.error(FirebaseFirestoreError(
          'Transactions lookups are invalid after writes.',
          FirebaseFirestoreErrorCode.failedPrecondition));
    }

    final List<MaybeDocument> result = await datastore.lookup(keys);
    result.forEach(_recordVersion);
    return result;
  }

  void _write(List<Mutation> mutations) {
    if (committed) {
      throw StateError('Transaction has already completed.');
    }
    this.mutations.addAll(mutations);
  }

  /// Returns version of this doc when it was read in this transaction as a
  /// precondition, or no precondition if it was not read.
  Precondition _precondition(DocumentKey key) {
    final SnapshotVersion version = readVersions[key];
    if (version != null) {
      return Precondition(updateTime: version);
    } else {
      return Precondition.none;
    }
  }

  /// Returns the precondition for a document if the operation is an update,
  /// based on the provided [UpdateOptions].
  Precondition _preconditionForUpdate(DocumentKey key) {
    final SnapshotVersion version = readVersions[key];
    if (version != null && version == SnapshotVersion.none) {
      // The document to update doesn't exist, so fail the transaction.
      throw StateError('Can\'t update a document that doesn\'t exist.');
    } else if (version != null) {
      // Document exists, base precondition on document update time.
      return Precondition(updateTime: version);
    } else {
      // Document was not read, so we just use the preconditions for a blind
      // write.
      return Precondition(exists: true);
    }
  }

  /// Stores a set mutation for the given key and value, to be committed when
  /// [commit] is called.
  void set(DocumentKey key, UserDataParsedSetData data) {
    _write(data.toMutationList(key, _precondition(key)));
  }

  /// Stores an update mutation for the given key and values, to be committed
  /// when [commit] is called.
  void update(DocumentKey key, UserDataParsedUpdateData data) {
    _write(data.toMutationList(key, _preconditionForUpdate(key)));
  }

  void delete(DocumentKey key) {
    _write(<DeleteMutation>[DeleteMutation(key, _precondition(key))]);
    // Since the delete will be applied before all following writes, we need to
    // ensure that the precondition for the next write will be exists: false.
    readVersions[key] = SnapshotVersion.none;
  }

  Future<void> commit() {
    if (committed) {
      return Future<void>.error(FirebaseFirestoreError(
          'Transaction has already completed.',
          FirebaseFirestoreErrorCode.failedPrecondition));
    }
    final Set<DocumentKey> unwritten = Set<DocumentKey>.from(readVersions.keys);
    // For each mutation, note that the doc was written.
    for (Mutation mutation in mutations) {
      unwritten.remove(mutation.key);
    }
    if (unwritten.isNotEmpty) {
      return Future<void>.error(FirebaseFirestoreError(
          'Every document read in a transaction must also be written.',
          FirebaseFirestoreErrorCode.failedPrecondition));
    }
    committed = true;

    return datastore.commit(mutations);
  }
}
