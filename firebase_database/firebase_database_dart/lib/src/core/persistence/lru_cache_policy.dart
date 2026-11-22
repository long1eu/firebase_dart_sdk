/// Least-recently-used pruning by size. JS: none; Android: `core/persistence/LRUCachePolicy.java`.
library;

import 'package:firebase_database_dart/src/core/persistence/cache_policy.dart';

/// Prunes the least recently used inactive queries when the cache exceeds [maxSizeBytes].
final class LruCachePolicy implements CachePolicy {
  /// Creates a policy.
  const LruCachePolicy(this.maxSizeBytes);

  /// The size limit.
  final int maxSizeBytes;

  @override
  bool shouldPrune(int currentSizeBytes, int countOfPrunableQueries) =>
      throw UnimplementedError();

  @override
  bool shouldCheckCacheSize(int serverUpdatesSinceLastCheck) =>
      throw UnimplementedError();

  @override
  double get percentOfQueriesToPruneAtOnce => throw UnimplementedError();

  @override
  int get maxNumberOfQueriesToKeep => throw UnimplementedError();
}
