/// Bookkeeping of tracked queries. JS: none; Android: `core/persistence/TrackedQueryManager.java`.
library;

import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/persistence/cache_policy.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_storage_engine.dart';
import 'package:firebase_database_dart/src/core/persistence/prune_forest.dart';
import 'package:firebase_database_dart/src/core/persistence/tracked_query.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/util/clock.dart';
import 'package:firebase_database_dart/src/core/util/immutable_tree.dart';
import 'package:firebase_database_dart/src/core/view/query_params.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';

/// Keeps the tracked queries in memory and in the storage engine: activity, completeness, pruning.
///
/// Owns the one-id-per-query rule: it hands out ids (one above the largest loaded) and keeps one
/// record per normalized query, asserting that a cached record keeps its id (Android
/// `TrackedQueryManager.java:398-399`, `cacheTrackedQuery`). A violation is a [StateError] here;
/// storage engines are not required to check it.
final class TrackedQueryManager {
  /// Resets the previously active tracked queries of [storageLayer] in a transaction of its own,
  /// then loads them; a loaded query that repeats another query's spec under a different id is a
  /// [StateError] (Android `TrackedQueryManager.java:97-124`).
  factory TrackedQueryManager(
    PersistenceStorageEngine storageLayer,
    Clock clock,
  ) {
    final TrackedQueryManager manager = TrackedQueryManager._(
      storageLayer,
      clock,
    );
    manager._resetPreviouslyActiveTrackedQueries();
    // Populate the in-memory cache from the storage layer.
    for (final TrackedQuery query in storageLayer.loadTrackedQueries()) {
      if (query.id + 1 > manager._currentQueryId) {
        manager._currentQueryId = query.id + 1;
      }
      manager._cacheTrackedQuery(query);
    }
    return manager;
  }

  TrackedQueryManager._(this._storageLayer, this._clock);

  /// Android: `TrackedQueryManager.storageLayer`, where tracked queries are stored for good.
  final PersistenceStorageEngine _storageLayer;

  /// Android: `TrackedQueryManager.clock`.
  final Clock _clock;

  /// In-memory cache of the tracked queries; always in sync with the storage layer. The maps are
  /// mutated in place, as Android's are. Android: `TrackedQueryManager.trackedQueryTree`.
  ImmutableTree<Map<QueryParams, TrackedQuery>> _trackedQueryTree =
      ImmutableTree<Map<QueryParams, TrackedQuery>>.empty();

  /// The id given to the next tracked query. Android: `TrackedQueryManager.currentQueryId`.
  int _currentQueryId = 0;

  static bool _hasDefaultComplete(Map<QueryParams, TrackedQuery> queries) {
    final TrackedQuery? trackedQuery = queries[QueryParams.defaultParams];
    return trackedQuery != null && trackedQuery.complete;
  }

  static bool _hasActiveDefault(Map<QueryParams, TrackedQuery> queries) {
    final TrackedQuery? trackedQuery = queries[QueryParams.defaultParams];
    return trackedQuery != null && trackedQuery.active;
  }

  static bool _isQueryPrunable(TrackedQuery query) => !query.active;

  static bool _isQueryUnprunable(TrackedQuery query) =>
      !_isQueryPrunable(query);

  static void _assertValidTrackedQuery(QuerySpec query) {
    if (query.loadsAllData && !query.isDefault) {
      throw StateError(
        "Can't have tracked non-default query that loads all data",
      );
    }
  }

  /// A query that loads all data does not care about its order, so it is the default query.
  static QuerySpec _normalizeQuery(QuerySpec query) =>
      query.loadsAllData ? QuerySpec.defaultAt(query.path) : query;

  int _now() => _clock().millisecondsSinceEpoch;

  void _resetPreviouslyActiveTrackedQueries() {
    // Android: most transactions are opened at the sync tree level, but this one is opened here.
    _storageLayer.beginTransaction();
    try {
      _storageLayer.resetPreviouslyActiveTrackedQueries(_now());
      _storageLayer.setTransactionSuccessful();
    } finally {
      _storageLayer.endTransaction();
    }
  }

  /// The record for [query], or null. Android: `TrackedQueryManager.findTrackedQuery`.
  TrackedQuery? findTrackedQuery(QuerySpec query) {
    final QuerySpec normalized = _normalizeQuery(query);
    final Map<QueryParams, TrackedQuery>? set = _trackedQueryTree.get(
      normalized.path,
    );
    return set?[normalized.params];
  }

  /// Removes the record for [query], which must exist. Android:
  /// `TrackedQueryManager.removeTrackedQuery`.
  void removeTrackedQuery(QuerySpec query) {
    final QuerySpec normalized = _normalizeQuery(query);
    final TrackedQuery? trackedQuery = findTrackedQuery(normalized);
    if (trackedQuery == null) {
      throw StateError('Query must exist to be removed.');
    }
    _storageLayer.deleteTrackedQuery(trackedQuery.id);
    final Map<QueryParams, TrackedQuery> trackedQueries = _trackedQueryTree.get(
      normalized.path,
    )!;
    trackedQueries.remove(normalized.params);
    if (trackedQueries.isEmpty) {
      _trackedQueryTree = _trackedQueryTree.remove(normalized.path);
    }
  }

  /// Marks [query] active and updates its last use, tracking it if needed. Android:
  /// `TrackedQueryManager.setQueryActive`.
  void setQueryActive(QuerySpec query) => _setQueryActiveFlag(query, true);

  /// Marks the tracked [query] inactive and updates its last use. Android and iOS:
  /// `TrackedQueryManager.setQueryInactive` / `FTrackedQueryManager.setQueryInactive` (the same;
  /// the iOS difference of engine rule 7 is in the sync tree, which calls this for each removed
  /// query).
  void setQueryInactive(QuerySpec query) => _setQueryActiveFlag(query, false);

  void _setQueryActiveFlag(QuerySpec query, bool isActive) {
    final QuerySpec normalized = _normalizeQuery(query);
    TrackedQuery? trackedQuery = findTrackedQuery(normalized);
    // Whether it is now active or no longer active, the last use is updated.
    final int lastUse = _now();
    if (trackedQuery != null) {
      trackedQuery = trackedQuery
          .withLastUse(lastUse)
          .withActiveState(isActive);
    } else {
      if (!isActive) {
        throw StateError(
          "If we're setting the query to inactive, we should already be tracking it!",
        );
      }
      trackedQuery = TrackedQuery(
        id: _currentQueryId++,
        querySpec: normalized,
        lastUse: lastUse,
        complete: false,
        active: isActive,
      );
    }
    _saveTrackedQuery(trackedQuery);
  }

  /// Marks [query] complete if it is tracked. Android:
  /// `TrackedQueryManager.setQueryCompleteIfExists`.
  void setQueryCompleteIfExists(QuerySpec query) {
    final TrackedQuery? trackedQuery = findTrackedQuery(_normalizeQuery(query));
    if (trackedQuery != null && !trackedQuery.complete) {
      _saveTrackedQuery(trackedQuery.withComplete());
    }
  }

  /// Marks every query at or below [path] complete. Android:
  /// `TrackedQueryManager.setQueriesComplete`.
  void setQueriesComplete(Path path) {
    _trackedQueryTree.subtree(path).forEach((
      Path relativePath,
      Map<QueryParams, TrackedQuery> value,
    ) {
      for (final TrackedQuery trackedQuery in value.values.toList()) {
        if (!trackedQuery.complete) {
          _saveTrackedQuery(trackedQuery.withComplete());
        }
      }
    });
  }

  /// Whether [query] (or a default query above it) is complete. Android:
  /// `TrackedQueryManager.isQueryComplete`.
  bool isQueryComplete(QuerySpec query) {
    if (_includedInDefaultCompleteQuery(query.path)) {
      return true;
    } else if (query.loadsAllData) {
      // No complete default query was found, so it is not complete.
      return false;
    } else {
      final Map<QueryParams, TrackedQuery>? trackedQueries = _trackedQueryTree
          .get(query.path);
      final TrackedQuery? trackedQuery = trackedQueries?[query.params];
      return trackedQuery != null && trackedQuery.complete;
    }
  }

  /// Chooses the queries to prune under [cachePolicy] (the least recently used inactive ones),
  /// removes their records and returns the forest to prune with. Android:
  /// `TrackedQueryManager.pruneOldQueries`.
  PruneForest pruneOldQueries(CachePolicy cachePolicy) {
    final List<TrackedQuery> prunable = _getQueriesMatching(_isQueryPrunable);
    final int countToPrune = _calculateCountToPrune(
      cachePolicy,
      prunable.length,
    );
    PruneForest forest = PruneForest();

    // A stable sort by last use, as Java's Collections.sort is.
    final List<int> order = List<int>.generate(prunable.length, (int i) => i)
      ..sort((int a, int b) {
        final int byLastUse = prunable[a].lastUse.compareTo(
          prunable[b].lastUse,
        );
        return byLastUse != 0 ? byLastUse : a.compareTo(b);
      });
    final List<TrackedQuery> sorted = <TrackedQuery>[
      for (final int i in order) prunable[i],
    ];

    for (int i = 0; i < countToPrune; i++) {
      final TrackedQuery toPrune = sorted[i];
      forest = forest.prune(toPrune.querySpec.path);
      removeTrackedQuery(toPrune.querySpec);
    }

    // Keep the rest of the prunable queries.
    for (int i = countToPrune; i < sorted.length; i++) {
      forest = forest.keep(sorted[i].querySpec.path);
    }

    // Also keep the unprunable queries.
    for (final TrackedQuery toKeep in _getQueriesMatching(_isQueryUnprunable)) {
      forest = forest.keep(toKeep.querySpec.path);
    }
    return forest;
  }

  static int _calculateCountToPrune(
    CachePolicy cachePolicy,
    int prunableCount,
  ) {
    // Prune by percentage.
    final double percentToKeep = 1 - cachePolicy.percentOfQueriesToPruneAtOnce;
    int countToKeep = (prunableCount * percentToKeep).floor();
    // Do not keep more than the max.
    if (cachePolicy.maxNumberOfQueriesToKeep < countToKeep) {
      countToKeep = cachePolicy.maxNumberOfQueriesToKeep;
    }
    return prunableCount - countToKeep;
  }

  /// The keys of complete filtered queries at [path] plus the complete default queries
  /// immediately below it, or null when a complete default query covers [path] (Android asserts
  /// instead). Android: `TrackedQueryManager.getKnownCompleteChildren`.
  Set<ChildKey>? getKnownCompleteChildren(Path path) {
    if (isQueryComplete(QuerySpec.defaultAt(path))) {
      return null;
    }
    final Set<ChildKey> completeChildren = <ChildKey>{};

    // First, complete children from any queries at this location.
    final Set<int> queryIds = _filteredQueryIdsAtPath(path);
    if (queryIds.isNotEmpty) {
      completeChildren.addAll(_storageLayer.loadTrackedQueryKeys(queryIds));
    }

    // Second, any complete default queries immediately below.
    _trackedQueryTree.subtree(path).forEachChild((
      ChildKey childKey,
      Map<QueryParams, TrackedQuery> value,
    ) {
      if (_hasDefaultComplete(value)) {
        completeChildren.add(childKey);
      }
    });
    return completeChildren;
  }

  /// Tracks a complete default query at [path] unless a complete default query covers it.
  /// Android: `TrackedQueryManager.ensureCompleteTrackedQuery`.
  void ensureCompleteTrackedQuery(Path path) {
    if (_includedInDefaultCompleteQuery(path)) {
      return;
    }
    final QuerySpec querySpec = QuerySpec.defaultAt(path);
    TrackedQuery? trackedQuery = findTrackedQuery(querySpec);
    if (trackedQuery == null) {
      trackedQuery = TrackedQuery(
        id: _currentQueryId++,
        querySpec: querySpec,
        lastUse: _now(),
        complete: true,
        active: false,
      );
    } else {
      if (trackedQuery.complete) {
        throw StateError('This should have been handled above!');
      }
      trackedQuery = trackedQuery.withComplete();
    }
    _saveTrackedQuery(trackedQuery);
  }

  /// Whether an active default query exists at or above [path]. Android:
  /// `TrackedQueryManager.hasActiveDefaultQuery`.
  bool hasActiveDefaultQuery(Path path) =>
      _trackedQueryTree.rootMostValueMatching(path, _hasActiveDefault) != null;

  /// The number of inactive queries. Android: `TrackedQueryManager.countOfPrunableQueries`.
  int countOfPrunableQueries() => _getQueriesMatching(_isQueryPrunable).length;

  bool _includedInDefaultCompleteQuery(Path path) =>
      _trackedQueryTree.findRootMostMatchingPathAndValue(
        path,
        _hasDefaultComplete,
      ) !=
      null;

  Set<int> _filteredQueryIdsAtPath(Path path) {
    final Set<int> ids = <int>{};
    final Map<QueryParams, TrackedQuery>? queries = _trackedQueryTree.get(path);
    if (queries != null) {
      for (final TrackedQuery query in queries.values) {
        if (!query.querySpec.loadsAllData) {
          ids.add(query.id);
        }
      }
    }
    return ids;
  }

  void _cacheTrackedQuery(TrackedQuery query) {
    _assertValidTrackedQuery(query.querySpec);
    Map<QueryParams, TrackedQuery>? trackedSet = _trackedQueryTree.get(
      query.querySpec.path,
    );
    if (trackedSet == null) {
      trackedSet = <QueryParams, TrackedQuery>{};
      _trackedQueryTree = _trackedQueryTree.set(
        query.querySpec.path,
        trackedSet,
      );
    }
    // One id per query (Android's sanity check).
    final TrackedQuery? existing = trackedSet[query.querySpec.params];
    if (existing != null && existing.id != query.id) {
      throw StateError(
        'Query ${query.querySpec} is tracked under id ${existing.id}, '
        'not ${query.id}.',
      );
    }
    trackedSet[query.querySpec.params] = query;
  }

  void _saveTrackedQuery(TrackedQuery query) {
    _cacheTrackedQuery(query);
    _storageLayer.saveTrackedQuery(query);
  }

  List<TrackedQuery> _getQueriesMatching(
    bool Function(TrackedQuery query) predicate,
  ) {
    final List<TrackedQuery> matching = <TrackedQuery>[];
    for (final MapEntry<Path, Map<QueryParams, TrackedQuery>> entry
        in _trackedQueryTree.entries) {
      for (final TrackedQuery query in entry.value.values) {
        if (predicate(query)) {
          matching.add(query);
        }
      }
    }
    return matching;
  }
}
