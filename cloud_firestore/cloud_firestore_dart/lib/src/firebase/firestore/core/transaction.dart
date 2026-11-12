// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/core/user_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/delete_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/verify_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/no_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/datastore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';

/// Internal transaction object responsible for accumulating the mutations to
/// perform and the base versions for any documents read.
class Transaction {
  /// Creates a transaction. A [readOnly] transaction rejects every write and, when committed, only verifies that the
  /// documents it read did not change.
  Transaction(this._transactionClient, {this.readOnly = false})
    : readVersions = <DocumentKey, SnapshotVersion>{},
      mutations = <Mutation>[],
      committed = false;

  final TransactionClient _transactionClient;

  /// Whether this transaction can only read.
  final bool readOnly;
  final Map<DocumentKey, SnapshotVersion> readVersions;
  final List<Mutation> mutations;

  /// A deferred usage error that occurred previously in this transaction that will cause the
  /// transaction to fail once it actually commits.
  FirestoreError? _lastWriteError;

  /// Set of documents that have been written in the transaction.
  ///
  /// When there's more than one write to the same key in a transaction, any
  /// writes after the first are handled differently.
  final Set<DocumentKey> writtenDocs = <DocumentKey>{};
  bool committed;

  /// Takes a set of keys and asynchronously attempts to fetch all the documents
  /// from the backend, ignoring any local changes.
  Future<List<MaybeDocument>> lookup(List<DocumentKey> keys) async {
    _ensureCommitNotCalled();

    if (mutations.isNotEmpty) {
      return Future<List<MaybeDocument>>.error(
        FirestoreError(
          'Transactions lookups are invalid after writes.',
          FirestoreErrorCode.invalidArgument,
        ),
      );
    }

    final List<MaybeDocument> result = await _transactionClient.lookup(keys);
    result.forEach(_recordVersion);
    return result;
  }

  /// Stores a set mutation for the given key and value, to be committed when
  /// [commit] is called.
  void set(DocumentKey key, UserDataParsedSetData data) {
    _ensureWritable();
    _write(<Mutation>[data.toMutation(key, _precondition(key))]);
    writtenDocs.add(key);
  }

  /// Stores an update mutation for the given key and values, to be committed
  /// when [commit] is called.
  void update(DocumentKey key, UserDataParsedUpdateData data) {
    _ensureWritable();
    try {
      _write(<Mutation>[data.toMutation(key, _preconditionForUpdate(key))]);
    } on FirestoreError catch (e) {
      _lastWriteError = e;
    }

    writtenDocs.add(key);
  }

  void delete(DocumentKey key) {
    _ensureWritable();
    _write(<DeleteMutation>[DeleteMutation(key, _precondition(key))]);
    writtenDocs.add(key);
  }

  Future<void> commit() {
    _ensureCommitNotCalled();
    final FirestoreError? lastWriteError = _lastWriteError;
    if (lastWriteError != null) {
      return Future<void>.error(lastWriteError);
    }

    if (readOnly) {
      // Nothing is written: ask the backend to check that every document read still has the version that was read.
      // A transaction that read nothing has nothing to verify.
      committed = true;
      if (readVersions.isEmpty) {
        return Future<void>.value();
      }
      return _transactionClient.commit(<Mutation>[
        for (DocumentKey key in readVersions.keys)
          VerifyMutation(key, _precondition(key)),
      ]);
    }

    final Set<DocumentKey> unwritten = Set<DocumentKey>.from(readVersions.keys);
    // For each mutation, note that the doc was written.
    for (Mutation mutation in mutations) {
      unwritten.remove(mutation.key);
    }
    // For each document that was read but not written, verify that its version is unchanged.
    for (DocumentKey key in unwritten) {
      mutations.add(VerifyMutation(key, _precondition(key)));
    }
    committed = true;

    return _transactionClient.commit(mutations);
  }

  void _recordVersion(MaybeDocument doc) {
    SnapshotVersion docVersion;
    if (doc is Document) {
      docVersion = doc.version;
    } else if (doc is NoDocument) {
      // For nonexistent docs, we must use precondition with version 0 when we
      // overwrite them.
      docVersion = SnapshotVersion.none;
    } else {
      throw fail('Unexpected document type in transaction: ${doc.runtimeType}');
    }

    if (readVersions.containsKey(doc.key)) {
      final SnapshotVersion? existingVersion = readVersions[doc.key];
      if (existingVersion != docVersion) {
        // This transaction will fail no matter what.
        throw FirestoreError(
          'Document version changed between two reads.',
          FirestoreErrorCode.aborted,
        );
      }
    } else {
      readVersions[doc.key] = docVersion;
    }
  }

  /// Returns version of this doc when it was read in this transaction as a
  /// precondition, or no precondition if it was not read.
  Precondition _precondition(DocumentKey key) {
    final SnapshotVersion? version = readVersions[key];
    if (!writtenDocs.contains(key) && version != null) {
      if (version == SnapshotVersion.none) {
        return Precondition(exists: false);
      } else {
        return Precondition(updateTime: version);
      }
    } else {
      return Precondition.none;
    }
  }

  /// Returns the precondition for a document if the operation is an update,
  /// based on the provided [UpdateOptions].
  Precondition _preconditionForUpdate(DocumentKey key) {
    final SnapshotVersion? version = readVersions[key];
    // The first time a document is written, we want to take into account the
    // read time and existence.
    if (!writtenDocs.contains(key) && version != null) {
      if (version == SnapshotVersion.none) {
        // The document to update doesn't exist, so fail the transaction.
        //
        // This has to be validated locally because you can't send a
        // precondition that a document does not exist without changing the
        // semantics of the backend write to be an insert. This is the reverse
        // of what we want, since we want to assert that the document doesn't
        // exist but then send the update and have it fail. Since we can't
        // express that to the backend, we have to validate locally.
        //
        // Note: this can change once we can send separate verify writes in the
        // transaction.
        throw FirestoreError(
          "Can't update a document that doesn't exist.",
          FirestoreErrorCode.invalidArgument,
        );
      }
      // Document exists, base precondition on document update time.
      return Precondition(updateTime: version);
    } else {
      // Document was not read, so we just use the preconditions for a blind
      // write.
      return Precondition(exists: true);
    }
  }

  void _ensureWritable() {
    if (readOnly) {
      throw FirestoreError(
        'Read-only transactions cannot write.',
        FirestoreErrorCode.invalidArgument,
      );
    }
  }

  void _write(List<Mutation> mutations) {
    if (committed) {
      throw StateError('Transaction has already completed.');
    }
    this.mutations.addAll(mutations);
  }

  void _ensureCommitNotCalled() {
    hardAssert(
      !committed,
      'A transaction object cannot be used after its update callback has been invoked.',
    );
  }
}
