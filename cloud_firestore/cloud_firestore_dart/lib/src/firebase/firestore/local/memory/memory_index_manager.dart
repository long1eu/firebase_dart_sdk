// File created by
// Lung Razvan <long1eu>
// on 15/03/2020

part of memory_persistence;

/// An in-memory implementation of IndexManager.
class MemoryIndexManager extends IndexManager {
  MemoryIndexManager()
      : _collectionParentsIndex = MemoryCollectionParentIndex();
  final MemoryCollectionParentIndex _collectionParentsIndex;

  @override
  Future<void> addToCollectionParentIndex(ResourcePath collectionPath) async {
    _collectionParentsIndex.add(collectionPath);
  }

  @override
  Future<List<ResourcePath>> getCollectionParents(String collectionId) async {
    return _collectionParentsIndex.getEntries(collectionId);
  }
}
