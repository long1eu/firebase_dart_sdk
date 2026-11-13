// File created by
// Lung Razvan <long1eu>
// on 19/09/2018

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/bundle_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/document_overlay_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/globals_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/mutation_queue.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/overlay_migration_manager.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/query_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/reference_delegate.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/remote_document_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/database.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/types.dart';

import 'index_manager.dart';

/// Called when a client becomes, or stops being, the primary client of its cache (see
/// [Persistence.setPrimaryStateListener]).
typedef PrimaryStateListener = void Function(bool isPrimary);

/// The message of the error a primary-only transaction fails with when the client is not, and cannot become, the
/// primary client (`PRIMARY_LEASE_LOST_ERROR_MSG` of the JS SDK, which speaks of browser tabs).
const String primaryLeaseLostErrorMessage =
    'This client is not the primary client of its persistent cache: another client that uses the same cache holds '
    'the primary lease.';

/// Whether [error] is the error of a primary-only transaction of a client that lost the primary lease.
bool isPrimaryLeaseLoss(Object error) =>
    error is FirestoreError &&
    error.code == FirestoreErrorCode.failedPrecondition &&
    error.message == primaryLeaseLostErrorMessage;

/// Persistence is the lowest-level shared interface to persistent storage in
/// Firestore.
///
/// Persistence is used to create [MutationQueue] and [RemoteDocumentCache]
/// instances backed by persistence (which might be in-memory or SQLite).
///
/// Persistence also exposes an API to run transactions against the backing
/// store. All read and write operations must be wrapped in a transaction.
/// Implementations of Persistence only need to guarantee that writes made
/// against the transaction are not made to durable storage until the
/// transaction commits. Since memory-only storage components do not alter
/// durable storage, they are free to ignore the transaction.
///
/// This contract is enough to allow the [LocalStore] be be written
/// independently of whether or not the stored state actually is durably
/// persisted. If persistent storage is enabled, writes are grouped together to
/// avoid inconsistent state that could cause crashes.
///
/// Concretely, when persistent storage is enabled, the persistent versions of
/// [MutationQueue], [RemoteDocumentCache], and others (the mutators) will defer
/// their writes into a transaction. Once the local store has completed one
/// logical operation, it commits the transaction.
///
/// When persistent storage is disabled, the non-persistent versions of the
/// mutators ignore the transaction. This short-cut is allowed because
/// memory-only storage leaves no state so it cannot be inconsistent.
///
/// This simplifies the implementations of the mutators and allows memory-only
/// implementations to supplement the persistent ones without requiring any
/// special dual-store implementation of [Persistence]. The cost is that the
/// [LocalStore] needs to be slightly careful about the order of its reads and
/// writes in order to avoid relying on being able to read back uncommitted
/// writes.
abstract class Persistence {
  Persistence();

  /// Called with the action of every transaction before the transaction starts. When it throws, the transaction fails
  /// with that error and does not run. Tests use it to simulate a failing database (the `failDatabase` spec step);
  /// implementations call it first thing in [runTransactionAndReturn].
  void Function(String action)? beforeTransaction;

  /// Starts persistent storage, opening the database or similar.
  Future<void> start();

  /// Releases any resources held during eager shutdown.
  Future<void> shutdown();

  bool get started;

  ReferenceDelegate get referenceDelegate;

  /// Returns a [MutationQueue] representing the persisted mutations for the
  /// given user.
  ///
  /// Note: The implementation is free to return the same instance every time
  /// this is called for a given user. In particular, the memory-backed
  /// implementation does this to emulate the persisted implementation to the
  /// extent possible (e.g. in the case of uid switching from
  /// sally=>jack=>sally, sally's mutation queue will be preserved).
  MutationQueue getMutationQueue(User user);

  /// The name of the data migration that builds the document overlays from the mutation queues (pending after the
  /// schema migration that adds the overlay table).
  static const String dataMigrationBuildOverlays = 'BUILD_OVERLAYS';

  /// Returns the [OverlayMigrationManager] that builds the document overlays of data written before they existed.
  OverlayMigrationManager get overlayMigrationManager;

  /// Returns a [DocumentOverlayCache] representing the persisted document overlays for the given user.
  DocumentOverlayCache getDocumentOverlayCache(User user);

  /// Creates a [QueryCache] representing the persisted cache of queries.
  QueryCache get queryCache;

  /// Returns a [BundleCache] representing the persisted cache of loaded bundles.
  BundleCache get bundleCache;

  /// Returns the [GlobalsCache] that stores values that cut across components, such as the session token.
  GlobalsCache get globalsCache;

  /// Creates a [RemoteDocumentCache] representing the persisted cache of remote
  /// documents.
  RemoteDocumentCache get remoteDocumentCache;

  /// The collection parent index, which is the same for all users.
  ///
  /// The field index methods of this [IndexManager] must not be used: field indexes keep their state per user, see
  /// [getIndexManager].
  IndexManager get indexManager;

  /// Returns an [IndexManager] that manages the persisted field indexes for the given user (and the collection parent
  /// index). It has to be started before its field index methods are used.
  IndexManager getIndexManager(User user);

  /// Performs an operation inside a persistence transaction. Any reads or
  /// writes against persistence must be performed within a transaction. Writes
  /// will be committed atomically once the transaction completes.
  ///
  /// [action] is a description of the action performed by this transaction,
  /// used for logging when executing the [operation] to be run inside a
  /// transaction.
  Future<void> runTransaction(String action, Transaction<void> operation);

  /// Performs an operation inside a persistence transaction. Any reads or
  /// writes against persistence must be performed within a transaction.
  /// Writes will be committed atomically once the transaction completes.
  Future<T> runTransactionAndReturn<T>(String action, Transaction<T> operation);

  /// Performs an operation that only the primary client of the cache may perform (a `readwrite-primary` transaction
  /// of the JS SDK): applying a remote event, acknowledging or rejecting a batch, releasing the persisted data of a
  /// target, garbage collection and index backfill.
  ///
  /// The client verifies that it holds the primary lease, or takes it if it may, before [operation] runs, and extends
  /// the lease afterwards. Otherwise the transaction fails with a [FirestoreError] with
  /// [FirestoreErrorCode.failedPrecondition] and [primaryLeaseLostErrorMessage] (see [isPrimaryLeaseLoss]) and the
  /// primary state listener is told that this client is not primary.
  ///
  /// A cache that only one client can use (memory) is always primary: this is [runTransactionAndReturn].
  Future<T> runPrimaryTransaction<T>(String action, Transaction<T> operation) {
    return runTransactionAndReturn(action, operation);
  }

  /// Registers [listener] to be told when this client becomes or stops being the primary client of its cache, and
  /// calls it right away with the current state. Only one listener is kept. A cache that only one client can use is
  /// always primary.
  ///
  /// The listener may be called while a transaction is running: it must not run a transaction itself before that one
  /// finished (it should schedule its work).
  void setPrimaryStateListener(PrimaryStateListener listener) {
    listener(true);
  }

  /// The ids of the clients that use this cache and are alive (refreshed their metadata recently), this one included.
  /// Empty for a cache that only one client can use.
  Future<List<String>> getActiveClients() async => const <String>[];
}

/// Whether [error], thrown by a persistence transaction, means that the transaction did not take effect and may work
/// when it is tried again later (the JS SDK's `isIndexedDbTransactionError`). The recovery paths retry such operations
/// with a backoff and keep the network offline meanwhile; every other error is fatal for the operation.
bool isRecoverablePersistenceError(Object? error) =>
    error is TransientDatabaseException;
