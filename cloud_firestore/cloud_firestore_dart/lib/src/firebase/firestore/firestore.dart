// File created by
// Lung Razvan <long1eu>
// on 25/09/2018

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
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
import 'package:cloud_firestore_dart/src/firebase/firestore/index/index_configuration.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/load_bundle_task.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/log_level.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/persistent_cache_index_manager.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/connectivity_monitor.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/transaction.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/transaction_options.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/user_data_converter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/database.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/log_level_util.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart'
    show checkNonEmptyPath;
import 'package:cloud_firestore_dart/src/firebase/firestore/write_batch.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_app_dart/internal.dart';

/// Represents a Firestore Database and is the entry point for all Firestore operations
///
/// **Subclassing Note**: Firestore classes are not meant to be subclassed except for use in test mocks. Subclassing is
/// not supported in production code and new SDK releases may break code that does so.
class Firestore {
  /// Implementation detail of the SDK; not part of the supported API. Use [instanceFor].
  Firestore._(
    this._databaseId,
    this.firebaseApp,
    FirestoreClient? client,
    this._scheduler,
  ) : _clientOrNull = client,
      _dataConverter = UserDataConverter(_databaseId);

  static const String _tag = 'FirebaseFirestore';

  final DatabaseId _databaseId;

  /// The id of the Google Cloud project this instance talks to.
  String get projectId => _databaseId.projectId;

  /// The id of the database inside the project: `(default)` unless another
  /// one was passed to [instanceFor]. The same name as FlutterFire's
  /// `FirebaseFirestore.databaseId` and the `database` argument of
  /// [instanceFor].
  String get databaseId => _databaseId.databaseId;

  /// The [FirebaseApp] this instance belongs to.
  final FirebaseApp? firebaseApp;

  /// The app this instance belongs to: the same as [firebaseApp], under the
  /// name the JS SDK, FlutterFire and Firestore Lite use.
  FirebaseApp? get app => firebaseApp;

  final UserDataConverter _dataConverter;

  /// Null only for an instance made by `FirestoreInternal.detached` (unit tests of code that needs a [Firestore]
  /// but never talks to a backend).
  final FirestoreClient? _clientOrNull;
  final TaskScheduler _scheduler;

  /// The instance of the default [FirebaseApp] and the default database.
  ///
  /// Throws a [StateError] if that instance has not been created with [instanceFor] yet.
  static Firestore get instance {
    final FirebaseApp app = FirebaseApp.instance;

    final Firestore? firestore =
        FirestoreMultiDbComponent.instances[FirestoreMultiDbComponent.keyFor(
          app.name,
          DatabaseId.defaultDatabaseId,
        )];
    if (firestore == null) {
      throw StateError(
        'Firestore.instance has no default instance yet: call '
        'Firestore.instanceFor(app: FirebaseApp.instance) first.',
      );
    }

    if (app == app.authProvider) {
      Log.w(
        _tag,
        'In case you are using FirebaseAuth make sure to first call [FirebaseAuth.instance] to register the auth provider with other Firebase Services.',
      );
    }

    return firestore;
  }

  /// Gets the instance for [app] and [database], creating it on the first call. Later calls return the same instance
  /// until it is terminated ([openDatabase] and [settings] only apply to the call that creates it).
  ///
  /// Returns at once, as the other SDKs do: the instance opens its cache and connects in the background, and every
  /// operation waits for that. If opening fails (for example [openDatabase] throws), the operations of the instance
  /// fail with that error.
  static Firestore instanceFor({
    required FirebaseApp app,
    String database = DatabaseId.defaultDatabaseId,
    OpenDatabase? openDatabase,
    FirestoreSettings? settings,
  }) {
    return getInstance(
      app,
      database: database,
      openDatabase: openDatabase,
      settings: settings,
    );
  }

  /// Gets the instance for [app] and [database], creating it on the first call. Same as [instanceFor].
  @Deprecated('Use instanceFor instead.')
  static Firestore getInstance(
    FirebaseApp app, {
    String database = DatabaseId.defaultDatabaseId,
    OpenDatabase? openDatabase,
    FirestoreSettings? settings,
  }) {
    checkNotNull(app, 'Provided FirebaseApp must not be null.');

    final FirestoreMultiDbComponent component = FirestoreMultiDbComponent(
      app,
      app.authProvider,
      settings,
      appCheckProvider: app.appCheckProvider,
    );
    checkNotNull(component, 'Firestore component is not present.');

    return component.get(database, openDatabase);
  }

  /// Implementation detail of the SDK; not part of the supported API. Use [instanceFor].
  static Firestore _newInstance(
    FirebaseApp app,
    String database, {
    InternalTokenProvider? authProvider,
    InternalAppCheckTokenProvider? appCheckProvider,
    OpenDatabase? openDatabase,
    FirestoreSettings? settings,
    Future<void>? after,
  }) {
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
        mockUserToken,
        projectId,
      );
    } else if (authProvider != null && authProvider != app) {
      provider = FirebaseAuthCredentialsProvider(authProvider);
    } else if (app.authProvider != app) {
      Log.d(
        _tag,
        'Using ${app.authProvider.runtimeType} as the auth provider.',
      );
      provider = FirebaseAuthCredentialsProvider(app.authProvider);
    } else {
      Log.d(
        _tag,
        'Firebase Auth not available, falling back to unauthenticated usage.',
      );
      provider = EmptyCredentialsProvider();
    }

    // No provider on the call and none on the app: no App Check header at all.
    final InternalAppCheckTokenProvider? appCheckSource =
        appCheckProvider ?? app.appCheckProvider;
    final AppCheckTokenProvider? appCheck = appCheckSource == null
        ? null
        : AppCheckTokenProvider(appCheckSource);

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
      forceLongPolling: firestoreSettings.experimentalForceLongPolling,
      autoDetectLongPolling:
          firestoreSettings.experimentalAutoDetectLongPolling,
      grpcFlowControlWindow: firestoreSettings.grpcFlowControlWindow,
      apiKey: app.options.apiKey,
      appId: app.options.applicationId,
    );

    final TaskScheduler scheduler = TaskScheduler(app.name);
    final FirestoreClient firestoreClient = FirestoreClient.start(
      databaseInfo,
      firestoreSettings,
      provider,
      openDatabase,
      withPlatformConnectivity(app.onNetworkConnected),
      scheduler,
      appCheckProvider: appCheck,
      connectivityDetector: createConnectivityChangeDetector(),
      after: after,
    );
    final Firestore firestore = Firestore._(
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
    checkNonEmptyPath('Firestore.collection', collectionPath);
    final ResourcePath resourcePath = ResourcePath.fromString(collectionPath);
    return CollectionReferenceInternal.create<Map<String, Object?>>(
      resourcePath,
      this,
    );
  }

  /// Gets a [DocumentReference] instance that refers to the document at the specified path within the database.
  /// [documentPath] is a slash-separated path to a document.
  DocumentReference<Map<String, Object?>> doc(String documentPath) =>
      document(documentPath);

  /// Gets a [DocumentReference] instance that refers to the document at the specified path within the database.
  /// [documentPath] is a slash-separated path to a document.
  @Deprecated('Use doc instead.')
  DocumentReference<Map<String, Object?>> document(String documentPath) {
    checkNotNull(documentPath, 'Provided document path must not be null.');
    checkNonEmptyPath('Firestore.doc', documentPath);
    return DocumentReferenceInternal.forPath(
      ResourcePath.fromString(documentPath),
      this,
    );
  }

  /// Creates and returns a new [Query] that includes all documents in the
  /// database that are contained in a collection or subcollection with the
  /// given [collectionId].
  ///
  /// Every collection or subcollection with this [collectionId] as the last
  /// segment of its path will be included. Cannot contain a slash.
  Query<Map<String, Object?>> collectionGroup(String collectionId) {
    checkNotNull(collectionId, 'Provided collection ID must not be null.');
    if (collectionId.isEmpty) {
      throw ArgumentError(
        'Function Firestore.collectionGroup() cannot be called with an empty '
        'collectionId.',
      );
    }
    if (collectionId.contains('/')) {
      throw ArgumentError(
        "Invalid collection ID '$collectionId' passed to function "
        "Firestore.collectionGroup(). Collection IDs must not contain '/'.",
      );
    }

    return QueryInternal.create(
      core.Query(ResourcePath.empty, collectionGroup: collectionId),
      this,
    );
  }

  /// Executes the given [updateFunction] and then attempts to commit the
  /// changes applied within the transaction. If any document read within the
  /// transaction has changed, the [updateFunction] will be retried. If it fails
  /// to commit after 5 attempts, the transaction will fail.
  ///
  /// There is no limit on the number of writes in a transaction, but its
  /// commit request must not exceed the maximum API request size of 10 MiB,
  /// and a single document takes at most 500 field transforms (such as
  /// [FieldValue.serverTimestamp] or [FieldValue.increment]).
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
      return updateFunction(
        TransactionInternal.create(internalTransaction, this),
      );
    }

    return client.transaction(
      wrappedUpdateFunction,
      options.maxAttempts,
      readOnly: options.readOnly,
      readTime: options.readTime == null
          ? null
          : SnapshotVersion(options.readTime!),
    );
  }

  /// Creates a write batch, used for performing multiple writes as a single
  /// atomic operation.
  ///
  /// There is no limit on the number of writes in a batch, but its commit
  /// request must not exceed the maximum API request size of 10 MiB, and a
  /// single document takes at most 500 field transforms (such as
  /// [FieldValue.serverTimestamp] or [FieldValue.increment]).
  ///
  /// Returns the created [WriteBatch] object.
  WriteBatch batch() {
    return WriteBatchInternal.create(this);
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
      // A terminated instance fails the listen: report it on the stream.
      onListen: () => client.addSnapshotsInSyncListener(listener).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        if (!controller.isClosed) {
          controller
            ..addError(error, stackTrace)
            ..close();
        }
      }),
      onCancel: () => client.removeSnapshotsInSyncListener(listener),
    );
    return controller.stream;
  }

  /// Terminates this [Firestore] instance, releasing all the resources it holds.
  ///
  /// After this the instance cannot be used anymore: to start again, create a new instance with [instanceFor].
  ///
  /// Termination does not cancel any pending writes and any tasks that are awaiting a response from the server will
  /// not be resolved. The next time you start an instance, it will resume attempting to send these writes to the
  /// server.
  ///
  /// Every operation on a terminated instance fails with a [FirestoreError] with the code
  /// [FirestoreErrorCode.failedPrecondition], delivered through the returned future or stream. Calling [terminate]
  /// again does nothing.
  ///
  /// Note: Under normal circumstances, calling [terminate] is not required. This method is useful only when you want
  /// to force this instance to release all of its resources.
  Future<void> terminate() => shutdown();

  /// Shuts down this [Firestore] instance.
  ///
  /// To restart after shutdown, simply create a new instance of Firestore with
  /// [instanceFor].
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
    // Forget the instance first (as Android and JS do), so that a caller that asks for an instance while this one
    // shuts down gets a new one rather than this one.
    FirestoreMultiDbComponent.deregister(this);
    await client.shutdown();
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
  Future<void> clearPersistence() async {
    final FirebaseApp? app = firebaseApp;
    if (client.isTerminated &&
        app != null &&
        FirestoreMultiDbComponent.hasInstance(app.name, databaseId)) {
      // This instance was terminated and a newer one has the same cache open: deleting the files under it would
      // detach it from its cache without any error.
      throw FirestoreError(
        'Persistence cannot be cleared while another firestore instance of the same app and database is running.',
        FirestoreErrorCode.failedPrecondition,
      );
    }
    await client.clearPersistence();
  }

  /// Configures the persistent cache indexes of this instance from an index definition in the JSON format of the
  /// Firebase CLI (`firestore.indexes.json`, see
  /// https://firebase.google.com/docs/reference/firestore/indexes/#json_format). The `queryScope` of an index and
  /// the `fieldOverrides` are ignored. The indexes replace the ones that were configured before; an index that is
  /// configured again keeps its entries.
  ///
  /// The index entries are written in the background while the app runs. A query against the local cache uses an
  /// index as far as it is filled, and the result of a query is the same with or without an index.
  ///
  /// The future fails with an [ArgumentError] when [json] is not a valid index definition and with a [StateError] when
  /// this instance does not use the persistent (SQLite) cache. On a terminated instance it fails with the same
  /// [FirestoreError] as every other operation, whatever the cache.
  @Deprecated(
    'Instead of creating cache indexes manually, consider using '
    'persistentCacheIndexManager.enableIndexAutoCreation() to let the SDK '
    'decide whether to create cache indexes for queries running locally.',
  )
  Future<void> setIndexConfiguration(String json) async {
    client.verifyNotTerminated();
    if (!client.supportsFieldIndexes) {
      throw StateError('Cannot enable indexes when persistence is disabled');
    }
    return client.configureFieldIndexes(parseIndexConfiguration(json));
  }

  /// The [PersistentCacheIndexManager] of this instance, or null when it does not use the persistent (SQLite) cache.
  ///
  /// Persistent cache indexes are optional indexes that only exist within the SDK to assist in local query execution;
  /// they are not the same as Cloud Firestore indexes.
  ///
  /// The getter never throws and keeps returning the same manager after [terminate]; the methods of that manager then
  /// fail with the [FirestoreError] of a terminated instance.
  PersistentCacheIndexManager? get persistentCacheIndexManager {
    if (!client.supportsFieldIndexes) {
      return null;
    }
    return _persistentCacheIndexManager ??=
        PersistentCacheIndexManagerInternal.create(client);
  }

  PersistentCacheIndexManager? _persistentCacheIndexManager;

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
      Stream<List<int>>.fromIterable(<List<int>>[bundleData]),
    );
  }

  /// Loads a Firestore bundle into the local cache.
  ///
  /// [bundleData] is a stream of the bundle bytes, delivered in chunks of any size (for example a file or an HTTP
  /// response). Returns a [LoadBundleTask], which notifies callers with progress updates, and completion or error
  /// events.
  LoadBundleTask loadBundleStream(Stream<List<int>> bundleData) {
    final LoadBundleTask resultTask = LoadBundleTaskInternal.create();
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
    return query == null ? null : QueryInternal.create(query, this);
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
      this,
      json,
      options,
      converter,
    );
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
      this,
      json,
      options,
      converter,
    );
  }

  /// Globally enables / disables Firestore logging for the SDK.
  ///
  /// Enabled is [LogLevel.debug]; disabled goes back to the default,
  /// [LogLevel.warn] (warnings and errors). [setLogLevel] gives finer
  /// control.
  static void setLoggingEnabled({bool loggingEnabled = false}) {
    applyLoggingEnabled(loggingEnabled);
  }

  /// Sets the verbosity of the Cloud Firestore logs: from [LogLevel.verbose]
  /// (everything) and [LogLevel.debug] through [LogLevel.warn] (the default)
  /// to [LogLevel.error] (errors only) and [LogLevel.silent] (nothing). The
  /// levels of `setLogLevel` of the JS SDK.
  ///
  /// The setting is global: it applies to every instance (and to the logs of
  /// the other Firebase packages of this SDK, which share the logger).
  static void setLogLevel(LogLevel level) {
    applyLogLevel(level);
  }

  /// Helper to validate a [DocumentReference]. Used by [WriteBatch] and [Transaction].
  void _validateReference(DocumentReference<Object?> docRef) {
    checkNotNull(docRef, 'Provided DocumentReference must not be null.');
    if (docRef.firestore != this) {
      throw ArgumentError(
        'Provided document reference is from a different Cloud Firestore instance.',
      );
    }
  }
}

/// Members of [Firestore] for the SDK itself. Not exported by the public libraries.
extension FirestoreInternal on Firestore {
  /// The project and database this instance talks to.
  DatabaseId get modelDatabaseId => _databaseId;

  /// Converts user data to model values for this database.
  UserDataConverter get dataConverter => _dataConverter;

  /// The client that runs the operations of this instance.
  FirestoreClient get client =>
      _clientOrNull ??
      (throw StateError('This Firestore instance has no client.'));

  /// The scheduler of the timers of this instance.
  TaskScheduler get scheduler => _scheduler;

  /// Throws an [ArgumentError] unless [docRef] belongs to this instance. Used by `WriteBatch` and `Transaction`.
  void validateReference(DocumentReference<Object?> docRef) =>
      _validateReference(docRef);

  /// An instance over an existing [client].
  static Firestore create(
    DatabaseId databaseId,
    FirebaseApp? firebaseApp,
    FirestoreClient client,
    TaskScheduler scheduler,
  ) => Firestore._(databaseId, firebaseApp, client, scheduler);

  /// An instance for [databaseId] without a client: references, queries and snapshots can be built for it, every
  /// operation that needs the backend or the cache throws. For unit tests.
  static Firestore detached(DatabaseId databaseId) =>
      Firestore._(databaseId, null, null, TaskScheduler('detached'));

  /// Creates a new instance for [app] and [database] and registers it as the instance of that app and database. Use
  /// `Firestore.instanceFor`. The instance initializes in the background, after [after] (the shutdown of an instance
  /// that has the same persistence open) completed; [initialized] completes when it is ready.
  static Firestore newInstance(
    FirebaseApp app,
    String database, {
    InternalTokenProvider? authProvider,
    InternalAppCheckTokenProvider? appCheckProvider,
    OpenDatabase? openDatabase,
    FirestoreSettings? settings,
    Future<void>? after,
  }) => Firestore._newInstance(
    app,
    database,
    authProvider: authProvider,
    appCheckProvider: appCheckProvider,
    openDatabase: openDatabase,
    settings: settings,
    after: after,
  );

  /// Completes when the client of this instance is initialized; fails with the error of the initialization.
  Future<void> get initialized => client.initialized;
}
