/// The engine of one database: writes, listens, transactions, onDisconnect, `.info`, and the
/// glue between the connection and the sync trees. JS: `core/Repo.ts`; Android: `core/Repo.java`.
///
/// The class body holds the public entry points; the work is split over part files by topic:
/// `repo_server_actions.dart` (the connection's delegate calls and `.info`), `repo_get.dart`
/// (`get`), `repo_transactions.dart` (the transaction queue tree), `repo_on_disconnect.dart`
/// (onDisconnect), `repo_listen_providers.dart` (the two listen providers) and
/// `repo_values.dart` (number normalisation of user values).
///
/// Differences from Android and JS, each on purpose:
///
/// * Events go to one [EventDispatcher] per Repo and are never raised inside the call; write and
///   transaction completions go through the same queue, after their events (Android posts both
///   to one event target).
/// * The events of a server update or an ack are queued before the transactions they touch are
///   rerun, as contract rule 4.2 requires (changes arrive in the order applied); Android and JS
///   rerun first and so raise the update's older events after the rerun's newer ones.
/// * `get` follows contract C25: no timer while connected, a 3 s wait for a connection while
///   disconnected, a refusal never answered from the cache.
library;

import 'dart:async';

import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/connection/listen_hash_provider.dart';
import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:firebase_database_dart/src/core/connection/wire_range_merge.dart';
import 'package:firebase_database_dart/src/core/database_error.dart';
import 'package:firebase_database_dart/src/core/event_registration.dart';
import 'package:firebase_database_dart/src/core/listen_provider.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/persistence/noop_persistence_manager.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_manager.dart';
import 'package:firebase_database_dart/src/core/repo_info.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/priority_index.dart';
import 'package:firebase_database_dart/src/core/snap/leaf_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/snap/range_merge.dart';
import 'package:firebase_database_dart/src/core/snapshot_holder.dart';
import 'package:firebase_database_dart/src/core/sparse_snapshot_tree.dart';
import 'package:firebase_database_dart/src/core/sync_tree.dart';
import 'package:firebase_database_dart/src/core/sync_tree_api.dart';
import 'package:firebase_database_dart/src/core/tag.dart';
import 'package:firebase_database_dart/src/core/transaction_data.dart';
import 'package:firebase_database_dart/src/core/user_write_record.dart';
import 'package:firebase_database_dart/src/core/util/clock.dart';
import 'package:firebase_database_dart/src/core/util/logger.dart';
import 'package:firebase_database_dart/src/core/util/numbers.dart';
import 'package:firebase_database_dart/src/core/util/server_values.dart'
    as server_values;
import 'package:firebase_database_dart/src/core/util/tree.dart';
import 'package:firebase_database_dart/src/core/view/change.dart';
import 'package:firebase_database_dart/src/core/view/event.dart';
import 'package:firebase_database_dart/src/core/view/event_dispatcher.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:firebase_database_dart/src/core/write_id.dart';
import 'package:meta/meta.dart';

part 'repo_get.dart';
part 'repo_listen_providers.dart';
part 'repo_on_disconnect.dart';
part 'repo_server_actions.dart';
part 'repo_transactions.dart';
part 'repo_values.dart';

/// Called once when a write, update or onDisconnect request finishes: [error] null on success.
typedef WriteCompletion = void Function(DatabaseError? error);

/// Creates the connection for a Repo; the connection team supplies it (tests pass a
/// `FakeServerActions`). The connection gets its token source from the factory's closure, not
/// from Repo, and logs through [logger] (null: dropped).
typedef ServerActionsFactory =
    ServerActions Function(
      ServerActionsDelegate delegate,
      DatabaseLogger? logger,
    );

/// How long a `get` waits for the server before answering from the persisted cache when
/// persistence is on (Android `Repo.java:64`). Runs on a plain `Timer`, so `fake_async` drives it.
const Duration getPersistedFallbackDelay = Duration(seconds: 3);

/// The interrupt reason of goOffline/goOnline.
const String interruptReason = 'repo_interrupt';

/// One database's engine.
///
/// It owns two sync trees: the server tree (listening through [connection], persisting through
/// the given [PersistenceManager]) and the `.info` tree (local only, always a
/// [NoopPersistenceManager]). It is the [ServerActionsDelegate] of its connection. Every user
/// write gets the next write id; sends go to the connection with paths as `/a/b` strings and
/// unresolved export-form JSON; local events use data with server values resolved against
/// [serverClock].
final class Repo implements ServerActionsDelegate {
  /// Creates the Repo for [repoInfo] and builds its connection with [connectionFactory].
  ///
  /// The start order lives here: load the persisted user writes from [persistenceManager],
  /// [restoreWrites] them, and only then `connection.initialize()`. A user write made before the
  /// restore would reuse a restored write id.
  ///
  /// Events go to [dispatcher] (a fresh [EventDispatcher] by default, one per Repo); messages go
  /// to [logger] (null: dropped), which is also handed to the connection.
  ///
  /// Android `Repo(RepoInfo, Context, FirebaseDatabase)` plus `deferredInitialization`; JS
  /// `new Repo` plus `repoStart`.
  factory Repo({
    required RepoInfo repoInfo,
    required ServerActionsFactory connectionFactory,
    PersistenceManager? persistenceManager,
    Clock? clock,
    EventDispatcher? dispatcher,
    DatabaseLogger? logger,
  }) {
    final Repo repo = Repo._(
      repoInfo,
      persistenceManager ?? NoopPersistenceManager(),
      ServerClock(clock ?? DateTime.now),
      dispatcher ?? EventDispatcher(),
      logger,
    );
    repo._connection = connectionFactory(repo, logger);
    final InfoListenProvider infoProvider = InfoListenProvider(
      repo._infoData,
      repo._post,
    );
    final SyncTree infoTree = SyncTree(listenProvider: infoProvider);
    infoProvider.syncTree = infoTree;
    repo._infoSyncTree = infoTree;
    repo._serverSyncTree = SyncTree(
      listenProvider: RepoListenProvider(
        repo._connection,
        repo._post,
        logger: logger,
      ),
      persistenceManager: repo._persistenceManager,
    );
    if (repoInfo.isDemoHost) {
      repo._log(
        DatabaseLogLevel.warning,
        'This is a demo database host (*.firebaseio-demo.com): data in it may be deleted at '
        'any time.',
      );
    }
    repo.restoreWrites();
    repo._updateInfo('authenticated', false);
    repo._updateInfo('connected', false);
    repo._connection.initialize();
    return repo;
  }

  Repo._(
    this._repoInfo,
    this._persistenceManager,
    this._serverClock,
    this._dispatcher,
    this._logger,
  );

  final RepoInfo _repoInfo;
  final PersistenceManager _persistenceManager;
  final ServerClock _serverClock;
  final EventDispatcher _dispatcher;
  final DatabaseLogger? _logger;
  late final ServerActions _connection;
  late final SyncTreeApi _serverSyncTree;
  late final SyncTreeApi _infoSyncTree;
  final SnapshotHolder _infoData = SnapshotHolder();

  /// The acknowledged onDisconnect writes, applied locally on disconnect (Android
  /// `Repo.onDisconnect`).
  SparseSnapshotTree _onDisconnect = SparseSnapshotTree();

  WriteId _nextWriteId = 1;
  int _dataUpdateCount = 0;
  bool _connected = false;
  bool _closed = false;
  bool _hijackHash = false;
  bool _loggedTransactionPersistenceWarning = false;

  /// The transaction queues by path (Android `Repo.transactionQueueTree`).
  final Tree<List<TransactionData>> _transactionQueueTree =
      Tree<List<TransactionData>>();
  int _transactionOrder = 0;

  /// The `get` requests still waiting for an answer.
  final Set<_PendingGet> _pendingGets = <_PendingGet>{};

  /// The completions of write and onDisconnect requests not answered yet, failed by [close].
  final Map<int, WriteCompletion> _pendingCompletions =
      <int, WriteCompletion>{};
  int _nextCompletionId = 0;

  /// The registrations added through [addEventCallback], cancelled by [close].
  final List<EventRegistration> _registrations = <EventRegistration>[];

  /// The queries the user keeps synced (the `get` bracket leaves them alone).
  final Set<QuerySpec> _keptSynced = <QuerySpec>{};

  /// Where the database is (Android `Repo.getRepoInfo`).
  RepoInfo get repoInfo => _repoInfo;

  /// The connection (Android `Repo.getConnection`).
  ServerActions get connection => _connection;

  /// The server data tree (Android `Repo.getServerSyncTree`).
  SyncTreeApi get serverSyncTree => _serverSyncTree;

  /// The `.info` tree (Android `Repo.getInfoSyncTree`).
  SyncTreeApi get infoSyncTree => _infoSyncTree;

  /// The `.info` data (`connected`, `serverTimeOffset`; Android `Repo.infoData`).
  SnapshotHolder get infoData => _infoData;

  /// The local clock plus the server time offset (Android `Repo.serverClock`).
  ServerClock get serverClock => _serverClock;

  /// The number of server data updates received (for tests; Android `Repo.dataUpdateCount`).
  int get dataUpdateCount => _dataUpdateCount;

  /// The estimated server time in milliseconds (Android `Repo.getServerTime`; JS
  /// `repoServerTime`).
  int serverTime() => _serverClock.nowMillis();

  /// The values server values resolve to now (Android `ServerValues.generateServerValues`; JS
  /// `generateWithValues`).
  Map<String, Object?> generateServerValues() =>
      server_values.generateServerValues(timestamp: serverTime());

  /// Overwrites [path] with [newValue] (unresolved; export form is sent), raises local events,
  /// aborts transactions below [path] with `set`, and calls [onComplete] on the server's answer.
  ///
  /// Numbers are normalised with `normalizeUserNumber` first. Server values resolve against the
  /// existing data (JS `repoSetWithPriority`, `resolveDeferredValueTree`). Android `Repo.setValue`.
  void setValue(Path path, Node newValue, {WriteCompletion? onComplete}) {
    if (_closed) {
      return _failClosed(onComplete);
    }
    _log(DatabaseLogLevel.debug, 'set: $path');
    final Node value = _normalizeUserNode(newValue);
    final Node resolved = server_values.resolveDeferredValueTree(
      path,
      value,
      _calcCompleteEventCache,
      generateServerValues(),
    );
    final WriteId writeId = _nextWriteId++;
    _post(
      _serverSyncTree.applyUserOverwrite(
        path,
        value,
        resolved,
        writeId,
        visible: true,
        persist: true,
      ),
    );
    final int completion = _track(onComplete);
    _connection.put(
      path.toString(),
      value.toJson(exportFormat: true),
      onComplete: (String status, Object? data) {
        if (_closed) {
          return;
        }
        final DatabaseError? error = _errorFor(status, data);
        _warnIfWriteFailed('setValue', path, error);
        _ackWriteAndRerunTransactions(writeId, path, error);
        _complete(completion, error);
      },
    );
    final Path affectedPath = _abortTransactions(
      path,
      DatabaseErrorCode.overriddenBySet,
    );
    _rerunTransactions(affectedPath);
  }

  /// Merges [updates] (relative paths) into [path]; [unparsedUpdates] is the caller's JSON sent
  /// as is. An empty update completes at once without a request.
  ///
  /// Numbers are normalised in both forms first. Android `Repo.updateChildren`; JS `repoUpdate`.
  void updateChildren(
    Path path,
    CompoundWrite updates,
    Map<String, Object?> unparsedUpdates, {
    WriteCompletion? onComplete,
  }) {
    if (_closed) {
      return _failClosed(onComplete);
    }
    _log(DatabaseLogLevel.debug, 'update: $path');
    if (updates.isEmpty) {
      _log(DatabaseLogLevel.debug, 'update called with no changes. No-op');
      if (onComplete != null) {
        scheduleMicrotask(() => onComplete(null));
      }
      return;
    }
    CompoundWrite normalized = CompoundWrite.empty;
    for (final MapEntry<Path, Node> entry in updates.entries) {
      normalized = normalized.addWrite(
        entry.key,
        _normalizeUserNode(entry.value),
      );
    }
    final CompoundWrite resolved = server_values.resolveDeferredValueMerge(
      normalized,
      path,
      _calcCompleteEventCache,
      generateServerValues(),
    );
    final WriteId writeId = _nextWriteId++;
    _post(
      _serverSyncTree.applyUserMerge(
        path,
        normalized,
        resolved,
        writeId,
        persist: true,
      ),
    );
    final int completion = _track(onComplete);
    _connection.merge(
      path.toString(),
      _normalizeUserJson(unparsedUpdates)! as Map<String, Object?>,
      onComplete: (String status, Object? data) {
        if (_closed) {
          return;
        }
        final DatabaseError? error = _errorFor(status, data);
        _warnIfWriteFailed('updateChildren', path, error);
        _ackWriteAndRerunTransactions(writeId, path, error);
        _complete(completion, error);
      },
    );
    for (final MapEntry<Path, Node> entry in normalized.entries) {
      final Path affectedPath = _abortTransactions(
        path.childPath(entry.key),
        DatabaseErrorCode.overriddenBySet,
      );
      _rerunTransactions(affectedPath);
    }
  }

  /// The value of [query]: from an active listen when complete, else a server `get` (while
  /// offline, the persisted cache, after [getPersistedFallbackDelay] without an answer), with a
  /// short keepSynced bracket so the result is cached.
  ///
  /// Android `Repo.getValue`; JS `repoGetValue`; the waiting rules are contract C25 (see
  /// `repo_get.dart`).
  Future<Node> getValue(QuerySpec query) => _getValue(query);

  /// Registers an onDisconnect overwrite of [path] with [newValue] and remembers it locally.
  /// Android `Repo.onDisconnectSetValue`; JS `repoOnDisconnectSet`.
  void onDisconnectSetValue(
    Path path,
    Node newValue, {
    WriteCompletion? onComplete,
  }) => _onDisconnectSetValue(path, newValue, onComplete);

  /// Registers an onDisconnect merge into [path]. Android `Repo.onDisconnectUpdate`; JS
  /// `repoOnDisconnectUpdate`.
  void onDisconnectUpdate(
    Path path,
    Map<Path, Node> newChildren,
    Map<String, Object?> unparsedUpdates, {
    WriteCompletion? onComplete,
  }) => _onDisconnectUpdate(path, newChildren, unparsedUpdates, onComplete);

  /// Cancels the onDisconnect operations at and below [path]. Android `Repo.onDisconnectCancel`;
  /// JS `repoOnDisconnectCancel`.
  void onDisconnectCancel(Path path, {WriteCompletion? onComplete}) =>
      _onDisconnectCancel(path, onComplete);

  /// Adds a listener; `.info` queries go to the info tree. After [close] the registration gets a
  /// `database-closed` cancel instead. Android `Repo.addEventCallback`; JS
  /// `repoAddEventCallbackForQuery`.
  void addEventCallback(EventRegistration registration) {
    if (_closed) {
      _post(<Event>[
        CancelEvent(registration, _closedError(), registration.querySpec.path),
      ]);
      return;
    }
    _registrations
      ..removeWhere((EventRegistration r) => r.isZombied)
      ..add(registration);
    _post(
      _isInfo(registration.querySpec.path)
          ? _infoSyncTree.addEventRegistration(registration)
          : _serverSyncTree.addEventRegistration(registration),
    );
  }

  /// Removes a listener. Android `Repo.removeEventCallback`; JS
  /// `repoRemoveEventCallbackForQuery`.
  void removeEventCallback(EventRegistration registration) {
    if (_closed) {
      return;
    }
    final int index = _registrations.indexWhere(
      (EventRegistration r) =>
          r.querySpec == registration.querySpec &&
          r.isSameListener(registration),
    );
    if (index != -1) {
      _registrations.removeAt(index);
    }
    _post(
      _isInfo(registration.querySpec.path)
          ? _infoSyncTree.removeEventRegistration(registration)
          : _serverSyncTree.removeEventRegistration(registration),
    );
  }

  /// Keeps [query] synced (or stops). Android `Repo.keepSynced`.
  void keepSynced(
    QuerySpec query, {
    required bool keep,
    bool skipDedup = false,
  }) {
    if (_closed) {
      return;
    }
    if (_isInfo(query.path)) {
      throw ArgumentError.value(
        query.path.toString(),
        'query',
        'keepSynced is not allowed on .info paths',
      );
    }
    if (keep) {
      _keptSynced.add(query);
    } else {
      _keptSynced.remove(query);
    }
    _serverSyncTree.keepSynced(query, keep: keep, skipDedup: skipDedup);
  }

  /// goOffline: interrupts the connection with [interruptReason]; waiting `get` requests answer
  /// from the cache at once (contract C25 rule 3). Android `Repo.interrupt`; JS `repoInterrupt`.
  void interrupt() {
    if (_closed) {
      return;
    }
    _connection.interrupt(interruptReason);
    for (final _PendingGet request in _pendingGets.toList()) {
      _answerGetFromCache(request);
    }
  }

  /// goOnline: resumes the connection. Android `Repo.resume`; JS `repoResume`.
  void resume() {
    if (_closed) {
      return;
    }
    _connection.resume(interruptReason);
  }

  /// Cancels every pending write: the connection drops them (`write_canceled`), the sync tree
  /// reverts them, and transactions abort. Android `Repo.purgeOutstandingWrites`.
  void purgeOutstandingWrites() {
    if (_closed) {
      return;
    }
    _log(DatabaseLogLevel.debug, 'Purging writes');
    _post(_serverSyncTree.removeAllWrites());
    _abortTransactions(Path.empty, DatabaseErrorCode.writeCanceled);
    _connection.purgeOutstandingWrites();
  }

  /// Starts a transaction at [path]: watches the path, runs [update] on the latest local value,
  /// sends a put with the hash of the input, reruns on `datastale` (up to
  /// [maxTransactionRetries]), aborts on a disconnect, and calls [onComplete] once.
  ///
  /// Android `Repo.startTransaction`; JS `repoStartTransaction`. The first run happens inside
  /// this call, as in both; its events and callback are queued, never delivered in the call.
  void startTransaction(
    Path path,
    TransactionUpdate update, {
    TransactionCompletion? onComplete,
    bool applyLocally = true,
  }) => _startTransaction(path, update, onComplete, applyLocally);

  /// Replays the persisted writes into the server tree (unpersisted) and re-sends them in
  /// write-id order; called by the factory before the connection starts, never by users.
  /// Android `Repo.restoreWrites`.
  @visibleForTesting
  void restoreWrites() {
    final List<UserWriteRecord> writes = List<UserWriteRecord>.of(
      _persistenceManager.loadUserWrites(),
    )..sort((UserWriteRecord a, UserWriteRecord b) => a.writeId - b.writeId);
    final Map<String, Object?> serverValues = generateServerValues();
    for (final UserWriteRecord write in writes) {
      if (write.writeId >= _nextWriteId) {
        _nextWriteId = write.writeId + 1;
      }
      void onComplete(String status, Object? data) {
        if (_closed) {
          return;
        }
        final DatabaseError? error = _errorFor(status, data);
        _warnIfWriteFailed('Persisted write', write.path, error);
        _ackWriteAndRerunTransactions(write.writeId, write.path, error);
      }

      final Node? overwrite = write.overwrite;
      if (overwrite != null) {
        _log(
          DatabaseLogLevel.debug,
          'Restoring overwrite with id ${write.writeId}',
        );
        _connection.put(
          write.path.toString(),
          overwrite.toJson(exportFormat: true),
          onComplete: onComplete,
        );
        final Node resolved = server_values.resolveDeferredValueTree(
          write.path,
          overwrite,
          _calcCompleteEventCache,
          serverValues,
        );
        _serverSyncTree.applyUserOverwrite(
          write.path,
          overwrite,
          resolved,
          write.writeId,
          visible: true,
          persist: false,
        );
      } else {
        final CompoundWrite merge = write.merge!;
        _log(
          DatabaseLogLevel.debug,
          'Restoring merge with id ${write.writeId}',
        );
        _connection.merge(
          write.path.toString(),
          merge.toJson(exportFormat: true),
          onComplete: onComplete,
        );
        final CompoundWrite resolved = server_values.resolveDeferredValueMerge(
          merge,
          write.path,
          _calcCompleteEventCache,
          serverValues,
        );
        _serverSyncTree.applyUserMerge(
          write.path,
          merge,
          resolved,
          write.writeId,
          persist: false,
        );
      }
    }
  }

  /// For tests: send a wrong hash with transaction puts (Android `Repo.setHijackHash`).
  // The method is the skeleton's signature (Android's name).
  // ignore: use_setters_to_change_properties
  void setHijackHash(bool hijackHash) => _hijackHash = hijackHash;

  /// Shuts the connection down (awaiting [ServerActions.shutdown]) and drops listeners; later
  /// calls fail.
  ///
  /// Order (contract C3): every registration gets a `database-closed` cancel, synchronously
  /// inside this call so events still queued for it are dropped (the one place a listener runs
  /// inside a Repo call), then pending writes, transactions and gets fail with
  /// `database-closed` (gets through the connection's shutdown, which fails them with
  /// `database_closed`), then the Future completes. Idempotent. JS `repoInterrupt` plus
  /// `Database._delete`; Android has no equivalent.
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    for (final _PendingGet request in _pendingGets) {
      request.timer?.cancel();
      request.timer = null;
    }
    final DatabaseError error = _closedError();
    // Synchronously, before anything queued can be delivered: the cancel is the last thing each
    // registration gets.
    final List<EventRegistration> registrations = List<EventRegistration>.of(
      _registrations,
    );
    _registrations.clear();
    for (final EventRegistration registration in registrations) {
      try {
        registration.fireCancelEvent(error);
      } on Object catch (e, s) {
        Zone.current.handleUncaughtError(e, s);
      }
      registration.zombify();
    }
    await _connection.shutdown();
    final List<WriteCompletion> completions = _pendingCompletions.values
        .toList();
    _pendingCompletions.clear();
    for (final WriteCompletion completion in completions) {
      completion(error);
    }
    // Outstanding gets are failed by the connection's shutdown (`database_closed`).
    _failAllTransactions(error);
  }

  /// A server data push (Android `Repo.onDataUpdate`; JS `repoOnDataUpdate`).
  @override
  void onDataUpdate(
    String path,
    Object? data, {
    required bool isMerge,
    int? tag,
  }) => _onDataUpdate(path, data, isMerge: isMerge, tag: tag);

  /// A range merge push (Android `Repo.onRangeMergeUpdate`).
  @override
  void onRangeMergeUpdate(
    String path,
    List<WireRangeMerge> merges, {
    int? tag,
  }) => _onRangeMergeUpdate(path, merges, tag: tag);

  /// The connection is up: `.info/connected` becomes true and waiting `get` requests stop their
  /// timers (Android `Repo.onConnect`; JS `repoOnConnectStatus`).
  @override
  void onConnect() => _onConnect();

  /// The connection is lost: `.info/connected` becomes false, the onDisconnect writes apply
  /// locally, and waiting `get` requests start their 3 s wait (Android `Repo.onDisconnect`; JS
  /// `repoOnConnectStatus`, `repoRunOnDisconnectEvents`).
  @override
  void onDisconnect() => _onDisconnected();

  /// The auth status: `.info/authenticated` (Android `Repo.onConnectionStatus`); a revoke is
  /// logged.
  @override
  void onAuthStatus(String status, {String? explanation}) =>
      _onAuthStatus(status, explanation);

  /// The App Check status; a revoke is logged (JS `PersistentConnection` logs it).
  @override
  void onAppCheckStatus(String status, {String? explanation}) =>
      _onAppCheckStatus(status, explanation);

  /// The server shut this client down; logged (JS `PersistentConnection.onKill_`).
  @override
  void onServerShutdown(String reason) => _log(
    DatabaseLogLevel.warning,
    'The server shut this client down: $reason',
  );

  /// Server info changed: written to `.info/<key>`, `serverTimeOffset` also to [serverClock]
  /// (Android `Repo.onServerInfoUpdate`; JS `repoOnServerInfoUpdate`).
  @override
  void onServerInfoUpdate(Map<String, Object?> updates) {
    for (final MapEntry<String, Object?> entry in updates.entries) {
      _updateInfo(entry.key, entry.value);
    }
  }

  // Helpers shared by the parts.

  void _post(List<Event> events) {
    if (events.isNotEmpty) {
      _dispatcher.enqueue(events);
    }
  }

  void _log(DatabaseLogLevel level, String message) =>
      _logger?.call(level, message);

  Node? _calcCompleteEventCache(Path path, List<WriteId> writeIdsToExclude) =>
      _serverSyncTree.calcCompleteEventCache(
        path,
        writeIdsToExclude: writeIdsToExclude,
      );

  static bool _isInfo(Path path) => path.front?.name == ChildKey.info.name;

  static DatabaseError _closedError() =>
      DatabaseError.fromStatus(DatabaseErrorCode.databaseClosed.wireStatus);

  /// The error of a request [status] (null for `ok`) with the reason in [data] (Android
  /// `Repo.fromErrorCode`).
  static DatabaseError? _errorFor(String status, Object? data) =>
      status == statusOk
      ? null
      : DatabaseError.fromStatus(status, data is String ? data : null);

  void _failClosed(WriteCompletion? onComplete) {
    if (onComplete != null) {
      final DatabaseError error = _closedError();
      scheduleMicrotask(() => onComplete(error));
    }
  }

  int _track(WriteCompletion? onComplete) {
    if (onComplete == null) {
      return -1;
    }
    final int id = _nextCompletionId++;
    _pendingCompletions[id] = onComplete;
    return id;
  }

  /// Calls the completion [id] with [error] through the event queue, after the events already
  /// queued (Android `Repo.callOnComplete` posts it to the event target).
  void _complete(int id, DatabaseError? error) {
    final WriteCompletion? completion = _pendingCompletions.remove(id);
    if (completion != null) {
      _postCallback(() => completion(error));
    }
  }

  /// Queues [callback] behind the events already queued, so a completion never overtakes the
  /// events of its own change (Android `Repo.postEvent`; JS raises events synchronously first).
  void _postCallback(void Function() callback) => _post(<Event>[
    DataEvent(
      EventType.value,
      _CallbackRegistration(callback),
      Path.empty,
      ChildrenNode.empty,
    ),
  ]);

  /// Android `Repo.warnIfWriteFailed`: `datastale` and `write_canceled` are expected.
  void _warnIfWriteFailed(String writeType, Path path, DatabaseError? error) {
    if (error != null &&
        error.code != DatabaseErrorCode.dataStale &&
        error.code != DatabaseErrorCode.writeCanceled) {
      _log(DatabaseLogLevel.warning, '$writeType at $path failed: $error');
    }
  }

  /// Android `Repo.ackWriteAndRerunTransactions`; the events are queued before the rerun.
  void _ackWriteAndRerunTransactions(
    WriteId writeId,
    Path path,
    DatabaseError? error,
  ) {
    if (error?.code == DatabaseErrorCode.writeCanceled) {
      // purgeOutstandingWrites already removed the write.
      return;
    }
    final List<Event> events = _serverSyncTree.ackUserWrite(
      writeId,
      revert: error != null,
      persist: true,
      serverValues: generateServerValues(),
    );
    _post(events);
    if (events.isNotEmpty) {
      _rerunTransactions(path);
    }
  }
}

/// Carries a completion callback through the [EventDispatcher] as a data event, so callbacks
/// keep their place in the one FIFO (Android posts them to the same event target as events).
final class _CallbackRegistration extends EventRegistration {
  _CallbackRegistration(this._callback);

  final void Function() _callback;

  @override
  QuerySpec get querySpec => QuerySpec.defaultAt(Path.empty);

  @override
  bool respondsTo(EventType type) => false;

  @override
  DataEvent createEvent(Change change, QuerySpec query) =>
      throw StateError('A callback registration raises no events');

  @override
  void fireEvent(DataEvent event) => _callback();

  @override
  void fireCancelEvent(DatabaseError error) {}

  @override
  EventRegistration clone(QuerySpec newQuery) => this;

  @override
  bool isSameListener(EventRegistration other) => identical(other, this);
}
