/// The storage under the persistence manager. JS: none; Android:
/// `core/persistence/PersistenceStorageEngine.java` (implemented there by
/// `android/SqlPersistenceStorageEngine.java`).
///
/// Implemented by the persistence team; `InMemoryPersistenceStorageEngine` (lib/src/testing) is
/// the reference implementation and `test/contract/persistence_storage_engine_contract_test.dart`
/// is the contract every engine passes.
library;

import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/persistence/prune_forest.dart';
import 'package:firebase_database_dart/src/core/persistence/tracked_query.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/user_write_record.dart';
import 'package:firebase_database_dart/src/core/write_id.dart';

/// A synchronous store of user writes, the server cache tree, tracked queries and their keys.
///
/// Mutations happen between [beginTransaction] and [endTransaction]; they are committed only if
/// [setTransactionSuccessful] was called in between. Reads may happen at any time.
abstract interface class PersistenceStorageEngine {
  /// Stores an overwrite.
  void saveUserOverwrite(Path path, Node node, WriteId writeId);

  /// Stores a merge.
  void saveUserMerge(Path path, CompoundWrite children, WriteId writeId);

  /// Removes write [writeId]; it must exist.
  void removeUserWrite(WriteId writeId);

  /// The stored writes ordered by write id.
  List<UserWriteRecord> loadUserWrites();

  /// Removes every write.
  void removeAllUserWrites();

  /// The cached node at [path] (empty when nothing is cached).
  Node serverCache(Path path);

  /// Replaces the cache at [path] with [node].
  void overwriteServerCache(Path path, Node node);

  /// Writes each child of [node] below [path], leaving other children alone.
  void mergeIntoServerCache(Path path, Node node);

  /// Writes each write of [children] below [path].
  void mergeIntoServerCacheWrite(Path path, CompoundWrite children);

  /// The estimated size of the server cache in bytes.
  int serverCacheEstimatedSizeInBytes();

  /// Stores [trackedQuery] (insert or replace by id).
  void saveTrackedQuery(TrackedQuery trackedQuery);

  /// Deletes tracked query [trackedQueryId] and its keys.
  void deleteTrackedQuery(int trackedQueryId);

  /// The tracked queries ordered by id.
  List<TrackedQuery> loadTrackedQueries();

  /// Marks every active tracked query inactive with [lastUse] (at start-up).
  void resetPreviouslyActiveTrackedQueries(int lastUse);

  /// Replaces the keys of [trackedQueryId]; the query must exist.
  void saveTrackedQueryKeys(int trackedQueryId, Set<ChildKey> keys);

  /// Adds and removes keys of [trackedQueryId]; the query must exist.
  void updateTrackedQueryKeys(int trackedQueryId, Set<ChildKey> added, Set<ChildKey> removed);

  /// The keys of [trackedQueryId].
  Set<ChildKey> loadTrackedQueryKeys(int trackedQueryId);

  /// The union of the keys of [trackedQueryIds].
  Set<ChildKey> loadTrackedQueryKeysForAll(Set<int> trackedQueryIds);

  /// Deletes the cached data below [root] that [pruneForest] prunes and does not keep.
  void pruneCache(Path root, PruneForest pruneForest);

  /// Starts a transaction; nesting is an error.
  void beginTransaction();

  /// Ends the transaction, committing it if [setTransactionSuccessful] was called.
  void endTransaction();

  /// Marks the current transaction to be committed.
  void setTransactionSuccessful();

  /// Releases the store.
  void close();
}
