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
///
/// Programming errors (a mutation outside a transaction, a nested [beginTransaction]) throw a
/// [StateError]. Storage errors at run time (disk full, I/O error, corruption, a lost lease) never
/// throw: the engine rolls back, becomes degraded ([isDurable] turns false for good), and from
/// then on stores nothing and reads as empty, while the sync tree's memory state stays
/// authoritative for the session.
///
/// A condition that only stored data can cause (an unknown write id or tracked query id, keys
/// removed that are not stored, data that a prune neither prunes nor keeps) is never an error an
/// engine must report: a degraded engine reads as empty, and a store may hold data an earlier
/// version wrote. The reference engine checks some of these while [isDurable] is true; each such
/// check is marked "a reference-engine check, not a requirement on engines".
abstract interface class PersistenceStorageEngine {
  /// Stores an overwrite.
  void saveUserOverwrite(Path path, Node node, WriteId writeId);

  /// Stores a merge.
  void saveUserMerge(Path path, CompoundWrite children, WriteId writeId);

  /// Removes write [writeId]; an unknown id is a no-op (Android deletes no row).
  ///
  /// The reference engine throws a [StateError] for an unknown id while [isDurable] is true: a
  /// reference-engine check, not a requirement on engines.
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
  ///
  /// One id per query is kept by `TrackedQueryManager`, which holds the tracked queries in
  /// memory. The reference engine throws a [StateError] when an id moves to another query or a
  /// query gets a second id while [isDurable] is true: a reference-engine check, not a requirement
  /// on engines.
  void saveTrackedQuery(TrackedQuery trackedQuery);

  /// Deletes tracked query [trackedQueryId] and its keys.
  void deleteTrackedQuery(int trackedQueryId);

  /// The tracked queries ordered by id.
  List<TrackedQuery> loadTrackedQueries();

  /// Marks every active tracked query inactive with [lastUse] (at start-up).
  ///
  /// Runs as its own transaction when called outside one, and as part of the current one
  /// otherwise. Android requires a transaction here (`SqlPersistenceStorageEngine.java:521`) and
  /// opens one in `TrackedQueryManager.resetPreviouslyActiveTrackedQueries` (:114-124).
  void resetPreviouslyActiveTrackedQueries(int lastUse);

  /// Replaces the keys of [trackedQueryId].
  ///
  /// The reference engine throws a [StateError] for an untracked id while [isDurable] is true: a
  /// reference-engine check, not a requirement on engines.
  void saveTrackedQueryKeys(int trackedQueryId, Set<ChildKey> keys);

  /// Adds and removes keys of [trackedQueryId]; removing a key that is not stored is a no-op.
  ///
  /// The reference engine throws a [StateError] for an untracked id or for removing keys that do
  /// not exist while [isDurable] is true: a reference-engine check, not a requirement on engines.
  void updateTrackedQueryKeys(
    int trackedQueryId,
    Set<ChildKey> added,
    Set<ChildKey> removed,
  );

  /// The union of the keys of [trackedQueryIds] (one id: a set of one); an unknown id adds no
  /// keys.
  ///
  /// The reference engine throws a [StateError] for an untracked id while [isDurable] is true: a
  /// reference-engine check, not a requirement on engines.
  Set<ChildKey> loadTrackedQueryKeys(Set<int> trackedQueryIds);

  /// Deletes the cached data below [root] that [pruneForest] prunes and does not keep.
  ///
  /// Data stored above [root], and data below it that [pruneForest] neither prunes nor keeps, is
  /// left alone with a warning through the engine's `DatabaseLogger`; it is never an error.
  /// Android: `SqlPersistenceStorageEngine.java:657-681`.
  void pruneCache(Path root, PruneForest pruneForest);

  /// Starts a transaction; nesting is an error.
  void beginTransaction();

  /// Ends the transaction, committing it if [setTransactionSuccessful] was called.
  void endTransaction();

  /// Marks the current transaction to be committed.
  void setTransactionSuccessful();

  /// Releases the store.
  void close();

  /// Whether data written now survives a restart: true after a successful open, false once the
  /// engine is degraded or fenced (or closed). Never turns true again in the same session; the
  /// public `persistenceEnabled` reads it.
  bool get isDurable;
}
