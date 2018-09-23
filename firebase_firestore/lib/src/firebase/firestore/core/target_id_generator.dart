// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

/**
 * Generates monotonically increasing integer IDs. There are separate generators for different
 * scopes. While these generators will operate independently of each other, they are scoped, such
 * that no two generators will ever produce the same ID. This is useful, because sometimes the
 * backend may group IDs from separate parts of the client into the same ID space.
 */

class TargetIdGenerator {
  /// Creates and returns the [TargetIdGenerator] for the local store.
  /// [after] is an ID to start at. Every call to nextID will return an
  /// id > after.
  factory TargetIdGenerator.getLocalStoreIdGenerator(int after) {
    return new TargetIdGenerator(_localStateId, after);
  }

  /// Creates and returns the [TargetIdGenerator] for the sync engine. [after]
  /// is an ID to start at. Every call to nextID will return an id > after.
  factory TargetIdGenerator.getSyncEngineGenerator(int after) {
    return new TargetIdGenerator(_syncEngineId, after);
  }

  static final int _localStateId = 0;
  static final int _syncEngineId = 1;
  static final int _reservedBits = 1;

  int _previousId;

  TargetIdGenerator(int generatorId, int after) {
    int afterWithoutGenerator = after >> _reservedBits << _reservedBits;
    print(afterWithoutGenerator);
    int afterGenerator = after - afterWithoutGenerator;
    if (afterGenerator >= generatorId) {
      // For example, if:
      //   self.generatorID = 0b0000
      //   after = 0b1011
      //   afterGenerator = 0b0001
      // Then:
      //   previous = 0b1010
      //   next = 0b1100
      _previousId = afterWithoutGenerator | generatorId;
    } else {
      // For example, if:
      //   self.generatorID = 0b0001
      //   after = 0b1010
      //   afterGenerator = 0b0000
      // Then:
      //   previous = 0b1001
      //   next = 0b1011
      _previousId =
          (afterWithoutGenerator | generatorId) - (1 << _reservedBits);
    }
  }

  /// Returns the next id in the sequence
  int nextId() {
    _previousId += 1 << _reservedBits;
    return _previousId;
  }
}
