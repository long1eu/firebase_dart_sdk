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
import 'package:cloud_firestore_vm/src/firebase/firestore/core/transaction.dart'
    as core;
import 'package:cloud_firestore_vm/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore_multi_db_component.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore_settings.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/transaction.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/user_data_converter.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/async_queue.dart';
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
  Firestore(this.databaseId, this._asyncQueue, this.firebaseApp, this.client)
      : dataConverter = UserDataConverter(databaseId);

  static const String _tag = 'FirebaseFirestore';

  final AsyncQueue _asyncQueue;

  final DatabaseId databaseId;
  final FirebaseApp firebaseApp;
  final UserDataConverter dataConverter;
  final FirestoreClient client;

  static Firestore get instance {
    final FirebaseApp app = FirebaseApp.instance;
    if (app == null) {
      throw StateError('You must call FirebaseApp.initializeApp first.');
    }
    return FirestoreMultiDbComponent.instances[DatabaseId.defaultDatabaseId];
  }

  static Future<Firestore> getInstance(
    FirebaseApp app, {
    String database = DatabaseId.defaultDatabaseId,
    OpenDatabase openDatabase,
    FirestoreSettings settings,
  }) async {
    checkNotNull(app, 'Provided FirebaseApp must not be null.');

    final FirestoreMultiDbComponent component =
        FirestoreMultiDbComponent(app, app.authProvider, settings);
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

    final AsyncQueue queue = AsyncQueue();

    CredentialsProvider provider;
    if (authProvider == null) {
      Log.d(_tag,
          'Firebase Auth not available, falling back to unauthenticated usage.');
      provider = EmptyCredentialsProvider();
    } else {
      provider = FirebaseAuthCredentialsProvider(authProvider);
    }

    // Firestore uses a different database for each app name. Note that we don't use app.getPersistenceKey() here
    // because it includes the application ID which is related to the project ID. We already include the project ID when
    // resolving the database, so there is no need to include it in the persistence key.
    final String persistenceKey = app.name;

    settings ??= FirestoreSettings();
    final DatabaseInfo databaseInfo = DatabaseInfo(
      databaseId,
      persistenceKey,
      settings.host,
      sslEnabled: settings.sslEnabled,
    );

    return Firestore(
      databaseId,
      queue,
      app,
      await FirestoreClient.initialize(
        databaseInfo,
        settings,
        provider,
        queue,
        openDatabase,
      ),
    );
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
    return DocumentReference.forPath(
        ResourcePath.fromString(documentPath), this);
  }

  /// Executes the given [updateFunction] and then attempts to commit the changes applied within the transaction. If any
  /// document read within the transaction has changed, the [updateFunction] will be retried. If it fails to commit
  /// after 5 attempts, the transaction will fail.
  ///
  /// [updateFunction] the function to execute within the transaction context.
  Future<TResult> runTransaction<TResult>(
      TransactionCallback<TResult> updateFunction) {
    _ensureClientConfigured();

    // We wrap the function they provide in order to
    // 1. Use internal implementation classes for Transaction,
    // 2. Convert exceptions they throw into Futures, and
    // 3. Run the user callback on the user queue.
    Future<TResult> wrappedUpdateFunction(
        core.Transaction internalTransaction) {
      return updateFunction(Transaction(internalTransaction, this));
    }

    return client.transaction(wrappedUpdateFunction, 5);
  }

  /// Creates a write batch, used for performing multiple writes as a single atomic operation.
  ///
  /// Returns the created [WriteBatch] object.
  WriteBatch batch() {
    _ensureClientConfigured();
    return WriteBatch(this);
  }

  @visibleForTesting
  Future<void> shutdown() async {
    if (client != null) {
      await client.shutdown();
    }
  }

  @visibleForTesting
  AsyncQueue getAsyncQueue() => _asyncQueue;

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

  /// Helper to validate a [DocumentReference]. Used by [WriteBatch] and [Transaction].
  void validateReference(DocumentReference docRef) {
    checkNotNull(docRef, 'Provided DocumentReference must not be null.');
    if (docRef.firestore != this) {
      throw ArgumentError(
          'Provided document reference is from a different Firestore instance.');
    }
  }
}
