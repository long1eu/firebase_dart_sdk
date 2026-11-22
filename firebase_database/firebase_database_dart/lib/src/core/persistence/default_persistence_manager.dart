/// The persistence manager over a storage engine. JS: none; Android:
/// `core/persistence/DefaultPersistenceManager.java`.
library;

import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/persistence/cache_policy.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_manager.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_storage_engine.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/user_write_record.dart';
import 'package:firebase_database_dart/src/core/util/clock.dart';
import 'package:firebase_database_dart/src/core/view/cache_node.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:firebase_database_dart/src/core/write_id.dart';

/// A [PersistenceManager] over a storage engine, tracking queries and pruning by a cache policy.
final class DefaultPersistenceManager implements PersistenceManager {
  /// Creates a manager.
  factory DefaultPersistenceManager(
    PersistenceStorageEngine storageLayer,
    CachePolicy cachePolicy,
    Clock clock,
  ) => throw UnimplementedError();

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
