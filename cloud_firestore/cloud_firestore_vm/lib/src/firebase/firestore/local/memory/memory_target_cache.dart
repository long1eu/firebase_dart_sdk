// File created by
// Lung Razvan <long1eu>
// on 21/09/2018

part of memory_persistence;

/// An implementation of the [TargetCache] protocol that merely keeps targets in memory, suitable for online only clients
/// with persistence disabled.
class MemoryTargetCache implements TargetCache {
  MemoryTargetCache(this.persistence);

  /// Maps a target to the data about that target.
  final Map<Target, TargetData> targets = <Target, TargetData>{};

  /// A ordered bidirectional mapping between documents and the remote target ids.
  final ReferenceSet references = ReferenceSet();

  /// The highest numbered target id encountered.
  @override
  int highestTargetId = 0;

  /// The last received snapshot version.
  @override
  SnapshotVersion lastRemoteSnapshotVersion = SnapshotVersion.none;

  int highestSequenceNumber = 0;

  final MemoryPersistence persistence;

  @override
  int get targetCount => targets.length;

  @override
  Future<void> forEachTarget(Consumer<TargetData> consumer) async {
    targets.values.forEach(consumer);
  }

  @override
  int get highestListenSequenceNumber => highestSequenceNumber;

  @override
  Future<void> setLastRemoteSnapshotVersion(SnapshotVersion snapshotVersion) async {
    lastRemoteSnapshotVersion = snapshotVersion;
  }

  // Query tracking

  @override
  Future<void> addTargetData(TargetData targetData) async {
    targets[targetData.target] = targetData;
    final int targetId = targetData.targetId;
    if (targetId > highestTargetId) {
      highestTargetId = targetId;
    }
    if (targetData.sequenceNumber > highestSequenceNumber) {
      highestSequenceNumber = targetData.sequenceNumber;
    }
  }

  @override
  Future<void> updateTargetData(TargetData targetData) async {
    // Memory persistence doesn't need to do anything different between add and remove.
    return addTargetData(targetData);
  }

  @override
  Future<void> removeTargetData(TargetData targetData) async {
    targets.remove(targetData.target);
    references.removeReferencesForId(targetData.targetId);
  }

  /// Drops any targets with sequence number less than or equal to the upper bound, excepting those present in
  /// [activeTargetIds]. Document associations for the removed targets are also removed.
  int removeQueries(int upperBound, Set<int> activeTargetIds) {
    int removed = 0;
    targets.removeWhere((Target target, TargetData queryData) {
      final int targetId = queryData.targetId;
      final int sequenceNumber = queryData.sequenceNumber;

      if (sequenceNumber <= upperBound && !activeTargetIds.contains(targetId)) {
        _removeMatchingKeysForTargetId(targetId);
        removed++;
        return true;
      }
      return false;
    });

    return removed;
  }

  @override
  Future<TargetData> getTargetData(Target target) async => targets[target];

  // Reference tracking

  @override
  Future<void> addMatchingKeys(ImmutableSortedSet<DocumentKey> keys, int targetId) async {
    references.addReferences(keys, targetId);
    final ReferenceDelegate referenceDelegate = persistence.referenceDelegate;

    for (DocumentKey key in keys) {
      await referenceDelegate.addReference(key);
    }
  }

  @override
  Future<void> removeMatchingKeys(ImmutableSortedSet<DocumentKey> keys, int targetId) async {
    references.removeReferences(keys, targetId);
    final ReferenceDelegate referenceDelegate = persistence.referenceDelegate;

    for (DocumentKey key in keys) {
      await referenceDelegate.removeReference(key);
    }
  }

  void _removeMatchingKeysForTargetId(int targetId) {
    references.removeReferencesForId(targetId);
  }

  @override
  Future<ImmutableSortedSet<DocumentKey>> getMatchingKeysForTargetId(int targetId) async {
    return references.referencesForId(targetId);
  }

  @override
  Future<bool> containsKey(DocumentKey key) async => references.containsKey(key);

  int getByteSize(LocalSerializer serializer) {
    int count = 0;
    for (TargetData value in targets.values) {
      count += serializer.encodeTargetData(value).writeToBuffer().lengthInBytes;
    }
    return count;
  }
}
