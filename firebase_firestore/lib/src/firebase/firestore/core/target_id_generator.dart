// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

/// Generates monotonically increasing target IDs for sending targets to the watch stream.
///
/// The client constructs two generators, one for the query cache [TargetIdGenerator.forQueryCache],
/// and one for limbo documents [TargetIdGenerator.forSyncEngine]. These two generators produce
/// non-overlapping IDs (by using even and odd IDs respectively).
///
/// By separating the target ID space, the query cache can generate target IDs that persist across
/// client restarts, while sync engine can independently generate in-memory target IDs that are
/// transient and can be reused after a restart.

// TODO(mrschmidt): Explore removing this class in favor of generating these IDs
//  directly in SyncEngine and LocalStore.
class TargetIdGenerator {
  /// Instantiates a new TargetIdGenerator, using the seed as the first target ID to return.
  TargetIdGenerator(int generatorId, int seed)
      : assert((generatorId & _reservedBits) == generatorId,
            'Generator ID $generatorId contains more than $_reservedBits reserved bits.'),
        assert((seed & _reservedBits) == generatorId,
            'Cannot supply target ID from different generator ID'),
        _nextId = seed;

  /// Creates and returns the [TargetIdGenerator] for the local store.
  factory TargetIdGenerator.forQueryCache(int after) {
    final TargetIdGenerator generator = TargetIdGenerator(_queryCacheId, after);
    // Make sure that the next call to `nextId()` returns the first value after 'after'.
    generator.nextId;
    return generator;
  }

  /// Creates and returns the [TargetIdGenerator] for the sync engine.
  factory TargetIdGenerator.forSyncEngine() {
    // Sync engine assigns target IDs for limbo document detection.
    return TargetIdGenerator(_syncEngineId, 1);
  }

  static const int _queryCacheId = 0;
  static const int _syncEngineId = 1;

  static const int _reservedBits = 1;

  int _nextId;

  /// Returns the next id in the sequence
  int get nextId {
    final int _nextId = this._nextId;
    this._nextId += 1 << _reservedBits;
    return _nextId;
  }
}
