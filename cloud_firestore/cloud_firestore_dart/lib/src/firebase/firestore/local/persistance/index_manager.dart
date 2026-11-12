// File created by
// Lung Razvan <long1eu>
// on 15/03/2020

import 'package:cloud_firestore_dart/src/firebase/firestore/core/target.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';

/// Represents the index state as it relates to a particular target.
enum IndexType {
  /// Indicates that no index could be found for serving the target.
  none,

  /// Indicates that only a "partial index" could be found for serving the
  /// target. A partial index is one which does not have a segment for every
  /// filter/orderBy in the target.
  partial,

  /// Indicates that a "full index" could be found for serving the target. A
  /// full index is one which has a segment for every filter/orderBy in the
  /// target.
  full,
}

/// Represents a set of indexes that are used to execute queries efficiently:
/// the [collection id] => [parent path] index, used to execute Collection
/// Group queries, and the field indexes.
///
/// PORTING NOTE: the field indexes keep their state per user, so the methods
/// for them are only usable on a manager obtained with
/// `Persistence.getIndexManager(user)` and after [start]. The collection
/// parent index is the same for all users and also works on
/// `Persistence.indexManager`.
abstract class IndexManager {
  /// Initializes the IndexManager: loads the configured field indexes.
  Future<void> start();

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

  /// Adds a field path index.
  ///
  /// Values for this index are persisted asynchronously. The index will only
  /// be used for query execution once values are persisted.
  Future<void> addFieldIndex(FieldIndex index);

  /// Removes the given field index and deletes all index values.
  Future<void> deleteFieldIndex(FieldIndex index);

  /// Removes all field indexes and deletes all index values.
  Future<void> deleteAllFieldIndexes();

  /// Creates a full matched field index which serves the given target.
  Future<void> createTargetIndexes(Target target);

  /// Returns the field indexes that correspond to the specified
  /// [collectionGroup], or all configured field indexes when it is null.
  List<FieldIndex> getFieldIndexes([String? collectionGroup]);

  /// Iterates over all field indexes that are used to serve the given target,
  /// and returns the minimum offset of them all. Asserts that the target can be
  /// served from index.
  IndexOffset getMinOffsetForTarget(Target target);

  /// Returns the minimum offset for the given collection group.
  IndexOffset getMinOffset(String collectionGroup);

  /// Returns the type of index (if any) that can be used to serve the given
  /// target.
  IndexType getIndexType(Target target);

  /// Returns the documents that match the given target based on the provided
  /// index or null if the query cannot be served from an index.
  Future<List<DocumentKey>?> getDocumentsMatchingTarget(Target target);

  /// Returns the next collection group to update. Returns null if no group
  /// exists.
  String? getNextCollectionGroupToUpdate();

  /// Sets the collection group's latest read time.
  ///
  /// This method updates the index offset for all field indices for the
  /// collection group and increments their sequence number. Subsequent calls
  /// to [getNextCollectionGroupToUpdate] will return a different collection
  /// group (unless only one collection group is configured).
  Future<void> updateCollectionGroup(
    String collectionGroup,
    IndexOffset offset,
  );

  /// Updates the index entries for the provided documents. A key that maps to
  /// null or to a document that does not exist loses its entries.
  Future<void> updateIndexEntries(Map<DocumentKey, MaybeDocument?> documents);
}

/// Internal implementation of the collection-parent index. Also used for
/// in-memory caching by SQLiteIndexManager and initial index population in
/// SQLiteSchema.
class MemoryCollectionParentIndex {
  MemoryCollectionParentIndex() : _index = <String, Set<ResourcePath>>{};

  final Map<String, Set<ResourcePath>> _index;

  /// Whether [collectionPath] was already added.
  bool contains(ResourcePath collectionPath) {
    return _index[collectionPath.getLastSegment()]?.contains(
          collectionPath.popLast(),
        ) ??
        false;
  }

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
