// LruCachePolicy against Android LRUCachePolicy.java's constants (Android has no unit test for
// it; PruningTest covers the SQLite engine).
import 'package:firebase_database_dart/src/core/persistence/lru_cache_policy.dart';
import 'package:test/test.dart';

void main() {
  const LruCachePolicy policy = LruCachePolicy(100);

  test('prunes above the size or above 1000 prunable queries', () {
    expect(policy.shouldPrune(100, 1000), isFalse);
    expect(policy.shouldPrune(101, 0), isTrue);
    expect(policy.shouldPrune(0, 1001), isTrue);
  });

  test('checks the size after more than 1000 server updates', () {
    expect(policy.shouldCheckCacheSize(1000), isFalse);
    expect(policy.shouldCheckCacheSize(1001), isTrue);
  });

  test('prunes 20% at once and keeps at most 1000', () {
    expect(policy.percentOfQueriesToPruneAtOnce, 0.2);
    expect(policy.maxNumberOfQueriesToKeep, 1000);
  });
}
