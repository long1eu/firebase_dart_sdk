// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/app_check_token_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/empty_credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/emulator_credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/firebase_auth_credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/database_info.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart'
    as core;
import 'package:cloud_firestore_dart/src/firebase/firestore/core/transaction.dart'
    as core;
import 'package:cloud_firestore_dart/src/firebase/firestore/core/transaction_runner.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/lite/document_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/lite/lite_transaction_client.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/lite/lite_transport.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/lite/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/lite/settings.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/lite/transaction.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/lite/write_batch.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/log_level.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/channel_options_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/datastore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/firestore_transport.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/transaction_options.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/user_data_converter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/exponential_backoff.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/log_level_util.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_app_dart/internal.dart';
import 'package:meta/meta.dart';

/// Replaces the transport of the platform for every Firestore Lite instance
/// that makes its first call afterwards, so that tests can run over another
/// transport or record the calls.
@visibleForTesting
FirestoreTransport Function(
  DatabaseInfo databaseInfo,
  ChannelOptionsProvider options,
)?
liteTransportOverride;

/// The entry point of Firestore Lite: a Cloud Firestore client without a local
/// cache and without listeners. Every call is one request to the backend and
/// one response.
///
/// **Experimental**: this API may change in any release.
///
/// ```dart
/// final Firestore firestore = Firestore.instanceFor(app: app);
/// final DocumentSnapshot<Map<String, Object?>> city =
///     await firestore.doc('cities/SF').get();
/// ```
class Firestore {
  Firestore._(this.app, this.modelDatabaseId, this.settings)
    : dataConverter = UserDataConverter(modelDatabaseId);

  /// Returns the instance of [app] for [database], creating it at the first
  /// call. Nothing is sent or opened until the instance is used.
  ///
  /// [settings] apply when the instance is created. Asking again for the same
  /// instance with different settings throws a [StateError]: [terminate] the
  /// instance first to get one with other settings.
  factory Firestore.instanceFor({
    required FirebaseApp app,
    String database = DatabaseId.defaultDatabaseId,
    FirestoreSettings? settings,
  }) {
    final String? projectId = app.options.projectId;
    if (projectId == null) {
      throw ArgumentError('FirebaseOptions.getProjectId() cannot be null');
    }
    final String key = _keyFor(app.name, database);
    final Firestore? existing = _instances[key];
    if (existing != null && identical(existing.app, app)) {
      if (settings != null && settings != existing.settings) {
        throw StateError(
          'Firestore.instanceFor() has already been called with different '
          'settings for this app and database. Call it without settings to '
          'get the existing instance, or terminate() that instance first.',
        );
      }
      return existing;
    }
    // An instance of another FirebaseApp object with the same name: that app
    // was deleted (names are unique among live apps) and its delete event,
    // which is delivered asynchronously, has not terminated the instance yet.
    existing?._terminateQuietly();

    final Firestore firestore = Firestore._(
      app,
      DatabaseId.forDatabase(projectId, database),
      settings ?? FirestoreSettings(),
    );
    _instances[key] = firestore;
    firestore._deleteSubscription = app.onDeleteApp.listen(
      (_) => firestore._terminateQuietly(),
    );
    return firestore;
  }

  static const String _tag = 'FirestoreLite';

  /// The message of the error for a call on a terminated instance.
  static const String _terminatedMessage =
      'The client has already been terminated.';

  static final Map<String, Firestore> _instances = <String, Firestore>{};

  static String _keyFor(String appName, String database) =>
      '$appName/$database';

  /// The instance of the default [FirebaseApp] for its default database.
  // ignore: prefer_constructors_over_static_methods
  static Firestore get instance =>
      Firestore.instanceFor(app: FirebaseApp.instance);

  /// Sets the verbosity of the Cloud Firestore logs (shared with the main
  /// library).
  static void setLogLevel(LogLevel level) => applyLogLevel(level);

  /// The app this instance belongs to.
  final FirebaseApp app;

  /// The settings this instance was created with.
  final FirestoreSettings settings;

  /// Implementation detail of the SDK; not part of the supported API.
  @internal
  final DatabaseId modelDatabaseId;

  /// Implementation detail of the SDK; not part of the supported API.
  @internal
  final UserDataConverter dataConverter;

  /// The ID of the project of this instance.
  String get projectId => modelDatabaseId.projectId;

  /// The id of the database of this instance (`(default)` for the default
  /// database), as FlutterFire's `FirebaseFirestore.databaseId`.
  String get databaseId => modelDatabaseId.databaseId;

  StreamSubscription<String>? _deleteSubscription;
  Datastore? _datastore;
  CredentialsProvider? _credentials;
  AppCheckTokenProvider? _appCheck;
  bool _terminated = false;
  Future<void>? _termination;

  /// The calls in flight. [terminate] lets them finish.
  int _inFlight = 0;
  Completer<void>? _idle;

  /// Gets a [CollectionReference] that refers to the collection at
  /// [collectionPath].
  CollectionReference<Map<String, Object?>> collection(String collectionPath) {
    return CollectionReference<Map<String, Object?>>.forPath(
      ResourcePath.fromString(collectionPath),
      this,
    );
  }

  /// Gets a [DocumentReference] that refers to the document at
  /// [documentPath].
  DocumentReference<Map<String, Object?>> doc(String documentPath) {
    return DocumentReference<Map<String, Object?>>.forPath(
      ResourcePath.fromString(documentPath),
      this,
    );
  }

  /// Creates a [Query] that includes all the documents in the database that
  /// are in a collection or subcollection with the given [collectionId].
  Query<Map<String, Object?>> collectionGroup(String collectionId) {
    if (collectionId.isEmpty) {
      throw ArgumentError(
        'Invalid collectionId. Collection IDs must not be empty.',
      );
    }
    if (collectionId.contains('/')) {
      throw ArgumentError(
        'Invalid collectionId \'$collectionId\'. Collection IDs must not contain \'/\'.',
      );
    }
    return Query<Map<String, Object?>>(
      core.Query(ResourcePath.empty, collectionGroup: collectionId),
      this,
    );
  }

  /// Creates a write batch, used for performing multiple writes as a single
  /// atomic operation.
  WriteBatch batch() => WriteBatch(this);

  /// Executes [updateFunction] and then attempts to commit the changes applied
  /// within the transaction. If any document read within the transaction has
  /// changed, [updateFunction] is run again, up to
  /// [TransactionOptions.maxAttempts] times.
  ///
  /// The transaction must read (with [Transaction.get]) before it writes.
  ///
  /// With `TransactionOptions(readOnly: true)` it is a read-only transaction
  /// of the backend: all its reads, also of queries ([Transaction.getQuery])
  /// and aggregations ([Transaction.getAggregate]), see the database at one
  /// point in time.
  ///
  /// If this instance is [terminate]d while the transaction runs, its next
  /// read or its commit fails with [FirestoreErrorCode.failedPrecondition]
  /// and it is not retried.
  Future<T> runTransaction<T>(
    Future<T> Function(Transaction transaction) updateFunction, {
    TransactionOptions options = TransactionOptions.defaultOptions,
  }) async {
    _checkNotTerminated();
    // Every request of the transaction is a call of its own (as in the JS
    // SDK): a transaction does not hold off terminate().
    final LiteTransactionClient client = LiteTransactionClient(this);
    return TransactionRunner<T>(
      createTransaction: () => core.Transaction(
        client,
        readOnly: options.readOnly,
        readTime: options.readTime == null
            ? null
            : SnapshotVersion(options.readTime!),
      ),
      maxAttempts: options.maxAttempts,
      // A scheduler of its own: a [TaskScheduler] holds only one pending
      // task per [TaskId], and transactions run concurrently.
      backoff: ExponentialBackoff(
        TaskScheduler('transaction'),
        TaskId.retryTransaction,
      ),
      updateFunction: (core.Transaction transaction) =>
          updateFunction(Transaction(transaction, this)),
      isTerminated: () => _terminated,
    ).run();
  }

  /// Terminates this instance: every later call on it, and on the references
  /// and queries made from it, fails with
  /// [FirestoreErrorCode.failedPrecondition]. The requests on the wire are not
  /// interrupted: the returned future completes when they are done and the
  /// connection is closed. A transaction in progress is not waited for: its
  /// next read or its commit fails (see [runTransaction]).
  ///
  /// [Firestore.instanceFor] returns a new instance afterwards. Calling this again does
  /// nothing.
  Future<void> terminate() {
    return _termination ??= _terminate();
  }

  Future<void> _terminate() async {
    _terminated = true;
    final String key = _keyFor(app.name, databaseId);
    if (identical(_instances[key], this)) {
      _instances.remove(key);
    }
    await _deleteSubscription?.cancel();
    _deleteSubscription = null;
    if (_inFlight > 0) {
      await (_idle ??= Completer<void>()).future;
    }
    await _datastore?.shutdown();
    await _appCheck?.close();
    // The provider of Firebase Auth stops following the token changes of the
    // app when its last listener leaves.
    await _credentials?.onChange.listen(null).cancel();
  }

  void _terminateQuietly() {
    // Nobody awaits this: report a failure instead of raising an unhandled
    // error.
    terminate().catchError((Object e) {
      Log.w(_tag, 'Terminating the instance failed: $e');
    });
  }

  /// Implementation detail of the SDK; not part of the supported API.
  ///
  /// Runs [operation] against the backend, unless this instance is terminated.
  @internal
  Future<R> run<R>(Future<R> Function(Datastore datastore) operation) async {
    _checkNotTerminated();
    final Datastore datastore = _datastore ??= _createDatastore();
    _inFlight++;
    try {
      return await operation(datastore);
    } finally {
      _inFlight--;
      if (_inFlight == 0) {
        _idle?.complete();
        _idle = null;
      }
    }
  }

  void _checkNotTerminated() {
    if (_terminated) {
      throw FirestoreError(
        _terminatedMessage,
        FirestoreErrorCode.failedPrecondition,
      );
    }
  }

  Datastore _createDatastore() {
    final CredentialsProvider credentials;
    final Object? mockUserToken = settings.mockUserToken;
    if (mockUserToken != null) {
      Log.d(_tag, 'Using the mockUserToken of the emulator settings.');
      credentials = EmulatorCredentialsProvider.forMockUserToken(
        mockUserToken,
        projectId,
      );
    } else if (app.authProvider != app) {
      Log.d(
        _tag,
        'Using ${app.authProvider.runtimeType} as the auth provider.',
      );
      credentials = FirebaseAuthCredentialsProvider(app.authProvider);
    } else {
      Log.d(
        _tag,
        'Firebase Auth not available, falling back to unauthenticated usage.',
      );
      credentials = EmptyCredentialsProvider();
    }

    // No provider on the app: no App Check header at all.
    final InternalAppCheckTokenProvider? appCheckSource = app.appCheckProvider;
    final AppCheckTokenProvider? appCheck = appCheckSource == null
        ? null
        : AppCheckTokenProvider(appCheckSource);
    _credentials = credentials;
    _appCheck = appCheck;

    return newUnaryDatastore(
      TaskScheduler(app.name),
      DatabaseInfo(
        modelDatabaseId,
        app.name,
        settings.host,
        port: settings.port,
        sslEnabled: settings.sslEnabled,
        grpcFlowControlWindow: settings.grpcFlowControlWindow,
      ),
      credentials,
      liteTransportOverride ?? createLiteTransport,
      appCheckProvider: appCheck,
    );
  }

  /// Implementation detail of the SDK; not part of the supported API.
  @internal
  void validateReference(DocumentReference<Object?> docRef) {
    if (!identical(docRef.firestore, this)) {
      throw ArgumentError(
        'Provided document reference is from a different Cloud Firestore instance.',
      );
    }
  }

  @override
  String toString() => 'Firestore{app: ${app.name}, database: $databaseId}';
}
