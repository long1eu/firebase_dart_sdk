// File created by
// Lung Razvan <long1eu>
// on 25/09/2018

import 'dart:async';

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/auth/credentials_provider.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/auth/empty_credentials_provider.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/auth/firebase_auth_credentials_provider.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/collection_reference.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/database_info.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/firestore_client.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/query.dart' as core;
import 'package:cloud_firestore_vm/src/firebase/firestore/core/transaction.dart' as core;
import 'package:cloud_firestore_vm/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/field_value.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore_multi_db_component.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore_settings.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/transaction.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/user_data_converter.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/async_task.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/database.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/write_batch.dart';
import 'package:firebase_core_vm/firebase_core_vm.dart';
import 'package:meta/meta.dart';

/// Represents a Firestore Database and is the entry point for all Firestore operations
///
/// **Subclassing Note**: Firestore classes are not meant to be subclassed except for use in test mocks. Subclassing is
/// not supported in production code and new SDK releases may break code that does so.
class Firestore {
  @visibleForTesting
  Firestore(this.databaseId, this.firebaseApp, this.client, this._scheduler)
      : userDataReader = UserDataConverter(databaseId);

  static const String _tag = 'FirebaseFirestore';

  final DatabaseId databaseId;
  final FirebaseApp firebaseApp;
  final UserDataConverter userDataReader;
  final FirestoreClient client;
  final AsyncQueue _scheduler;

  static Firestore get instance {
    final FirebaseApp app = FirebaseApp.instance;
    if (app == null) {
      throw StateError('You must call [FirebaseApp.initializeApp] first.');
    }

    final Firestore firestore = FirestoreMultiDbComponent.instances[DatabaseId.defaultDatabaseId];
    if (firestore == null) {
      throw StateError('You must call [Firestore.getInstance] first.');
    }

    if (app == app.authProvider) {
      Log.w(_tag,
          'In case you are using FirebaseAuth make sure to first call [FirebaseAuth.instance] to register the auth provider with other Firebase Services.');
    }

    return firestore;
  }

  @visibleForTesting
  AsyncQueue get scheduler => _scheduler;

  static Future<Firestore> getInstance(
    FirebaseApp app, {
    String database = DatabaseId.defaultDatabaseId,
    OpenDatabase openDatabase,
    FirestoreSettings settings,
  }) async {
    checkNotNull(app, 'Provided FirebaseApp must not be null.');
    Firestore.setLoggingEnabled();

    final FirestoreMultiDbComponent component = FirestoreMultiDbComponent(app, app.authProvider, settings);
    checkNotNull(component, 'Firestore component is not present.');

    final Firestore firestore = await component.get(database, openDatabase);
    return firestore;
  }

  static Future<Firestore> newInstance(
    FirebaseApp app,
    String database, {
    InternalTokenProvider authProvider,
    OpenDatabase openDatabase,
    FirestoreSettings settings,
  }) async {
    final String projectId = app.options.projectId;
    if (projectId == null) {
      throw ArgumentError('FirebaseOptions.getProjectId() cannot be null');
    }
    final DatabaseId databaseId = DatabaseId.forDatabase(projectId, database);

    CredentialsProvider provider;
    if (authProvider != null) {
      provider = FirebaseAuthCredentialsProvider(authProvider);
    } else if (app.authProvider != app) {
      Log.d(_tag, 'Using ${app.authProvider.runtimeType} as the auth provider.');
      provider = FirebaseAuthCredentialsProvider(app.authProvider);
    } else {
      Log.d(_tag, 'Firebase Auth not available, falling back to unauthenticated usage.');
      provider = EmptyCredentialsProvider();
    }

    // Firestore uses a different database for each app name. Note that we
    // don't use app.getPersistenceKey() here because it includes the
    // application ID which is related to the project ID. We already include the
    // project ID when resolving the database, so there is no need to include it
    // in the persistence key.
    final String persistenceKey = app.name;

    settings ??= FirestoreSettings();
    final DatabaseInfo databaseInfo = DatabaseInfo(
      databaseId,
      persistenceKey,
      settings.host,
      sslEnabled: settings.sslEnabled,
    );

    final AsyncQueue scheduler = AsyncQueue(app.name);
    final FirestoreClient firestoreClient = await FirestoreClient.initialize(
      databaseInfo,
      settings,
      provider,
      openDatabase,
      app.onNetworkConnected,
      scheduler,
    );
    final Firestore firestore = Firestore(
      databaseId,
      app,
      firestoreClient,
      scheduler,
    );
    return FirestoreMultiDbComponent.instances[database] = firestore;
  }

  void _ensureClientConfigured() {
    hardAssert(
        client != null,
        'You must call FirebaseApp.initializeApp first. Don\'t try to get a firestore instance using the default '
        'constructor. Use [FirebaseFirestore.instance] for the default instance or [FirebaseFirestore.getInstance(app)]'
        ' for a specific FirebaseApp.');
  }

  /// Gets a [CollectionReference] instance that refers to the collection at the specified path within the database.
  /// [collectionPath] is a slash-separated path to a collection.
  CollectionReference collection(String collectionPath) {
    checkNotNull(collectionPath, 'Provided collection path must not be null.');
    _ensureClientConfigured();
    final ResourcePath resourcePath = ResourcePath.fromString(collectionPath);
    return CollectionReference(resourcePath, this);
  }

  /// Gets a [DocumentReference] instance that refers to the document at the specified path within the database.
  /// [documentPath] is a slash-separated path to a document.
  DocumentReference document(String documentPath) {
    checkNotNull(documentPath, 'Provided document path must not be null.');
    _ensureClientConfigured();
    return DocumentReference.forPath(ResourcePath.fromString(documentPath), this);
  }

  /// Creates and returns a new [Query] that includes all documents in the
  /// database that are contained in a collection or subcollection with the
  /// given [collectionId].
  ///
  /// Every collection or subcollection with this [collectionId] as the last
  /// segment of its path will be included. Cannot contain a slash.
  Query collectionGroup(String collectionId) {
    checkNotNull(collectionId, 'Provided collection ID must not be null.');
    if (collectionId.contains('/')) {
      throw ArgumentError('Invalid collectionId \'$collectionId\'. Collection IDs must not contain \'/\'.');
    }

    _ensureClientConfigured();
    return Query(
      core.Query(
        ResourcePath.empty,
        collectionGroup: collectionId,
      ),
      this,
    );
  }

  /// Executes the given [updateFunction] and then attempts to commit the
  /// changes applied within the transaction. If any document read within the
  /// transaction has changed, the [updateFunction] will be retried. If it fails
  /// to commit after 5 attempts, the transaction will fail.
  ///
  /// The maximum number of writes allowed in a single transaction is 500, but
  /// note that each usage of [FieldValue.serverTimestamp],
  /// [FieldValue.arrayUnion], [FieldValue.arrayRemove], or
  /// [FieldValue.increment] inside a transaction counts as an additional write.
  ///
  /// [updateFunction] the function to execute within the transaction context.
  Future<T> runTransaction<T>(TransactionCallback<T> updateFunction) {
    _ensureClientConfigured();

    // We wrap the function they provide in order to
    // 1. Use internal implementation classes for Transaction,
    // 2. Convert exceptions they throw into Futures, and
    // 3. Run the user callback on the user queue.
    Future<T> wrappedUpdateFunction(core.Transaction internalTransaction) {
      return updateFunction(Transaction(internalTransaction, this));
    }

    return client.transaction(wrappedUpdateFunction, 5);
  }

  /// Creates a write batch, used for performing multiple writes as a single
  /// atomic operation.
  ///
  /// The maximum number of writes allowed in a single batch is 500, but note
  /// that each usage of [FieldValue.serverTimestamp], [FieldValue.arrayUnion],
  /// [FieldValue.arrayRemove], or [FieldValue.increment] inside a transaction
  /// counts as an additional write.
  ///
  /// Returns the created [WriteBatch] object.
  WriteBatch batch() {
    _ensureClientConfigured();
    return WriteBatch(this);
  }

  /// Executes a [batchFunction] on a newly created [WriteBatch] and then
  /// commits all of the writes made by the batchFunction as a single atomic
  /// unit.
  Future<void> runBatch(BatchCallback batchFunction) async {
    final WriteBatch batch = this.batch();
    await batchFunction(batch);
    return batch.commit();
  }

  Future<void> _shutdownInternal() {
    // The client must be initialized to ensure that all subsequent API usage throws an exception.
    _ensureClientConfigured();
    return client.terminate();
  }

  /// Shuts down this [Firestore] instance.
  ///
  /// To restart after shutdown, simply create a new instance of Firestore with
  /// [newInstance] or [getInstance].
  ///
  /// Shutdown does not cancel any pending writes and any tasks that are
  /// awaiting a response from the server will not be resolved. The next time
  /// you start this instance, it will resume attempting to send these writes to
  /// the server.
  ///
  /// Note: Under normal circumstances, calling [shutdown] is not required. This
  /// method is useful only when you want to force this instance to release all
  /// of its resources.
  Future<void> shutdown() async {
    return _shutdownInternal();
  }

  /// Re-enables network usage for this instance after a prior call to [disableNetwork].
  ///
  /// Returns a [Future] that will be completed once networking is enabled.
  Future<void> enableNetwork() {
    _ensureClientConfigured();
    return client.enableNetwork();
  }

  /// Disables network access for this instance. While the network is disabled, any snapshot listeners or get() calls
  /// will return results from cache, and any write operations will be queued until network usage is re-enabled via a
  /// call to [enableNetwork].
  ///
  /// Returns a [Future] that will be completed once networking is disabled.
  Future<void> disableNetwork() {
    _ensureClientConfigured();
    return client.disableNetwork();
  }

  /// Globally enables / disables Firestore logging for the SDK.
  static void setLoggingEnabled({bool loggingEnabled = false}) {
    if (loggingEnabled) {
      Log.level = LogLevel.d;
    } else {
      Log.level = LogLevel.w;
    }
  }

  /// Clears the persistent storage, including pending writes and cached documents.
  ///
  /// <p>Must be called while the FirebaseFirestore instance is not started (after the app is
  /// shutdown or when the app is first initialized). On startup, this method must be called before
  /// other methods (other than <code>setFirestoreSettings()</code>). If the FirebaseFirestore
  /// instance is still running, the <code>Task</code> will fail with an error code of <code>
  /// FAILED_PRECONDITION</code>.
  ///
  /// <p>Note: <code>clearPersistence()</code> is primarily intended to help write reliable tests
  /// that use Cloud Firestore. It uses an efficient mechanism for dropping existing data but does
  /// not attempt to securely overwrite or otherwise make cached data unrecoverable. For applications
  /// that are sensitive to the disclosure of cached data in between user sessions, we strongly
  /// recommend not enabling persistence at all.
  ///
  /// @return A <code>Task</code> that is resolved when the persistent storage is cleared. Otherwise,
  ///     the <code>Task</code> is rejected with an error.
  Future<void> clearPersistence() {
    final Completer<void> completer = Completer<void>();
    _scheduler.enqueueAndForgetEvenAfterShutdown(() async {
      try {
        if (client != null && !client.isTerminated) {
          throw FirestoreError('Persistence cannot be cleared while the firestore instance is running.',
              FirestoreErrorCode.failedPrecondition);
        }
        SQLitePersistence.clearPersistence(databaseId, persistenceKey);
        completer.complete();
      } on FirestoreError catch (e, s) {
        completer.completeError(e, s);
      }
    });
    return completer.future;
  }

  /// Helper to validate a [DocumentReference]. Used by [WriteBatch] and [Transaction].
  void validateReference(DocumentReference docRef) {
    checkNotNull(docRef, 'Provided DocumentReference must not be null.');
    if (docRef.firestore != this) {
      throw ArgumentError('Provided document reference is from a different Cloud Firestore instance.');
    }
  }
}
