// File created by
// Lung Razvan <long1eu>
// on 25/09/2018

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
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
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/listen_source.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/get_options.dart';
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

/// A Cloud Firestore database, and the entry point for every Firestore operation.
///
/// There is one instance per [FirebaseApp] and database. Get it with [instanceFor]; from there, [collection] and
/// [doc] give references to read, write and listen to, [collectionGroup] queries every collection with a given id,
/// and [batch] and [runTransaction] group writes atomically.
///
/// The instance keeps a local cache. It is in memory unless you pass an `openDatabase` function to [instanceFor]
/// (SQLite on the VM, SQLite in WebAssembly on the web; see the offline persistence guide). Reads and listeners work
/// offline from that cache, and writes made offline are applied to the cache at once and sent when the client is
/// back online.
///
/// On the Dart VM the instance holds network connections and timers, so a command line program does not exit while
/// it is alive: [terminate] it when you are done.
///
/// ```dart
/// final FirebaseApp app = FirebaseApp.withOptions(
///   const FirebaseOptions(
///     apiKey: 'my-api-key',
///     appId: '1:1234567890:web:0123456789abcdef',
///     projectId: 'my-project',
///   ),
/// );
/// final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(app: app);
///
/// await firestore.doc('cities/SF').set({'name': 'San Francisco'});
/// final DocumentSnapshot<Map<String, Object?>> sf = await firestore
///     .doc('cities/SF')
///     .get();
/// print(sf.data());
///
/// await firestore.terminate();
/// ```
///
/// **Subclassing Note**: Firestore classes are not meant to be subclassed except for use in test mocks. Subclassing is
/// not supported in production code and new SDK releases may break code that does so.
class FirebaseFirestore {
  /// Implementation detail of the SDK; not part of the supported API. Use [instanceFor].
  FirebaseFirestore._(
    this._databaseId,
    this._app,
    FirestoreClient? client,
    this._scheduler, {
    Settings? settings,
  }) : _clientOrNull = client,
       _settings = settings ?? Settings(),
       _dataConverter = UserDataConverter(_databaseId);

  /// The settings this instance was created with.
  final Settings _settings;

  static const String _tag = 'FirebaseFirestore';

  final DatabaseId _databaseId;

  /// The id of the Google Cloud project this instance talks to, from the `projectId` of the app's options.
  String get projectId => _databaseId.projectId;

  /// The id of the database inside the project: `(default)` unless another
  /// one was passed to [instanceFor]. The same name as FlutterFire's
  /// `FirebaseFirestore.databaseId` and the `database` argument of
  /// [instanceFor].
  String get databaseId => _databaseId.databaseId;

  final FirebaseApp? _app;

  /// The [FirebaseApp] this instance belongs to.
  FirebaseApp get app =>
      _app ?? (throw StateError('This FirebaseFirestore instance has no app.'));

  /// The settings this instance was created with (the defaults of [Settings] when [instanceFor] got none), for
  /// example to check whether its cache is persistent ([Settings.persistenceEnabled], [Settings.cacheSettings]).
  ///
  /// There is no setter: give the settings to [instanceFor].
  Settings get settings => _settings;

  final UserDataConverter _dataConverter;

  /// Null only for an instance made by `FirestoreInternal.detached` (unit tests of code that needs a [FirebaseFirestore]
  /// but never talks to a backend).
  final FirestoreClient? _clientOrNull;
  final TaskScheduler _scheduler;

  /// The instance of the default [FirebaseApp] and the default database.
  ///
  /// Like FlutterFire, it creates the instance on first use, with the default [Settings] and a memory cache, when
  /// [instanceFor] has not created it yet. Call [instanceFor] first to give it settings or a persistent cache.
  /// Throws the error of [FirebaseApp.instance] if there is no default app.
  ///
  /// ```dart
  /// await Firebase.initializeApp(options: options);
  /// // Later, anywhere in the program:
  /// final FirebaseFirestore firestore = FirebaseFirestore.instance;
  /// ```
  static FirebaseFirestore get instance {
    return instanceFor(app: FirebaseApp.instance);
  }

  /// Gets the instance for [app] and [databaseId], creating it on the first call. Later calls return the same instance
  /// until it is terminated.
  ///
  /// [databaseId] is the id of the database in the project, `(default)` unless you use a named database.
  ///
  /// [settings] are those of the call that creates the instance (the defaults of [Settings] when null). A
  /// later call without settings, or with equal settings, returns the existing instance; a later call with different
  /// settings throws a [StateError], as the other SDKs do (`initializeFirestore` called twice with different options
  /// in the JS SDK, settings changed after the start on Android): [terminate] the instance first to get one with
  /// other settings.
  ///
  /// [openDatabase] opens the SQLite database of the persistent cache. Without it the cache is in memory, whatever
  /// the settings say, and is lost when the instance is terminated. It only applies to the call that creates the
  /// instance.
  ///
  /// Returns at once, as the other SDKs do: the instance opens its cache and connects in the background, and every
  /// operation waits for that. If opening fails (for example [openDatabase] throws), the operations of the instance
  /// fail with that error. Throws an [ArgumentError] if the options of [app] have no `projectId`.
  ///
  /// The requests are authenticated with the token provider registered on [app] (for example by
  /// `firebase_auth_providers_dart`), and are sent without a user otherwise.
  ///
  /// ```dart
  /// // The default database, a memory cache, the production backend.
  /// final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(app: app);
  ///
  /// // A named database, against the emulator.
  /// final FirebaseFirestore other = FirebaseFirestore.instanceFor(
  ///   app: app,
  ///   databaseId: 'my-database',
  ///   settings: Settings().withEmulator('127.0.0.1', 8080),
  /// );
  /// ```
  static FirebaseFirestore instanceFor({
    required FirebaseApp app,
    String databaseId = DatabaseId.defaultDatabaseId,
    OpenDatabase? openDatabase,
    Settings? settings,
  }) {
    final FirestoreMultiDbComponent component = FirestoreMultiDbComponent(
      app,
      app.authProvider,
      settings,
      appCheckProvider: app.appCheckProvider,
    );
    return component.get(databaseId, openDatabase);
  }

  /// Implementation detail of the SDK; not part of the supported API. Use [instanceFor].
  static FirebaseFirestore _newInstance(
    FirebaseApp app,
    String database, {
    AuthTokenProvider? authProvider,
    AppCheckTokenProvider? appCheckProvider,
    OpenDatabase? openDatabase,
    Settings? settings,
    Future<void>? after,
  }) {
    final String? projectId = app.options.projectId;
    if (projectId == null) {
      throw ArgumentError(
        'FirebaseOptions.projectId must be set to use Firestore',
      );
    }
    final DatabaseId databaseId = DatabaseId.forDatabase(projectId, database);

    final Settings firestoreSettings = settings ?? Settings();

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
    final AppCheckTokenProvider? appCheckSource =
        appCheckProvider ?? app.appCheckProvider;
    final FirebaseAppCheckTokenProvider? appCheck = appCheckSource == null
        ? null
        : FirebaseAppCheckTokenProvider(appCheckSource);

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
      forceLongPolling: firestoreSettings.webExperimentalForceLongPolling,
      autoDetectLongPolling:
          firestoreSettings.webExperimentalAutoDetectLongPolling,
      longPollingOptions: firestoreSettings.webExperimentalLongPollingOptions,
      grpcFlowControlWindow: firestoreSettings.grpcFlowControlWindow,
      apiKey: app.options.apiKey,
      appId: app.options.appId,
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
    final FirebaseFirestore firestore = FirebaseFirestore._(
      databaseId,
      app,
      firestoreClient,
      scheduler,
      settings: firestoreSettings,
    );
    FirestoreMultiDbComponent.register(app, database, firestore);
    return firestore;
  }

  /// Returns a [CollectionReference] to the collection at [collectionPath].
  ///
  /// [collectionPath] is a slash-separated path from the root of the database with an odd number of segments, such
  /// as `cities` or `cities/SF/landmarks`. Throws an [ArgumentError] if it is empty or names a document (an even
  /// number of segments).
  ///
  /// Creating a reference does not contact the backend, and the collection does not need to exist. The reference
  /// reads and writes `Map<String, Object?>` values; use [CollectionReference.withConverter] for your own type.
  ///
  /// ```dart
  /// final CollectionReference<Map<String, Object?>> cities = firestore
  ///     .collection('cities');
  /// final QuerySnapshot<Map<String, Object?>> all = await cities.get();
  /// print(all.length);
  /// ```
  CollectionReference<Map<String, Object?>> collection(String collectionPath) {
    checkNotNull(collectionPath, 'Provided collection path must not be null.');
    checkNonEmptyPath('Firestore.collection', collectionPath);
    final ResourcePath resourcePath = ResourcePath.fromString(collectionPath);
    return CollectionReferenceInternal.create<Map<String, Object?>>(
      resourcePath,
      this,
    );
  }

  /// Returns a [DocumentReference] to the document at [documentPath].
  ///
  /// [documentPath] is a slash-separated path from the root of the database with an even number of segments, such
  /// as `cities/SF` or `cities/SF/landmarks/bridge`. Throws an [ArgumentError] if it is empty or names a collection
  /// (an odd number of segments).
  ///
  /// Creating a reference does not contact the backend, and the document does not need to exist.
  ///
  /// ```dart
  /// final DocumentReference<Map<String, Object?>> sf = firestore.doc(
  ///   'cities/SF',
  /// );
  /// await sf.set({'name': 'San Francisco', 'population': 870000});
  /// ```
  DocumentReference<Map<String, Object?>> doc(String documentPath) {
    checkNotNull(documentPath, 'Provided document path must not be null.');
    checkNonEmptyPath('Firestore.doc', documentPath);
    return DocumentReferenceInternal.forPath(
      ResourcePath.fromString(documentPath),
      this,
    );
  }

  /// Returns a [Query] over the documents of every collection or subcollection in the database whose id is
  /// [collectionId].
  ///
  /// Every collection whose path ends with [collectionId] is included, at any depth. Throws an [ArgumentError] if
  /// [collectionId] is empty or contains a slash. Filters and orderings on a collection group query may need a
  /// collection group index on the backend; the backend answers with an error that links to its creation.
  ///
  /// ```dart
  /// // Every landmark of every city.
  /// final QuerySnapshot<Map<String, Object?>> landmarks = await firestore
  ///     .collectionGroup('landmarks')
  ///     .where('type', isEqualTo: 'museum')
  ///     .get();
  /// for (final QueryDocumentSnapshot<Map<String, Object?>> doc in landmarks) {
  ///   print(doc.reference.path);
  /// }
  /// ```
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

  /// Runs [updateFunction] in a transaction and commits its writes atomically; completes with the value it returns.
  ///
  /// Transactions are optimistic: [Transaction.get] reads the current version of a document from the backend, and
  /// the commit fails if a document that was read changed in the meantime. Then [updateFunction] runs again, up to
  /// [maxAttempts] times (5 by default), after which the returned future fails with the last
  /// error. So [updateFunction] can run more than once: it must not have side effects of its own, and it must do
  /// all its reads before its writes. If [updateFunction] throws, nothing is committed and the future fails with
  /// that error.
  ///
  /// The reads of a transaction go to the backend, never to the cache, so a transaction fails when the backend
  /// cannot be reached. Writes made with [Transaction] are only sent at the commit and are not visible locally
  /// before.
  ///
  /// [maxAttempts] must be at least 1. With [readOnly] it is a read-only transaction, which reads a consistent snapshot of the database and can also run
  /// queries with [Transaction.getQuery] and aggregations with [Transaction.getAggregate]. The JS and Android client
  /// SDKs have no read-only transactions.
  ///
  /// A commit whose answer is lost on the network can be applied twice, as in the other SDKs: make transactions
  /// that must not run twice idempotent.
  ///
  /// There is no limit on the number of writes in a transaction, but its
  /// commit request must not exceed the maximum API request size of 10 MiB,
  /// and a single document takes at most 500 field transforms (such as
  /// [FieldValue.serverTimestamp] or [FieldValue.increment]).
  ///
  /// ```dart
  /// final DocumentReference<Map<String, Object?>> sf = firestore.doc(
  ///   'cities/SF',
  /// );
  /// final int newPopulation = await firestore.runTransaction((
  ///   Transaction transaction,
  /// ) async {
  ///   final DocumentSnapshot<Map<String, Object?>> snapshot = await transaction
  ///       .get(sf);
  ///   final int population = snapshot.get('population') as int? ?? 0;
  ///   transaction.update(sf, {'population': population + 1});
  ///   return population + 1;
  /// });
  /// print(newPopulation);
  /// ```
  Future<T> runTransaction<T>(
    TransactionHandler<T> updateFunction, {
    int maxAttempts = 5,
    bool readOnly = false,
    Timestamp? readTime,
  }) {
    final TransactionOptions options = TransactionOptions(
      maxAttempts: maxAttempts,
      readOnly: readOnly,
      readTime: readTime,
    );
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

  /// Returns a new [WriteBatch], which applies several writes as a single atomic operation.
  ///
  /// Add writes with [WriteBatch.set], [WriteBatch.update] and [WriteBatch.delete], then call [WriteBatch.commit]:
  /// either all the writes are applied or none. Unlike a transaction a batch reads nothing, so it also works offline:
  /// the writes are applied to the local cache at the commit and sent when the client is online, and the future of
  /// [WriteBatch.commit] completes when the backend has acknowledged them.
  ///
  /// There is no limit on the number of writes in a batch, but its commit
  /// request must not exceed the maximum API request size of 10 MiB, and a
  /// single document takes at most 500 field transforms (such as
  /// [FieldValue.serverTimestamp] or [FieldValue.increment]).
  ///
  /// ```dart
  /// final WriteBatch batch = firestore.batch();
  /// batch.set(firestore.doc('cities/NYC'), {'name': 'New York City'});
  /// batch.update(firestore.doc('cities/SF'), {'population': 1000000});
  /// batch.delete(firestore.doc('cities/LA'));
  /// await batch.commit();
  /// ```
  WriteBatch batch() {
    return WriteBatchInternal.create(this);
  }

  /// Runs [batchFunction] on a new [WriteBatch] and then commits the writes it added as a single atomic unit.
  ///
  /// The returned future completes when the commit completes (see [batch]). If [batchFunction] throws, nothing is
  /// committed and the future fails with that error.
  ///
  /// ```dart
  /// await firestore.runBatch((WriteBatch batch) async {
  ///   batch.set(firestore.doc('cities/NYC'), {'name': 'New York City'});
  ///   batch.delete(firestore.doc('cities/LA'));
  /// });
  /// ```
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
  ///
  /// Call it before [terminate] when the writes matter and the cache is in memory: writes that the backend has not
  /// acknowledged are lost with a memory cache.
  ///
  /// ```dart
  /// await firestore.waitForPendingWrites();
  /// await firestore.terminate();
  /// ```
  Future<void> waitForPendingWrites() {
    return client.waitForPendingWrites();
  }

  /// A stream that emits whenever all the snapshot listeners of this instance are in sync with each other, which
  /// means every listener received the snapshot that reflects the same state of the local cache and of the backend.
  ///
  /// It emits once when it is listened to, and then once after each round of snapshots (it emits once for several
  /// snapshots that are raised together, also when none of the queries changed but only their metadata). It does not
  /// emit for changes that no snapshot listener is interested in.
  ///
  /// This is the JS SDK `onSnapshotsInSync()`. On a terminated instance the stream fails with the [FirestoreException]
  /// of a terminated instance and closes.
  ///
  /// ```dart
  /// final StreamSubscription<void> subscription = firestore.snapshotsInSync()
  ///     .listen((_) => print('every listener is up to date'));
  /// // ...
  /// await subscription.cancel();
  /// ```
  Stream<void> snapshotsInSync() {
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

  /// Terminates this [FirebaseFirestore] instance, releasing all the resources it holds.
  ///
  /// After this the instance cannot be used anymore: to start again, create a new instance with [instanceFor].
  /// Listeners stop receiving events, and the connections and the local cache are closed.
  ///
  /// Every operation on a terminated instance fails with a [FirestoreException] with the code
  /// [FirestoreErrorCode.failedPrecondition], delivered through the returned future or stream. Calling [terminate]
  /// again does nothing.
  ///
  /// Termination does not cancel pending writes, but a write whose future has not completed when the instance is
  /// terminated never completes (it neither succeeds nor fails). With a persistent cache the write stays in the cache
  /// and the next instance on that cache sends it; with a memory cache it is lost. Call [waitForPendingWrites] first
  /// when the writes matter. A transaction, an aggregation or a server read that is in flight fails.
  ///
  /// On the Dart VM a program does not exit while an instance is alive (it holds connections and timers), so a
  /// command line program or a test terminates its instances when it is done. In a long-running app you rarely need
  /// it, except to change the settings of an instance or to call [clearPersistence].
  ///
  /// ```dart
  /// await firestore.waitForPendingWrites();
  /// await firestore.terminate();
  /// // FirebaseFirestore.instanceFor(app: app) now creates a new instance.
  /// ```
  Future<void> terminate() async {
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
  /// fails with a [FirestoreException] with code
  /// [FirestoreErrorCode.failedPrecondition]. Create a new instance with the
  /// same app and database to start again with an empty cache.
  ///
  /// Note: [clearPersistence] is primarily intended to help write reliable
  /// tests that use Cloud Firestore. It uses an efficient mechanism for
  /// dropping existing data but does not attempt to securely overwrite or
  /// otherwise make cached data unrecoverable. For applications that are
  /// sensitive to the disclosure of cached data in between user sessions, we
  /// strongly recommend not enabling persistence at all.
  ///
  /// It also fails with [FirestoreErrorCode.failedPrecondition] when a newer instance of the same app and database
  /// is already running on that cache.
  ///
  /// ```dart
  /// await firestore.terminate();
  /// await firestore.clearPersistence();
  /// ```
  Future<void> clearPersistence() async {
    final FirebaseApp? app = _app;
    if (client.isTerminated &&
        app != null &&
        FirestoreMultiDbComponent.hasInstance(app.name, databaseId)) {
      // This instance was terminated and a newer one has the same cache open: deleting the files under it would
      // detach it from its cache without any error.
      throw FirestoreException(
        message:
            'Persistence cannot be cleared while another firestore instance of the same app and database is running.',
        errorCode: FirestoreErrorCode.failedPrecondition,
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
  /// [FirestoreException] as every other operation, whatever the cache.
  @Deprecated(
    'Instead of creating cache indexes manually, consider using '
    'persistentCacheIndexManager.enableIndexAutoCreation() to let the SDK '
    'decide whether to create cache indexes for queries running locally.',
  )
  Future<void> setIndexConfigurationFromJSON(String json) async {
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
  /// fail with the [FirestoreException] of a terminated instance.
  ///
  /// ```dart
  /// await firestore.persistentCacheIndexManager?.enableIndexAutoCreation();
  /// ```
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
  /// Returns a [Future] that will be completed once networking is enabled. Listeners then catch up with the backend
  /// and the queued writes are sent.
  Future<void> enableNetwork() {
    return client.enableNetwork();
  }

  /// Disables network access for this instance. While the network is disabled, any snapshot listeners or get() calls
  /// will return results from cache, and any write operations will be queued until network usage is re-enabled via a
  /// call to [enableNetwork].
  ///
  /// Returns a [Future] that will be completed once networking is disabled.
  ///
  /// While the network is disabled, a [DocumentReference.get] of a document that is not in the cache fails with
  /// [FirestoreErrorCode.unavailable], the futures of writes do not complete, and transactions and aggregations
  /// fail.
  ///
  /// ```dart
  /// await firestore.disableNetwork();
  /// // Answered from the cache; the write is sent later.
  /// final DocumentSnapshot<Map<String, Object?>> cached = await firestore
  ///     .doc('cities/SF')
  ///     .get();
  /// print(cached.metadata.isFromCache); // true
  /// unawaited(firestore.doc('cities/SF').update({'visited': true}));
  /// await firestore.enableNetwork();
  /// ```
  Future<void> disableNetwork() {
    return client.disableNetwork();
  }

  /// Loads a Firestore bundle into the local cache.
  ///
  /// [bundleData] holds the whole bundle. Returns a [LoadBundleTask], which notifies callers with progress updates, and
  /// completion or error events. To load a bundle held in a string, pass `utf8.encode(bundle)`; for a file or an
  /// HTTP response that arrives in chunks use [loadBundleStream].
  ///
  /// The named queries of the bundle become available through [namedQuery].
  ///
  /// ```dart
  /// final LoadBundleTaskSnapshot progress = await firestore
  ///     .loadBundle(bundleBytes)
  ///     .future;
  /// print('${progress.documentsLoaded} documents loaded');
  /// ```
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
  ///
  /// ```dart
  /// await firestore.loadBundle(bundleBytes).future;
  /// final Query<Map<String, Object?>>? latest = await firestore.namedQuery(
  ///   'latest-stories',
  /// );
  /// if (latest != null) {
  ///   final QuerySnapshot<Map<String, Object?>> stories = await latest.get(
  ///     const GetOptions(source: Source.cache),
  ///   );
  ///   print(stories.size);
  /// }
  /// ```
  Future<Query<Map<String, Object?>>?> namedQuery(String name) async {
    final core.Query? query = await client.getNamedQuery(name);
    return query == null ? null : QueryInternal.create(query, this);
  }

  /// Runs the named query [name] of a loaded bundle (see [namedQuery]) and returns its results: FlutterFire's
  /// `namedQueryGet`.
  ///
  /// The future fails with a [FirestoreException] with [FirestoreErrorCode.notFound] when the cache has no query
  /// with this name.
  ///
  /// ```dart
  /// final QuerySnapshot<Map<String, Object?>> stories = await firestore
  ///     .namedQueryGet(
  ///       'latest-stories',
  ///       options: const GetOptions(source: Source.cache),
  ///     );
  /// ```
  Future<QuerySnapshot<Map<String, Object?>>> namedQueryGet(
    String name, {
    GetOptions options = const GetOptions(),
  }) async {
    final Query<Map<String, Object?>>? query = await namedQuery(name);
    if (query == null) {
      throw FirestoreException(
        errorCode: FirestoreErrorCode.notFound,
        message: 'Named query "$name" not found.',
      );
    }
    return query.get(options);
  }

  /// Listens to the document of a [DocumentSnapshot.toJson] result, starting from that snapshot.
  ///
  /// The document in [json] is loaded into the local cache (as with [loadBundle]) and the document is then listened
  /// to with [options], so the first event can be raised from the cache. Pass the [converter] of the original
  /// reference to get typed snapshots. Throws a [FirestoreException] if [json] is not a document snapshot JSON object;
  /// errors loading the bundle are delivered on the stream.
  ///
  /// This is the JS SDK `onSnapshotResume()` for a `DocumentSnapshot`.
  Stream<DocumentSnapshot<T>> documentSnapshotsFromJson<T>(
    Map<String, Object?> json, {
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
    FirestoreDataConverter<T>? converter,
  }) {
    return snapshot_json.documentSnapshotsFromJson<T>(
      this,
      json,
      includeMetadataChanges: includeMetadataChanges,
      source: source,
      converter: converter,
    );
  }

  /// Listens to the query of a [QuerySnapshot.toJson] result, resuming from that snapshot.
  ///
  /// The query and documents in [json] are loaded into the local cache (as with [loadBundle]) and the query is then
  /// listened to with [options]. The listen is resumed from the read time of the snapshot, so the backend only sends
  /// what changed since then. Pass the [converter] of the original query to get typed snapshots. Throws a
  /// [FirestoreException] if [json] is not a query snapshot JSON object; errors loading the bundle are delivered on the
  /// stream.
  ///
  /// This is the JS SDK `onSnapshotResume()` for a `QuerySnapshot`.
  ///
  /// ```dart
  /// // `json` was written by QuerySnapshot.toJson, for example on a server.
  /// firestore.querySnapshotsFromJson<Map<String, Object?>>(json).listen((
  ///   QuerySnapshot<Map<String, Object?>> snapshot,
  /// ) {
  ///   print(snapshot.length);
  /// });
  /// ```
  Stream<QuerySnapshot<T>> querySnapshotsFromJson<T>(
    Map<String, Object?> json, {
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
    FirestoreDataConverter<T>? converter,
  }) {
    return snapshot_json.querySnapshotsFromJson<T>(
      this,
      json,
      includeMetadataChanges: includeMetadataChanges,
      source: source,
      converter: converter,
    );
  }

  /// Globally enables / disables Firestore logging for the SDK.
  ///
  /// Enabled is [LogLevel.debug]; disabled goes back to the default,
  /// [LogLevel.warn] (warnings and errors). [setLogLevel] gives finer
  /// control.
  static void setLoggingEnabled(bool enabled) {
    applyLoggingEnabled(enabled);
  }

  /// Sets the verbosity of the Cloud Firestore logs: from [LogLevel.verbose]
  /// (everything) and [LogLevel.debug] through [LogLevel.warn] (the default)
  /// to [LogLevel.error] (errors only) and [LogLevel.silent] (nothing). The
  /// levels of `setLogLevel` of the JS SDK, without `info`.
  ///
  /// The setting is global: it applies to every instance (and to the logs of
  /// the other Firebase packages of this SDK, which share the logger).
  ///
  /// ```dart
  /// FirebaseFirestore.setLogLevel(LogLevel.debug);
  /// ```
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

/// Members of [FirebaseFirestore] for the SDK itself. Not exported by the public libraries.
extension FirestoreInternal on FirebaseFirestore {
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
  static FirebaseFirestore create(
    DatabaseId databaseId,
    FirebaseApp? app,
    FirestoreClient client,
    TaskScheduler scheduler,
  ) => FirebaseFirestore._(databaseId, app, client, scheduler);

  /// An instance for [databaseId] without a client: references, queries and snapshots can be built for it, every
  /// operation that needs the backend or the cache throws. For unit tests.
  static FirebaseFirestore detached(DatabaseId databaseId) =>
      FirebaseFirestore._(databaseId, null, null, TaskScheduler('detached'));

  /// Creates a new instance for [app] and [database] and registers it as the instance of that app and database. Use
  /// `FirebaseFirestore.instanceFor`. The instance initializes in the background, after [after] (the shutdown of an instance
  /// that has the same persistence open) completed; [initialized] completes when it is ready.
  static FirebaseFirestore newInstance(
    FirebaseApp app,
    String database, {
    AuthTokenProvider? authProvider,
    AppCheckTokenProvider? appCheckProvider,
    OpenDatabase? openDatabase,
    Settings? settings,
    Future<void>? after,
  }) => FirebaseFirestore._newInstance(
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
