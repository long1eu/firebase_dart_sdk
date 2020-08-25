// File created by
// Lung Razvan <long1eu>
// on 15/03/2020

part of sqlite_persistence;

/// An in-memory implementation of IndexManager.
class SqliteIndexManager extends IndexManager {
  SqliteIndexManager(this.db)
      : _collectionParentsIndex = MemoryCollectionParentIndex();

  /// An in-memory copy of the index entries we've already written since the SDK
  /// launched. Used to avoid re-writing the same entry repeatedly.
  ///
  /// This is NOT a complete cache of what's in persistence and so can never be
  /// used to satisfy reads.
  final MemoryCollectionParentIndex _collectionParentsIndex;
  final SQLitePersistence db;

  @override
  Future<void> addToCollectionParentIndex(ResourcePath collectionPath) async {
    hardAssert(collectionPath.length % 2 == 1, 'Expected a collection path.');

    if (_collectionParentsIndex.add(collectionPath)) {
      final String collectionId = collectionPath.getLastSegment();
      final ResourcePath parentPath = collectionPath.popLast();
      await db.execute(
        'INSERT OR REPLACE INTO collection_parents (collection_id, parent) VALUES (?, ?)',
        <Object>[collectionId, EncodedPath.encode(parentPath)],
      );
    }
  }

  @override
  Future<List<ResourcePath>> getCollectionParents(String collectionId) async {
    final List<Map<String, dynamic>> data = await db.query(
      'SELECT parent FROM collection_parents WHERE collection_id = ?',
      <String>[collectionId],
    );

    return data
        .map((Map<String, dynamic> row) =>
            EncodedPath.decodeResourcePath(row['parent']))
        .toList();
  }
}
