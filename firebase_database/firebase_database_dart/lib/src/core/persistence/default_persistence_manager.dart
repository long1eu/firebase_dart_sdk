/// The persistence manager over a storage engine. JS: none; Android:
/// `core/persistence/DefaultPersistenceManager.java`.
library;

import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/persistence/cache_policy.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_manager.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_storage_engine.dart';
import 'package:firebase_database_dart/src/core/persistence/prune_forest.dart';
import 'package:firebase_database_dart/src/core/persistence/tracked_query.dart';
import 'package:firebase_database_dart/src/core/persistence/tracked_query_manager.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/user_write_record.dart';
import 'package:firebase_database_dart/src/core/util/clock.dart';
import 'package:firebase_database_dart/src/core/util/logger.dart';
import 'package:firebase_database_dart/src/core/view/cache_node.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:firebase_database_dart/src/core/write_id.dart';

/// A [PersistenceManager] over a storage engine, tracking queries and pruning by a cache policy.
///
/// Android: `DefaultPersistenceManager.java`. Difference: [runInTransaction] rethrows the body's
/// exception as is (after logging it) instead of wrapping it in a `RuntimeException`.
final class DefaultPersistenceManager implements PersistenceManager {
  /// Creates a manager over [storageLayer]; builds its `TrackedQueryManager`, which resets the
  /// previously active tracked queries in a transaction of its own. Android:
  /// `DefaultPersistenceManager(Context, PersistenceStorageEngine, CachePolicy, Clock)`; the
  /// Context's logger is [logger] (Repo's, null: dropped), shared with the tracked queries.
  factory DefaultPersistenceManager(
    PersistenceStorageEngine storageLayer,
    CachePolicy cachePolicy,
    Clock clock, {
    DatabaseLogger? logger,
  }) => DefaultPersistenceManager._(
    storageLayer,
    TrackedQueryManager(storageLayer, clock, logger: logger),
    cachePolicy,
    logger,
  );

  DefaultPersistenceManager._(
    this._storageLayer,
    this._trackedQueryManager,
    this._cachePolicy,
    this._logger,
  );

  /// Android: `DefaultPersistenceManager.logger`.
  final DatabaseLogger? _logger;

  final PersistenceStorageEngine _storageLayer;
  final TrackedQueryManager _trackedQueryManager;
  final CachePolicy _cachePolicy;
  int _serverCacheUpdatesSinceLastPruneCheck = 0;

  /// Android: `DefaultPersistenceManager.saveUserOverwrite`.
  @override
  void saveUserOverwrite(Path path, Node node, WriteId writeId) =>
      _storageLayer.saveUserOverwrite(path, node, writeId);

  /// Android: `DefaultPersistenceManager.saveUserMerge`.
  @override
  void saveUserMerge(Path path, CompoundWrite children, WriteId writeId) =>
      _storageLayer.saveUserMerge(path, children, writeId);

  /// Android: `DefaultPersistenceManager.removeUserWrite`.
  @override
  void removeUserWrite(WriteId writeId) =>
      _storageLayer.removeUserWrite(writeId);

  /// Android: `DefaultPersistenceManager.removeAllUserWrites`.
  @override
  void removeAllUserWrites() => _storageLayer.removeAllUserWrites();

  /// Android: `DefaultPersistenceManager.applyUserWriteToServerCache(Path, Node)`.
  @override
  void applyUserWriteToServerCache(Path path, Node node) {
    // Android's guess: an active default query at [path] already received this write's data from
    // the server. Otherwise the write is cached by hand with a complete tracked query to keep it.
    // The guess can be wrong (a filtered query got the update, or a server value resolved
    // differently), as Android notes.
    if (!_trackedQueryManager.hasActiveDefaultQuery(path)) {
      _storageLayer.overwriteServerCache(path, node);
      _trackedQueryManager.ensureCompleteTrackedQuery(path);
    }
  }

  /// Android: `DefaultPersistenceManager.applyUserWriteToServerCache(Path, CompoundWrite)`.
  @override
  void applyUserMergeToServerCache(Path path, CompoundWrite merge) {
    for (final MapEntry<Path, Node> write in merge.entries) {
      applyUserWriteToServerCache(path.childPath(write.key), write.value);
    }
  }

  /// Android: `DefaultPersistenceManager.loadUserWrites`.
  @override
  List<UserWriteRecord> loadUserWrites() => _storageLayer.loadUserWrites();

  /// The cached node at the query's path; the query decides completeness and, for a filtered
  /// query or a partly known path, which children are served. Android:
  /// `DefaultPersistenceManager.serverCache`.
  @override
  CacheNode serverCache(QuerySpec query) {
    Set<ChildKey>? trackedKeys;
    final bool complete;
    if (_trackedQueryManager.isQueryComplete(query)) {
      complete = true;
      final TrackedQuery? trackedQuery = _trackedQueryManager.findTrackedQuery(
        query,
      );
      if (!query.loadsAllData &&
          trackedQuery != null &&
          trackedQuery.complete) {
        trackedKeys = _storageLayer.loadTrackedQueryKeys(<int>{
          trackedQuery.id,
        });
      } else {
        trackedKeys = null;
      }
    } else {
      complete = false;
      trackedKeys = _trackedQueryManager.getKnownCompleteChildren(query.path);
    }

    final Node serverCacheNode = _storageLayer.serverCache(query.path);
    if (trackedKeys != null) {
      Node filteredNode = ChildrenNode.empty;
      for (final ChildKey key in trackedKeys) {
        filteredNode = filteredNode.updateImmediateChild(
          key,
          serverCacheNode.getImmediateChild(key),
        );
      }
      return CacheNode(
        filteredNode,
        fullyInitialized: complete,
        filtered: true,
      );
    }
    return CacheNode(
      serverCacheNode,
      fullyInitialized: complete,
      filtered: false,
    );
  }

  /// Android: `DefaultPersistenceManager.updateServerCache(QuerySpec, Node)`.
  @override
  void updateServerCache(QuerySpec query, Node node) {
    if (query.loadsAllData) {
      _storageLayer.overwriteServerCache(query.path, node);
    } else {
      _storageLayer.mergeIntoServerCache(query.path, node);
    }
    setQueryComplete(query);
    _doPruneCheckAfterServerUpdate();
  }

  /// Android: `DefaultPersistenceManager.updateServerCache(Path, CompoundWrite)`.
  @override
  void updateServerCacheWithMerge(Path path, CompoundWrite children) {
    _storageLayer.mergeIntoServerCacheWrite(path, children);
    _doPruneCheckAfterServerUpdate();
  }

  /// Android: `DefaultPersistenceManager.setQueryActive`.
  @override
  void setQueryActive(QuerySpec query) =>
      _trackedQueryManager.setQueryActive(query);

  /// Android: `DefaultPersistenceManager.setQueryInactive`.
  @override
  void setQueryInactive(QuerySpec query) =>
      _trackedQueryManager.setQueryInactive(query);

  /// Android: `DefaultPersistenceManager.setQueryComplete`.
  @override
  void setQueryComplete(QuerySpec query) {
    if (query.loadsAllData) {
      _trackedQueryManager.setQueriesComplete(query.path);
    } else {
      _trackedQueryManager.setQueryCompleteIfExists(query);
    }
  }

  /// Android: `DefaultPersistenceManager.setTrackedQueryKeys`.
  @override
  void setTrackedQueryKeys(QuerySpec query, Set<ChildKey> keys) {
    final TrackedQuery trackedQuery = _activeFilteredTrackedQuery(query);
    _storageLayer.saveTrackedQueryKeys(trackedQuery.id, keys);
  }

  /// Android: `DefaultPersistenceManager.updateTrackedQueryKeys`.
  @override
  void updateTrackedQueryKeys(
    QuerySpec query,
    Set<ChildKey> added,
    Set<ChildKey> removed,
  ) {
    final TrackedQuery trackedQuery = _activeFilteredTrackedQuery(query);
    _storageLayer.updateTrackedQueryKeys(trackedQuery.id, added, removed);
  }

  TrackedQuery _activeFilteredTrackedQuery(QuerySpec query) {
    if (query.loadsAllData) {
      throw StateError('We should only track keys for filtered queries.');
    }
    final TrackedQuery? trackedQuery = _trackedQueryManager.findTrackedQuery(
      query,
    );
    if (trackedQuery == null || !trackedQuery.active) {
      throw StateError(
        'We only expect tracked keys for currently-active queries.',
      );
    }
    return trackedQuery;
  }

  /// The storage engine's `isDurable`. Android: none (always durable there).
  @override
  bool get isDurable => _storageLayer.isDurable;

  /// One storage transaction around [body]; committed only when [body] returns. Android:
  /// `DefaultPersistenceManager.runInTransaction`.
  @override
  T runInTransaction<T>(T Function() body) {
    _storageLayer.beginTransaction();
    try {
      final T result = body();
      _storageLayer.setTransactionSuccessful();
      return result;
    } on Object catch (e) {
      _logger?.call(DatabaseLogLevel.error, 'Caught Throwable. $e');
      rethrow;
    } finally {
      _storageLayer.endTransaction();
    }
  }

  void _doPruneCheckAfterServerUpdate() {
    _serverCacheUpdatesSinceLastPruneCheck++;
    if (!_cachePolicy.shouldCheckCacheSize(
      _serverCacheUpdatesSinceLastPruneCheck,
    )) {
      return;
    }
    _logger?.call(DatabaseLogLevel.debug, 'Reached prune check threshold.');
    _serverCacheUpdatesSinceLastPruneCheck = 0;
    bool canPrune = true;
    int cacheSize = _storageLayer.serverCacheEstimatedSizeInBytes();
    _logger?.call(DatabaseLogLevel.debug, 'Cache size: $cacheSize');
    while (canPrune &&
        _cachePolicy.shouldPrune(
          cacheSize,
          _trackedQueryManager.countOfPrunableQueries(),
        )) {
      final PruneForest pruneForest = _trackedQueryManager.pruneOldQueries(
        _cachePolicy,
      );
      if (pruneForest.prunesAnything()) {
        _storageLayer.pruneCache(Path.empty, pruneForest);
      } else {
        canPrune = false;
      }
      cacheSize = _storageLayer.serverCacheEstimatedSizeInBytes();
      _logger?.call(
        DatabaseLogLevel.debug,
        'Cache size after prune: $cacheSize',
      );
    }
  }
}
