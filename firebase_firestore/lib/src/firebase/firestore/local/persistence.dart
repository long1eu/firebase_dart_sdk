// File created by
// Lung Razvan <long1eu>
// on 19/09/2018

import 'dart:async';

import 'package:firebase_firestore/src/firebase/firestore/auth/user.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/local_store.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/mutation_queue.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_cache.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/reference_delegate.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/remote_document_cache.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/types.dart';

/// Persistence is the lowest-level shared interface to persistent storage in Firestore.
///
/// Persistence is used to create [MutationQueue] and [RemoteDocumentCache] instances backed by
/// persistence (which might be in-memory or SQLite).
///
/// Persistence also exposes an API to run transactions against the backing store. All read and
/// write operations must be wrapped in a transaction. Implementations of Persistence only need to
/// guarantee that writes made against the transaction are not made to durable storage until the
/// transaction commits. Since memory-only storage components do not alter durable storage, they are
/// free to ignore the transaction.
///
/// This contract is enough to allow the [LocalStore] be be written independently of whether or
/// not the stored state actually is durably persisted. If persistent storage is enabled, writes are
/// grouped together to avoid inconsistent state that could cause crashes.
///
/// Concretely, when persistent storage is enabled, the persistent versions of [MutationQueue],
/// [RemoteDocumentCache], and others (the mutators) will defer their writes into a transaction.
/// Once the local store has completed one logical operation, it commits the transaction.
///
/// When persistent storage is disabled, the non-persistent versions of the mutators ignore the
/// transaction. This short-cut is allowed because memory-only storage leaves no state so it cannot
/// be inconsistent.
///
/// This simplifies the implementations of the mutators and allows memory-only implementations to
/// supplement the persistent ones without requiring any special dual-store implementation of
/// [Persistence]. The cost is that the [LocalStore] needs to be slightly careful about the order of
/// its reads and writes in order to avoid relying on being able to read back uncommitted writes.
abstract class Persistence {
  const Persistence();

  static const String tag = 'Persistence';

  /// Temporary setting for enabling indexing-specific code paths while in development.
  // TODO: Remove this.
  static bool indexingSupportEnabled = false;

  /// Starts persistent storage, opening the database or similar.
  Future<void> start();

  /// Releases any resources held during eager shutdown.
  Future<void> shutdown();

  bool get started;

  ReferenceDelegate get referenceDelegate;

  /// Returns a [MutationQueue] representing the persisted mutations for the given user.
  ///
  /// Note: The implementation is free to return the same instance every time this is called for a
  /// given user. In particular, the memory-backed implementation does this to emulate the persisted
  /// implementation to the extent possible (e.g. in the case of uid switching from
  /// sally=>jack=>sally, sally's mutation queue will be preserved).
  MutationQueue getMutationQueue(User user);

  /// Creates a [QueryCache] representing the persisted cache of queries.
  QueryCache get queryCache;

  /// Creates a [RemoteDocumentCache] representing the persisted cache of remote documents.
  RemoteDocumentCache get remoteDocumentCache;

  /// Performs an operation inside a persistence transaction. Any reads or writes against
  /// persistence must be performed within a transaction. Writes will be committed atomically once
  /// the transaction completes.
  ///
  /// [action] is a description of the action performed by this transaction, used for logging when
  /// executing the [operation] to be run inside a transaction.
  Future<void> runTransaction(String action, Transaction<void> operation);

  /// Performs an operation inside a persistence transaction. Any reads or writes against
  /// persistence must be performed within a transaction. Writes will be committed atomically once
  /// the transaction completes.
  Future<T> runTransactionAndReturn<T>(String action, Transaction<T> operation);
}
