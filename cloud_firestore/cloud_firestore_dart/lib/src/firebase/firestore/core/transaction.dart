// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/aggregate_field.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
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
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/datastore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;

/// Internal transaction object responsible for accumulating the mutations to
/// perform and the base versions for any documents read.
class Transaction {
  /// Creates a transaction.
  ///
  /// A [readOnly] transaction is a transaction of the backend: it is started there with its first read, every read
  /// (documents, queries, aggregations) sees the database at the same point in time ([readTime] when given), nothing
  /// is committed and it is released when it ends. It rejects every write.
  ///
  /// PORTING NOTE: the Android and JS client SDKs have no read-only transactions; this follows the server SDKs.
  Transaction(this._transactionClient, {this.readOnly = false, this.readTime})
    : assert(
        readTime == null || readOnly,
        'readTime needs a read-only transaction',
      ),
      readVersions = <DocumentKey, SnapshotVersion>{},
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

  /// The time whose state a [readOnly] transaction reads, or null for the time it starts.
  final SnapshotVersion? readTime;

  /// The start of the backend transaction of a [readOnly] transaction, once a read asked for it.
  Future<Uint8List>? _backendTransaction;

  Future<Uint8List> _ensureBackendTransaction() {
    return _backendTransaction ??= _transactionClient.beginReadOnlyTransaction(
      readTime: readTime,
    );
  }

  /// Runs [query] on the backend, in the snapshot of this (read-only) transaction.
  Future<List<Document>> runQuery(Query query) async {
    _ensureCommitNotCalled();
    _ensureReadOnly('Queries');
    return _transactionClient.runQuery(
      query,
      await _ensureBackendTransaction(),
    );
  }

  /// Runs an aggregation over [query] on the backend, in the snapshot of this (read-only) transaction.
  Future<Map<String, FieldValue>> runAggregateQuery(
    Query query,
    List<AggregateField> aggregateFields,
  ) async {
    _ensureCommitNotCalled();
    _ensureReadOnly('Aggregations');
    return _transactionClient.runAggregateQuery(
      query,
      aggregateFields,
      await _ensureBackendTransaction(),
    );
  }

  /// Executes the pipeline of [request] on the backend, in the snapshot of this (read-only) transaction.
  Future<List<proto.ExecutePipelineResponse>> executePipeline(
    proto.ExecutePipelineRequest request,
  ) async {
    _ensureCommitNotCalled();
    _ensureReadOnly('Pipelines');
    return _transactionClient.executePipeline(
      request,
      await _ensureBackendTransaction(),
    );
  }

  void _ensureReadOnly(String what) {
    if (!readOnly) {
      // A read-write transaction is optimistic: it verifies the documents it read when it commits, and the result
      // of a query can't be verified that way.
      throw FirestoreError(
        '$what can only be run in a read-only transaction '
        '(TransactionOptions(readOnly: true)).',
        FirestoreErrorCode.invalidArgument,
      );
    }
  }

  /// Ends a [readOnly] transaction on the backend, if it was started there. Never fails: the backend also drops
  /// transactions by itself. Does nothing for a read-write transaction.
  Future<void> release() async {
    final Future<Uint8List>? backendTransaction = _backendTransaction;
    if (backendTransaction == null) {
      return;
    }
    _backendTransaction = null;
    try {
      await _transactionClient.rollback(await backendTransaction);
    } catch (_) {
      // Best effort.
    }
  }

  /// Takes a set of keys and asynchronously attempts to fetch all the documents
  /// from the backend, ignoring any local changes.
  Future<List<MaybeDocument>> lookup(List<DocumentKey> keys) async {
    _ensureCommitNotCalled();

    if (readOnly) {
      return _transactionClient.lookup(
        keys,
        transaction: await _ensureBackendTransaction(),
      );
    }

    if (mutations.isNotEmpty) {
      // As in the JS SDK, the error also fails the commit: a transaction that
      // tried to read after writing does not commit, even if the update
      // function caught the error.
      final FirestoreError error = FirestoreError(
        'Firestore transactions require all reads to be executed before all '
        'writes.',
        FirestoreErrorCode.invalidArgument,
      );
      _lastWriteError = error;
      return Future<List<MaybeDocument>>.error(error);
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
      // Nothing to commit or to verify: every read came from one snapshot of the backend.
      committed = true;
      return release();
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
