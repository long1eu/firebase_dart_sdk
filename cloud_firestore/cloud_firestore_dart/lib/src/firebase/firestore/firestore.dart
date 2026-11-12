// File created by
// Lung Razvan <long1eu>
// on 25/09/2018

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/snapshot_listen_options.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_data_converter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/snapshot_json.dart'
    as snapshot_json;
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/app_check_token_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/empty_credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/emulator_credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/firebase_auth_credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/collection_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/database_info.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/firestore_client.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart'
    as core;
import 'package:cloud_firestore_dart/src/firebase/firestore/core/transaction.dart'
    as core;
import 'package:cloud_firestore_dart/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_multi_db_component.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_settings.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/load_bundle_task.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/log_level.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/transaction.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/transaction_options.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/user_data_converter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/database.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/log_level_util.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/write_batch.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_app_dart/internal.dart';
import 'package:meta/meta.dart';

/// Represents a Firestore Database and is the entry point for all Firestore operations
///
/// **Subclassing Note**: Firestore classes are not meant to be subclassed except for use in test mocks. Subclassing is
/// not supported in production code and new SDK releases may break code that does so.
class Firestore {
  @visibleForTesting
  @internal
  Firestore(this.databaseId, this.firebaseApp, this.client, this._scheduler)
      : dataConverter = UserDataConverter(databaseId);

  static const String _tag = 'FirebaseFirestore';

  @internal
  final DatabaseId databaseId;

  /// The id of the Google Cloud project this instance talks to.
  String get projectId => databaseId.projectId;

  /// The name of the database inside the project, `(default)` unless another
  /// one was passed to [instanceFor].
  String get databaseName => databaseId.databaseId;

  final FirebaseApp? firebaseApp;
  @internal
  final UserDataConverter dataConverter;
  @internal
  final FirestoreClient client;
  final TaskScheduler _scheduler;

  static Firestore get instance {
    final FirebaseApp app = FirebaseApp.instance;

    final Firestore? firestore =
        FirestoreMultiDbComponent.instances[FirestoreMultiDbComponent.keyFor(
            app.name, DatabaseId.defaultDatabaseId)];
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
  @internal
  TaskScheduler get scheduler => _scheduler;

  /// Gets the instance for [app] and [database]. Same as [getInstance]; this is
  /// the name used by the current official Firestore API.
  static Future<Firestore> instanceFor({
    required FirebaseApp app,
    String database = DatabaseId.defaultDatabaseId,
    OpenDatabase? openDatabase,
    FirestoreSettings? settings,
  }) {
    return getInstance(app,
        database: database, openDatabase: openDatabase, settings: settings);
  }

  @Deprecated('Use instanceFor instead.')
  static Future<Firestore> getInstance(
    FirebaseApp app, {
    String database = DatabaseId.defaultDatabaseId,
    OpenDatabase? openDatabase,
    FirestoreSettings? settings,
  }) async {
    checkNotNull(app, 'Provided FirebaseApp must not be null.');

    final FirestoreMultiDbComponent component = FirestoreMultiDbComponent(
        app, app.authProvider, settings,
        appCheckProvider: app.appCheckProvider);
    checkNotNull(component, 'Firestore component is not present.');

    final Firestore firestore = await component.get(database, openDatabase);
    return firestore;
  }

  @internal
  static Future<Firestore> newInstance(
    FirebaseApp app,
    String database, {
    InternalTokenProvider? authProvider,
    InternalAppCheckTokenProvider? appCheckProvider,
    OpenDatabase? openDatabase,
    FirestoreSettings? settings,
  }) async {
    final String? projectId = app.options.projectId;
    if (projectId == null) {
      throw ArgumentError('FirebaseOptions.getProjectId() cannot be null');
    }
    final DatabaseId databaseId = DatabaseId.forDatabase(projectId, database);

    final FirestoreSettings firestoreSettings = settings ?? FirestoreSettings();

    final CredentialsProvider provider;
    final Object? mockUserToken = firestoreSettings.mockUserToken;
    if (mockUserToken != null) {
      Log.d(_tag, 'Using the mockUserToken of the emulator settings.');
      provider = EmulatorCredentialsProvider.forMockUserToken(
          mockUserToken, projectId);
    } else if (authProvider != null && authProvider != app) {
      provider = FirebaseAuthCredentialsProvider(authProvider);
    } else if (app.authProvider != app) {
      Log.d(
          _tag, 'Using ${app.authProvider.runtimeType} as the auth provider.');
      provider = FirebaseAuthCredentialsProvider(app.authProvider);
    } else {
      Log.d(_tag,
          'Firebase Auth not available, falling back to unauthenticated usage.');
      provider = EmptyCredentialsProvider();
    }

    // No provider on the call and none on the app: no App Check header at all.
    final InternalAppCheckTokenProvider? appCheckSource =
        appCheckProvider ?? app.appCheckProvider;
    final AppCheckTokenProvider? appCheck =
        appCheckSource == null ? null : AppCheckTokenProvider(appCheckSource);

    // Firestore uses a different database for each app name. Note that we
    // don't use app.getPersistenceKey() here because it includes the
    // application ID which is related to the project ID. We already include the
    // project ID when resolving the database, so there is no need to include it
    // in the persistence key.
    final String persistenceKey = app.name;

    final DatabaseInfo databaseInfo = DatabaseInfo(
      databaseId,
      persistenceKey,
      firestoreSettings.host,
      port: firestoreSettings.port,
      sslEnabled: firestoreSettings.sslEnabled,
    );

    final TaskScheduler scheduler = TaskScheduler(app.name);
    final FirestoreClient firestoreClient = await FirestoreClient.initialize(
      databaseInfo,
      firestoreSettings,
      provider,
      openDatabase,
      app.onNetworkConnected,
      scheduler,
      appCheckProvider: appCheck,
    );
    final Firestore firestore = Firestore(
      databaseId,
      app,
      firestoreClient,
      scheduler,
    );
    FirestoreMultiDbComponent.register(app, database, firestore);
    return firestore;
  }

  /// Gets a [CollectionReference] instance that refers to the collection at the specified path within the database.
  /// [collectionPath] is a slash-separated path to a collection.
  CollectionReference<Map<String, Object?>> collection(String collectionPath) {
    checkNotNull(collectionPath, 'Provided collection path must not be null.');
    final ResourcePath resourcePath = ResourcePath.fromString(collectionPath);
    return CollectionReference<Map<String, Object?>>(resourcePath, this);
  }

  /// Gets a [DocumentReference] instance that refers to the document at the specified path within the database.
  /// [documentPath] is a slash-separated path to a document.
  DocumentReference<Map<String, Object?>> doc(String documentPath) => document(documentPath);

  /// Gets a [DocumentReference] instance that refers to the document at the specified path within the database.
  /// [documentPath] is a slash-separated path to a document.
  @Deprecated('Use doc instead.')
  DocumentReference<Map<String, Object?>> document(String documentPath) {
    checkNotNull(documentPath, 'Provided document path must not be null.');
    return DocumentReference.forPath(
        ResourcePath.fromString(documentPath), this);
  }

  /// Creates and returns a new [Query] that includes all documents in the
  /// database that are contained in a collection or subcollection with the
  /// given [collectionId].
  ///
  /// Every collection or subcollection with this [collectionId] as the last
  /// segment of its path will be included. Cannot contain a slash.
  Query<Map<String, Object?>> collectionGroup(String collectionId) {
    checkNotNull(collectionId, 'Provided collection ID must not be null.');
    if (collectionId.contains('/')) {
      throw ArgumentError(
          'Invalid collectionId \'$collectionId\'. Collection IDs must not contain \'/\'.');
    }

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
  /// [options] customizes the execution, for example the maximum number of
  /// attempts (5 by default) after which the transaction fails, or whether it
  /// is read-only.
  Future<T> runTransaction<T>(
    TransactionCallback<T> updateFunction, {
    TransactionOptions options = TransactionOptions.defaultOptions,
  }) {
    // We wrap the function they provide in order to
    // 1. Use internal implementation classes for Transaction,
    // 2. Convert exceptions they throw into Futures, and
    // 3. Run the user callback on the user queue.
    Future<T> wrappedUpdateFunction(core.Transaction internalTransaction) {
      return updateFunction(Transaction(internalTransaction, this));
    }

    return client.transaction(wrappedUpdateFunction, options.maxAttempts,
        readOnly: options.readOnly);
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

  /// Returns a future that completes when all the writes that are pending at the time of the call were acknowledged
  /// (or rejected) by the backend. Writes that are made later are not waited for.
  ///
  /// If the user changes while waiting, the future fails with [FirestoreErrorCode.cancelled].
  ///
  /// The future does not complete while the network is disabled and writes are pending.
  Future<void> waitForPendingWrites() {
    return client.waitForPendingWrites();
  }

  /// A stream that emits whenever all the snapshot listeners of this instance are in sync with each other, which
  /// means every listener received the snapshot that reflects the same state of the local cache and of the backend.
  ///
  /// It emits once when it is listened to, and then once after each round of snapshots (it emits once for several
  /// snapshots that are raised together, also when none of the queries changed but only their metadata). It does not
  /// emit for changes that no snapshot listener is interested in.
  Stream<void> get snapshotsInSync {
    late final StreamController<void> controller;
    void listener() {
      if (!controller.isClosed) {
        controller.add(null);
      }
    }

    controller = StreamController<void>(
      onListen: () => client.addSnapshotsInSyncListener(listener),
      onCancel: () => client.removeSnapshotsInSyncListener(listener),
    );
    return controller.stream;
  }

  /// Terminates this [Firestore] instance, releasing all the resources it holds.
  ///
  /// After this the instance cannot be used anymore: to start again, create a new instance with [newInstance] or
  /// [getInstance].
  ///
  /// Termination does not cancel any pending writes and any tasks that are awaiting a response from the server will
  /// not be resolved. The next time you start an instance, it will resume attempting to send these writes to the
  /// server.
  ///
  /// Note: Under normal circumstances, calling [terminate] is not required. This method is useful only when you want
  /// to force this instance to release all of its resources.
  Future<void> terminate() => shutdown();

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
  @Deprecated('Use terminate instead.')
  Future<void> shutdown() async {
    // The client must be initialized to ensure that all subsequent API usage
    // throws an exception.
    try {
      await client.shutdown();
    } finally {
      FirestoreMultiDbComponent.deregister(this);
    }
  }

  /// Clears the persistent storage of this instance: the local SQLite database
  /// with the cached documents and the pending writes. Does nothing when the
  /// instance uses memory persistence.
  ///
  /// Must be called after [terminate] (an instance of this SDK starts as soon
  /// as it is created). While the instance is running the returned future
  /// fails with a [FirestoreError] with code
  /// [FirestoreErrorCode.failedPrecondition]. Create a new instance with the
  /// same app and database to start again with an empty cache.
  ///
  /// Note: [clearPersistence] is primarily intended to help write reliable
  /// tests that use Cloud Firestore. It uses an efficient mechanism for
  /// dropping existing data but does not attempt to securely overwrite or
  /// otherwise make cached data unrecoverable. For applications that are
  /// sensitive to the disclosure of cached data in between user sessions, we
  /// strongly recommend not enabling persistence at all.
  Future<void> clearPersistence() => client.clearPersistence();

  /// Re-enables network usage for this instance after a prior call to [disableNetwork].
  ///
  /// Returns a [Future] that will be completed once networking is enabled.
  Future<void> enableNetwork() {
    return client.enableNetwork();
  }

  /// Disables network access for this instance. While the network is disabled, any snapshot listeners or get() calls
  /// will return results from cache, and any write operations will be queued until network usage is re-enabled via a
  /// call to [enableNetwork].
  ///
  /// Returns a [Future] that will be completed once networking is disabled.
  Future<void> disableNetwork() {
    return client.disableNetwork();
  }

  /// Loads a Firestore bundle into the local cache.
  ///
  /// [bundleData] holds the whole bundle. Returns a [LoadBundleTask], which notifies callers with progress updates, and
  /// completion or error events.
  LoadBundleTask loadBundle(List<int> bundleData) {
    return loadBundleStream(
        Stream<List<int>>.fromIterable(<List<int>>[bundleData]));
  }

  /// Loads a Firestore bundle into the local cache.
  ///
  /// [bundleData] is a stream of the bundle bytes, delivered in chunks of any size (for example a file or an HTTP
  /// response). Returns a [LoadBundleTask], which notifies callers with progress updates, and completion or error
  /// events.
  LoadBundleTask loadBundleStream(Stream<List<int>> bundleData) {
    final LoadBundleTask resultTask = LoadBundleTask();
    client.loadBundle(bundleData, resultTask).catchError((Object error) {
      if (!resultTask.isComplete) {
        resultTask.setException(error);
      }
    });
    return resultTask;
  }

  /// Reads a Firestore [Query] from local cache, identified by the given [name].
  ///
  /// The named queries are packaged into bundles on the server side (along with resulting documents) and loaded to
  /// local cache using [loadBundle]. Once in local cache, you can use this method to extract a query by name. Returns
  /// null if there is no query with this name.
  Future<Query<Map<String, Object?>>?> getNamedQuery(String name) async {
    final core.Query? query = await client.getNamedQuery(name);
    return query == null ? null : Query(query, this);
  }

  /// Listens to the document of a [DocumentSnapshot.toJson] result, starting from that snapshot.
  ///
  /// The document in [json] is loaded into the local cache (as with [loadBundle]) and the document is then listened
  /// to with [options], so the first event can be raised from the cache. Pass the [converter] of the original
  /// reference to get typed snapshots. Throws a [FirestoreError] if [json] is not a document snapshot JSON object;
  /// errors loading the bundle are delivered on the stream.
  ///
  /// This is the JS SDK `onSnapshotResume()` for a `DocumentSnapshot`.
  Stream<DocumentSnapshot<T>> documentSnapshotsFromJson<T>(
    Map<String, Object?> json, {
    SnapshotListenOptions options = const SnapshotListenOptions(),
    FirestoreDataConverter<T>? converter,
  }) {
    return snapshot_json.documentSnapshotsFromJson<T>(
        this, json, options, converter);
  }

  /// Listens to the query of a [QuerySnapshot.toJson] result, resuming from that snapshot.
  ///
  /// The query and documents in [json] are loaded into the local cache (as with [loadBundle]) and the query is then
  /// listened to with [options]. The listen is resumed from the read time of the snapshot, so the backend only sends
  /// what changed since then. Pass the [converter] of the original query to get typed snapshots. Throws a
  /// [FirestoreError] if [json] is not a query snapshot JSON object; errors loading the bundle are delivered on the
  /// stream.
  ///
  /// This is the JS SDK `onSnapshotResume()` for a `QuerySnapshot`.
  Stream<QuerySnapshot<T>> querySnapshotsFromJson<T>(
    Map<String, Object?> json, {
    SnapshotListenOptions options = const SnapshotListenOptions(),
    FirestoreDataConverter<T>? converter,
  }) {
    return snapshot_json.querySnapshotsFromJson<T>(
        this, json, options, converter);
  }

  /// Globally enables / disables Firestore logging for the SDK.
  ///
  /// Enabled logs everything ([LogLevel.debug]); disabled goes back to the
  /// default, which logs warnings and errors. [setLogLevel] gives finer
  /// control.
  static void setLoggingEnabled({bool loggingEnabled = false}) {
    applyLoggingEnabled(loggingEnabled);
  }

  /// Sets the verbosity of the Cloud Firestore logs: [LogLevel.debug] for the
  /// most verbose logging, [LogLevel.error] to log errors only, or
  /// [LogLevel.silent] to turn logging off. Like `setLogLevel` of the JS SDK.
  ///
  /// The setting is global: it applies to every instance (and to the logs of
  /// the other Firebase packages of this SDK, which share the logger).
  static void setLogLevel(LogLevel level) {
    applyLogLevel(level);
  }

  /// Helper to validate a [DocumentReference]. Used by [WriteBatch] and [Transaction].
  @internal
  void validateReference(DocumentReference<Object?> docRef) {
    checkNotNull(docRef, 'Provided DocumentReference must not be null.');
    if (docRef.firestore != this) {
      throw ArgumentError(
          'Provided document reference is from a different Cloud Firestore instance.');
    }
  }
}
