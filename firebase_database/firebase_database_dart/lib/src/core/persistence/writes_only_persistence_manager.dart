/// Tier 1 persistence: restart-safe pending writes only. JS: none; Android: none (a split of
/// `core/persistence/DefaultPersistenceManager.java`; see the storage engine design, section 13a).
library;

import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/persistence/default_persistence_manager.dart';
import 'package:firebase_database_dart/src/core/persistence/noop_persistence_manager.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_manager.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_storage_engine.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/user_write_record.dart';
import 'package:firebase_database_dart/src/core/view/cache_node.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:firebase_database_dart/src/core/write_id.dart';

/// A [PersistenceManager] that sends the user-write methods ([saveUserOverwrite],
/// [saveUserMerge], [removeUserWrite], [removeAllUserWrites], [loadUserWrites]) and
/// [runInTransaction] to [engine], and behaves like [NoopPersistenceManager] for everything else:
/// [serverCache] is empty and not complete, nothing is tracked, acknowledged writes are not
/// promoted into a server cache.
///
/// Why a separate manager and not a writes-only engine under [DefaultPersistenceManager]: the
/// default manager takes completeness from its in-memory tracked queries and the data from the
/// engine, so a query marked complete earlier in the session would come back, when listened to
/// again, as complete but empty, and the listener would get a false null before the server
/// answers. Here nothing is ever reported complete, so listeners after a restart start empty and
/// wait for the server, as the JS SDK does.
final class WritesOnlyPersistenceManager implements PersistenceManager {
  /// Creates a manager over [engine].
  const WritesOnlyPersistenceManager(this.engine);

  /// The storage engine (its server-cache and tracked-query tables stay empty).
  final PersistenceStorageEngine engine;

  @override
  void saveUserOverwrite(Path path, Node node, WriteId writeId) =>
      throw UnimplementedError();

  @override
  void saveUserMerge(Path path, CompoundWrite children, WriteId writeId) =>
      throw UnimplementedError();

  @override
  void removeUserWrite(WriteId writeId) => throw UnimplementedError();

  @override
  void removeAllUserWrites() => throw UnimplementedError();

  @override
  void applyUserWriteToServerCache(Path path, Node node) =>
      throw UnimplementedError();

  @override
  void applyUserMergeToServerCache(Path path, CompoundWrite merge) =>
      throw UnimplementedError();

  @override
  List<UserWriteRecord> loadUserWrites() => throw UnimplementedError();

  @override
  CacheNode serverCache(QuerySpec query) => throw UnimplementedError();

  @override
  void updateServerCache(QuerySpec query, Node node) =>
      throw UnimplementedError();

  @override
  void updateServerCacheWithMerge(Path path, CompoundWrite children) =>
      throw UnimplementedError();

  @override
  void setQueryActive(QuerySpec query) => throw UnimplementedError();

  @override
  void setQueryInactive(QuerySpec query) => throw UnimplementedError();

  @override
  void setQueryComplete(QuerySpec query) => throw UnimplementedError();

  @override
  void setTrackedQueryKeys(QuerySpec query, Set<ChildKey> keys) =>
      throw UnimplementedError();

  @override
  void updateTrackedQueryKeys(
    QuerySpec query,
    Set<ChildKey> added,
    Set<ChildKey> removed,
  ) => throw UnimplementedError();

  @override
  bool get isDurable => throw UnimplementedError();

  @override
  T runInTransaction<T>(T Function() body) => throw UnimplementedError();
}
