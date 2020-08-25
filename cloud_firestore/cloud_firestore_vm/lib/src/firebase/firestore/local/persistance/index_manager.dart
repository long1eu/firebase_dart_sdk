// File created by
// Lung Razvan <long1eu>
// on 15/03/2020

import 'package:cloud_firestore_vm/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';

/// Represents a set of indexes that are used to execute queries efficiently.
///
/// Currently the only index is a [collection id] => [parent path] index, used
/// to execute Collection Group queries.
abstract class IndexManager {
  /// Creates an index entry mapping the collectionId (last segment of the path)
  /// to the parent path (either the containing document location or the empty
  /// path for root-level collections). Index entries can be retrieved via
  /// [getCollectionParents].
  ///
  /// NOTE: Currently we don't remove index entries. If this ends up being an
  /// issue we can devise some sort of GC strategy.
  Future<void> addToCollectionParentIndex(ResourcePath collectionPath);

  /// Retrieves all parent locations containing the given collectionId, as a set
  /// of paths (each path being either a document location or the empty path for
  /// a root-level collection).
  Future<List<ResourcePath>> getCollectionParents(String collectionId);
}

/// Internal implementation of the collection-parent index. Also used for
/// in-memory caching by SQLiteIndexManager and initial index population in
/// SQLiteSchema.
class MemoryCollectionParentIndex {
  MemoryCollectionParentIndex() : _index = <String, Set<ResourcePath>>{};

  final Map<String, Set<ResourcePath>> _index;

  // Returns false if the entry already existed.
  bool add(ResourcePath collectionPath) {
    hardAssert(collectionPath.length % 2 == 1, 'Expected a collection path.');
    final String collectionId = collectionPath.getLastSegment();
    final ResourcePath parentPath = collectionPath.popLast();

    return (_index[collectionId] ??= <ResourcePath>{}).add(parentPath);
  }

  List<ResourcePath> getEntries(String collectionId) {
    return _index[collectionId]?.toList() ?? <ResourcePath>[];
  }
}
