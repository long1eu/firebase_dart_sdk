/// Least-recently-used pruning by size. JS: none; Android: `core/persistence/LRUCachePolicy.java`.
library;

import 'package:firebase_database_dart/src/core/persistence/cache_policy.dart';

/// Prunes the least recently used inactive queries when the cache exceeds [maxSizeBytes].
final class LruCachePolicy implements CachePolicy {
  /// Creates a policy.
  const LruCachePolicy(this.maxSizeBytes);

  /// Android: `LRUCachePolicy.SERVER_UPDATES_BETWEEN_CACHE_SIZE_CHECKS`.
  static const int _serverUpdatesBetweenCacheSizeChecks = 1000;

  /// Android: `LRUCachePolicy.MAX_NUMBER_OF_PRUNABLE_QUERIES_TO_KEEP`.
  static const int _maxNumberOfPrunableQueriesToKeep = 1000;

  /// 20% at a time until the cache is below the limit. Android:
  /// `LRUCachePolicy.PERCENT_OF_QUERIES_TO_PRUNE_AT_ONCE`.
  static const double _percentOfQueriesToPruneAtOnce = 0.2;

  /// The size limit. Android: `LRUCachePolicy.maxSizeBytes`.
  final int maxSizeBytes;

  /// Prunes above [maxSizeBytes] or above 1000 prunable queries. Android:
  /// `LRUCachePolicy.shouldPrune`.
  @override
  bool shouldPrune(int currentSizeBytes, int countOfPrunableQueries) =>
      currentSizeBytes > maxSizeBytes ||
      countOfPrunableQueries > _maxNumberOfPrunableQueriesToKeep;

  /// Checks after more than 1000 server updates. Android: `LRUCachePolicy.shouldCheckCacheSize`.
  @override
  bool shouldCheckCacheSize(int serverUpdatesSinceLastCheck) =>
      serverUpdatesSinceLastCheck > _serverUpdatesBetweenCacheSizeChecks;

  /// 0.2. Android: `LRUCachePolicy.getPercentOfQueriesToPruneAtOnce`.
  @override
  double get percentOfQueriesToPruneAtOnce => _percentOfQueriesToPruneAtOnce;

  /// 1000. Android: `LRUCachePolicy.getMaxNumberOfQueriesToKeep`.
  @override
  int get maxNumberOfQueriesToKeep => _maxNumberOfPrunableQueriesToKeep;
}
