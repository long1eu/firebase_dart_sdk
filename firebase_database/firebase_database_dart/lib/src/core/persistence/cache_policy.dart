/// When to prune the cache. JS: none; Android: `core/persistence/CachePolicy.java`.
library;

/// Decides when the cache is pruned and how much.
abstract interface class CachePolicy {
  /// The policy that never prunes. Android: `CachePolicy.NONE`.
  static const CachePolicy none = _NoCachePolicy();

  /// Whether to prune at [currentSizeBytes] with [countOfPrunableQueries]. Android:
  /// `CachePolicy.shouldPrune`.
  bool shouldPrune(int currentSizeBytes, int countOfPrunableQueries);

  /// Whether to check the size after [serverUpdatesSinceLastCheck] server updates. Android:
  /// `CachePolicy.shouldCheckCacheSize`.
  bool shouldCheckCacheSize(int serverUpdatesSinceLastCheck);

  /// The share of prunable queries pruned at once (0 to 1). Android:
  /// `CachePolicy.getPercentOfQueriesToPruneAtOnce`.
  double get percentOfQueriesToPruneAtOnce;

  /// The largest number of prunable queries kept after a prune. Android:
  /// `CachePolicy.getMaxNumberOfQueriesToKeep`.
  int get maxNumberOfQueriesToKeep;
}

final class _NoCachePolicy implements CachePolicy {
  const _NoCachePolicy();

  @override
  bool shouldPrune(int currentSizeBytes, int countOfPrunableQueries) => false;

  @override
  bool shouldCheckCacheSize(int serverUpdatesSinceLastCheck) => false;

  @override
  double get percentOfQueriesToPruneAtOnce => 0;

  @override
  int get maxNumberOfQueriesToKeep => 0x7fffffff;
}
