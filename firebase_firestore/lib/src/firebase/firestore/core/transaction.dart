// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

import 'dart:async';

import 'package:firebase_firestore/src/firebase/firestore/firebase_firestore_error.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/maybe_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/delete_mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/snapshot_version.dart';
import 'package:firebase_firestore/src/firebase/firestore/no_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/datastore.dart';
import 'package:firebase_firestore/src/firebase/firestore/user_data_converter.dart';

/// Internal transaction object responsible for accumulating the mutations to
/// perform and the base versions for any documents read.
class Transaction {
  final Datastore datastore;
  final Map<DocumentKey, SnapshotVersion> readVersions =
      <DocumentKey, SnapshotVersion>{};
  final List<Mutation> mutations = <Mutation>[];
  bool committed;

  Transaction(this.datastore);

  //p
  void recordVersion(MaybeDocument doc) {
    SnapshotVersion docVersion = doc.version;
    if (doc is NoDocument) {
      // For nonexistent docs, we must use precondition with version 0 when we overwrite them.
      docVersion = SnapshotVersion.none;
    }

    if (readVersions.containsKey(doc.key)) {
      SnapshotVersion existingVersion = readVersions[doc.key];
      if (existingVersion != doc.version) {
        // This transaction will fail no matter what.
        throw new FirebaseFirestoreError(
            "Document version changed between two reads.",
            FirebaseFirestoreErrorCode.failedPrecondition);
      }
    } else {
      readVersions[doc.key] = docVersion;
    }
  }

  /**
   * Takes a set of keys and asynchronously attempts to fetch all the documents from the backend,
   * ignoring any local changes.
   */
  Future<List<MaybeDocument>> lookup(List<DocumentKey> keys) async {
    if (committed) {
      return Future.error(new FirebaseFirestoreError(
          "Transaction has already completed.",
          FirebaseFirestoreErrorCode.failedPrecondition));
    }
    if (mutations.isNotEmpty) {
      return Future.error(new FirebaseFirestoreError(
          "Transactions lookups are invalid after writes.",
          FirebaseFirestoreErrorCode.failedPrecondition));
    }

    final List<MaybeDocument> result = await datastore.lookup(keys);
    result.forEach(recordVersion);
    return result;
  }

  //p
  void write(List<Mutation> mutations) {
    if (committed) {
      throw new StateError("Transaction has already completed.");
    }
    this.mutations.addAll(mutations);
  }

  /**
   * Returns version of this doc when it was read in this transaction as a precondition, or no
   * precondition if it was not read.
   */
  //p
  Precondition precondition(DocumentKey key) {
    SnapshotVersion version = readVersions[key];
    if (version != null) {
      return Precondition.fromUpdateTime(version);
    } else {
      return Precondition.none;
    }
  }

  /**
   * Returns the precondition for a document if the operation is an update, based on the provided
   * UpdateOptions.
   */
  //p
  Precondition preconditionForUpdate(DocumentKey key) {
    SnapshotVersion version = this.readVersions[key];
    if (version != null && version == SnapshotVersion.none) {
      // The document to update doesn't exist, so fail the transaction.
      throw new StateError("Can't update a document that doesn't exist.");
    } else if (version != null) {
      // Document exists, base precondition on document update time.
      return Precondition.fromUpdateTime(version);
    } else {
      // Document was not read, so we just use the preconditions for a blind write.
      return Precondition.fromExists(true);
    }
  }

  /** Stores a set mutation for the given key and value, to be committed when commit() is called. */
  void set(DocumentKey key, ParsedDocumentData data) {
    write(data.toMutationList(key, precondition(key)));
  }

  /**
   * Stores an update mutation for the given key and values, to be committed when commit() is
   * called.
   */
  void update(DocumentKey key, ParsedUpdateData data) {
    write(data.toMutationList(key, preconditionForUpdate(key)));
  }

  void delete(DocumentKey key) {
    write([new DeleteMutation(key, precondition(key))]);
    // Since the delete will be applied before all following writes, we need to ensure that the
    // precondition for the next write will be exists: false.
    readVersions[key] = SnapshotVersion.none;
  }

  Future<void> commit() {
    if (committed) {
      return Future.error(new FirebaseFirestoreError(
          "Transaction has already completed.",
          FirebaseFirestoreErrorCode.failedPrecondition));
    }
    Set<DocumentKey> unwritten = Set<DocumentKey>.from(readVersions.keys);
    // For each mutation, note that the doc was written.
    for (Mutation mutation in mutations) {
      unwritten.remove(mutation.key);
    }
    if (unwritten.isNotEmpty) {
      return Future.error(new FirebaseFirestoreError(
          "Every document read in a transaction must also be written.",
          FirebaseFirestoreErrorCode.failedPrecondition));
    }
    committed = true;

    return datastore.commit(mutations);
  }
/*
  //p
  static final Executor defaultExecutor = createDefaultExecutor();

  //p
  static Executor createDefaultExecutor() {
    // Create a thread pool with a reasonable size.
    int corePoolSize = 5;
    // maxPoolSize only gets used when queue is full, and queue size is MAX_INT, so this is a no-op.
    int maxPoolSize = corePoolSize;
    int keepAliveSeconds = 1;
    LinkedBlockingQueue<Runnable> queue = new LinkedBlockingQueue<>();
    ThreadPoolExecutor executor =
    new ThreadPoolExecutor(
        corePoolSize, maxPoolSize, keepAliveSeconds, TimeUnit.SECONDS, queue);
    executor.allowCoreThreadTimeOut(true);
    return executor;
  }

  static Executor getDefaultExecutor() {
    return defaultExecutor;
  }
  */
}
