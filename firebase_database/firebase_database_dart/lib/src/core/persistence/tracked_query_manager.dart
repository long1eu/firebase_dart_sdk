/// Bookkeeping of tracked queries. JS: none; Android: `core/persistence/TrackedQueryManager.java`.
library;

import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/persistence/cache_policy.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_storage_engine.dart';
import 'package:firebase_database_dart/src/core/persistence/prune_forest.dart';
import 'package:firebase_database_dart/src/core/persistence/tracked_query.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/util/clock.dart';
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
  ) => throw UnimplementedError();

  /// The record for [query], or null.
  TrackedQuery? findTrackedQuery(QuerySpec query) => throw UnimplementedError();

  /// Removes the record for [query].
  void removeTrackedQuery(QuerySpec query) => throw UnimplementedError();

  /// Marks [query] active.
  void setQueryActive(QuerySpec query) => throw UnimplementedError();

  /// Marks [query] inactive.
  void setQueryInactive(QuerySpec query) => throw UnimplementedError();

  /// Marks [query] complete if it is tracked.
  void setQueryCompleteIfExists(QuerySpec query) => throw UnimplementedError();

  /// Marks every query at or below [path] complete.
  void setQueriesComplete(Path path) => throw UnimplementedError();

  /// Whether [query] (or a default query above it) is complete.
  bool isQueryComplete(QuerySpec query) => throw UnimplementedError();

  /// Chooses the queries to prune under [cachePolicy] and removes their records.
  PruneForest pruneOldQueries(CachePolicy cachePolicy) =>
      throw UnimplementedError();

  /// The keys of complete filtered queries at [path], or null when a complete default query
  /// covers it.
  Set<ChildKey>? getKnownCompleteChildren(Path path) =>
      throw UnimplementedError();

  /// Tracks a complete default query at [path] if none exists.
  void ensureCompleteTrackedQuery(Path path) => throw UnimplementedError();

  /// Whether an active default query exists at [path].
  bool hasActiveDefaultQuery(Path path) => throw UnimplementedError();

  /// The number of inactive queries.
  int countOfPrunableQueries() => throw UnimplementedError();
}
