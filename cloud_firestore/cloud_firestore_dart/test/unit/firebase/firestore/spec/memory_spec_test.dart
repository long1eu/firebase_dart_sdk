// File created by
// Lung Razvan <long1eu>
// on 05/10/2018

import '../local/persistence_test_helpers.dart';
import 'spec_runner.dart';
import 'spec_skip_list.dart';

/// Runs the upstream JSON spec tests on the memory persistence (eager or LRU garbage collection, as the spec's
/// `useEagerGCForMemory` config asks).
void main() {
  registerSpecTests(
    variant: 'memory',
    getPersistence: (bool useEagerGc, _) => useEagerGc
        ? createEagerGCMemoryPersistence()
        : createLRUMemoryPersistence(),
    excludedTags: memoryExcludedTags,
  );
}
