// File created by
// Lung Razvan <long1eu>
// on 15/03/2020

part of 'memory_persistence.dart';

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

  // Field indices are not supported with memory persistence.

  @override
  Future<void> start() async {}

  @override
  Future<void> addFieldIndex(FieldIndex index) async {}

  @override
  Future<void> deleteFieldIndex(FieldIndex index) async {}

  @override
  Future<void> deleteAllFieldIndexes() async {}

  @override
  Future<void> createTargetIndexes(Target target) async {}

  @override
  Future<List<DocumentKey>?> getDocumentsMatchingTarget(Target target) async =>
      null;

  @override
  String? getNextCollectionGroupToUpdate() => null;

  @override
  Future<void> updateCollectionGroup(
      String collectionGroup, IndexOffset offset) async {}

  @override
  List<FieldIndex> getFieldIndexes([String? collectionGroup]) =>
      const <FieldIndex>[];

  @override
  IndexOffset getMinOffsetForTarget(Target target) => IndexOffset.none;

  @override
  IndexOffset getMinOffset(String collectionGroup) => IndexOffset.none;

  @override
  IndexType getIndexType(Target target) => IndexType.none;

  @override
  Future<void> updateIndexEntries(
      Map<DocumentKey, MaybeDocument?> documents) async {}
}
