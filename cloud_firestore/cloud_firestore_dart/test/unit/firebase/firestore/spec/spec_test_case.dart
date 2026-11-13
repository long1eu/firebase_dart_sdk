// File created by
// Lung Razvan <long1eu>
// on 04/10/2018

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_reader.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/document_view_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/event_manager.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/online_state.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query_stream.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/serial_queue.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/sync_engine.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/view_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/decimal128_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/listen_source.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/load_bundle_task.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/index/index_configuration.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/lru_delegate.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_purpose.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/shared_client_state.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/shared_client_state_storage.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/client_metadata_refresher.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/field_transform.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/numeric_increment_transform_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/patch_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/existence_filter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_event.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/watch_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart'
    as asserts;
import 'package:cloud_firestore_dart/src/firebase/firestore/util/retryable_operation_queue.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as proto;
import 'package:firebase_app_dart/internal.dart';
import 'package:grpc/grpc.dart';
import 'package:rxdart/subjects.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';
import '../local/mock/database_mock.dart';
import '../local/persistence_fault_injector.dart';
import '../remote/mock_datastore.dart';
import 'query_event.dart';

/// Async-delivery tolerance.
///
/// Upstream drives everything through a synchronous AsyncQueue (`queue.runSync`), so once a step returns, every event
/// it caused has been delivered. The port's streams (watch/write streams, query listeners, the task scheduler) deliver
/// their events asynchronously instead. A zero-length delay yields to the event loop so that all microtasks and
/// zero-delay timers scheduled by the step run before the expectations are validated. Do not remove it: without it the
/// expectations race with the delivery of the events.
const Duration _delayDuration = Duration(milliseconds: 0);

/// Thrown by the harness when a spec uses a step or a value the port can not execute. The runner skips such specs up
/// front (see spec_skip_list.dart), so reaching this in a running test means the feature detection is incomplete.
class UnsupportedSpecFeature implements Exception {
  UnsupportedSpecFeature(this.message);

  final String message;

  @override
  String toString() => 'UnsupportedSpecFeature: $message';
}

/// Runs one spec test. Like `runSpec` of the JS spec_test_runner, it owns one [SpecClient] per `clientIndex` (created
/// when a step first addresses it) and the state the clients share:
/// - the persistence: every SQLite client opens its own [SQLitePersistence] on the same database file, a memory
///   persistence is one instance used by all clients;
/// - the writes the user made, which the backend acknowledges or rejects in order whichever client sends them (the JS
///   `SharedWriteTracker`).
///
/// Each client has its own task scheduler, local store, remote store, mock datastore (watch and write streams), sync
/// engine and event manager, and validates the expectations of the steps addressed to it. A single-client spec only
/// ever has client 0.
class SpecTestCase {
  /// [getPersistence] creates the persistence layer. [useEagerGc] is the value of the spec's `useEagerGCForMemory`
  /// config entry, [name] is a name that is unique per spec test and stable across restarts of that spec test (SQLite
  /// uses it as the database name, so all clients of a spec share the file).
  ///
  /// [getSharedPersistence] creates the persistence of a client of a multi-client spec: the client [clientId] of the
  /// SQLite database [name], with a primary lease that uses [clock]. Without it the multi-client specs use
  /// [getPersistence] (memory persistence, which does not support them).
  SpecTestCase(this.getPersistence, {this.getSharedPersistence});

  final Future<Persistence> Function(bool useEagerGc, String name)
      getPersistence;

  final Future<Persistence> Function(
    String name,
    ClientId clientId,
    int Function() clock,
  )? getSharedPersistence;

  /// The clock of the primary lease of the clients of a multi-client spec. It does not move: no lease expires during
  /// a spec, the clients give the lease up (shutdown, network, visibility) or a step takes it (applyClientState).
  final int _now = DateTime.now().millisecondsSinceEpoch;

  int _clock() => _now;

  String? currentName;

  static void info(String line) => SpecClient.info(line);

  static void log(String line) => SpecClient.log(line);

  late Map<String, dynamic> _config;

  /// The clients, by `clientIndex`; null for an index no step addressed yet.
  final List<SpecClient?> _clients = <SpecClient?>[];

  /// The storage of the shared client state of a multi-client spec (the JS `SharedFakeWebStorage`).
  final InMemorySharedClientStateStorage _sharedStorage =
      InMemorySharedClientStateStorage();

  /// Whether the clients share their state through [_sharedStorage]: in a multi-client spec. A single-client spec
  /// uses a [MemorySharedClientState].
  bool get _isMultiClient => (_config['numClients'] ?? 1) > 1;

  /// The writes sent to the [SyncEngine] of any client but not yet acknowledged or rejected by the backend, per user
  /// (see [SpecClient._outstandingWrites]).
  final Map<User, List<Pair<Mutation, Future<void>>>> _outstandingWrites =
      <User, List<Pair<Mutation, Future<void>>>>{};

  /// The persistence instance all clients share when the variant's persistence is not SQLite (memory), and how many
  /// clients hold it.
  Persistence? _sharedPersistence;
  int _sharedPersistenceHolders = 0;

  /// The SQLite persistences currently open on the spec's database file, one per running client.
  final List<SQLitePersistence> _openSQLitePersistences =
      <SQLitePersistence>[];

  /// The shutdowns of SQLite persistences that are in progress.
  final Set<Future<void>> _closingSQLitePersistences = <Future<void>>{};

  /// Returns the persistence for a client that starts (or restarts).
  Future<Persistence> _acquirePersistence(
    bool useEagerGc,
    ClientId clientId,
  ) async {
    final Persistence? shared = _sharedPersistence;
    if (shared != null) {
      _sharedPersistenceHolders++;
      return shared;
    }
    final Persistence persistence = _isMultiClient &&
            getSharedPersistence != null
        ? await getSharedPersistence!(currentName ?? 'init', clientId, _clock)
        : await getPersistence(useEagerGc, currentName ?? 'init');
    if (persistence is SQLitePersistence) {
      _openSQLitePersistences.add(persistence);
    } else {
      _sharedPersistence = persistence;
      _sharedPersistenceHolders = 1;
    }
    return persistence;
  }

  /// Releases the persistence of a client that shuts down (or restarts). The bookkeeping is done synchronously, before
  /// the first await, so that a restart can release and acquire concurrently.
  Future<void> _releasePersistence(Persistence persistence) async {
    if (identical(persistence, _sharedPersistence)) {
      if (--_sharedPersistenceHolders > 0) {
        return;
      }
      _sharedPersistence = null;
    } else if (persistence is SQLitePersistence) {
      _openSQLitePersistences.remove(persistence);
      // The database file is renamed on close so that the next run of the spec starts from scratch; keep it for the
      // clients that still use it.
      final Object database = persistence.database;
      if (_openSQLitePersistences.isNotEmpty && database is DatabaseMock) {
        database.renamePath = false;
      }
      final Future<void> shutdown = persistence.shutdown();
      _closingSQLitePersistences.add(shutdown);
      try {
        await shutdown;
      } finally {
        _closingSQLitePersistences.remove(shutdown);
      }
      // The database of a multi-client spec is shared by connections that do not rename it on close (see
      // createSharedSQLitePersistenceForProject): the last client deletes it, once no other client is still closing
      // (clients shut down concurrently, e.g. when another client cleared the cache).
      if (_openSQLitePersistences.isEmpty &&
          _closingSQLitePersistences.isEmpty &&
          _isMultiClient &&
          database is DatabaseMock) {
        for (final String suffix in <String>['', '_', '-journal', '-wal', '-shm']) {
          final File file = File('${database.path}$suffix');
          if (file.existsSync()) {
            file.deleteSync();
          }
        }
      }
      return;
    }
    await persistence.shutdown();
  }

  /// Returns the client [clientIndex], creating and starting it first if needed.
  Future<SpecClient> _client(int clientIndex) async {
    while (_clients.length <= clientIndex) {
      _clients.add(null);
    }
    SpecClient? client = _clients[clientIndex];
    if (client == null) {
      client = SpecClient(this, clientIndex);
      await client.specSetUp(_config);
      _clients[clientIndex] = client;
    }
    return client;
  }

  Future<void> runSteps(
    List<dynamic> steps,
    Map<String, dynamic> config,
  ) async {
    _config = config;
    // Like the JS runner, a client is created when a step first addresses it: in a multi-client spec the first client
    // to start takes the primary lease.
    try {
      for (int i = 0; i < steps.length; ++i) {
        final Map<String, dynamic> step = steps[i];
        final int clientIndex = step['clientIndex'] ?? 0;
        final SpecClient client = await _client(clientIndex);
        await client.runStep(step);
      }
    } catch (_) {
      // Always release the persistence (SQLite opens its database exclusively), but report the original failure.
      for (final SpecClient? client in _clients) {
        try {
          await client?.specTearDown(isError: true);
        } catch (_) {}
      }
      rethrow;
    }
    for (final SpecClient? client in _clients) {
      await client?.specTearDown();
    }
  }
}

/// One client of a spec test (the JS `TestRunner`): a Firestore client stack on the persistence shared by the spec, and
/// the expectations of the steps addressed to it.
class SpecClient implements RemoteStoreCallback {
  SpecClient(this._spec, this.clientIndex);

  /// Set this to true when debugging test failures.
  static const bool _debug = false;

  final SpecTestCase _spec;

  /// The index of this client in the spec (the `clientIndex` of its steps).
  final int clientIndex;

  /// Whether a `shutdown` step shut this client down.
  bool _isShutdown = false;

  late bool _useEagerGc;
  late LocalStore _localStore;
  bool _networkEnabled = true;

  // Parts of the Firestore system that the spec tests need to control.

  late Persistence _localPersistence;
  late TaskScheduler _queue;
  late MockDatastore _datastore;
  late RemoteStore _remoteStore;
  late SyncEngine _syncEngine;
  final BundleSerializer _bundleSerializer =
      BundleSerializer(RemoteSerializer(DatabaseId.forProject('test-project')));
  late EventManager _eventManager;

  /// The 'snapshots in sync' listeners that the spec added, and how often a listener fired since the last step.
  final List<void Function()> _snapshotsInSyncListeners = <void Function()>[];
  int _snapshotsInSyncEvents = 0;

  /// How many waitForPendingWrites tasks of the spec completed since the last step.
  int _waitForPendingWritesEvents = 0;

  /// Events to be checked by the expectations.
  late List<QueryEvent> _events;

  /// A dictionary for tracking the listens on queries. Note that the identity of the listeners is used to remove them.
  late Map<Query, QueryStream> _queryListeners;

  /// Set of documents that are expected to be in limbo. Verified at every step.
  late Set<DocumentKey> _expectedLimboDocs;

  /// Set of documents that are expected to be in limbo, enqueued for resolution and, therefore, without an active
  /// target. Verified at every step.
  late Set<DocumentKey> _expectedEnqueuedLimboDocs;

  int _maxConcurrentLimboResolutions = 0x7fffffff;

  /// The spec config `allowUnlistedTargetRemoval`: a watch removal with a cause may name a target that is not active.
  bool _allowUnlistedTargetRemoval = false;

  /// The remote target ids that the [RemoteStore] assigned to the listens of each SDK target id, in order.
  final Map<int, List<int>> _sdkToRemoteTargetIds = <int, List<int>>{};

  /// The index (into the lists of [_sdkToRemoteTargetIds]) of the listen that watch steps address, as set by the
  /// `watchUsesTargetIndex` step; null means the latest listen.
  int? _currentRemoteTargetIndex;

  /// Set of expected active targets, keyed by target ID.
  late Map<int, QueryData> _expectedActiveTargets;
  Map<int, QueryPurpose> _expectedPurposes = <int, QueryPurpose>{};

  /// The writes that have been sent to the [SyncEngine] via [SyncEngine.writeMutations] but not yet acknowledged by
  /// calling receiveWriteAck/Error. They are tracked per-user.
  ///
  /// It is mostly an implementation detail used internally to validate that the writes sent to the mock backend by the
  /// [SyncEngine] match the user mutations that initiated them.
  ///
  /// It is exposed specifically for use [_doRestart] to test persistence scenarios where the [SyncEngine] is restarted
  /// while the [Persistence] implementation still has outstanding persisted mutations.
  ///
  /// Note: The size of the list for the current user will generally be the same as [_writesSent], but not necessarily,
  /// since the [RemoteStore] limits the number of outstanding writes to the backend at a given time.
  ///
  /// Shared by all clients of the spec: in a multi-client spec the client that sends a write to the backend (the
  /// primary) is not necessarily the one that made it.
  Map<User, List<Pair<Mutation, Future<void>>>> get _outstandingWrites =>
      _spec._outstandingWrites;

  final List<DocumentKey> _acknowledgedDocs = <DocumentKey>[];
  final List<DocumentKey> _rejectedDocs = <DocumentKey>[];

  /// The current user for the [SyncEngine]. Determines which mutation queue is
  /// active.
  late User _currentUser;

  static void info(String line) {
    if (_debug) {
      // Print log information out directly to cut down on logger-related cruft like the extra line for the date and
      // class method which are always SpecTestCase+info
      Log.d('SpecTestCase', line);
    } else {
      Log.i('SpecTestCase', line);
    }
  }

  static void log(String line) {
    if (_debug) {
      info(line);
    }
  }

  Future<void> specSetUp(Map<String, dynamic> config) async {
    log('    Clearing all state.');

    _useEagerGc = config['useEagerGCForMemory'] ?? true;
    _maxConcurrentLimboResolutions =
        config['maxConcurrentLimboResolutions'] ?? 0x7fffffff;
    _allowUnlistedTargetRemoval = config['allowUnlistedTargetRemoval'] ?? false;

    _currentUser = User.unauthenticated;

    _networkEnabled = true;
    _acknowledgedDocs.clear();
    _rejectedDocs.clear();

    await _initClient();

    // Set up internal event tracking for the spec tests.
    _events = <QueryEvent>[];
    _queryListeners = <Query, QueryStream>{};

    _expectedLimboDocs = <DocumentKey>{};
    _expectedEnqueuedLimboDocs = <DocumentKey>{};
    _snapshotsInSyncListeners.clear();
    _snapshotsInSyncEvents = 0;
    _waitForPendingWritesEvents = 0;
    _expectedActiveTargets = <int, QueryData>{};
    _expectedPurposes = <int, QueryPurpose>{};
  }

  Future<void> specTearDown({bool isError = false}) async {
    if (isError) {
      log('~~~onError~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~');
    }
    await Future<void>.delayed(_delayDuration);
    // A client that a `shutdown` step shut down has released everything already.
    if (!_isShutdown) {
      _metadataRefresher?.stop();
      _retryQueue.stop();
      _sharedClientState.shutdown();
      await _remoteStore.shutdown();
      await _spec._releasePersistence(_localPersistence);
    }
    log('~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~');
  }

  /// Sets up a new client. Is used to initially setup the client initially and after every restart.
  Future<void> _initClient([bool isRestart = false]) async {
    log('    Set up a new client $clientIndex.');

    _localPersistence = await _spec._acquirePersistence(_useEagerGc, _clientId);

    final LocalStore localStore = LocalStore(_localPersistence, _currentUser);
    _localStore = localStore;

    _queue = TaskScheduler('', manualTasks: <TaskId>{TaskId.asyncQueueRetry});

    // Set up the sync engine and various stores.
    _datastore = MockDatastore(_queue)
      ..allowUnlistedTargetRemoval = _allowUnlistedTargetRemoval;
    // ignore: close_sinks
    final BehaviorSubject<bool> onNetworkConnected =
        BehaviorSubject<bool>.seeded(true);
    _remoteStore = RemoteStore(
      this,
      localStore,
      _datastore,
      onNetworkConnected,
      _queue,
    );
    _retryQueue = RetryableOperationQueue(_queue, _sharedStateQueue);
    final SharedClientState sharedClientState = _sharedClientState =
        _spec._isMultiClient
        ? StorageSharedClientState(
            _spec._sharedStorage.connect(),
            _enqueueRetryable,
            'spec',
            _clientId,
            _currentUser,
          )
        : MemorySharedClientState();
    _syncEngine = SyncEngine(
      localStore,
      _remoteStore,
      _currentUser,
      maxConcurrentLimboResolutions: _maxConcurrentLimboResolutions,
      sharedClientState: sharedClientState,
      // A client of a shared cache is primary once the lease says so (as in the JS SDK).
      startAsPrimary: !_spec._isMultiClient,
    );
    sharedClientState
      ..syncEngine = _syncEngine
      ..onlineStateHandler = (OnlineState onlineState) => unawaited(
        _syncEngine.applyOnlineStateChange(
          onlineState,
          OnlineStateSource.sharedClientState,
        ),
      );
    _eventManager = EventManager(_syncEngine);
    await localStore.start();
    await sharedClientState.start();

    // The lease decides which client is primary (`setPrimaryStateListener` in the JS
    // `MultiTabOfflineComponentProvider`). The listener is called right away, and later from inside transactions: the
    // change is applied after the task that is running. It is applied before the remote store starts, so that a
    // secondary client never opens a stream.
    _localPersistence.setPrimaryStateListener((bool isPrimary) {
      // Retried while it fails with a recoverable persistence error (the JS `enqueueRetryable`).
      unawaited(
        _enqueueSharedStateEvent(
          () => _retryQueue.enqueue(
            () => _syncEngine.applyPrimaryState(isPrimary),
          ),
          later: true,
        ),
      );
    });
    await _drainSharedStateEvents();
    await _remoteStore.start();

    final SQLitePersistence? persistence = _sharedSQLitePersistence;
    if (persistence != null) {
      // Another client cleared the cache: this one shuts down (the JS `setDatabaseDeletedListener`).
      persistence.databaseClearedListener = () => unawaited(
        _enqueueSharedStateEvent(() async {
          if (!_isShutdown) {
            await _doShutdown();
          }
        }),
      );
      // The `ClientMetadataRefresh` timer: the lease is refreshed, taken or given up when it fires.
      _metadataRefresher = ClientMetadataRefresher(
        _queue,
        run: () => _enqueueSharedStateEvent(persistence.refreshClientMetadata),
      )..start();
    }
  }

  /// The persistence of a client of a multi-client spec, which has a primary lease.
  SQLitePersistence? get _sharedSQLitePersistence {
    final Persistence persistence = _localPersistence;
    return _spec._isMultiClient && persistence is SQLitePersistence
        ? persistence
        : null;
  }

  ClientMetadataRefresher? _metadataRefresher;

  /// The id of this client in the shared client state.
  ClientId get _clientId => 'client$clientIndex';

  late SharedClientState _sharedClientState;

  /// Applies the changes of the other clients one after the other (the JS `AsyncQueue` of the client).
  final SerialQueue _sharedStateQueue = SerialQueue();
  int _pendingSharedStateEvents = 0;

  ///
  /// With [later] the operation runs after the task that is running, also when called from it.
  /// Applies a change of another client, retrying it on the `async_queue_retry` timer while it fails with a
  /// recoverable persistence error (the JS `AsyncQueue.enqueueRetryable` of `WebStorageSharedClientState`). Waiting for
  /// it waits for its first attempt only, as the JS `drain` does not run delayed retries.
  Future<void> _enqueueRetryable(Future<void> Function() operation) {
    _pendingSharedStateEvents++;
    return _retryQueue.enqueue(operation).whenComplete(() {
      _pendingSharedStateEvents--;
    });
  }

  late RetryableOperationQueue _retryQueue;

  Future<void> _enqueueSharedStateEvent(
    Future<void> Function() operation, {
    bool later = false,
  }) {
    _pendingSharedStateEvents++;
    final Future<void> Function<T>(Future<T> Function()) run = later
        ? _sharedStateQueue.runLater
        : _sharedStateQueue.run;
    return run<void>(() async {
      try {
        await operation();
      } finally {
        _pendingSharedStateEvents--;
      }
    });
  }

  /// Waits until the changes of the other clients are applied, including the ones that applying them caused (the JS
  /// `AsyncQueue.drain`).
  Future<void> _drainSharedStateEvents() async {
    while (_pendingSharedStateEvents > 0) {
      await _sharedStateQueue.run<void>(() async {});
      await Future<void>.delayed(_delayDuration);
    }
  }

  @override
  Future<void> handleOnlineStateChange(OnlineState onlineState) async {
    await _syncEngine.handleOnlineStateChange(onlineState);
  }

  List<Pair<Mutation, Future<void>>> _getCurrentOutstandingWrites() {
    List<Pair<Mutation, Future<void>>>? writes =
        _outstandingWrites[_currentUser];
    if (writes == null) {
      writes = <Pair<Mutation, Future<void>>>[];
      _outstandingWrites[_currentUser] = writes;
    }
    return writes;
  }

  // Methods for mocking out the grpc streams.

  /// Validates that a write was sent and matches the expected write.
  void _validateNextWriteSent(Mutation expectedWrite) {
    final List<Mutation> request = _datastore.waitForWriteSend();
    // TODO(long1eu): Batch writes not supported yet
    expect(request.length, 1);
    final Mutation actualWrite = request[0];
    expect(actualWrite, expectedWrite);
    log('      This write was sent: $actualWrite');
  }

  int _writesSent() => _datastore.writesSent;

  // Methods for constructing objects from specs.

  /// The format for a query is string|{path, limit?}.
  /// https://github.com/firebase/firebase-js-sdk/blob/master/packages/firestore/test/unit/specs/spec_test_runner.ts#L1115
  Query _parseQuery(Object querySpec) {
    if (querySpec is String) {
      return Query(ResourcePath.fromString(querySpec));
    } else if (querySpec is Map<String, dynamic>) {
      final Map<String, dynamic> queryDict = querySpec;
      final String path = queryDict['path'];
      final String? collectionGroup = queryDict.containsKey('collectionGroup')
          ? queryDict['collectionGroup']
          : null;
      Query query = Query(
        ResourcePath.fromString(path),
        collectionGroup: collectionGroup,
      );
      if (queryDict.containsKey('limit')) {
        final String limitType = queryDict['limitType'] ?? 'LimitToFirst';
        if (limitType == 'LimitToFirst') {
          query = query.limit(queryDict['limit']);
        } else if (limitType == 'LimitToLast') {
          query = query.limitToLast(queryDict['limit']);
        } else {
          throw asserts.fail('Unknown limit type: $limitType');
        }
      }
      if (queryDict.containsKey('filters')) {
        final List<dynamic> array = queryDict['filters'];
        for (int i = 0; i < array.length; i++) {
          final List<dynamic> _filter = array[i];
          final String field = _filter[0];
          final String op = _filter[1];
          final Object? value = _filter[2];
          query = query.filter(filter(field, op, value));
        }
      }
      if (queryDict.containsKey('orderBys')) {
        final List<dynamic> array = queryDict['orderBys'];
        for (int i = 0; i < array.length; i++) {
          final List<dynamic> _orderBy = array[i];
          final String field = _orderBy[0];
          final String direction = _orderBy[1];
          query = query.orderBy(orderBy(field, direction));
        }
      }
      return query;
    } else {
      throw asserts.fail('Invalid query: $querySpec');
    }
  }

  DocumentViewChange _parseChange(
    Map<String, dynamic> jsonDoc,
    DocumentViewChangeType type,
  ) {
    final int version = jsonDoc['version'];
    final Map<String, dynamic> options = jsonDoc['options'];
    final DocumentState documentState = options['hasLocalMutations'] ?? false
        ? DocumentState.localMutations
        : (options['hasCommittedMutations'] ?? false
            ? DocumentState.committedMutations
            : DocumentState.synced);

    final Map<String, Object?> values = _parseMap(jsonDoc['value']);
    final Document document = doc(
      jsonDoc['key'],
      version,
      values,
      documentState,
    );
    return DocumentViewChange(type, document);
  }

  Object? _parseObject(Object? obj) {
    if (obj is List<dynamic>) {
      return _parseList(obj);
    } else if (obj is Map<String, dynamic>) {
      if (obj.containsKey('__decimal128__')) {
        final Object? decimal = obj['__decimal128__'];
        if (decimal is Map<String, dynamic> && decimal['stringValue'] != null) {
          return Decimal128Value(decimal['stringValue'] as String);
        } else if (decimal is String) {
          return Decimal128Value(decimal);
        }
      }
      if (obj['_methodName'] == 'increment') {
        return _SpecIncrement(_parseObject(obj['_operand']));
      }
      return _parseMap(obj);
    } else {
      return obj;
    }
  }

  List<Object?> _parseList(List<dynamic> arr) {
    final List<Object?> result = List<Object?>.filled(arr.length, null);
    for (int i = 0; i < arr.length; ++i) {
      result[i] = _parseObject(arr[i]);
    }
    return result;
  }

  Map<String, Object?> _parseMap(Map<String, dynamic> obj) {
    final Map<String, Object?> values = <String, Object?>{};
    final Iterable<String> keys = obj.keys;

    for (String key in keys) {
      values[key] = _parseObject(obj[key]);
    }
    return values;
  }

  /// Parses the SDK target ids of a watch step and maps each to the remote target id that watch should address (see
  /// [_remoteTargetId]).
  List<int> _parseWatchTargets(List<dynamic>? arr) {
    return _parseIntList(arr)
        .map((int id) => _remoteTargetId(id, isWatchStep: true))
        .toList();
  }

  /// Resolves an SDK target id to the remote target id of one of its listens: the one chosen by the last
  /// `watchUsesTargetIndex` step, otherwise the latest.
  int _remoteTargetId(int sdkTargetId, {bool isWatchStep = false}) {
    final List<int> list =
        _sdkToRemoteTargetIds.putIfAbsent(sdkTargetId, () => <int>[]);
    // Listens that did not go through a userListen step (limbo resolutions) are picked up here.
    final int? current = _remoteStore.getRemoteTargetId(sdkTargetId);
    if (current != null && !list.contains(current)) {
      list.add(current);
    }
    if (list.isEmpty) {
      return sdkTargetId;
    }
    final int? index = _currentRemoteTargetIndex;
    return isWatchStep && index != null ? list[index] : list.last;
  }

  List<int> _parseIntList(List<dynamic>? arr) {
    final List<int> result = <int>[];
    if (arr == null) {
      return result;
    }
    for (int i = 0; i < arr.length; ++i) {
      result.add(arr[i]);
    }
    return result;
  }

  // Methods for doing the steps of the spec test.

  Future<void> _doListen(Map<String, dynamic> listenSpec) async {
    final int expectedId = listenSpec['targetId'];
    final Query query = _parseQuery(listenSpec['query']);

    // Like upstream, spec tests include metadata changes by default; `includeMetadataChanges` / `waitForSyncWhenOnline`
    // in the spec's options are ignored upstream as well. The listen source can be 'cache'.
    final Map<String, dynamic>? optionsSpec = listenSpec['options'];
    final bool includeMetadata =
        optionsSpec?['includeDocumentMetadataChanges'] ?? true;
    final ListenOptions options = ListenOptions(
      includeDocumentMetadataChanges: includeMetadata,
      includeQueryMetadataChanges: includeMetadata,
      source: optionsSpec?['source'] == 'cache'
          ? ListenSource.cache
          : ListenSource.defaultSource,
    );

    final QueryStream listener = QueryStream(query, options)
      ..listen(
        (ViewSnapshot value) {
          _events.add(QueryEvent(query: query, view: value));
        },
        onError: (dynamic error) {
          asserts.hardAssert(
            error is FirestoreError,
            'The recived error is not a FirebaseFirestoreError it is ${error.runtimeType}.',
          );
          _events.add(QueryEvent(query: query, error: error));
        },
      );

    _queryListeners[query] = listener;

    final int actualId = await _eventManager.addQueryListener(listener);
    expect(actualId, expectedId);

    // The remote store maps the listen to a new remote target id; remember it for `watchUsesTargetIndex`.
    final int? remoteTargetId = _remoteStore.getRemoteTargetId(expectedId);
    if (remoteTargetId != null) {
      _sdkToRemoteTargetIds
          .putIfAbsent(expectedId, () => <int>[])
          .add(remoteTargetId);
    }

    // Skip the backoff that a previous `watchStreamClose` may have left
    // pending (JS doListen).
    if (_datastore.isWatchStreamInBackoff) {
      _datastore.runWatchStreamBackoff();
    }

    await Future<void>.delayed(_delayDuration);
  }

  Future<void> _doUnlisten(List<dynamic> unlistenSpec) async {
    final Query query = _parseQuery(unlistenSpec[1]);
    final QueryStream listener = _queryListeners.remove(query)!;
    await _eventManager.removeQueryListener(listener);
  }

  Future<void> _doMutation(Mutation mutation) async {
    final DocumentKey documentKey = mutation.key;
    final Completer<void> callback = Completer<void>();

    final Future<void> writeProcessed = callback.future //
        .then((_) => _acknowledgedDocs.add(documentKey))
        .catchError((dynamic e) => _rejectedDocs.add(documentKey));

    // A write that can not be stored is rejected locally and never sent (as the JS runner).
    if (!_isFailing('Locally write mutations')) {
      _getCurrentOutstandingWrites().add(
        Pair<Mutation, Future<void>>(mutation, writeProcessed),
      );
    }
    log('      Sending this write: $mutation');

    await _syncEngine.writeMutations(<Mutation>[mutation], callback);
    // Let the write stream handshake and the write pipeline settle.
    await Future<void>.delayed(_delayDuration);
  }

  Future<void> _doSet(List<dynamic> setSpec) async {
    await _doMutation(setMutation(setSpec[0], _parseMap(setSpec[1])));
  }

  Future<void> _doPatch(List<dynamic> patchSpec) async {
    final Map<String, Object?> values = _parseMap(patchSpec[1]);
    // An increment is a field transform, it is neither part of the patched
    // data nor of the field mask.
    final List<FieldTransform> transforms = <FieldTransform>[
      for (final MapEntry<String, Object?> entry in values.entries)
        if (entry.value is _SpecIncrement)
          FieldTransform(field(entry.key),
              (entry.value! as _SpecIncrement).toOperation()),
    ];
    values.removeWhere((String key, Object? value) => value is _SpecIncrement);
    final PatchMutation patch = patchMutation(patchSpec[0], values);
    await _doMutation(transforms.isEmpty
        ? patch
        : PatchMutation(
            patch.key, patch.value, patch.mask, patch.precondition, transforms));
  }

  Future<void> _doDelete(String key) async {
    await _doMutation(deleteMutation(key));
  }

  // Helper for calling datastore.writeWatchChange() on the AsyncQueue.

  Future<void> _writeWatchChange(
    WatchChange change,
    SnapshotVersion version,
  ) async {
    await _datastore.writeWatchChange(change, version);
    await Future<void>.delayed(_delayDuration);
  }

  Future<void> _doWatchAck(List<dynamic> ackedTargets) async {
    final WatchChangeWatchTargetChange change = WatchChangeWatchTargetChange(
      WatchTargetChangeType.added,
      _parseWatchTargets(ackedTargets),
    );
    await _writeWatchChange(change, SnapshotVersion.none);
  }

  Future<void> _doWatchCurrent(List<dynamic> currentSpec) async {
    final List<int> currentTargets = _parseWatchTargets(currentSpec[0]);
    final Uint8List resumeToken = Uint8List.fromList(
      utf8.encode(currentSpec[1]),
    );
    final WatchChangeWatchTargetChange change = WatchChangeWatchTargetChange(
      WatchTargetChangeType.current,
      currentTargets,
      resumeToken,
    );
    await _writeWatchChange(change, SnapshotVersion.none);
  }

  Future<void> _doWatchRemove(Map<String, dynamic> watchRemoveSpec) async {
    GrpcError? error;
    final Map<String, dynamic>? cause = watchRemoveSpec['cause'];
    if (cause != null) {
      final int code = cause['code'];
      if (code != 0) {
        error = GrpcError.custom(code, '');
      }
    }

    final List<int> targetIds = _parseWatchTargets(
      watchRemoveSpec['targetIds'].cast<int>(),
    );
    final WatchChangeWatchTargetChange change = WatchChangeWatchTargetChange(
      WatchTargetChangeType.removed,
      targetIds,
      Uint8List(0),
      error,
    );

    await _writeWatchChange(change, SnapshotVersion.none);
    // Unlike web, the MockDatastore detects a watch removal with cause and will remove active targets

    await Future<void>.delayed(_delayDuration);
  }

  Future<void> _doWatchEntity(Map<String, dynamic> watchEntity) async {
    if (watchEntity.containsKey('docs')) {
      asserts.hardAssert(
        !watchEntity.containsKey('doc'),
        'Exactly one of |doc| or |docs| needs to be set.',
      );
      final List<dynamic> docs = watchEntity['docs'];
      for (int i = 0; i < docs.length; ++i) {
        final Map<String, dynamic> doc = docs[i];
        final Map<String, dynamic> watchSpec = <String, dynamic>{};
        watchSpec['doc'] = doc;
        if (watchEntity.containsKey('targets')) {
          watchSpec['targets'] = watchEntity['targets'];
        }
        if (watchEntity.containsKey('removedTargets')) {
          watchSpec['removedTargets'] = watchEntity['removedTargets'];
        }
        await _doWatchEntity(watchSpec);
      }
    } else if (watchEntity.containsKey('doc')) {
      final Map<String, dynamic> docSpec = watchEntity['doc'];
      final String key = docSpec['key'];

      final Map<String, Object?>? value =
          docSpec['value'] == null ? null : _parseMap(docSpec['value']);
      final int version = docSpec['version'];

      final MaybeDocument document =
          value != null ? doc(key, version, value) : deletedDoc(key, version);

      final List<int> updated = _parseWatchTargets(
        watchEntity['targets'] ?? <int>[].cast<int>(),
      );
      final List<int> removed = _parseWatchTargets(
        (watchEntity['removedTargets'] ?? <int>[]).cast<int>(),
      );
      final WatchChange change = WatchChangeDocumentChange(
        updated,
        removed,
        document.key,
        document,
      );

      await _writeWatchChange(change, SnapshotVersion.none);
    } else if (watchEntity.containsKey('key')) {
      final String _key = watchEntity['key'];
      final List<int> removed = _parseWatchTargets(
        watchEntity['removedTargets'].cast<int>(),
      );
      final WatchChange change = WatchChangeDocumentChange(
        <int>[],
        removed,
        key(_key),
        null,
      );
      await _writeWatchChange(change, SnapshotVersion.none);
    } else {
      throw asserts.fail('Either key, doc or docs must be set.');
    }
  }

  Future<void> _doWatchFilter(Map<String, dynamic> watchFilter) async {
    final List<int> targets = _parseWatchTargets(watchFilter['targetIds']);
    asserts.hardAssert(
      targets.length == 1,
      'ExistenceFilters currently support exactly one target only.',
    );

    // The format is {targetIds, keys, bloomFilter?}: the keys are the documents the backend says matched the target,
    // the optional bloom filter describes the unchanged documents.
    final List<dynamic> keys = watchFilter['keys'];
    final Map<String, dynamic>? bloomFilter = watchFilter['bloomFilter'];

    final ExistenceFilter filter = ExistenceFilter(
      keys.length,
      bloomFilter != null ? _parseBloomFilter(bloomFilter) : null,
    );
    final WatchChangeExistenceFilterWatchChange change =
        WatchChangeExistenceFilterWatchChange(targets[0], filter);

    await _writeWatchChange(change, SnapshotVersion.none);
  }

  QueryPurpose _parseQueryPurpose(String name) {
    switch (name) {
      case 'TargetPurposeListen':
        return QueryPurpose.listen;
      case 'TargetPurposeExistenceFilterMismatch':
        return QueryPurpose.existenceFilterMismatch;
      case 'TargetPurposeExistenceFilterMismatchBloom':
        return QueryPurpose.existenceFilterMismatchBloom;
      case 'TargetPurposeLimboResolution':
        return QueryPurpose.limboResolution;
      default:
        throw asserts.fail('Unknown target purpose: $name');
    }
  }

  /// Parses a JSON object into a bloom filter proto. Padding and hash count default to 0 when they are missing.
  proto.BloomFilter _parseBloomFilter(Map<String, dynamic> json) {
    final Map<String, dynamic> bits = json['bits'];
    List<int> bitmap;
    int? hashCount = json['hashCount'];
    try {
      bitmap = base64.decode(bits['bitmap']);
    } on FormatException {
      // A bitmap that is not valid base64 can not be represented in a proto. Use a bloom filter that is invalid
      // for the client, which is handled the same way: the bloom filter is ignored.
      bitmap = <int>[];
      hashCount = -1;
    }
    return proto.BloomFilter(
      bits: proto.BitSequence(bitmap: bitmap, padding: bits['padding'] ?? 0),
      hashCount: hashCount ?? 0,
    );
  }

  Future<void> _doWatchReset(List<dynamic> targetIds) async {
    final List<int> targets = _parseWatchTargets(targetIds);
    final WatchChange change = WatchChangeWatchTargetChange(
      WatchTargetChangeType.reset,
      targets,
    );
    await _writeWatchChange(change, SnapshotVersion.none);
  }

  Future<void> _doWatchSnapshot(Map<String, dynamic> watchSnapshot) async {
    // The client will only respond to watchSnapshots if they are on a target change with an empty set of target IDs.
    final List<int> targets = _parseWatchTargets(
      watchSnapshot['targetIds']?.cast<int>(),
    );
    final String resumeToken = watchSnapshot['resumeToken'] ?? '';

    final WatchChange change = WatchChangeWatchTargetChange(
      WatchTargetChangeType.noChange,
      targets,
      Uint8List.fromList(utf8.encode(resumeToken)),
    );

    await _writeWatchChange(change, version(watchSnapshot['version']));
  }

  Future<void> _doWatchStreamClose(Map<String, dynamic> spec) async {
    final Map<String, dynamic> error = spec['error'];

    final bool runBackoffTimer = spec['runBackoffTimer'] ?? false;

    final GrpcError status = GrpcError.custom(error['code'], error['message']);
    _datastore.failWatchStream(status);
    // Let the stream close event be delivered to the remote store.
    await Future<void>.delayed(_delayDuration);
    // The watch stream re-opens through its backoff timer if there are active
    // listeners (JS doWatchStreamClose); without runBackoffTimer it stays in
    // backoff. Only the backoff timer runs: with JS's real backoff delays it is
    // the first timer due, the mock's never elapses on its own.
    if (runBackoffTimer && _queryListeners.isNotEmpty) {
      _datastore.runWatchStreamBackoff();
      await Future<void>.delayed(_delayDuration);
      assert(_datastore.isWatchStreamOpen, 'Watch stream is open');
    }
  }

  Future<void> _doWriteAck(Map<String, dynamic> writeAckSpec) async {
    final int _version = writeAckSpec['version'];
    // keepInQueue: the acknowledgement is not stored (failDatabase) or not seen by this client, the write stays
    // outstanding (as the JS runner).
    final bool keepInQueue = writeAckSpec['keepInQueue'] ?? false;
    final Pair<Mutation, Future<void>> write = keepInQueue
        ? _getCurrentOutstandingWrites().first
        : _getCurrentOutstandingWrites().removeAt(0);
    _validateNextWriteSent(write.first);

    final List<FieldValue> transformResults = <FieldValue>[
      for (final dynamic value
          in (writeAckSpec['transformResults'] as List<dynamic>?) ??
              const <dynamic>[])
        _bundleSerializer.decodeValue(value as Map<String, dynamic>),
    ];
    final MutationResult mutationResult =
        MutationResult(version(_version), transformResults);
    await _datastore.ackWrite(version(_version), <MutationResult>[
      mutationResult,
    ]);
    // Let the write response be delivered to the remote store.
    await Future<void>.delayed(_delayDuration);
  }

  Future<void> _doFailWrite(Map<String, dynamic> writeFailureSpec) async {
    final Map<String, dynamic> errorSpec = writeFailureSpec['error'];
    final bool keepInQueue = writeFailureSpec['keepInQueue'] ?? false;

    final int code = errorSpec['code'];
    final GrpcError error = GrpcError.custom(code, '');

    final Pair<Mutation, Future<void>> write =
        _getCurrentOutstandingWrites()[0];
    _validateNextWriteSent(write.first);

    // If this is a permanent error, the write is not expected to be sent again.
    if (!keepInQueue) {
      _getCurrentOutstandingWrites().removeAt(0);
    }

    log('      Failing a write.');
    await _datastore.failWrite(error);
    // Let the write failure be delivered to the remote store.
    await Future<void>.delayed(_delayDuration);
  }

  Future<void> _doRunTimer(String timer) async {
    late TaskId taskId;
    switch (timer) {
      case 'all':
        taskId = TaskId.all;
        break;
      case 'listen_stream_idle':
        taskId = TaskId.listenStreamIdle;
        break;
      case 'listen_stream_connection_backoff':
        taskId = TaskId.listenStreamConnectionBackoff;
        break;
      case 'write_stream_idle':
        taskId = TaskId.writeStreamIdle;
        break;
      case 'write_stream_connection_backoff':
        taskId = TaskId.writeStreamConnectionBackoff;
        break;
      case 'online_state_timeout':
        taskId = TaskId.onlineStateTimeout;
        break;
      case 'async_queue_retry':
        taskId = TaskId.asyncQueueRetry;
        // As in JS (runAllDelayedOperationsUntil does not require the timer), nothing may be waiting for a retry.
        if (_queue.getTask(taskId) == null) {
          await Future<void>.delayed(_delayDuration);
          return;
        }
        break;
      case 'client_metadata_refresh':
        taskId = TaskId.clientMetadataRefresh;
        break;
      default:
        throw asserts.fail(
          'runTimer spec step specified unknown timer: $timer',
        );
    }

    _queue.runUntil(taskId);
    // Let the task run to completion.
    await Future<void>.delayed(_delayDuration);
  }

  Future<void> _doDisableNetwork() async {
    _networkEnabled = false;
    // Make sure to execute all writes that are currently queued. This allows us to assert on the total number of
    // requests sent before shutdown.
    await _remoteStore.fillWritePipeline();
    _setPersistenceNetworkEnabled(false);
    await _remoteStore.disableNetwork();
    await Future<void>.delayed(_delayDuration);
  }

  Future<void> _doEnableNetwork() async {
    _networkEnabled = true;
    _setPersistenceNetworkEnabled(true);
    await _remoteStore.enableNetwork();
  }

  /// A client without network gives the primary lease to a client with network (the JS
  /// `IndexedDbPersistence.setNetworkEnabled`, which refreshes the lease on the queue of the client).
  void _setPersistenceNetworkEnabled(bool enabled) {
    final SQLitePersistence? persistence = _sharedSQLitePersistence;
    if (persistence != null) {
      unawaited(
        _enqueueSharedStateEvent(() => persistence.setNetworkEnabled(enabled)),
      );
    }
  }

  /// The `applyClientState` step: the visibility of the client (an application in the foreground is preferred as the
  /// primary client) and taking the primary lease (the lease is cleared and this client refreshes its metadata).
  Future<void> _doApplyClientState(Map<String, dynamic> state) async {
    final SQLitePersistence? persistence = _sharedSQLitePersistence;
    if (persistence == null) {
      throw UnsupportedSpecFeature(
        'applyClientState needs a persistence with a primary lease',
      );
    }
    final String? visibility = state['visibility'];
    if (visibility != null) {
      // The JS persistence refreshes its metadata on a visibility change.
      persistence.clientMetadata.inForeground = visibility == 'visible';
      unawaited(_enqueueSharedStateEvent(persistence.refreshClientMetadata));
    }
    if (state['primary'] == true) {
      // `clearCurrentPrimaryLease` of the JS runner, then the refresh timer of this client.
      await _enqueueSharedStateEvent(
        () => persistence.execute('DELETE FROM primary_client'),
      );
      _queue.runUntil(TaskId.clientMetadataRefresh);
      await Future<void>.delayed(_delayDuration);
    }
  }

  Future<void> _doChangeUser(String? uid) async {
    _currentUser = User(uid);
    await _syncEngine.handleCredentialChange(_currentUser);
    await Future<void>.delayed(_delayDuration);
  }

  Future<void> _doRestart() async {
    if (_localPersistence is SQLitePersistence) {
      final SQLitePersistence persistence =
          _localPersistence as SQLitePersistence;
      final DatabaseMock databaseMock = persistence.database as DatabaseMock;
      // ignore: cascade_invocations
      databaseMock.renamePath = false;
    }
    _sdkToRemoteTargetIds.clear();
    _currentRemoteTargetIndex = null;

    _metadataRefresher?.stop();
    _retryQueue.stop();
    _sharedClientState.shutdown();
    await Future.wait(<Future<void>>[
      _remoteStore.shutdown(),
      _spec._releasePersistence(_localPersistence),
      _initClient(true),
    ]);

    if (_localPersistence is SQLitePersistence) {
      final SQLitePersistence persistence =
          _localPersistence as SQLitePersistence;
      final DatabaseMock databaseMock = persistence.database as DatabaseMock;
      // ignore: cascade_invocations
      databaseMock.renamePath = true;
    }
  }

  /// Shuts this client down for good (the JS `doShutdown`): its remote store stops and it releases the persistence. The
  /// other clients keep running on the shared persistence.
  Future<void> _doShutdown() async {
    _metadataRefresher?.stop();
    _retryQueue.stop();
    _sharedClientState.shutdown();
    await _remoteStore.shutdown();
    await _spec._releasePersistence(_localPersistence);
    _isShutdown = true;
  }

  /// Steps that exist in the spec format but that the port can not execute. Kept here so that the runner can detect
  /// them up front (spec_skip_list.dart maps them to named skip entries).
  static const Set<String> unsupportedSteps = <String>{};

  /// The `clearPersistence` step of a client that was shut down: the cache is cleared, and the clients that still use
  /// it shut down (the JS `clearTestPersistence`, which deletes the IndexedDB database).
  Future<void> _doClearPersistence() async {
    final Persistence persistence = _localPersistence;
    if (persistence is! SQLitePersistence) {
      throw UnsupportedSpecFeature('clearPersistence needs SQLite persistence');
    }
    await persistence.clearPersistence();
  }

  /// The step carries the index definition as a JSON object (the JS spec builder) or as its string form.
  Future<void> _doSetIndexConfiguration(Object? configuration) async {
    await _localStore.configureFieldIndexes(
      configuration is String
          ? parseIndexConfiguration(configuration)
          : parseIndexConfigurationMap(configuration),
    );
  }

  /// Parses an index of `expectedState.indexes`, which is the JSON form of a `FieldIndex` of the JS SDK: the field
  /// paths as `{segments: [...]}` and the kinds as numbers (0 ascending, 1 descending, 2 contains).
  static FieldIndex _parseExpectedIndex(Map<String, dynamic> json) {
    return FieldIndex(
      FieldIndex.unknownId,
      json['collectionGroup'] as String,
      <IndexSegment>[
        for (final dynamic field in json['fields'] as List<dynamic>)
          IndexSegment(
            FieldPath.fromSegments(
              (field['fieldPath']['segments'] as List<dynamic>).cast<String>(),
            ),
            SegmentKind.values[field['kind'] as int],
          ),
      ],
      FieldIndex.initialState,
    );
  }

  Future<void> _doLoadBundle(String json) async {
    final BundleReader bundleReader =
        BundleReader.fromBytes(_bundleSerializer, utf8.encode(json));
    final LoadBundleTask bundleTask = LoadBundleTaskInternal.create();
    await _syncEngine.loadBundle(bundleReader, bundleTask);
    // Let the resulting snapshots be delivered to the listeners.
    await Future<void>.delayed(_delayDuration);
    expect(bundleTask.isSuccessful, isTrue,
        reason: 'Loading bundle failed with ${bundleTask.exception}');
  }

  Future<void> _doTriggerLruGc(int cacheThreshold) async {
    final Object delegate = _localPersistence.referenceDelegate;
    if (delegate is LruDelegate) {
      // Upstream's LruGarbageCollector.withNewThreshold(): the new byte threshold and a 100% collection percentile.
      final LruGarbageCollector collector = LruGarbageCollector(
          delegate,
          LruGarbageCollectorParams(
              minBytesThreshold: cacheThreshold, percentileToCollect: 100));
      await _localStore.collectGarbage(collector);
    }
    await Future<void>.delayed(_delayDuration);
  }

  void _doAddSnapshotsInSyncListener() {
    void listener() => _snapshotsInSyncEvents += 1;
    _snapshotsInSyncListeners.add(listener);
    _eventManager.addSnapshotsInSyncListener(listener);
  }

  void _doRemoveSnapshotsInSyncListener() {
    if (_snapshotsInSyncListeners.isEmpty) {
      throw StateError('There must be a listener to unlisten to');
    }
    _eventManager
        .removeSnapshotsInSyncListener(_snapshotsInSyncListeners.removeAt(0));
  }

  Future<void> _doWaitForPendingWrites() async {
    final Completer<void> task = Completer<void>();
    unawaited(task.future
        .then((_) => _waitForPendingWritesEvents += 1, onError: (Object _) {}));
    await _syncEngine.registerPendingWritesTask(task);
  }

  // --- failDatabase / recoverDatabase (persistence failure recovery) ---

  /// Fails the transactions of the persistence of this client by action name (the JS `injectFailures`). Attached at
  /// the first `failDatabase` step; a restart creates a new persistence, which starts without failures (as in JS).
  PersistenceFaultInjector? _faultInjector;

  /// The `failDatabase` step: a list of actions makes their transactions fail, `false` (the JS `recoverDatabase`)
  /// makes them work again.
  void _doFailDatabase(Object? failActions) {
    PersistenceFaultInjector? injector = _faultInjector;
    if (injector == null || !identical(injector.persistence, _localPersistence)) {
      injector = _faultInjector = PersistenceFaultInjector(_localPersistence);
    }
    injector.failActions = failActions is List
        ? failActions.cast<String>().toList()
        : <String>[];
  }

  /// Whether the transactions of [action] fail right now.
  bool _isFailing(String action) {
    final PersistenceFaultInjector? injector = _faultInjector;
    return injector != null &&
        identical(injector.persistence, _localPersistence) &&
        injector.failActions.contains(action);
  }

  // --- end of failDatabase / recoverDatabase ---

  Future<void> _doStep(Map<String, dynamic> step) async {
    // The `clientIndex` of the step was used by SpecTestCase to pick this client.
    if (step.containsKey('userListen')) {
      await _doListen(step['userListen']);
    } else if (step.containsKey('userUnlisten')) {
      await _doUnlisten(step['userUnlisten']);
    } else if (step.containsKey('userSet')) {
      await _doSet(step['userSet']);
    } else if (step.containsKey('userPatch')) {
      await _doPatch(step['userPatch']);
    } else if (step.containsKey('userDelete')) {
      await _doDelete(step['userDelete']);
    } else if (step.containsKey('addSnapshotsInSyncListener')) {
      _doAddSnapshotsInSyncListener();
    } else if (step.containsKey('removeSnapshotsInSyncListener')) {
      _doRemoveSnapshotsInSyncListener();
    } else if (step.containsKey('waitForPendingWrites')) {
      await _doWaitForPendingWrites();
    } else if (step.containsKey('setIndexConfiguration')) {
      await _doSetIndexConfiguration(step['setIndexConfiguration']);
    } else if (step.containsKey('drainQueue')) {
      await _drainSharedStateEvents();
      // Upstream waits for its AsyncQueue to be empty. Here the equivalent is letting the event loop settle, which
      // runSteps does after every step anyway.
      await Future<void>.delayed(_delayDuration);
    } else if (step.containsKey('triggerLruGC')) {
      await _doTriggerLruGc(step['triggerLruGC']);
    } else if (step.containsKey('watchAck')) {
      await _doWatchAck(step['watchAck']);
    } else if (step.containsKey('watchCurrent')) {
      await _doWatchCurrent(step['watchCurrent']);
    } else if (step.containsKey('watchRemove')) {
      await _doWatchRemove(step['watchRemove']);
    } else if (step.containsKey('watchEntity')) {
      await _doWatchEntity(step['watchEntity']);
    } else if (step.containsKey('watchFilter')) {
      await _doWatchFilter(step['watchFilter']);
    } else if (step.containsKey('watchReset')) {
      await _doWatchReset(step['watchReset']);
    } else if (step.containsKey('watchSnapshot')) {
      await _doWatchSnapshot(step['watchSnapshot']);
    } else if (step.containsKey('watchStreamClose')) {
      await _doWatchStreamClose(step['watchStreamClose']);
    } else if (step.containsKey('watchProto')) {
      // watchProto isn't yet used, and it's unclear how to create arbitrary protos from JSON.
      throw asserts.fail('watchProto is not yet supported.');
    } else if (step.containsKey('writeAck')) {
      await _doWriteAck(step['writeAck']);
    } else if (step.containsKey('failWrite')) {
      await _doFailWrite(step['failWrite']);
    } else if (step.containsKey('runTimer')) {
      await _doRunTimer(step['runTimer']);
    } else if (step.containsKey('enableNetwork')) {
      if (step['enableNetwork']) {
        await _doEnableNetwork();
      } else {
        await _doDisableNetwork();
      }
    } else if (step.containsKey('changeUser')) {
      // NOTE: Map<String, dynamic>.getString('foo') where 'foo' is mapped to null will return 'null'. Explicitly
      // testing for isNull here allows the null value to be preserved. This is important because the unauthenticated
      // user is represented as having a null uid as a value for 'changeUser'.
      final String? uid = step['changeUser'];
      await _doChangeUser(uid);
    } else if (step.containsKey('loadBundle')) {
      await _doLoadBundle(step['loadBundle']);
    } else if (step.containsKey('restart')) {
      await _doRestart();
    } else if (step.containsKey('clearPersistence')) {
      await _doClearPersistence();
    } else if (step.containsKey('applyClientState')) {
      await _doApplyClientState(step['applyClientState']);
    } else if (step.containsKey('shutdown')) {
      await _doShutdown();
    } else if (step.containsKey('watchUsesTargetIndex')) {
      // Every listen of a target gets a fresh remote target id; this step picks which of them the following watch
      // steps address.
      final dynamic index = step['watchUsesTargetIndex'];
      _currentRemoteTargetIndex = index == 'latest' ? null : index as int;
    } else if (step.containsKey('failDatabase')) {
      _doFailDatabase(step['failDatabase']);
    } else {
      for (String unsupported in unsupportedSteps) {
        if (step.containsKey(unsupported)) {
          throw UnsupportedSpecFeature('step $unsupported');
        }
      }
      throw asserts.fail('Unknown step: $step');
    }
  }

  // Methods for validating expectations.

  void _assertEventMatches(Map<String, dynamic> expected, QueryEvent actual) {
    final Query expectedQuery = _parseQuery(expected['query']);
    expect(actual.query, expectedQuery);
    if (expected.containsKey('errorCode') &&
        expected['errorCode'] != StatusCode.ok) {
      expect(actual.error, isNotNull);
      expect(actual.error!.code.value, expected['errorCode']);
    } else {
      final List<DocumentViewChange> expectedChanges = <DocumentViewChange>[];
      final List<dynamic>? removed = expected['removed'];
      for (int i = 0; removed != null && i < removed.length; ++i) {
        expectedChanges.add(
          _parseChange(removed[i], DocumentViewChangeType.removed),
        );
      }

      final List<dynamic>? added = expected['added'];
      for (int i = 0; added != null && i < added.length; ++i) {
        expectedChanges.add(
          _parseChange(added[i], DocumentViewChangeType.added),
        );
      }
      final List<dynamic>? modified = expected['modified'];
      for (int i = 0; modified != null && i < modified.length; ++i) {
        expectedChanges.add(
          _parseChange(modified[i], DocumentViewChangeType.modified),
        );
      }

      final List<dynamic>? metadata = expected['metadata'];
      for (int i = 0; metadata != null && i < metadata.length; ++i) {
        expectedChanges.add(
          _parseChange(metadata[i], DocumentViewChangeType.metadata),
        );
      }
      // The order of changes for different documents is not significant: compare them sorted by key.
      int byKey(DocumentViewChange a, DocumentViewChange b) =>
          a.document.key.compareTo(b.document.key);
      expect(
        actual.view!.changes.toList()..sort(byKey),
        expectedChanges..sort(byKey),
      );

      final bool expectedHasPendingWrites =
          expected['hasPendingWrites'] ?? false;
      final bool expectedFromCache = expected['fromCache'] ?? false;
      expect(
        actual.view!.hasPendingWrites,
        expectedHasPendingWrites,
        reason: 'hasPendingWrites',
      );
      expect(actual.view!.isFromCache, expectedFromCache, reason: 'fromCache');
    }
  }

  void _validateStepExpectations(List<dynamic>? stepExpectations) {
    if (stepExpectations == null) {
      for (QueryEvent event in _events) {
        fail('Unexpected event: $event');
      }
      return;
    }

    // Sort both the expected and actual events by the query's canonical ID.
    _events.sort(
      (QueryEvent q1, QueryEvent q2) =>
          q1.query.canonicalId.compareTo(q2.query.canonicalId),
    );

    final List<Map<String, dynamic>> expectedEvents = <Map<String, dynamic>>[];
    for (int i = 0; i < stepExpectations.length; ++i) {
      expectedEvents.add(stepExpectations[i]);
    }
    expectedEvents.sort((
      Map<String, dynamic> left,
      Map<String, dynamic> right,
    ) {
      final Query leftQuery = _parseQuery(left['query']);
      final Query rightQuery = _parseQuery(right['query']);
      return leftQuery.canonicalId.compareTo(rightQuery.canonicalId);
    });

    int i = 0;
    for (; i < expectedEvents.length && i < _events.length; ++i) {
      _assertEventMatches(expectedEvents[i], _events[i]);
    }

    if (i < stepExpectations.length) {
      fail('Missing event: ${stepExpectations[i]}');
    }

    if (i < _events.length) {
      fail('Unexpected event: ${_events[i]}');
    }
  }

  Future<void> _validateStateExpectations(Map<String, dynamic>? expected) async {
    if (expected != null) {
      if (expected.containsKey('isPrimary')) {
        expect(
          _syncEngine.isPrimaryClient,
          expected['isPrimary'],
          reason: 'isPrimary',
        );
      }

      if (expected.containsKey('numActiveClients')) {
        expect(
          (await _localPersistence.getActiveClients()).length,
          expected['numActiveClients'],
          reason: 'numActiveClients',
        );
      }

      if (expected.containsKey('isShutdown')) {
        expect(_isShutdown, expected['isShutdown'], reason: 'isShutdown');
      }

      if (expected.containsKey('numOutstandingWrites')) {
        expect(_writesSent(), expected['numOutstandingWrites']);
      }

      if (expected.containsKey('writeStreamRequestCount')) {
        expect(
          _datastore.writeStreamRequestCount,
          expected['writeStreamRequestCount'],
        );
      }

      if (expected.containsKey('watchStreamRequestCount')) {
        expect(
          _datastore.watchStreamRequestCount,
          expected['watchStreamRequestCount'],
        );
      }

      if (expected.containsKey('indexes')) {
        // Like the JS runner: the configured indexes are compared by collection group and segments, ignoring ids
        // and backfill state.
        final List<FieldIndex> expectedIndexes = <FieldIndex>[
          for (final dynamic index in expected['indexes'] as List<dynamic>)
            _parseExpectedIndex(index as Map<String, dynamic>),
        ]..sort(FieldIndex.semanticCompare);
        // Read in a transaction, like the JS runner (localStoreGetFieldIndexes): it picks up the indexes another client
        // configured on the shared database.
        final List<FieldIndex> actualIndexes = (await _localPersistence
            .runTransactionAndReturn('Get field indexes',
                () async => _localStore.getFieldIndexes()))
          ..sort(FieldIndex.semanticCompare);
        expect(
          actualIndexes.length,
          expectedIndexes.length,
          reason: 'configured indexes: $actualIndexes',
        );
        for (int i = 0; i < expectedIndexes.length; i++) {
          expect(
            FieldIndex.semanticCompare(actualIndexes[i], expectedIndexes[i]),
            0,
            reason: 'expected ${expectedIndexes[i]}, got ${actualIndexes[i]}',
          );
        }
      }

      if (expected.containsKey('activeLimboDocs')) {
        _expectedLimboDocs = <DocumentKey>{};
        final List<dynamic> limboDocs = expected['activeLimboDocs'];
        for (int i = 0; i < limboDocs.length; i++) {
          _expectedLimboDocs.add(key(limboDocs[i]));
        }
      }

      if (expected.containsKey('enqueuedLimboDocs')) {
        _expectedEnqueuedLimboDocs = <DocumentKey>{};
        final List<dynamic> limboDocs = expected['enqueuedLimboDocs'];
        for (int i = 0; i < limboDocs.length; i++) {
          _expectedEnqueuedLimboDocs.add(key(limboDocs[i]));
        }
      }

      if (expected.containsKey('activeTargets')) {
        _expectedActiveTargets = <int, QueryData>{};
        _expectedPurposes = <int, QueryPurpose>{};
        final Map<String, dynamic> activeTargets = expected['activeTargets'];
        final Iterable<String> keys = activeTargets.keys;

        for (String targetIdString in keys) {
          final int targetId = int.parse(targetIdString);
          final Map<String, dynamic> queryDataJson =
              activeTargets[targetIdString];
          // A target can serve several queries; like upstream only the first one is validated.
          final List<dynamic> queries = queryDataJson['queries'];
          final Query query = _parseQuery(queries.first);

          // A target either has a resume token or, when it was resumed from a bundle, only a read time.
          final String resumeToken = queryDataJson['resumeToken'] ?? '';
          final SnapshotVersion snapshotVersion =
              queryDataJson.containsKey('resumeToken')
                  ? SnapshotVersion.none
                  : version(queryDataJson['readTime']);

          // Specs without an explicit purpose expect a plain listen.
          final String? purposeName = queryDataJson['targetPurpose'];
          final QueryPurpose purpose = purposeName != null
              ? _parseQueryPurpose(purposeName)
              : QueryPurpose.listen;
          if (purposeName != null) {
            _expectedPurposes[targetId] = purpose;
          }

          _expectedActiveTargets[targetId] = QueryData(
            query.toTarget(),
            targetId,
            arbitrarySequenceNumber,
            purpose,
            snapshotVersion,
            Uint8List.fromList(utf8.encode(resumeToken)),
            queryDataJson['expectedCount'],
          );
        }
      }
    }

    // A lone client is always primary.
    if (!_spec._isMultiClient) {
      expect(_syncEngine.isPrimaryClient, isTrue, reason: 'isPrimary');
    }
    // Always validate the we received the expected number of events.
    _validateUserCallbacks(expected);
    // Like upstream: a client that was shut down does not reset its limbo documents and targets, do not validate them.
    if (_isShutdown) {
      return;
    }
    // Always validate that the expected limbo docs match the actual limbo docs.
    _validateActiveLimboDocs();
    _validateEnqueuedLimboDocs();
    // Always validate that the expected active targets match the actual active targets.
    _validateActiveTargets();
  }

  void _validateUserCallbacks(Map<String, dynamic>? expected) {
    if (expected != null && expected.containsKey('userCallbacks')) {
      final Map<String, dynamic> userCallbacks = expected['userCallbacks'];

      final List<dynamic> expectedAcknowledgedDocs =
          userCallbacks['acknowledgedDocs'];
      for (int i = 0; i < expectedAcknowledgedDocs.length; i++) {
        final String documentKey = expectedAcknowledgedDocs[i];
        expect(
          _acknowledgedDocs.contains(key(documentKey)),
          isTrue,
          reason: 'Expected acknowledgment for $documentKey',
        );
      }

      final List<dynamic> expectedRejectedDocs = userCallbacks['rejectedDocs'];
      for (int i = 0; i < expectedRejectedDocs.length; i++) {
        final String documentKey = expectedRejectedDocs[i];
        expect(
          _rejectedDocs.contains(key(documentKey)),
          isTrue,
          reason: 'Expected rejection for $documentKey',
        );
      }
    } else {
      expect(_acknowledgedDocs, isEmpty);
      expect(_rejectedDocs, isEmpty);
    }
  }

  void _validateActiveLimboDocs() {
    // Make a copy so it can modified while checking against the expected limbo docs.
    final Map<DocumentKey, int> actualLimboDocs = Map<DocumentKey, int>.from(
      _syncEngine.getActiveLimboDocumentResolutions(),
    );

    // Validate that each limbo doc has an expected active target (as JS, only while the watch stream is open: an
    // offline client keeps its limbo resolutions without active targets).
    if (_datastore.isWatchStreamOpen) {
      for (MapEntry<DocumentKey, int> limboDoc in actualLimboDocs.entries) {
        expect(_expectedActiveTargets.containsKey(limboDoc.value), isTrue);
      }
    }

    for (DocumentKey expectedLimboDoc in _expectedLimboDocs) {
      expect(actualLimboDocs.containsKey(expectedLimboDoc), isTrue);
      actualLimboDocs.remove(expectedLimboDoc);
    }
    expect(actualLimboDocs, isEmpty);
  }

  void _validateEnqueuedLimboDocs() {
    final Set<DocumentKey> actualLimboDocs =
        _syncEngine.getEnqueuedLimboDocumentResolutions().toSet();

    for (DocumentKey key in actualLimboDocs) {
      expect(
        _expectedEnqueuedLimboDocs.contains(key),
        isTrue,
        reason:
            'Found enqueued limbo doc ${key.path.canonicalString}, but it was not in the set of expected enqueued limbo documents ($_expectedEnqueuedLimboDocs)',
      );
    }

    for (DocumentKey key in _expectedEnqueuedLimboDocs) {
      expect(
        actualLimboDocs.contains(key),
        isTrue,
        reason:
            'Expected doc ${key.path.canonicalString} to be enqueued for limbo resolution, but it was not in the queue ($actualLimboDocs)',
      );
    }
  }

  void _validateActiveTargets() {
    // Like upstream: a secondary client does not listen to anything, the primary client listens for it.
    if (!_syncEngine.isPrimaryClient) {
      expect(_datastore.activeTargets, isEmpty);
      return;
    }
    if (!_networkEnabled) {
      return;
    }

    final Map<int, QueryData> actualTargets = _datastore.activeTargets;
    for (MapEntry<int, QueryData> expected in _expectedActiveTargets.entries) {
      // The spec names SDK target ids; the datastore sees the remote target ids the remote store mapped them to.
      final int remoteTargetId = _remoteTargetId(expected.key);
      expect(actualTargets.containsKey(remoteTargetId), isTrue,
          reason: 'Expected active target not found: ${expected.key}');

      final QueryData expectedTarget = expected.value;
      final QueryData? actualTarget = actualTargets[remoteTargetId];

      // TODO(long1eu): validate the purpose of the target once it's possible to encode that in the spec tests. For now,
      //  only validate properties that can be validated.
      // expect(actualTarget, expectedTarget);

      expect(actualTarget!.target, expectedTarget.target);
      expect(actualTarget.targetId, remoteTargetId);
      expect(actualTarget.snapshotVersion, expectedTarget.snapshotVersion);
      expect(
        utf8.decode(actualTarget.resumeToken),
        utf8.decode(expectedTarget.resumeToken),
      );
      if (_expectedPurposes.containsKey(expected.key)) {
        expect(
          actualTarget.purpose,
          expectedTarget.purpose,
          reason: 'purpose of target ${expected.key}',
        );
      }
      if (expectedTarget.expectedCount != null) {
        expect(
          actualTarget.expectedCount,
          expectedTarget.expectedCount,
          reason: 'expectedCount of target ${expected.key}',
        );
      }
      actualTargets.remove(remoteTargetId);
    }

    expect(actualTargets, isEmpty);
  }

  /// Runs one step addressed to this client and validates its expectations against this client (the JS
  /// `TestRunner.run`). Events of this client caused by the steps of other clients are validated with the next step of
  /// this client.
  Future<void> runStep(Map<String, dynamic> step) async {
    final List<dynamic>? expect = step.remove('expectedSnapshotEvents');
    final Map<String, dynamic>? stateExpect = step.remove('expectedState');
    final int expectedSnapshotsInSync =
        step.remove('expectedSnapshotsInSyncEvents') ?? 0;
    final int expectedWaitForPendingWrites =
        step.remove('expectedWaitForPendingWritesEvents') ?? 0;

    log('    Doing step $step');
    await _doStep(step);
    await _drainSharedStateEvents();
    // The Android SDK processes everything synchronously. Here the streams deliver their events asynchronously, so
    // let them settle before validating the expectations.
    await Future<void>.delayed(_delayDuration);

    if (expect != null) {
      log('      Validating step expectations $expect');
    }

    _validateStepExpectations(expect);
    if (stateExpect != null) {
      log('      Validating state expectations $stateExpect');
    }
    await _validateStateExpectations(stateExpect);
    if (_snapshotsInSyncEvents != expectedSnapshotsInSync) {
      fail('Expected $expectedSnapshotsInSync snapshots in sync events but '
          'got $_snapshotsInSyncEvents');
    }
    _snapshotsInSyncEvents = 0;
    if (_waitForPendingWritesEvents != expectedWaitForPendingWrites) {
      fail('Expected $expectedWaitForPendingWrites waitForPendingWrites '
          'events but got $_waitForPendingWritesEvents');
    }
    _waitForPendingWritesEvents = 0;

    _events.clear();
    _acknowledgedDocs.clear();
    _rejectedDocs.clear();
  }

  // RemoteStoreCallback Methods

  @override
  Future<void> handleRemoteEvent(RemoteEvent remoteEvent) async {
    await _syncEngine.handleRemoteEvent(remoteEvent);
  }

  @override
  Future<void> handleRejectedListen(int targetId, GrpcError error) async {
    await _syncEngine.handleRejectedListen(targetId, error);
  }

  @override
  Future<void> handleSuccessfulWrite(
    MutationBatchResult mutationBatchResult,
  ) async {
    await _syncEngine.handleSuccessfulWrite(mutationBatchResult);
  }

  @override
  Future<void> handleRejectedWrite(int batchId, GrpcError error) async {
    await _syncEngine.handleRejectedWrite(batchId, error);
  }

  @override
  ImmutableSortedSet<DocumentKey> Function(int) get getRemoteKeysForTarget =>
      (int targetId) => _syncEngine.getRemoteKeysForTarget(targetId);
}

class Pair<F, S> {
  Pair(this.first, this.second);

  final F first;
  final S second;
}

/// A `FieldValue.increment()` in the data of a spec.
class _SpecIncrement {
  const _SpecIncrement(this.operand);

  final Object? operand;

  NumericIncrementTransformOperation toOperation() {
    final Object? operand = this.operand;
    // PORTING NOTE: like the public API of the Android SDK, the operand of an
    // increment is an integer or a double.
    final num number = operand is Decimal128Value
        ? double.parse(operand.stringValue)
        : operand is String
            ? double.parse(operand)
            : operand! as num;
    return NumericIncrementTransformOperation(wrap(number) as NumberValue);
  }
}
