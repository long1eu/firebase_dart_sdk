/// When to prune the cache. JS: none; Android: `core/persistence/CachePolicy.java`.
library;

/// Decides when the cache is pruned and how much.
abstract interface class CachePolicy {
  /// The policy that never prunes.
  static const CachePolicy none = _NoCachePolicy();

  /// Whether to prune at [currentSizeBytes] with [countOfPrunableQueries].
  bool shouldPrune(int currentSizeBytes, int countOfPrunableQueries);

  /// Whether to check the size after [serverUpdatesSinceLastCheck] server updates.
  bool shouldCheckCacheSize(int serverUpdatesSinceLastCheck);

  /// The share of prunable queries pruned at once (0 to 1).
  double get percentOfQueriesToPruneAtOnce;

  /// The number of prunable queries always kept.
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
